// ManualAnnotationVM.swift

import Foundation
import SwiftUI
import Combine

@Observable
final class ManualAnnotationVM {

    // MARK: - Annotation points (keyed by frame index)
    var annotationsByFrame: [Int: [AnnotationPoint]] = [:]

    // MARK: - Measurements (keyed by annotation ID)
    var measurements: [UUID: ManualMeasurementResult] = [:]

    // MARK: - Depth visualisation
    var depthColormapImage: UIImage?
    var isLoadingDepth: Bool = false

    // MARK: - Depth loader
    let depthLoader = DepthFrameLoader()

    var depthWidth:  Int = 256
    var depthHeight: Int = 192

    // ✅ Track the in-flight load task so we can cancel stale ones
    private var loadTask: Task<Void, Never>?

    // MARK: - Configuration

    func configure(recordingFolderURL: URL) {
        loadTask?.cancel()
        loadTask = nil
        annotationsByFrame.removeAll()
        measurements.removeAll()
        depthColormapImage = nil
        depthLoader.configure(recordingFolderURL: recordingFolderURL)
    }

    var isLiDARAvailable: Bool { depthLoader.isAvailable }

    // MARK: - Add / remove points

    func addPoint(_ point: AnnotationPoint) {
        annotationsByFrame[point.frameIndex, default: []].append(point)
    }

    func removePoint(id: UUID, frameIndex: Int) {
        annotationsByFrame[frameIndex]?.removeAll { $0.id == id }
        measurements.removeValue(forKey: id)
    }

    func clearFrame(_ frameIndex: Int) {
        let ids = annotationsByFrame[frameIndex]?.map(\.id) ?? []
        ids.forEach { measurements.removeValue(forKey: $0) }
        annotationsByFrame.removeValue(key: frameIndex)
    }

    func allPoints() -> [AnnotationPoint] {
        annotationsByFrame.values.flatMap { $0 }.sorted { $0.frameIndex < $1.frameIndex }
    }

    // MARK: - Compute measurement for a point

    func computeMeasurement(
        for point: AnnotationPoint,
        calibration: CalibrationModel
    ) async {
        let depthAtPoint: Float?
        let depthAtBarTop: Float?

        if depthLoader.isAvailable,
           let barTopNorm = calibration.barTopPoint {
            async let dPoint = depthLoader.depth(
                at: CGPoint(x: point.normalizedX, y: point.normalizedY),
                frameIndex: point.frameIndex,
                width: depthWidth,
                height: depthHeight
            )
            async let dBar = depthLoader.depth(
                at: barTopNorm,
                frameIndex: point.frameIndex,
                width: depthWidth,
                height: depthHeight
            )
            depthAtPoint  = await dPoint
            depthAtBarTop = await dBar
        } else {
            depthAtPoint  = nil
            depthAtBarTop = nil
        }

        let result = ManualAnnotationCalculator.compute(
            point: point,
            calibration: calibration,
            depthAtPoint: depthAtPoint,
            depthAtBarTop: depthAtBarTop
        )

        await MainActor.run {
            self.measurements[point.id] = result
        }
    }

    // MARK: - Load depth colourmap for a frame

    func loadDepthColormap(frameIndex: Int) async {
        guard depthLoader.isAvailable else { return }

        // ✅ Cancel any in-flight load — only the latest frame matters
        loadTask?.cancel()

        loadTask = Task {
            // ✅ Mark loading ONLY after a short delay — avoids spinner flash
            //    when the frame is already cached (near-instant)
            let spinnerTask = Task {
                try? await Task.sleep(nanoseconds: 80_000_000) // 80ms
                guard !Task.isCancelled else { return }
                await MainActor.run { self.isLoadingDepth = true }
            }

            let frame = await depthLoader.loadFrame(
                frameIndex,
                width: depthWidth,
                height: depthHeight
            )

            // Cancel the spinner if we finished before it fired
            spinnerTask.cancel()

            guard !Task.isCancelled else { return }

            let image: UIImage? = frame.flatMap { MetalJETRenderer.shared?.render(frame: $0) }
                               ?? frame.flatMap { depthLoader.renderColormap(frame: $0) }

            await MainActor.run {
                if depthLoader.frameWidth > 0 {
                    depthWidth  = depthLoader.frameWidth
                    depthHeight = depthLoader.frameHeight
                }
                // ✅ Only replace image if we actually got one — keeps last-good
                //    frame visible if the new one fails or is nil
                if image != nil {
                    depthColormapImage = image
                }
                isLoadingDepth = false
            }
        }

        await loadTask?.value
    }

    // MARK: - Pre-fetch (silent, no UI side-effects)

    func prefetchDepthColormap(frameIndex: Int) async {
        guard isLiDARAvailable, frameIndex >= 0 else { return }
        _ = await depthLoader.loadFrame(
            frameIndex,
            width: depthWidth,
            height: depthHeight
        )
    }
}

// MARK: - Dictionary helper

private extension Dictionary {
    mutating func removeValue(key: Key) { removeValue(forKey: key) }
}
