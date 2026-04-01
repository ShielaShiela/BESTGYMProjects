//
//  FlightHeightCalculator.swift
//  PoseA
//
//  Created by Shiela Cabahug on 2026/2/19.
//
// FlightHeightCalculator.swift
import Foundation
import CoreGraphics

// MARK: - Keypoint Selection
enum FlightKeypointMode: String, CaseIterable, Identifiable {
    // Single keypoints
    case nose           = "Nose"
    case leftEye        = "Left Eye"
    case rightEye       = "Right Eye"
    case leftEar        = "Left Ear"
    case rightEar       = "Right Ear"
    case leftShoulder   = "Left Shoulder"
    case rightShoulder  = "Right Shoulder"
    case leftElbow      = "Left Elbow"
    case rightElbow     = "Right Elbow"
    case leftWrist      = "Left Wrist"
    case rightWrist     = "Right Wrist"
    case leftHip        = "Left Hip"
    case rightHip       = "Right Hip"
    case leftKnee       = "Left Knee"
    case rightKnee      = "Right Knee"
    case leftAnkle      = "Left Ankle"
    case rightAnkle     = "Right Ankle"

    // Midpoints (average of left + right pair)
    case midEyes        = "Mid Eyes (L+R)"
    case midEars        = "Mid Ears (L+R)"
    case midShoulders   = "Mid Shoulders (L+R)"
    case midElbows      = "Mid Elbows (L+R)"
    case midWrists      = "Mid Wrists (L+R)"
    case midHips        = "Mid Hips (L+R)"
    case midKnees       = "Mid Knees (L+R)"
    case midAnkles      = "Mid Ankles (L+R)"

    var id: String { rawValue }

    var cocoIndex: Int? {
        switch self {
        case .nose:          return 0
        case .leftEye:       return 1
        case .rightEye:      return 2
        case .leftEar:       return 3
        case .rightEar:      return 4
        case .leftShoulder:  return 5
        case .rightShoulder: return 6
        case .leftElbow:     return 7
        case .rightElbow:    return 8
        case .leftWrist:     return 9
        case .rightWrist:    return 10
        case .leftHip:       return 11
        case .rightHip:      return 12
        case .leftKnee:      return 13
        case .rightKnee:     return 14
        case .leftAnkle:     return 15
        case .rightAnkle:    return 16
        default:             return nil   // midpoints handled below
        }
    }

    var midpointIndices: (Int, Int)? {
        switch self {
        case .midEyes:      return (1, 2)
        case .midEars:      return (3, 4)
        case .midShoulders: return (5, 6)
        case .midElbows:    return (7, 8)
        case .midWrists:    return (9, 10)
        case .midHips:      return (11, 12)
        case .midKnees:     return (13, 14)
        case .midAnkles:    return (15, 16)
        default:            return nil
        }
    }

    var isMidpoint: Bool { midpointIndices != nil }
}

// MARK: - Data Model
struct FlightHeightData {
    let frameIndex: Int
    let headY: Double           // normalized (0–1)
    let barTopY: Double         // normalized (0–1)
    let normalizedDiff: Double  // positive = keypoint above bar
    let cmAboveBar: Double?     // nil if not calibrated
}

// MARK: - Calculator
class FlightHeightCalculator {

    static func calculate(
        mediaManager: MediaManagerVM,
        calibration: CalibrationModel,
        quadCalibration: QuadCalibrationModel,
        keypointMode: FlightKeypointMode = .nose
    ) -> [FlightHeightData] {

        // Bar position always from 2-point calibration
        guard let barTopNormalized = calibration.barTopPoint else { return [] }

      

        let totalFrames = mediaManager.fileLoaderViewModel.FrameImageURLs.count
        guard totalFrames > 0 else { return [] }

        var results: [FlightHeightData] = []

        for frameIndex in 0..<totalFrames {
            guard let keypoints = mediaManager.getKeypointsByIndex(frameIndex),
                  keypoints.count >= 1 else { continue }
            guard let kp = resolveKeypoint(keypoints: keypoints, mode: keypointMode) else { continue }

            let trackY         = Double(kp.y)
            let barTopY        = Double(barTopNormalized.y)
            let normalizedDiff = barTopY - trackY   // + => above bar
            

            // Use unified scale API — returns nil if active source isn't calibrated
            let cmAboveBar: Double?
            if quadCalibration.isCalibrated {
                cmAboveBar = quadCalibration.normalizedYDiffToCm(normalizedDiff)
            } else {
                cmAboveBar = calibration.normalizedYDiffToCm(normalizedDiff)
            }
            
            results.append(FlightHeightData(
                frameIndex: frameIndex,
                headY: trackY,
                barTopY: barTopY,
                normalizedDiff: normalizedDiff,
                cmAboveBar: cmAboveBar
            ))
        }

        return results
    }

    // MARK: - Keypoint Resolver
    /// Returns the (x, y) point for the selected mode, or nil if indices are out of range.
    private static func resolveKeypoint(
        keypoints: [KeypointData],        // your existing type
        mode: FlightKeypointMode
    ) -> KeypointData? {

        if let idx = mode.cocoIndex {
            guard idx < keypoints.count else { return nil }
            return keypoints[idx]
        }

        if let (a, b) = mode.midpointIndices {
            guard a < keypoints.count, b < keypoints.count else { return nil }
            let kpA = keypoints[a]
            let kpB = keypoints[b]
            // Return a synthetic midpoint using your KeypointData initializer
            // Adjust field names to match your actual struct
            return KeypointData(
                name: kpA.name,
                x: (kpA.x + kpB.x) / 2,
                y: (kpA.y + kpB.y) / 2,
                confidence: min(kpA.confidence, kpB.confidence),
                depth: (kpA.depth + kpB.depth) / 2,
                frameIndex: kpA.frameIndex
            )
        }

        return nil
    }

    static func maxFlightHeight(_ data: [FlightHeightData]) -> FlightHeightData? {
        return data.max(by: {
            ($0.cmAboveBar ?? -999) < ($1.cmAboveBar ?? -999)
        })
    }
}
