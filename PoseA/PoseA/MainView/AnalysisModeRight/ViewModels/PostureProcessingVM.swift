//
//  CoachingVM.swift
//  PoseA
//
//  Created by Ardhika Maulidani on 4/21/26.
//


import Foundation
import CoreGraphics

// MARK: - Output types

struct JointPostureData {
    var feature:  CompareList
    var athlete:  [CGPoint]   // raw athlete series          x=t(s), y=angle(°)
    var refMean:  [CGPoint]   // reference mean              x=t(s), y=mean(°)
    var refUpper: [CGPoint]   // reference mean + 1 std      x=t(s), y=(°)
    var refLower: [CGPoint]   // reference mean − 1 std      x=t(s), y=(°)
    var zScore:   [CGPoint]   // deviation from reference    x=t(s), y=z-score
    var rmsZScore: Double?    // RMS z-score over window (quality scalar)
}

struct PostureData {
    var phase:       ComparisonPhase
    var anchorFrame: Int?
    var joints:      [CompareList: JointPostureData]

    subscript(joint: CompareList) -> JointPostureData? { joints[joint] }
}

enum ComparisonPhase {
    case release, flight
    var label:       String { self == .release ? "Release Phase" : "Flight Phase" }
}

@Observable
class PostureProcessingVM {
    private let mediaManager: MediaManagerVM

    init(mediaManager: MediaManagerVM) {
        self.mediaManager = mediaManager
    }

    // MARK: - Public function
    func compare(reference: ReferencesModel) async throws {
        guard mediaManager.isMediaAvailable else {
            throw PipelineError.insufficientData(reason: "No media data is found")
        }
        guard !mediaManager.FeaturesData.isEmpty else {
            throw PipelineError.insufficientData(reason: "No features data is imported")
        }
        guard mediaManager.EventsData.rotationDir != "" else {
            throw PipelineError.insufficientData(reason: "No event index frame data is imported")
        }

        var result: [PostureData] = []

        if let rel = buildPhaseComparison(reference: reference, phase: ComparisonPhase.release) {
            result.append(rel)
        }
        if let flt = buildPhaseComparison(reference: reference, phase: ComparisonPhase.flight) {
            result.append(flt)
        }
        
        // Update MediaManager with processed data
        let postureData = result
        await MainActor.run {
            mediaManager.updatePostureData(postureData, source: .processing)
        }
    }

    // MARK: - Phase builder
    private func buildPhaseComparison(reference: ReferencesModel, phase: ComparisonPhase) -> PostureData? {
        let (windowStart, windowEnd, anchorFrame) = phaseRange(phase: phase)
        guard let start = windowStart, let end = windowEnd else { return nil }

        let refPhase = phase == .release ? reference.release : reference.flight
        var joints:  [CompareList: JointPostureData] = [:]

        for feature in CompareList.allCases {
            // 1. Athlete anchor-aligned series (raw, as plotted in plot_all)
            let athlete = extractTimeSeries(feature:     feature,
                                            windowStart: start,
                                            windowEnd:   end,
                                            anchorFrame: anchorFrame)
            guard !athlete.isEmpty else { continue }

            // 2. Build comparison (reference band + z-score)
            if let joint = buildJointData(feature:  feature,
                                          athlete:  athlete,
                                          refPhase: refPhase) {
                joints[feature] = joint
            }
        }

        return PostureData(phase: phase, anchorFrame: anchorFrame, joints: joints)
    }

    // MARK: - Time series extraction
    // Matches Python extract_series(): iterate window frames, shift by anchor.

    private func extractTimeSeries(feature:     CompareList,
                                   windowStart: Int,
                                   windowEnd:   Int,
                                   anchorFrame: Int?) -> [CGPoint] {
        let anchor = anchorFrame ?? windowStart
        var pts: [CGPoint] = []
        
        for i in windowStart...windowEnd {
            guard let f = mediaManager.FeaturesData[i] else { continue }
            let t = Double(i - anchor) / mediaManager.fps
            pts.append(CGPoint(x: t, y: jointValue(f, feature: feature)))
        }
        return pts
    }

    // MARK: - Joint comparison
    private func buildJointData(feature:  CompareList,
                                 athlete:  [CGPoint],
                                 refPhase: ReferencePhase) -> JointPostureData? {
        let refCurve = refPhase[feature]
        guard !refPhase.tGrid.isEmpty,
              refPhase.tGrid.count == refCurve.mean.count,
              refCurve.mean.count == refCurve.std.count
        else { return nil }

        let sorted = athlete.sorted { $0.x < $1.x }
        let tMin   = sorted.first!.x
        let tMax   = sorted.last!.x

        // Clip reference grid to athlete window
        let clipped = refPhase.tGrid.indices.filter {
            refPhase.tGrid[$0] >= tMin && refPhase.tGrid[$0] <= tMax
        }
        guard !clipped.isEmpty else { return nil }

        // Build chart-ready CGPoint arrays for the reference band
        var refMean:  [CGPoint] = []
        var refUpper: [CGPoint] = []
        var refLower: [CGPoint] = []
        var zScore:   [CGPoint] = []

        for i in clipped {
            let t  = refPhase.tGrid[i]
            let sd = refCurve.std[i]

            let isCCW  = mediaManager.EventsData.rotationDir == "CCW"
            let mu = isCCW ? 360.0 - refCurve.mean[i] : refCurve.mean[i]
            
            refMean.append(CGPoint(x: t, y: mu))
            refUpper.append(CGPoint(x: t, y: mu + sd))
            refLower.append(CGPoint(x: t, y: mu - sd))

            // Interpolate athlete onto this reference grid point
            let athleteVal = linearInterp(x: t, pts: sorted)
            let z = sd > 1e-9 ? (athleteVal - mu) / sd : 0.0
            zScore.append(CGPoint(x: t, y: z))
        }

        // RMS z-score scalar
        let rms: Double? = zScore.isEmpty ? nil
            : sqrt(zScore.map { $0.y * $0.y }.reduce(0, +) / Double(zScore.count))

        return JointPostureData(feature:   feature,
                                athlete:   sorted,
                                refMean:   refMean,
                                refUpper:  refUpper,
                                refLower:  refLower,
                                zScore:    zScore,
                                rmsZScore: rms)
    }

    // MARK: - Helpers

    private func phaseRange(_ phase: ComparisonPhase? = nil,
                             phase p: ComparisonPhase) -> (Int?, Int?, Int?) {
        phaseRange(phase: p)
    }

    private func phaseRange(phase: ComparisonPhase) -> (Int?, Int?, Int?) {
        let e = mediaManager.EventsData
        switch phase {
        case .release: return (e.releaseStartPoseIdx, e.releaseEndPoseIdx, e.release180PoseIdx)
        case .flight:  return (e.flightStartPoseIdx,  e.flightEndPoseIdx,  e.ankleCrossIdx)
        }
    }

    private func jointValue(_ f: FeaturesModel, feature: CompareList) -> Double {
        switch feature {
        case .shoulder: return f.shoulderAngle
        case .hip:      return f.hipAngle
        case .knee:     return f.kneeAngle
        }
    }

    /// Linear interpolation — clamps at endpoints, matching np.interp behaviour.
    private func linearInterp(x: Double, pts: [CGPoint]) -> Double {
        guard pts.count >= 2 else { return pts.first!.y }
        if x <= pts.first!.x { return pts.first!.y }
        if x >= pts.last!.x  { return pts.last!.y  }
        var lo = 0, hi = pts.count - 1
        while lo + 1 < hi {
            let mid = (lo + hi) / 2
            pts[mid].x <= x ? (lo = mid) : (hi = mid)
        }
        let t = (x - pts[lo].x) / (pts[hi].x - pts[lo].x)
        return pts[lo].y + t * (pts[hi].y - pts[lo].y)
    }
}

// MARK: - Convenience

extension PostureData {
    // Average RMS z-score across all joints (overall phase quality indicator).
    var overallRmsZScore: Double? {
        let scores = CompareList.allCases.compactMap { joints[$0]?.rmsZScore }
        guard !scores.isEmpty else { return nil }
        return scores.reduce(0, +) / Double(scores.count)
    }
}
