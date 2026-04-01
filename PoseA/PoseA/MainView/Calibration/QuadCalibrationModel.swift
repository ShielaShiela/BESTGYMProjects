import SwiftUI

// MARK: - QuadCalibrationModel

/// A 4-point planar reference calibration.
/// The user places four corners of a known real-world rectangle
/// (e.g. a mat, a board, a court line) and inputs its real dimensions.
/// This gives independent cm/normalizedUnit scales for X and Y,
/// which FlightHeightView can use instead of the 2-point bar calibration.
@Observable
class QuadCalibrationModel {

    // MARK: - Stored state

    /// Four corners in normalized image coordinates (0…1, 0…1).
    /// Order: topLeft, topRight, bottomRight, bottomLeft  (clockwise)
    var corners: [CGPoint] = []

    /// Real-world size of the reference rectangle
    var realWidthCm:  Double = 100
    var realHeightCm: Double = 100

    var isQuadCalibrationMode: Bool = false

    enum Step { case idle, placing, inputtingDimensions, complete }
    var step: Step = .idle

    // MARK: - Derived scale

    /// Average pixel width of the quad (normalized 0…1 units)
    var normalizedWidthSpan: Double? {
        guard corners.count == 4 else { return nil }
        let topW    = abs(Double(corners[1].x - corners[0].x))
        let bottomW = abs(Double(corners[2].x - corners[3].x))
        let avg = (topW + bottomW) / 2
        return avg > 0 ? avg : nil
    }

    /// Average pixel height of the quad (normalized 0…1 units)
    var normalizedHeightSpan: Double? {
        guard corners.count == 4 else { return nil }
        let leftH  = abs(Double(corners[3].y - corners[0].y))
        let rightH = abs(Double(corners[2].y - corners[1].y))
        let avg = (leftH + rightH) / 2
        return avg > 0 ? avg : nil
    }

    /// cm per 1.0 of normalized X
    var cmPerNormalizedX: Double? {
        guard let span = normalizedWidthSpan else { return nil }
        return realWidthCm / span
    }

    /// cm per 1.0 of normalized Y  (use this like CalibrationModel.cmPerNormalizedY)
    var cmPerNormalizedY: Double? {
        guard let span = normalizedHeightSpan else { return nil }
        return realHeightCm / span
    }

    var isCalibrated: Bool { cmPerNormalizedY != nil && cmPerNormalizedX != nil }

    // MARK: - Mutations

    func addCorner(_ point: CGPoint) {
        guard corners.count < 4 else { return }
        corners.append(point)
        if corners.count == 4 { step = .inputtingDimensions }
    }

    func moveCorner(index: Int, to point: CGPoint) {
        guard corners.indices.contains(index) else { return }
        corners[index] = point
    }

    func reset() {
        corners = []
        step = .idle
        isQuadCalibrationMode = false
    }

    func startPlacing() {
        corners = []
        step = .placing
        isQuadCalibrationMode = true
    }

    func confirmDimensions() {
        guard corners.count == 4 else { return }
        step = .complete
    }

    // MARK: - Convert a normalised Y-difference to cm (mirrors CalibrationModel API)

    func normalizedYDiffToCm(_ normalizedDiffY: Double) -> Double? {
        guard let scale = cmPerNormalizedY else { return nil }
        return normalizedDiffY * scale
    }

    func normalizedXDiffToCm(_ normalizedDiffX: Double) -> Double? {
        guard let scale = cmPerNormalizedX else { return nil }
        return normalizedDiffX * scale
    }

    // MARK: - Persistence helpers

    var toDictionary: [String: Any] {
        var dict: [String: Any] = [
            "realWidthCm": realWidthCm,
            "realHeightCm": realHeightCm
        ]
        dict["corners"] = corners.map { ["x": Double($0.x), "y": Double($0.y)] }
        return dict
    }

    func load(from dict: [String: Any]) {
        realWidthCm  = dict["realWidthCm"]  as? Double ?? 100
        realHeightCm = dict["realHeightCm"] as? Double ?? 100
        if let arr = dict["corners"] as? [[String: Double]] {
            corners = arr.compactMap { d in
                guard let x = d["x"], let y = d["y"] else { return nil }
                return CGPoint(x: x, y: y)
            }
        }
        step = isCalibrated ? .complete : .idle
    }

    // MARK: - UserDefaults persistence

    private enum UDKey {
        static let prefix = "quadCal_"
        static let hasCalibration = "quadCal_hasCalibration"
        static let realWidthCm    = "quadCal_realWidthCm"
        static let realHeightCm   = "quadCal_realHeightCm"
        static let corners        = "quadCal_corners"
    }

    func saveToUserDefaults() {
        let ud = UserDefaults.standard
        guard corners.count == 4 else {
            ud.set(false, forKey: UDKey.hasCalibration)
            return
        }
        ud.set(true, forKey: UDKey.hasCalibration)
        ud.set(realWidthCm,  forKey: UDKey.realWidthCm)
        ud.set(realHeightCm, forKey: UDKey.realHeightCm)
        let arr = corners.map { ["x": Double($0.x), "y": Double($0.y)] }
        ud.set(arr, forKey: UDKey.corners)
    }

    func loadFromUserDefaults() {
        let ud = UserDefaults.standard
        guard ud.bool(forKey: UDKey.hasCalibration) else { return }
        realWidthCm  = ud.double(forKey: UDKey.realWidthCm)
        realHeightCm = ud.double(forKey: UDKey.realHeightCm)
        if realWidthCm  == 0 { realWidthCm  = 100 }
        if realHeightCm == 0 { realHeightCm = 100 }
        if let arr = ud.array(forKey: UDKey.corners) as? [[String: Double]] {
            corners = arr.compactMap { d in
                guard let x = d["x"], let y = d["y"] else { return nil }
                return CGPoint(x: x, y: y)
            }
        }
        step = isCalibrated ? .complete : .idle
    }
}
