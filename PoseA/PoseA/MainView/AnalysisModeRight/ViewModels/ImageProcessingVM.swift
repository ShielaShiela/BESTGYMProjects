//
//  ImageProcessingVM.swift
//  PoseA
//
//  Created by Ardhika Maulidani on 11/7/25.
//

import SwiftUI
import CoreGraphics

@Observable
class ImageProcessingVM {
    // MARK: - Properties
    var mediaManager: MediaManagerVM

    // MARK: - Output Variable
    private var processedKeypoints: [Int: PoseBox] = [:]
    private var processedCoM: [Int: CGPoint] = [:]
    
    // MARK: - Image Processing Custom Settings
    private let batchSize = 10
    private var ROI: CGRect = .zero
    private var keypointKalmanFilters: [KalmanFilter2D] = []
    private var comKalmanFilter: KalmanFilter2D
    private let confidenceThreshold: Float = 0.025
    private var comDistanceThreshold: Double = 108.0
    private var frameInterval: Double = 1.0 / 30.0

    // MARK: - Initialization
    init(mediaManager: MediaManagerVM) {
        self.mediaManager = mediaManager
        self.keypointKalmanFilters = (0..<17).map { _ in KalmanFilter2D(dt: 1.0 / 30.0) }
        self.comKalmanFilter = KalmanFilter2D(dt: 1.0 / 30.0)
        self.updateFrameInterval()
    }

    private func updateFrameInterval() {
        if mediaManager.isMediaAvailable {
            self.frameInterval = mediaManager.mediaPlayerVM.frameInterval
            self.keypointKalmanFilters = (0..<17).map { _ in KalmanFilter2D(dt: frameInterval) }
            self.comKalmanFilter = KalmanFilter2D(dt: frameInterval)
            let videoHeight = Double(mediaManager.importFileVM.mediaMetadata?.resolution.width ?? 1080)
            self.comDistanceThreshold = 0.1 * videoHeight
        }
    }

    // MARK: - Processing
    func resetKalmanFilters() {
        keypointKalmanFilters = (0..<17).map { _ in KalmanFilter2D(dt: frameInterval) }
        comKalmanFilter = KalmanFilter2D(dt: frameInterval)
    }

    func setROI(rect: CGRect) { self.ROI = rect }
    
    func process(onProgress: @escaping @Sendable (Double) async -> Void) async throws {
        guard mediaManager.isMediaAvailable else {
            throw PipelineError.mediaUnavailable
        }
        updateFrameInterval()

        var currentBatch = 0
        let totalFrames  = mediaManager.mediaPlayerVM.totalFrames
        let totalBatches = Int(ceil(Double(totalFrames) / Double(batchSize)))

        for batchIndex in 0..<totalBatches {
            let startFrame = batchIndex * batchSize
            let endFrame   = min(startFrame + batchSize, totalFrames)

            let (processedCount, failedIndices) = await self.batchProcess(
                startFrame: startFrame,
                endFrame: endFrame
            )
            _ = processedCount
            _ = failedIndices

            currentBatch += 1

            await onProgress(Double(currentBatch) / Double(totalBatches))
        }

        await MainActor.run {
            mediaManager.updateKeypointsData(processedKeypoints, source: .processing)
            mediaManager.updateCoMData(processedCoM, source: .processing)
        }
    }

    private func batchProcess(startFrame: Int, endFrame: Int) async -> (Int, [Int]) {
        var batchProcessedFrames = 0
        var batchFailedFrames: [Int] = []

        for frameIndex in startFrame..<endFrame {
            guard let frameImage = await mediaManager.mediaPlayerVM.moveToFrameAsync(frameIndex) else {
                log("Error loading image at index \(frameIndex)", level: .warn)
                batchFailedFrames.append(frameIndex)
                continue
            }
            let cgImg = frameImage.cgImage!
            let (imageToProcess, roiOffset) = self.cropImageToROI(cgImg, roiRect: self.ROI) ?? (cgImg, .zero)

            let detectionResults = await withCheckedContinuation { continuation in
                YOLOPoseProcessor.shared.offlineProcess(inputImg: imageToProcess) { result in
                    continuation.resume(returning: result)
                }
            }

            let processedPose = await detectionSynthesis(
                detectionResults: detectionResults,
                roiOffset: roiOffset,
                frameIndex: frameIndex
            )

            if let pose = processedPose {
                self.processedKeypoints[frameIndex] = pose
                batchProcessedFrames += 1
            } else {
                log("No pose processed for frame \(frameIndex)", level: .warn)
                batchFailedFrames.append(frameIndex)
            }
        }
        return (batchProcessedFrames, batchFailedFrames)
    }

    private func detectionSynthesis(
        detectionResults: [PoseBox],
        roiOffset: CGPoint,
        frameIndex: Int
    ) async -> PoseBox? {

        // ── CoM KF: single predict ─────────────────────────────────────────────
        let predictedCoM = comKalmanFilter.initialized ? comKalmanFilter.predict() : nil

        let (bestPose, candidateCoM, poseMissing) = selectBestDetection(
            detections: detectionResults,
            predictedCoM: predictedCoM,
            roiOffset: roiOffset
        )

        var finalKeypoints: [KeypointData] = []
        var finalBbox: CGRect = .zero
        var finalConfidence: Float = 0.0

        // ── CoM KF: single update ──────────────────────────────────────────────
        var trackedCoM: CGPoint
        if !poseMissing, let candidateCoM = candidateCoM {
            trackedCoM = comKalmanFilter.update(x: Double(candidateCoM.x), y: Double(candidateCoM.y))
        } else {
            trackedCoM = predictedCoM ?? .zero
        }

        // ── Per-keypoint KF ────────────────────────────────────────────────────
        if !poseMissing, let pose = bestPose {
            finalBbox       = pose.bbox
            finalConfidence = pose.confidence

            for (index, keypoint) in pose.keypoints.enumerated() {
                let kf = keypointKalmanFilters[index]
                let adjustedKeypoint = KeypointData(
                    name: keypoint.name,
                    x: keypoint.x + roiOffset.x,
                    y: keypoint.y + roiOffset.y,
                    confidence: keypoint.confidence,
                    depth: keypoint.depth,
                    frameIndex: frameIndex
                )
                let filteredPosition: CGPoint
                if adjustedKeypoint.confidence > confidenceThreshold {
                    if kf.initialized { _ = kf.predict() }
                    filteredPosition = kf.update(x: Double(adjustedKeypoint.x), y: Double(adjustedKeypoint.y))
                } else {
                    filteredPosition = kf.predict() ?? CGPoint(x: Double(adjustedKeypoint.x), y: Double(adjustedKeypoint.y))
                }
                finalKeypoints.append(KeypointData(
                    name: adjustedKeypoint.name,
                    x: filteredPosition.x,
                    y: filteredPosition.y,
                    confidence: adjustedKeypoint.confidence,
                    depth: adjustedKeypoint.depth,
                    frameIndex: frameIndex
                ))
            }
            finalBbox = CGRect(
                x: pose.bbox.origin.x + roiOffset.x,
                y: pose.bbox.origin.y + roiOffset.y,
                width: pose.bbox.size.width,
                height: pose.bbox.size.height
            )
        } else {
            log("Frame \(frameIndex): pose missing, predicting all keypoints from KF", level: .debug)
            for (index, kf) in keypointKalmanFilters.enumerated() {
                let predictedPosition = kf.predict() ?? .zero
                finalKeypoints.append(KeypointData(
                    name: keypointNames[index],
                    x: predictedPosition.x,
                    y: predictedPosition.y,
                    confidence: 0.0,
                    depth: 0.0,
                    frameIndex: frameIndex
                ))
            }
            if !finalKeypoints.isEmpty {
                let minX = finalKeypoints.map { $0.x }.min() ?? 0
                let maxX = finalKeypoints.map { $0.x }.max() ?? 0
                let minY = finalKeypoints.map { $0.y }.min() ?? 0
                let maxY = finalKeypoints.map { $0.y }.max() ?? 0
                finalBbox = CGRect(x: minX - 20, y: minY - 20, width: maxX - minX + 40, height: maxY - minY + 40)
            }
        }

        self.processedCoM[frameIndex] = trackedCoM
        return PoseBox(bbox: finalBbox, confidence: finalConfidence, keypoints: finalKeypoints)
    }

    private func selectBestDetection(
        detections: [PoseBox],
        predictedCoM: CGPoint?,
        roiOffset: CGPoint
    ) -> (bestPose: PoseBox?, candidateCoM: CGPoint?, poseMissing: Bool) {

        guard !detections.isEmpty else {
            return (nil, predictedCoM, true)
        }

        var candidates: [(PoseBox, CGPoint)] = []

        for (_, detection) in detections.enumerated() {
            let adjustedKeypoints = detection.keypoints.map { keypoint in
                KeypointData(
                    name: keypoint.name,
                    x: keypoint.x + roiOffset.x,
                    y: keypoint.y + roiOffset.y,
                    confidence: keypoint.confidence,
                    depth: keypoint.depth,
                    frameIndex: keypoint.frameIndex
                )
            }

            let com = CoMLevaModel.computePlanarCoM(keypoints: adjustedKeypoints, side: "left")
            candidates.append((detection, com))
        }

        guard let predictedCoM = predictedCoM else {
            let (bestPose, bestCoM) = candidates.first!
            return (bestPose, bestCoM, false)
        }

        let (bestPose, bestCoM) = candidates.min { a, b in
            predictedCoM.distance(to: a.1) < predictedCoM.distance(to: b.1)
        }!

        let dist = predictedCoM.distance(to: bestCoM)
        
        // CoM too far, fallback
        if dist > comDistanceThreshold {
            return (nil, predictedCoM, true)
        }
        return (bestPose, bestCoM, false)
    }

    // MARK: - Image Cropping to ROI
    private func cropImageToROI(_ cgImage: CGImage, roiRect: CGRect) -> (croppedImage: CGImage, roiOffset: CGPoint)? {
        if roiRect != .zero {
            let imageSize = CGSize(width: cgImage.width, height: cgImage.height)
            let clampedROI = CGRect(
                x: max(0, min(roiRect.origin.x * imageSize.width, imageSize.width - 1)),
                y: max(0, min(roiRect.origin.y * imageSize.height, imageSize.height - 1)),
                width: min(roiRect.width * imageSize.width, imageSize.width - roiRect.origin.x),
                height: min(roiRect.height * imageSize.height, imageSize.height - roiRect.origin.y)
            )
            if let croppedCGImage = cgImage.cropping(to: clampedROI) {
                return (croppedCGImage, CGPoint(x: clampedROI.origin.x, y: clampedROI.origin.y))
            }
        }
        return (cgImage, .zero)
    }
}

// MARK: - ImageProcessing Export/Import Extension
extension ImageProcessingVM {
    func exportCoM(to fileURL: URL) throws {
        let comData = mediaManager.CoMData
        guard !comData.isEmpty else { return }
        
        let missingFrames = Set(
            mediaManager.keypointData
                .filter { _, pose in pose.keypoints.allSatisfy { $0.confidence == 0 } }
                .keys
        )
        
        try ExportImportManager.exportCoM(
            comData: comData,
            missingFrames: missingFrames,
            to: fileURL
        )
    }
    
    func exportKeypoints(to fileURL: URL, sourceInfo: [String: Any]? = nil) throws {
        let keypointsData = mediaManager.keypointData
        guard !keypointsData.isEmpty else { return }
        
        var frameBboxData: [String: [String: Any]] = [:]
        var framesKeyData: [String: [[String: Any]]] = [:]
        
        for (_, poseBox) in keypointsData {
            let keypointData = poseBox.keypoints.map { keypoint -> [String: Any] in
                ["name": keypoint.name, "x": keypoint.x, "y": keypoint.y,
                 "confidence": keypoint.confidence, "depth": keypoint.depth,
                 "frameIndex": keypoint.frameIndex]
            }
            var bboxData: [String: Any] = [:]
            bboxData["x"]          = poseBox.bbox.origin.x
            bboxData["y"]          = poseBox.bbox.origin.y
            bboxData["width"]      = poseBox.bbox.size.width
            bboxData["height"]     = poseBox.bbox.size.height
            bboxData["confidence"] = poseBox.confidence
            framesKeyData["frame_\(poseBox.keypoints.first!.frameIndex)"]    = keypointData
            frameBboxData["framebbox_\(poseBox.keypoints.first!.frameIndex)"] = bboxData
        }
        
        var exportData: [String: Any] = [
            "frames": framesKeyData, "frames_bbox": frameBboxData,
            "frameCount": keypointsData.count,
            "exportTime": Date().timeIntervalSince1970
        ]
        if let metadata = sourceInfo { exportData["metadata"] = metadata }
        let jsonData = try JSONSerialization.data(withJSONObject: exportData, options: .prettyPrinted)
        try jsonData.write(to: fileURL)
    }
}
