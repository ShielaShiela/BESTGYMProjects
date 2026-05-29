//
//  EventExtractionVM.swift
//  PoseA
//
//  Created by Ardhika Maulidani on 4/20/26.
//

import Foundation
import CoreGraphics

// MARK: - Thresholds
private enum HandstandThreshold {
    static let posToleranceDeg:   Double = 35.0  // CoM must be within this of 0°/360°
    static let jointToleranceDeg: Double = 35.0  // joint angles must be within this of 180°
    static let headToleranceM:    Double = -0.10 // head_height_m must exceed this (margin)
    static let minConsecutive:    Int    = 3     // consecutive frames all conditions must hold
    static let lockoutFrames:     Int    = 30    // frames to skip after a trigger
    static let rotSampleFrames:   Int    = 40    // frames sampled to determine rotation direction
}

private enum ReleaseThreshold {
    // Forward scan: (keyPath, mustExceed)
    static let forward: [(KeyPath<FeaturesModel, Double>, Double)] = [
        (\.barSpringLenM, 0.20),
        (\.headHeightM,   0.60),
        (\.vTorsoAngle,   130.801065),
    ]

    // Backtrack scan: (keyPath, mustExceed)
    static let backtrack: [(KeyPath<FeaturesModel, Double>, Double)] = [
        (\.barSpringLenM, 0.125),
        (\.headHeightM,   0.50),
        (\.vTorsoAngle,   110.0),
    ]

    static let minConsecutive:    Int    = 3
    static let minFramesAfterHS:  Int    = 20
    static let maxBacktrackFrames: Int   = 10
}

private enum FlightThreshold {
    static let posToleranceDeg:     Double = 20.0
    static let headThreshM:         Double = 0.20
    static let minDuration:         Int    = 5
    static let maxSearch:           Int    = 120
    static let endConsecutive:      Int    = 3
}

@Observable
class EventsExtractionVM {
    // MARK: - Properties
    private var mediaManager: MediaManagerVM
    
    // Output Variable
    private var processedEvents: EventsModel = EventsModel(rotationDir: "")
    
    init(mediaManager: MediaManagerVM) {
        self.mediaManager = mediaManager
    }
    
    // MARK: - Public function
    func buildEvents() async throws{
        // Collect features as a sorted array
        let featuresDict = mediaManager.FeaturesData
        guard !featuresDict.isEmpty else {
            throw PipelineError.insufficientData(reason: "No features found in import file")
        }

        // Sort by frame index
        let frames = featuresDict.values.sorted { $0.frameIdx < $1.frameIdx }

        // Detect handstand posture frame index
        let hsFrame: Int? = self.detectHandstand(frames: frames)

        // Detect released posture frame index
        let releaseFrameEnd: Int? = self.detectReleaseEnd(frames: frames,
                                                          hsFrame: hsFrame)
        
        // Do the rest detection if and only-if there are release phase
        var releaseFrameStart: Int? = nil
        var releaseFrame180: Int? = nil
        if let releaseFrameEnd = releaseFrameEnd, let hsFrame = hsFrame {
            // Backtrack detection for releasing posture frame index
            releaseFrameStart = self.detectReleaseStart(frames: frames,
                                                        releaseFrame: releaseFrameEnd,
                                                        hsFrame: hsFrame) ?? (hsFrame + 1)
            
            // Forward detection for 180 deg release anchor
            if let releaseFrameStart = releaseFrameStart {
                releaseFrame180 = self.detectRelease180(frames: frames,
                                                        releaseStart: releaseFrameStart,
                                                        releaseEnd: releaseFrameEnd
                )
            }
        }
        
        // Detect rotation direction
        var rotationDir = ""
        if let start = releaseFrameStart, let end = releaseFrameEnd {
            rotationDir = self.detectRotationDir(frames: frames,
                                                 startIdx: start,
                                                 endIdx: end)
        } else if let start = hsFrame, releaseFrameStart == nil {
            rotationDir = self.detectRotationDir(frames: frames,
                                                 startIdx: start,
                                                 endIdx: frames[frames.count].frameIdx)
        }
        
        // Detect flight posture frame index
        var flightFrameEnd: Int? = nil
        var peakFlightFrame: Int? = nil
        var ankleCrossFrame: Int? = nil

        if let releaseFrameEnd = releaseFrameEnd {
            flightFrameEnd = self.detectFlightEnd(frames: frames, releaseFrameEnd: releaseFrameEnd)
            
            if let flightFrameEnd = flightFrameEnd {
                // Detect peak flight frame
                peakFlightFrame = detectPeakFlight(frames: frames,
                                                   flightStart: releaseFrameEnd + 1,
                                                   flightEnd: flightFrameEnd)
            
            
                // Detect Ankle bar crossing
                ankleCrossFrame = detectAnkleBarCross(frames: frames,
                                                      flightStart: releaseFrameEnd + 1,
                                                      flightEnd: flightFrameEnd,
                                                      barTopPx: mediaManager.BarReferenceData[0]!,
                                                      rotationDirection: rotationDir)
            }
        }
        
        // Append the result in EventModel
        self.processedEvents = EventsModel(
            rotationDir: rotationDir,
            handstandPoseIdx: hsFrame,
            releaseStartPoseIdx: releaseFrameStart,
            releaseEndPoseIdx: releaseFrameEnd,
            release180PoseIdx: releaseFrame180,
            flightStartPoseIdx: releaseFrameEnd == nil ? nil : releaseFrameEnd! + 1,
            flightEndPoseIdx: flightFrameEnd,
            ankleCrossIdx: ankleCrossFrame,
            peakFlightIdx: peakFlightFrame
            )
        
        // Update MediaManager with processed data
        await MainActor.run {
            mediaManager.updateEventsData(self.processedEvents, source: .processing)
        }
    }

    // MARK: - Handstand Posture Detection
    private func detectHandstand(frames: [FeaturesModel]) -> Int? {
        var consecutive   = 0
        var lockout       = 0
        var triggerFrame: Int? = nil

        for f in frames {
            if lockout > 0 {
                lockout -= 1
                consecutive = 0
                continue
            }

            // C1: CoM above bar
            let c1 = self.angleNear0(f.comAngle, tol: HandstandThreshold.posToleranceDeg)

            // C2: all three joints nearly straight (≈ 180°)
            let c2 = angleNear180(f.shoulderAngle, tol: HandstandThreshold.jointToleranceDeg)
                  && angleNear180(f.hipAngle,      tol: HandstandThreshold.jointToleranceDeg)
                  && angleNear180(f.kneeAngle,     tol: HandstandThreshold.jointToleranceDeg)

            // C3: head above bar (with margin)
            let c3 = f.headHeightM > HandstandThreshold.headToleranceM

            if c1 && c2 && c3 {
                consecutive += 1
                if consecutive >= HandstandThreshold.minConsecutive && triggerFrame == nil {
                    triggerFrame = f.frameIdx - (consecutive - 1)
                    lockout = HandstandThreshold.lockoutFrames
                }
            } else {
                consecutive = 0
            }
        }

        return triggerFrame
    }

    // MARK: - Release phase detection
    // Backtracks from release frame until com_angle is near 0°/360°.
    private func detectReleaseStart(frames: [FeaturesModel],
                                    releaseFrame: Int,
                                    hsFrame: Int) -> Int? {
        guard let relIdx = frames.firstIndex(where: { $0.frameIdx == releaseFrame })
        else { return nil }

        let maxSteps = releaseFrame - hsFrame
        for steps in 1..<maxSteps {
            let i = relIdx - steps
            if i < 0 { break }
            if self.angleNear0(frames[i].comAngle, tol: FlightThreshold.posToleranceDeg) {
                return frames[i].frameIdx
            }
        }
        return nil
    }

    private func detectReleaseEnd(frames: [FeaturesModel], hsFrame: Int?) -> Int? {
        guard let hs = hsFrame,
              let hsIdx = frames.firstIndex(where: { $0.frameIdx == hs })
        else { return nil }

        let searchStart = hsIdx + ReleaseThreshold.minFramesAfterHS
        guard let candidateIdx = self.findCandidate(frames: frames, from: searchStart) else {
            return nil
        }

        let relIdx = self.backtrack(frames: frames, candidateIdx: candidateIdx)
        return frames[relIdx].frameIdx
    }
    
    private func detectRelease180(frames: [FeaturesModel], releaseStart: Int, releaseEnd: Int) -> Int? {
        var bestFrame: Int?   = nil
        var bestVal:   Double = .greatestFiniteMagnitude

        for f in frames where f.frameIdx >= releaseStart && f.frameIdx <= releaseEnd {
            let angle = mod360(f.comAngle)
            if angle < 90 || angle > 270 { continue }

            let angleDist = abs(angle - 180.0)
            if angleDist < bestVal {
                bestVal   = angleDist
                bestFrame = f.frameIdx
            }
        }
        return bestFrame
    }
    
    // Forward scan: MIN_CONSECUTIVE frames all meeting forward thresholds.
    private func findCandidate(frames: [FeaturesModel], from start: Int) -> Int? {
        var consecutive = 0
        for i in start..<frames.count {
            if allForwardConditions(frames[i]) {
                consecutive += 1
                if consecutive >= ReleaseThreshold.minConsecutive {
                    return i - (consecutive - 1)
                }
            } else {
                consecutive = 0
            }
        }
        return nil
    }

    // Step backward until backtrack thresholds are no longer met.
    private func backtrack(frames: [FeaturesModel], candidateIdx: Int) -> Int {
        for steps in 1...ReleaseThreshold.maxBacktrackFrames {
            let i = candidateIdx - steps
            if i < 0 { break }
            if !allBacktrackConditions(frames[i]) {
                return i + 1
            }
        }
        return candidateIdx
    }

    // MARK: - Rotation direction detection
    // Positive median → angle increasing → CW.  Negative → CCW.
    private func detectRotationDir(frames: [FeaturesModel],
                                   startIdx: Int,
                                   endIdx: Int) -> String {
        // Collect com_angle values in the release window
        var angles: [Double] = []
        for f in frames where f.frameIdx >= startIdx && f.frameIdx <= endIdx {
            angles.append(f.comAngle)
        }

        // Convert to radians, unwrap, convert back
        let radians   = angles.map { $0 * .pi / 180.0 }
        let unwrapped = unwrapAnglesRad(radians)
        let degrees   = unwrapped.map { $0 * 180.0 / .pi }

        // Consecutive differences
        var diffs: [Double] = []
        for i in 1..<degrees.count {
            diffs.append(degrees[i] - degrees[i - 1])
        }

        let medianDiff = median(of: diffs)
        // Positive diff = angle increasing = CW (image Y-down convention)
        return medianDiff > 0 ? "CW" : "CCW"
    }

    // MARK: - Flight phase detection
    // Forward scan from release for frames where head_height_m drops below headThreshM.

    private func detectFlightEnd(frames: [FeaturesModel],
                                 releaseFrameEnd: Int) -> Int? {
        guard let relIdx = frames.firstIndex(where: { $0.frameIdx == releaseFrameEnd })
        else { return nil }

        let searchStart = relIdx + 1 + FlightThreshold.minDuration
        let searchEnd   = min(relIdx + 1 + FlightThreshold.maxSearch, frames.count)
        var consecutive = 0

        for i in searchStart..<searchEnd {
            if frames[i].headHeightM < FlightThreshold.headThreshM {
                consecutive += 1
                if consecutive >= FlightThreshold.endConsecutive {
                    let endIdx = i - (consecutive - 1)
                    return frames[endIdx].frameIdx
                }
            } else {
                consecutive = 0
            }
        }
        return nil
    }

    // MARK: - Peak flight detection
    // Frame with maximum head_height_m within flight phase constraint frames
    private func detectPeakFlight(frames: [FeaturesModel],
                                  flightStart: Int,
                                  flightEnd: Int) -> Int? {
        var bestFrame: Int?  = nil
        var bestVal:   Double = -.greatestFiniteMagnitude

        for f in frames where f.frameIdx >= flightStart && f.frameIdx <= flightEnd {
            if f.headHeightM > bestVal {
                bestVal   = f.headHeightM
                bestFrame = f.frameIdx
            }
        }
        return bestFrame
    }

    // MARK: - Ankle bar crossing detection
    // CW  → ankle travels left→right: detect first frame ankle_x > bar_x while ankle_y < bar_y.
    // CCW → ankle travels right→left: detect first frame ankle_x < bar_x while ankle_y < bar_y.
    private func detectAnkleBarCross(frames: [FeaturesModel],
                                     flightStart: Int,
                                      flightEnd: Int,
                                      barTopPx: CGPoint,
                                      rotationDirection: String) -> Int? {
        // Get Top Bar Points
        let barX = Double(barTopPx.x)
        let barY = Double(barTopPx.y)

        var seenApproachSide = false

        for f in frames where f.frameIdx >= flightStart && f.frameIdx <= flightEnd {
            let frameIdx = f.frameIdx

            // Get keypoints for current frame
            guard let kp_detection = mediaManager.getKeypointsByIndex(frameIdx) else {
                continue
            }
            let kp = kp_detection.keypoints
            let lAnk = kp[15]
            let rAnk = kp[16]
            let ankleX = (lAnk.x + rAnk.x) / 2.0
            let ankleY = (lAnk.y + rAnk.y) / 2.0

            // Y crossing: ankle must be above bar (smaller Y in image coords)
            let ankleAboveBar = ankleY < barY

            if rotationDirection == "CW" {
                // Ankle travels from left (ankle_x < bar_x) to right (ankle_x > bar_x)
                if !seenApproachSide {
                    if ankleX < barX { seenApproachSide = true }
                    continue
                }
                if ankleX > barX && ankleAboveBar { return frameIdx }

            } else {
                // CCW: ankle travels from right to left
                if !seenApproachSide {
                    if ankleX > barX { seenApproachSide = true }
                    continue
                }
                if ankleX < barX && ankleAboveBar { return frameIdx }
            }
        }
        return nil
    }

    // MARK: - Threshold helpers

    private func allForwardConditions(_ f: FeaturesModel) -> Bool {
        ReleaseThreshold.forward.allSatisfy { (kp, thresh) in f[keyPath: kp] > thresh }
    }

    private func allBacktrackConditions(_ f: FeaturesModel) -> Bool {
        ReleaseThreshold.backtrack.allSatisfy { (kp, thresh) in f[keyPath: kp] > thresh }
    }

    // MARK: - Math helpers
    
    private func mod360(_ x: Double) -> Double {
        let r = x.truncatingRemainder(dividingBy: 360.0)
        return r < 0 ? r + 360.0 : r
    }
    
    private func angleNear180(_ angleDeg: Double, tol: Double) -> Bool {
        let diff = abs(mod360(angleDeg) - 180.0)
        return diff <= tol
    }

    private func angleNear0(_ angleDeg: Double, tol: Double) -> Bool {
        let a = mod360(angleDeg)
        return a <= tol || a >= (360.0 - tol)
    }
    
    private func unwrapAnglesRad(_ radians: [Double]) -> [Double] {
        var result = radians
        for i in 1..<result.count {
            var diff = result[i] - result[i - 1]
            // Wrap diff into (-π, π]
            while diff >  .pi { diff -= 2 * .pi }
            while diff < -.pi { diff += 2 * .pi }
            result[i] = result[i - 1] + diff
        }
        return result
    }

    private func median(of array: [Double]) -> Double {
        guard !array.isEmpty else { return 0 }
        let sorted = array.sorted()
        let n = sorted.count
        return n % 2 == 0
            ? (sorted[n / 2 - 1] + sorted[n / 2]) / 2.0
            : sorted[n / 2]
    }
}

// MARK: - Features Export Extension
extension EventsExtractionVM {
    func exportEvents(to fileURL: URL) throws {
        let eventsData = mediaManager.EventsData
        guard eventsData.rotationDir != "" else {
            throw ExportImportError.invalidFormat
        }
        
        try ExportImportManager.exportEvents(
            eventsData: eventsData,
            to: fileURL
        )
    }
}
