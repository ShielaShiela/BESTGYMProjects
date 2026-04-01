import SwiftUI

// MARK: - CalibrationModel + Quad Mode Integration
//
// Drop this file next to CalibrationModel.swift.
// It adds a `quadCalibration` property and a unified
// `effectiveCmPerNormalizedY` accessor that FlightHeightView
// (and any other consumer) can use without caring which mode
// is active.
// Replace the extension with this complete version

extension CalibrationModel {

    enum CalibrationSource: String {
        case none
        case twoPoint
        case quad
    }

    var activeCalibrationSource: CalibrationSource {
        get {
            let raw = UserDefaults.standard.string(forKey: "calibrationSource") ?? "twoPoint"
            return CalibrationSource(rawValue: raw) ?? .twoPoint
        }
        set {
            let savedBarTop = barTopPoint       // capture before anything changes
            let savedBarBottom = barBottomPoint
            UserDefaults.standard.set(newValue.rawValue, forKey: "calibrationSource")
            // Always restore — these points are source-independent
            barTopPoint = savedBarTop
            barBottomPoint = savedBarBottom
        }
    }
    
    // Convenience — used by CalibrationOverlayView guard
    var isTwoPointCalibrationMode: Bool {
        isCalibrationMode && activeCalibrationSource == .twoPoint
    }

    func effectiveCmPerNormalizedY(quad: QuadCalibrationModel) -> Double? {
        switch activeCalibrationSource {
        case .twoPoint, .none: return cmPerNormalizedY
        case .quad:            return quad.cmPerNormalizedY
        }
    }

    func effectiveNormalizedYDiffToCm(_ diff: Double, quad: QuadCalibrationModel) -> Double? {
        guard let scale = effectiveCmPerNormalizedY(quad: quad) else { return nil }
        return diff * scale   // keep sign: positive = above bar, negative = below bar
    }
    func calibrationDescription(quad: QuadCalibrationModel) -> String {
        switch activeCalibrationSource {
        case .none:
            return "Not calibrated"
        case .twoPoint:
            guard isCalibrated else { return "Not calibrated" }
            return String(format: "Bar ref  %.0f cm  (2-pt)", realBarHeightCm)
        case .quad:
            guard quad.isCalibrated else { return "Quad not calibrated" }
            return String(format: "Quad ref  %.0f × %.0f cm",
                          quad.realWidthCm, quad.realHeightCm)
        }
    }
}
