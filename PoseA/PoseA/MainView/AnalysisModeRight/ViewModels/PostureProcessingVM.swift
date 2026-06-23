//
//  CoachingVM.swift
//  PoseA
//
//  Created by Ardhika Maulidani on 4/21/26.
//

import Foundation
import CoreGraphics

@Observable
class PostureProcessingVM {
    private let mediaManager: MediaManagerVM

    init(mediaManager: MediaManagerVM) {
        self.mediaManager = mediaManager
    }

    // MARK: - Public

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

        if let rel = buildPhaseComparison(reference: reference, phase: .release) {
            result.append(rel)
        }
        if let flt = buildPhaseComparison(reference: reference, phase: .flight) {
            result.append(flt)
        }

        let postureData = result
        await MainActor.run {
            mediaManager.updatePostureData(postureData, source: .processing)
        }
    }

    // MARK: - Phase builder

    private func buildPhaseComparison(reference: ReferencesModel,
                                      phase: ComparisonPhase) -> PostureData? {
        let (windowStart, windowEnd) = phaseRange(phase: phase)
        guard let start = windowStart, let end = windowEnd else { return nil }

        let refPhase  = phase == .release ? reference.release : reference.flight
        let isRelease = phase == .release
        var joints: [CompareList: JointPostureData] = [:]

        for feature in CompareList.allCases {
            let athlete = extractComSeries(feature:     feature,
                                           windowStart: start,
                                           windowEnd:   end,
                                           isRelease:   isRelease)
            guard !athlete.isEmpty else { continue }

            if let joint = buildJointData(feature:  feature,
                                          athlete:  athlete,
                                          refPhase: refPhase,
                                          phase:    phase) {
                joints[feature] = joint
            }
        }

        return PostureData(skill: reference.skill, phase: phase, joints: joints)
    }

    // MARK: - CoM angle series extraction

    /// Extracts a [CGPoint] series where x = CoM angle (°, unwrapped) and y = joint angle (°).
    /// Release phase applies range normalisation so all trials share the same starting band.
    /// Flight phase skips normalisation because it legitimately starts near 300°.
    private func extractComSeries(feature:     CompareList,
                                  windowStart: Int,
                                  windowEnd:   Int,
                                  isRelease:   Bool) -> [CGPoint] {
        var rawComs:   [Double] = []
        var jointVals: [Double] = []

        for i in windowStart...windowEnd {
            guard let f = mediaManager.FeaturesData[i] else { continue }
            rawComs.append(f.comAngle)
            jointVals.append(jointValue(f, feature: feature))
        }

        guard rawComs.count >= 2 else { return [] }

        var coms = unwrapDeg(rawComs)
        if isRelease { coms = normaliseComRange(coms) }

        return zip(coms, jointVals).map { CGPoint(x: $0, y: $1) }
    }

    // MARK: - Joint comparison

    private func buildJointData(feature:  CompareList,
                                athlete:  [CGPoint],
                                refPhase: ReferencePhase,
                                phase:    ComparisonPhase) -> JointPostureData? {
        let refCurve = refPhase[feature]
        guard !refPhase.comGrid.isEmpty,
              refPhase.comGrid.count == refCurve.mean.count,
              refCurve.mean.count == refCurve.std.count
        else { return nil }

        // ── Step 1: sort by CoM angle ──────────────────────────────────────
        var processed = athlete.sorted { $0.x < $1.x }

        // ── Step 2: CCW → CW frame transformation ─────────────────────────

        let isCCW = mediaManager.EventsData.rotationDir == "CCW"
        if isCCW {
            processed = processed
                .map { CGPoint(x: 360.0 - $0.x, y: 360.0 - $0.y) }
                .sorted { $0.x < $1.x }
        }

        // ── Step 3: align to reference revolution ──────────────────────────
        let aligned = alignComShift(processed, refGrid: refPhase.comGrid)
        let comMin  = aligned.first!.x
        let comMax  = aligned.last!.x

        // ── Step 4: clip reference to athlete CoM range ────────────────────
        let clipped = refPhase.comGrid.indices.filter {
            refPhase.comGrid[$0] >= comMin && refPhase.comGrid[$0] <= comMax
        }
        guard !clipped.isEmpty else { return nil }

        // ── Step 5: build comparison series ───────────────────────────────
        var refMean:  [CGPoint] = []
        var refUpper: [CGPoint] = []
        var refLower: [CGPoint] = []
        var zScore:   [CGPoint] = []

        for i in clipped {
            let com = refPhase.comGrid[i]
            let mu  = refCurve.mean[i]   // already in CW frame; athlete was transformed above
            let sd  = refCurve.std[i]

            refMean.append(CGPoint(x: com, y: mu))
            refUpper.append(CGPoint(x: com, y: mu + sd))
            refLower.append(CGPoint(x: com, y: mu - sd))

            let athleteVal = linearInterp(x: com, pts: aligned)
            let z = sd > 1e-9 ? (athleteVal - mu) / sd : 0.0
            zScore.append(CGPoint(x: com, y: z))
        }

        // ── Step 6: deviation detection ────────────────────────────────────
        let rawDev = detectMagnitudeDevWindows(zScore: zScore)
        let magDev = rawDev.map { dev in
            DeviationModel(
                tStart:     dev.tStart,
                tEnd:       dev.tEnd,
                duration:   dev.duration,
                meanVal:    dev.meanVal,
                direction:  dev.direction,
                severity:   dev.severity,
                suggestion: generateSuggestion(feature:   feature,
                                               phase:     phase,
                                               direction: dev.direction,
                                               tStart:    dev.tStart,
                                               tEnd:      dev.tEnd)
            )
        }

        let rms: Double? = zScore.isEmpty ? nil
            : sqrt(zScore.map { $0.y * $0.y }.reduce(0, +) / Double(zScore.count))

        return JointPostureData(feature:   feature,
                                athlete:   aligned,
                                refMean:   refMean,
                                refUpper:  refUpper,
                                refLower:  refLower,
                                zScore:    zScore,
                                magDev:    magDev,
                                rmsZScore: rms)
    }

    /// Shifts a sorted [CGPoint] series by the nearest whole revolution (0, ±360, ±720…)
    /// so the series midpoint aligns with the reference grid midpoint.
    private func alignComShift(_ pts: [CGPoint], refGrid: [Double]) -> [CGPoint] {
        guard !pts.isEmpty, !refGrid.isEmpty else { return pts }
        let refMid = (refGrid.first! + refGrid.last!) / 2.0
        let ptsMid = (pts.first!.x   + pts.last!.x)  / 2.0
        let shift  = 360.0 * ((refMid - ptsMid) / 360.0).rounded()
        guard shift != 0.0 else { return pts }
        return pts.map { CGPoint(x: $0.x + shift, y: $0.y) }
    }

    // MARK: - Deviation detection

    private func detectMagnitudeDevWindows(zScore:         [CGPoint],
                                           zThreshold:     Double = 1.0,
                                           zSignificant:   Double = 2.0,
                                           minSustainedDeg: Double = 10.0) -> [DeviationModel] {
        guard zScore.count >= 2 else { return [] }

        var results: [DeviationModel] = []

        for direction in [DeviationDirection.above, DeviationDirection.below] {
            var runStart: Int? = nil

            func flush(from start: Int, to end: Int) {
                let comStart = zScore[start].x
                let comEnd   = zScore[end].x
                let span     = comEnd - comStart
                guard span >= minSustainedDeg else { return }

                let zValues = zScore[start...end].map { $0.y }
                let meanZ   = zValues.reduce(0, +) / Double(zValues.count)
                let maxAbsZ = zValues.map { abs($0) }.max() ?? 0

                results.append(DeviationModel(
                    tStart:     comStart,
                    tEnd:       comEnd,
                    duration:   (span    * 10).rounded() / 10,
                    meanVal:    (meanZ   * 100).rounded() / 100,
                    direction:  direction,
                    severity:   maxAbsZ >= zSignificant ? .significant : .notable,
                    suggestion: ""
                ))
            }

            for i in zScore.indices {
                let z            = zScore[i].y
                let isDeviation  = direction == .above ? z >= zThreshold : z <= -zThreshold

                if isDeviation && runStart == nil {
                    runStart = i
                } else if !isDeviation, let start = runStart {
                    flush(from: start, to: i - 1)
                    runStart = nil
                }
            }
            if let start = runStart {
                flush(from: start, to: zScore.count - 1)
            }
        }

        return results.sorted { $0.tStart < $1.tStart }
    }

    // MARK: - CoM angle helpers

    /// Unwraps a sequence of angles in degrees, removing 360° jumps.
    /// Example: [350, 5, 20] → [350, 365, 380]
    private func unwrapDeg(_ angles: [Double]) -> [Double] {
        guard angles.count >= 2 else { return angles }
        var result = [angles[0]]
        for a in angles.dropFirst() {
            let raw  = a - result.last!
            let diff = raw - 360.0 * floor((raw + 180.0) / 360.0)
            result.append(result.last! + diff)
        }
        return result
    }

    /// Shifts release-phase trials that start above `threshold` down by 360°,
    /// aligning trials that begin just before the top (~350°) with those that
    /// begin just after (~0°–10°) so they share one continuous X range.
    private func normaliseComRange(_ angles: [Double],
                                   threshold: Double = 270.0) -> [Double] {
        guard let first = angles.first, first > threshold else { return angles }
        return angles.map { $0 - 360.0 }
    }

    // MARK: - Misc helpers

    private func phaseRange(phase: ComparisonPhase) -> (Int?, Int?) {
        let e = mediaManager.EventsData
        switch phase {
        case .release: return (e.releaseStartPoseIdx, e.releaseEndPoseIdx)
        case .flight:  return (e.flightStartPoseIdx,  e.flightEndPoseIdx)
        }
    }

    private func jointValue(_ f: FeaturesModel, feature: CompareList) -> Double {
        switch feature {
        case .shoulder: return f.shoulderAngle
        case .hip:      return f.hipAngle
        case .knee:     return f.kneeAngle
        }
    }

    /// Linear interpolation over a sorted [CGPoint] array, clamping at endpoints.
    private func linearInterp(x: Double, pts: [CGPoint]) -> Double {
        guard pts.count >= 2   else { return pts.first!.y }
        if x <= pts.first!.x   { return pts.first!.y }
        if x >= pts.last!.x    { return pts.last!.y  }

        var lo = 0, hi = pts.count - 1
        while lo + 1 < hi {
            let mid = (lo + hi) / 2
            pts[mid].x <= x ? (lo = mid) : (hi = mid)
        }
        let t = (x - pts[lo].x) / (pts[hi].x - pts[lo].x)
        return pts[lo].y + t * (pts[hi].y - pts[lo].y)
    }
}

// MARK: - Export

extension PostureProcessingVM {
    func exportPosture(to fileURL: URL) throws {
        let postureData = mediaManager.PostureData
        guard !postureData.isEmpty else { throw ExportImportError.invalidFormat }
        try ExportImportManager.exportPosture(postureData: postureData, to: fileURL)
    }
}

// MARK: - Suggestion Sentence Generation
//
// Evidence basis:
//   Release hip / shoulder: Hiley & Yeadon (2007) Tkatchev biomechanical analysis.
//   Flight phase:           Inferred from gymnastics biomechanics principles.
//
// Language principle:
//   Short, athlete-perspective sentences — what they feel, not what a coach sees.
//   Format: "<action> <when>."

extension PostureProcessingVM {

    func generateSuggestion(feature:   CompareList,
                            phase:     ComparisonPhase,
                            direction: DeviationDirection,
                            tStart:    Double,
                            tEnd:      Double) -> String {
        let action   = jointAction(feature: feature, phase: phase, direction: direction)
        let when     = timing(phase: phase, comMid: (tStart + tEnd) / 2.0)
        return "\(action) \(when)."
    }

    // MARK: - Action
    // .above → athlete angle > reference → more EXTENDED than expected
    // .below → athlete angle < reference → more FLEXED than expected

    private func jointAction(feature:   CompareList,
                             phase:     ComparisonPhase,
                             direction: DeviationDirection) -> String {
        switch (phase, feature, direction) {
        // ── Release ───────────────────────────────────────────────────────
        case (.release, .hip,      .below): return "Pull your hips in more"
        case (.release, .hip,      .above): return "Hold your hip bend longer"
        case (.release, .shoulder, .below): return "Engage your shoulders earlier"
        case (.release, .shoulder, .above): return "Let your shoulders open wider"
        case (.release, .knee,     .below): return "Keep your legs straight"
        case (.release, .knee,     .above): return "Relax the knee tension"
        // ── Flight ────────────────────────────────────────────────────────
        case (.flight, .hip,      .below): return "Pull into your tuck sooner"
        case (.flight, .hip,      .above): return "Open your hips earlier"
        case (.flight, .shoulder, .below): return "Reach for the bar sooner"
        case (.flight, .shoulder, .above): return "Wait before reaching for the bar"
        case (.flight, .knee,     .below): return "Straighten your legs"
        case (.flight, .knee,     .above): return "Ease the leg tension"
        }
    }

    // MARK: - Timing
    private func timing(phase: ComparisonPhase, comMid: Double) -> String {
        switch phase {
        case .release:
            switch comMid {
            case ..<60:    return "when you're upside down at the top"
            case 60..<150: return "as you swing down"
            case 150..<210: return "as you swing pass the bar"
            case 210..<270: return "as you swing back up"
            default:        return "just before you release"
            }
        case .flight:
            switch comMid {
            case ..<315:    return "the moment you release"
            case 315..<335: return "as your feet pass over the bar"
            case 335..<365: return "at the top of your flight"
            default:        return "as you reach back for the bar"
            }
        }
    }
}
