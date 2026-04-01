// ManualAnnotationData.swift
// BESTGYM — Manual height annotation with 2D, 2D+depth assumption, and 3D LiDAR measurement

import Foundation
import CoreGraphics

// MARK: - A single user-placed annotation point

struct AnnotationPoint: Identifiable, Codable {
    let id: UUID
    var frameIndex: Int
    /// Normalized (0–1) position in the display image coordinate space
    var normalizedX: Double
    var normalizedY: Double
    var label: String

    init(id: UUID = UUID(), frameIndex: Int, normalizedX: Double, normalizedY: Double, label: String = "") {
        self.id = id
        self.frameIndex = frameIndex
        self.normalizedX = normalizedX
        self.normalizedY = normalizedY
        self.label = label
    }
}

// MARK: - Measurement result for one annotation point

struct ManualMeasurementResult: Identifiable {
    let id: UUID
    let frameIndex: Int
    let label: String

    /// Normalized Y of the annotated point
    let pointNormY: Double

    // ── Method 1: Pure 2D (pixel-based) ─────────────────────────────────────
    /// cm above bar, computed purely from normalised-Y pixel ratio + calibration
    let cm2D: Double?

    // ── Method 2: 2D + Depth Assumption ─────────────────────────────────────
    /// The bar is assumed to be at 8.3 m from camera, subject at 8.3 + 1.6 = 9.9 m.
    /// We scale the pixel measurement by the depth ratio to correct perspective.
    let cm2DWithDepthAssumption: Double?

    // ── Method 3: 3D LiDAR ──────────────────────────────────────────────────
    /// Uses actual depth from the depth bin at the tapped pixel.
    /// Bar top depth from LiDAR is used as the reference (defaults to 8.3 m if nil).
    let cm3D: Double?

    /// Raw depth value read from the LiDAR depth frame at the annotation pixel (metres)
    let rawDepthAtPoint: Float?

    /// Depth at the bar top (metres), from LiDAR or assumed 8.3 m
    let depthAtBarTop: Float?
}

// MARK: - Constants

enum DepthConstants {
    /// Assumed distance from camera to horizontal bar (metres)
    static let barDepthMetres: Float = 8.3
    /// Assumed extra depth from bar to subject body (metres)
    static let subjectExtraDepthMetres: Float = 1.6
    /// Combined assumed subject depth
    static let subjectDepthMetres: Float = barDepthMetres + subjectExtraDepthMetres
}
