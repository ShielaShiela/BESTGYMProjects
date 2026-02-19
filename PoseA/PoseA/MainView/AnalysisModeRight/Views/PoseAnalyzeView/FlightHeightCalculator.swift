//
//  FlightHeightCalculator.swift
//  PoseA
//
//  Created by Shiela Cabahug on 2026/2/19.
//
// FlightHeightCalculator.swift
import Foundation
import CoreGraphics

struct FlightHeightData {
    let frameIndex: Int
    let headY: Double           // normalized (0-1)
    let barTopY: Double         // normalized (0-1)
    let normalizedDiff: Double  // positive = head above bar
    let cmAboveBar: Double? // nil if not calibrated
}

class FlightHeightCalculator {

    static func calculate(
        mediaManager: MediaManagerVM,
        calibration: CalibrationModel
    ) -> [FlightHeightData] {

        guard let barTopNormalized = calibration.barTopPoint else { return [] }

        let totalFrames = mediaManager.fileLoaderViewModel.FrameImageURLs.count
        guard totalFrames > 0 else { return [] }

        var results: [FlightHeightData] = []
        
        guard let imageSize = mediaManager.currentFrameImage?.size else { return [] }
        // Paste this before the for loop
        if let firstKeypoints = mediaManager.getKeypointsByIndex(0),
           firstKeypoints.count > 0 {

            let nose = firstKeypoints[0]

            print("🧠 DEBUG START --------------------")
            print("Nose raw y =", nose.y)
            print("Image height (px) =", imageSize.height)
            print("Bar top normalized y =", barTopNormalized.y)
            print("Span normalized =", calibration.referenceSpanNormalizedY ?? -1)
            print("cmPerNormalizedY =", calibration.cmPerNormalizedY ?? -1)
            print("🧠 DEBUG END ----------------------")
        }
        
        if let top = calibration.barTopPoint, let bottom = calibration.barBottomPoint {
            print("📍 Bar top normalized: \(top)")
            print("📍 Bar bottom normalized: \(bottom)")
//            print("📏 pixelsPerMeter: \(calibration.pixelsPerCm ?? -1)")
        }

        for frameIndex in 0..<totalFrames {
            guard let keypoints = mediaManager.getKeypointsByIndex(frameIndex),
                  keypoints.count >= 1 else { continue }

            // COCO index 0 = nose (head proxy)
            let nose = keypoints[0]

            // keypoints x/y are normalized (0-1) based on your KeypointData struct usage
            let headY = Double(nose.y)
            let barTopY = Double(barTopNormalized.y)

            // In image coords: smaller Y = higher up
            // positive diff = head is above bar top
//            let normalizedDiff = barTopY - headY

            // Convert to meters using the calibration scale
            // calibration is based on vertical pixel span between barTop and barBottom
//            let cmAboveBar: Double?
//            let cmAboveBar = calibration.normalizedYDiffToCm(normalizedDiff)
            let normalizedDiff = barTopY - headY     // + => above bar
            let cmAboveBar = calibration.normalizedYDiffToCm(normalizedDiff)

            
            results.append(FlightHeightData(
                frameIndex: frameIndex,
                headY: headY,
                barTopY: barTopY,
                normalizedDiff: normalizedDiff,
                cmAboveBar: cmAboveBar
            ))
        }
        
        let sample = results.prefix(5)
        for entry in sample {
            print("🏅 Frame \(entry.frameIndex) — headY: \(String(format: "%.3f", entry.headY)), barTopY: \(String(format: "%.3f", entry.barTopY)), height: \(String(format: "%.3f", entry.cmAboveBar ?? -99))cm")
        }
        if let max = maxFlightHeight(results) {
            print("🏆 Max flight: \(String(format: "%.3f", max.cmAboveBar ?? -99))cm at frame \(max.frameIndex)")
        }

        return results
    }

    static func maxFlightHeight(_ data: [FlightHeightData]) -> FlightHeightData? {
        return data.max(by: {
            ($0.cmAboveBar ?? -999) < ($1.cmAboveBar ?? -999)
        })
    }
}
