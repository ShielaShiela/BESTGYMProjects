//
//  GCNClassifierVM.swift
//  PoseA
//
//  Created by Ardhika Maulidani on 4/23/26.
//

//  ST-GCN skill classifier inference.
//  Preprocessing pipeline:
//    1. Window frames: releasePhase.start → flightPhase.end
//    2. frame_to_graph: FeaturesModel → (V=6, C=8) node feature matrix
//    3. extract_sequence: stack frames → resample to T=32 via linear interp
//    4. Normalize: (x - mean) / std  (per-channel, from gcn_norm_stats.json)
//    5. Transpose: (T, V, C) → (C, T, V) then flatten to (1, C*T*V) for CoreML
//    6. CoreML inference → probabilities
//    7. Map indices → skill names via gcn_label_map.json
//

import Foundation
import CoreML


@Observable
class GCNClassifierVM {
    // MARK: - Properties
    private let mediaManager: MediaManagerVM

    private var model:    MLModel?
    private var normMean: [Double] = []
    private var normStd:  [Double] = []
    private var labelMap: [Int: String] = [:]

    // MARK: - Graph constants
    private let V = 6
    private let C = 8
    private let T = 32

    // MARK: - Node feature extractors
    // Each row = one graph node, each slot = one channel (nil → 0.0).
    // Optional velocities use ?? 0.0 to match Python frame_to_graph()'s
    // nan/None → 0.0 behaviour.
    private typealias Extractor = (FeaturesModel) -> Double

    private var nodeFeatureMap: [[Extractor?]] = [
        // Node 0: bar_top
        [nil, nil, { $0.barSpringLenM }, nil, nil, nil, nil, nil],
        // Node 1: wrist
        [{ $0.vArmAngle }, { $0.armActualLenM }, { $0.armSpringDeflectionM },
         { $0.barSpringLenM }, { $0.vArmAngleVel ?? 0.0 }, nil, nil, nil],
        // Node 2: shoulder
        [{ $0.shoulderAngle }, { $0.armRestLenM }, { $0.upperArmLenM },
         { $0.forearmLenM }, { $0.shoulderAngleVel ?? 0.0 }, nil, nil, nil],
        // Node 3: hip
        [{ $0.hipAngle }, { $0.torsoLenM }, { $0.vTorsoAngle },
         { $0.comAngle }, { $0.hipAngleVel ?? 0.0 }, { $0.vTorsoAngleVel ?? 0.0 },
         { $0.headHeightM }, nil],
        // Node 4: knee
        [{ $0.kneeAngle }, { $0.thighLenM }, { $0.vThighAngle },
         nil, { $0.kneeAngleVel ?? 0.0 }, { $0.vThighAngleVel ?? 0.0 }, nil, nil],
        // Node 5: ankle
        [{ $0.lowerLegLenM }, { $0.vLowerLegAngle },
         nil, nil, { $0.vLowerLegAngleVel ?? 0.0 }, nil, nil, nil],
    ]

    // MARK: - Init
    init(mediaManager: MediaManagerVM) {
        self.mediaManager = mediaManager
    }

    // MARK: - Load
    func load() async -> String? {
        return await Task.detached(priority: .userInitiated) { [weak self] in
            guard let self else { return "GCNClassifierVM was deallocated." }
            do {
                // CoreML model
                guard let modelURL = Bundle.main.url(forResource: "STGCNModel",
                                                      withExtension: "mlmodelc") else {
                    return "STGCNModel.mlpackage not found in bundle."
                }
                let loadedModel = try MLModel(contentsOf: modelURL)

                // Norm stats
                guard let normURL = Bundle.main.url(forResource: "gcn_norm_stats",
                                                     withExtension: "json") else {
                    return "gcn_norm_stats.json not found in bundle."
                }
                let stats = try JSONDecoder().decode(NormStats.self,
                                                     from: Data(contentsOf: normURL))
                guard stats.mean.count == self.C, stats.std.count == self.C else {
                    return "gcn_norm_stats.json has wrong channel count (expected \(self.C))."
                }

                // Label map
                guard let labelURL = Bundle.main.url(forResource: "gcn_label_map",
                                                      withExtension: "json") else {
                    return "gcn_label_map.json not found in bundle."
                }
                let rawMap = try JSONDecoder().decode([String: String].self,
                                                      from: Data(contentsOf: labelURL))
                let labelMap = Dictionary(uniqueKeysWithValues:
                    rawMap.compactMap { k, v in Int(k).map { ($0, v) } }
                )

                // Commit to main actor storage
                await MainActor.run {
                    self.model    = loadedModel
                    self.normMean = stats.mean
                    self.normStd  = stats.std
                    self.labelMap = labelMap
                }
                return nil   // success

            } catch {
                return error.localizedDescription
            }
        }.value
    }

    // MARK: - Classify
    // Heavy preprocessing + CoreML inference run off the main thread.
    func classify() async -> (prediction: SkillPrediction?, error: String?) {
        guard let model else {
            return (nil, "Model is not loaded. Call load() first.")
        }
        guard mediaManager.isMediaAvailable else {
            return (nil, "No media data available.")
        }
        guard !mediaManager.FeaturesData.isEmpty else {
            return (nil, "Features data is missing.")
        }

        let events = mediaManager.EventsData
        guard let windowStart = events.releaseStartPoseIdx,
              let windowEnd   = events.flightEndPoseIdx,
              windowEnd > windowStart
        else {
            return (nil, "Release or flight phase indices are missing.")
        }

        // Snapshot the data needed off the main thread
        let featuresSnapshot = mediaManager.FeaturesData
        let normMean = self.normMean
        let normStd  = self.normStd
        let labelMap = self.labelMap

        return await Task.detached(priority: .userInitiated) { [weak self] in
            guard let self else { return (nil, "GCNClassifierVM was deallocated.") }
            do {
                let rawSeq     = self.buildRawSequence(windowStart:      windowStart,
                                                       windowEnd:        windowEnd,
                                                       features:         featuresSnapshot)
                let resampled  = self.resampleSequence(rawSeq, toLength: self.T)
                let normalized = self.normalizeSequence(resampled,
                                                        mean: normMean,
                                                        std:  normStd)
                let inputArray = self.transposeAndFlatten(normalized)
                let probs      = try self.runInference(inputArray, model: model)
                return (self.buildPrediction(probs, labelMap: labelMap), nil)
            } catch {
                return (nil, error.localizedDescription)
            }
        }.value
    }

    // MARK: - Preprocessing

    private func buildRawSequence(windowStart: Int,
                                   windowEnd:   Int,
                                   features:    [Int: FeaturesModel]) -> [[[Double]]] {
        var sequence: [[[Double]]] = []
        for i in windowStart...windowEnd {
            var nodeMatrix = Array(repeating: Array(repeating: 0.0, count: C), count: V)
            if let f = features[i] {
                for (nodeIdx, channelKeys) in nodeFeatureMap.enumerated() {
                    for (chanIdx, extractor) in channelKeys.enumerated() {
                        guard let extractor else { continue }
                        let val = extractor(f)
                        nodeMatrix[nodeIdx][chanIdx] = val.isFinite ? val : 0.0
                    }
                }
            }
            sequence.append(nodeMatrix)
        }
        return sequence
    }

    private func resampleSequence(_ seq: [[[Double]]], toLength tOut: Int) -> [[[Double]]] {
        let tIn = seq.count
        guard tIn > 0 else {
            return Array(repeating: Array(repeating: Array(repeating: 0.0, count: C), count: V),
                         count: tOut)
        }
        if tIn == 1 { return Array(repeating: seq[0], count: tOut) }
        if tIn == tOut { return seq }

        var out = Array(repeating: Array(repeating: Array(repeating: 0.0, count: C), count: V),
                        count: tOut)
        let tInD  = Double(tIn  - 1)
        let tOutD = Double(tOut - 1)

        for v in 0..<V {
            for c in 0..<C {
                let ys = seq.map { $0[v][c] }
                for j in 0..<tOut {
                    let pos  = Double(j) / tOutD * tInD
                    let lo   = Int(pos)
                    let hi   = min(lo + 1, tIn - 1)
                    let frac = pos - Double(lo)
                    out[j][v][c] = ys[lo] + frac * (ys[hi] - ys[lo])
                }
            }
        }
        return out
    }

    private func normalizeSequence(_ seq: [[[Double]]],
                                   mean: [Double],
                                   std:  [Double]) -> [[[Double]]] {
        var out = seq
        for t in 0..<seq.count {
            for v in 0..<V {
                for c in 0..<C {
                    let s = std[c] > 1e-9 ? std[c] : 1.0
                    out[t][v][c] = (seq[t][v][c] - mean[c]) / s
                }
            }
        }
        return out
    }

    private func transposeAndFlatten(_ seq: [[[Double]]]) -> [Float] {
        var flat: [Float] = []
        flat.reserveCapacity(C * T * V)
        for c in 0..<C {
            for t in 0..<T {
                for v in 0..<V {
                    flat.append(Float(seq[t][v][c]))
                }
            }
        }
        return flat
    }

    private func runInference(_ inputArray: [Float], model: MLModel) throws -> [Double] {
        let shape: [NSNumber] = [1, NSNumber(value: C),
                                    NSNumber(value: T),
                                    NSNumber(value: V)]
        let mlArray = try MLMultiArray(shape: shape, dataType: .float32)
        for (i, val) in inputArray.enumerated() { mlArray[i] = NSNumber(value: val) }

        let output = try model.prediction(
            from: try MLDictionaryFeatureProvider(dictionary: ["input": mlArray])
        )
        guard let probArray = output.featureValue(for: "probabilities")?.multiArrayValue else {
            throw NSError(domain: "GCN", code: -1,
                          userInfo: [NSLocalizedDescriptionKey: "CoreML output 'probabilities' missing."])
        }
        return (0..<probArray.count).map { probArray[$0].doubleValue }
    }

    private func buildPrediction(_ probs: [Double],
                                  labelMap: [Int: String]) -> SkillPrediction {
        var probDict: [String: Double] = [:]
        for (idx, prob) in probs.enumerated() {
            probDict[labelMap[idx] ?? "class_\(idx)"] = prob
        }
        let top = probDict.max(by: { $0.value < $1.value }) ?? (key: "unknown", value: 0.0)
        return SkillPrediction(probabilities: probDict,
                               topLabel:      top.key,
                               confidence:    top.value)
    }
}
