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

    
    // In CalibrationModel — replace startCalibration() with these two clean methods:

    func startTwoPointCalibration() {
        isCalibrationMode = true
        // Only restart from scratch if not yet complete — preserve existing points
        if calibrationStep != .complete {
            barTopPoint = nil
            barBottomPoint = nil
            calibrationStep = .selectingBarTop
        }
        // If already complete, just re-open overlay without wiping — user can adjust
    }

    func exitCalibrationMode() {
        isCalibrationMode = false
        if calibrationStep == .selectingBarBottom || calibrationStep == .complete {
            calibrationStep = .complete
        }
    }
    // Add a separate method for explicitly redoing 2-point
    func restartTwoPointCalibration() {
        barTopPoint = nil
        barBottomPoint = nil
        calibrationStep = .selectingBarTop
        isCalibrationMode = true
    }

    /// Convert a normalized Y difference into cm (THIS is what FlightHeight should use)
    func normalizedYDiffToCm(_ normalizedDiffY: Double) -> Double? {
        guard let scale = cmPerNormalizedY else { return nil }
        return normalizedDiffY * scale   // ← abs() kills the sign
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


// CalibrationPersistence.swift
extension CalibrationModel {

    // MARK: - UserDefaults keys

    private enum UDKey {
        static let barTopX       = "cal_barTopX"
        static let barTopY       = "cal_barTopY"
        static let barBottomX    = "cal_barBottomX"
        static let barBottomY    = "cal_barBottomY"
        static let realBarHeight = "cal_realBarHeightCm"
        static let hasCalibration = "cal_hasCalibration"
    }

    // MARK: - Save to UserDefaults

    func saveToUserDefaults() {
        let ud = UserDefaults.standard
        guard let top = barTopPoint, let bottom = barBottomPoint else {
            ud.set(false, forKey: UDKey.hasCalibration)
            return
        }
        ud.set(true,            forKey: UDKey.hasCalibration)
        ud.set(Double(top.x),   forKey: UDKey.barTopX)
        ud.set(Double(top.y),   forKey: UDKey.barTopY)
        ud.set(Double(bottom.x),forKey: UDKey.barBottomX)
        ud.set(Double(bottom.y),forKey: UDKey.barBottomY)
        ud.set(realBarHeightCm, forKey: UDKey.realBarHeight)
    }

    // MARK: - Load from UserDefaults

    func loadFromUserDefaults() {
        let ud = UserDefaults.standard
        guard ud.bool(forKey: UDKey.hasCalibration) else { return }
        barTopPoint    = CGPoint(x: ud.double(forKey: UDKey.barTopX),
                                 y: ud.double(forKey: UDKey.barTopY))
        barBottomPoint = CGPoint(x: ud.double(forKey: UDKey.barBottomX),
                                 y: ud.double(forKey: UDKey.barBottomY))
        realBarHeightCm = ud.double(forKey: UDKey.realBarHeight)
        if realBarHeightCm == 0 { realBarHeightCm = 260 }
        calibrationStep = isCalibrated ? .complete : .idle
    }

    // MARK: - Write calibration block into an existing metadata JSON file

    /// Call this right after a recording finishes.
    /// `metadataURL` points to the `recording_metadata.json` file that
    /// `CameraManagerVM` already writes.  If the file doesn't exist yet
    /// we create it.  The calibration block is merged in (or added) under
    /// the key `"calibration"`.
    func writeToMetadata(at metadataURL: URL) {
        var root: [String: Any] = [:]

        // Read existing metadata if present
        if let data = try? Data(contentsOf: metadataURL),
           let existing = try? JSONSerialization.jsonObject(with: data) as? [String: Any] {
            root = existing
        }

        root["calibration"] = toDictionary
        root["calibrationStep"] = calibrationStep == .complete ? "complete" : "idle"

        if let data = try? JSONSerialization.data(withJSONObject: root,
                                                  options: .prettyPrinted) {
            try? data.write(to: metadataURL, options: .atomic)
        }
    }

    // MARK: - Read calibration from metadata JSON

    /// Returns `true` if calibration data was found and loaded.
    @discardableResult
    func readFromMetadata(at metadataURL: URL) -> Bool {
        guard let data = try? Data(contentsOf: metadataURL),
              let root = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let calDict = root["calibration"] as? [String: Any] else { return false }
        load(from: calDict)
        return isCalibrated
    }
}
