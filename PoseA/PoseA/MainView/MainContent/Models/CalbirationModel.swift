//
//  CalbirationModel.swift
//  PoseA
//
//  Created by Shiela Cabahug on 2026/2/19.
//
import SwiftUI

@Observable
class CalibrationModel {
    var barTopPoint: CGPoint?
    var barBottomPoint: CGPoint?

    // Real-world reference
    var realBarHeightCm: Double = 260

    var isCalibrationMode: Bool = false
    var calibrationStep: CalibrationStep = .idle

    enum CalibrationStep {
        case idle
        case selectingBarTop
        case selectingBarBottom
        case complete
    }

    /// Vertical span in normalized image coordinates (0..1)
    var referenceSpanNormalizedY: Double? {
        guard let top = barTopPoint, let bottom = barBottomPoint else { return nil }
        let span = abs(Double(bottom.y - top.y))
        return span > 0 ? span : nil
    }

    /// Main scale you should use everywhere for height: cm per 1.0 normalized Y
    var cmPerNormalizedY: Double? {
        guard let spanN = referenceSpanNormalizedY else { return nil }
        return realBarHeightCm / spanN
    }

    /// Optional: for displaying "px/cm" in UI (requires image height in pixels)
    func pixelsPerCm(imagePixelHeight: Double) -> Double? {
        guard let spanN = referenceSpanNormalizedY else { return nil }
        let spanPx = spanN * imagePixelHeight
        return spanPx / realBarHeightCm
    }

    var isCalibrated: Bool { cmPerNormalizedY != nil }

    func reset() {
        barTopPoint = nil
        barBottomPoint = nil
        calibrationStep = .idle
        isCalibrationMode = false
    }

    func startCalibration() {
        barTopPoint = nil
        barBottomPoint = nil
        isCalibrationMode = true
        calibrationStep = .selectingBarTop
    }

    /// Convert a normalized Y difference into cm (THIS is what FlightHeight should use)
    func normalizedYDiffToCm(_ normalizedDiffY: Double) -> Double? {
        guard let scale = cmPerNormalizedY else { return nil }
        return normalizedDiffY * scale
    }

    // Save/load unchanged
    var toDictionary: [String: Any] {
        var dict: [String: Any] = ["realBarHeightCm": realBarHeightCm]
        if let top = barTopPoint { dict["barTopPoint"] = ["x": top.x, "y": top.y] }
        if let bottom = barBottomPoint { dict["barBottomPoint"] = ["x": bottom.x, "y": bottom.y] }
        return dict
    }

    func load(from dict: [String: Any]) {
        realBarHeightCm = dict["realBarHeightCm"] as? Double ?? 260
        if let topDict = dict["barTopPoint"] as? [String: Double],
           let x = topDict["x"], let y = topDict["y"] {
            barTopPoint = CGPoint(x: x, y: y)
        }
        if let bottomDict = dict["barBottomPoint"] as? [String: Double],
           let x = bottomDict["x"], let y = bottomDict["y"] {
            barBottomPoint = CGPoint(x: x, y: y)
        }
        calibrationStep = isCalibrated ? .complete : .idle
    }
}
