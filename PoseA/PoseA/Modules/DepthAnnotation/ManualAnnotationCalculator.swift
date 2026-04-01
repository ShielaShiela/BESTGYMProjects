// ManualAnnotationCalculator.swift
// Computes the three height measurement variants for a manually annotated point.

import Foundation
import CoreGraphics

final class ManualAnnotationCalculator {

    // MARK: - Main entry point

    /// Compute all three height measurements for a single annotation point.
    ///
    /// - Parameters:
    ///   - point:           The user-placed annotation (normalised 0–1 coords).
    ///   - calibration:     The CalibrationModel (must be calibrated).
    ///   - depthAtPoint:    Depth from the LiDAR bin file at the annotation pixel (metres). Nil if no LiDAR.
    ///   - depthAtBarTop:   Depth from the LiDAR bin file at the bar-top calibration pixel (metres). Nil → use assumed 8.3 m.
    static func compute(
        point: AnnotationPoint,
        calibration: CalibrationModel,
        depthAtPoint: Float?,
        depthAtBarTop: Float?
    ) -> ManualMeasurementResult {

        guard calibration.isCalibrated,
              let barTopNorm = calibration.barTopPoint else {
            return ManualMeasurementResult(
                id: point.id,
                frameIndex: point.frameIndex,
                label: point.label,
                pointNormY: point.normalizedY,
                cm2D: nil,
                cm2DWithDepthAssumption: nil,
                cm3D: nil,
                rawDepthAtPoint: depthAtPoint,
                depthAtBarTop: depthAtBarTop
            )
        }

        let barTopNormY = Double(barTopNorm.y)
        // In image coords: smaller Y = higher up.
        // Positive diff = annotation is above bar top.
        let normDiff = barTopNormY - point.normalizedY

        // ── Method 1: Pure 2D ────────────────────────────────────────────────
        let cm2D = calibration.normalizedYDiffToCm(normDiff)

        // ── Method 2: 2D + depth assumption ─────────────────────────────────
        // The calibration ruler is on the bar plane at ~8.3 m.
        // The gymnast's CoM is ~1.6 m further (arms/body). We scale the
        // apparent pixel height by the ratio: subjectDepth / barDepth.
        // This corrects for the perspective foreshortening of a body that is
        // further from the camera than the bar.
        let cm2DAssumption: Double?
        if let cm = cm2D {
            let scale = Double(DepthConstants.subjectDepthMetres) /
                        Double(DepthConstants.barDepthMetres)
            cm2DAssumption = cm * scale
        } else {
            cm2DAssumption = nil
        }

        // ── Method 3: Full 3D LiDAR ──────────────────────────────────────────
        // Formula:
        //   Δy_pixels     = normDiff * imagePixelHeight
        //   pixelsPerMetre (at bar plane) from calibration
        //   physical_height_at_bar_plane = Δy_pixels / pixelsPerMetre
        //   depth_subject = depthAtPoint  (from bin)
        //   depth_bar     = depthAtBarTop (from bin) or 8.3 m
        //   3D_height = physical_height_at_bar_plane * (depth_subject / depth_bar)
        let cm3D: Double?
        if let cm = cm2D {
            let dSubject = Double(depthAtPoint  ?? DepthConstants.subjectDepthMetres)
            let dBar     = Double(depthAtBarTop ?? DepthConstants.barDepthMetres)
            if dBar > 0.01 && dSubject > 0.01 {
                cm3D = cm * (dSubject / dBar)
            } else {
                cm3D = nil
            }
        } else {
            cm3D = nil
        }

        return ManualMeasurementResult(
            id: point.id,
            frameIndex: point.frameIndex,
            label: point.label,
            pointNormY: point.normalizedY,
            cm2D: cm2D,
            cm2DWithDepthAssumption: cm2DAssumption,
            cm3D: cm3D,
            rawDepthAtPoint: depthAtPoint,
            depthAtBarTop: depthAtBarTop
        )
    }
}
