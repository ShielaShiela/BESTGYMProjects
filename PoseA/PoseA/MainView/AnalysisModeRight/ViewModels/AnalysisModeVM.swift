//
//  AnalysisModeVM.swift
//  PoseA
//
//  Created by Ardhika Maulidani on 11/7/25.
//

import SwiftUI
import CoreGraphics

@Observable
class AnalysisModeVM {
    // MARK: - Properties
    var poseProcessor: YOLOPoseProcessor
    var mediaManager: MediaManagerVM
    
    // Output
    var processedKeypoints: [PoseBox] = []
    var ROI: CGRect = .zero
    private let batchSize = 10                          // Process 10 frames at a time

    // MARK: - Initialization
    init(poseProcessor: YOLOPoseProcessor, mediaManager: MediaManagerVM) {
        self.poseProcessor = poseProcessor
        self.mediaManager = mediaManager
    }
    
    // MARK: - Processing Function
    func setROI(rect: CGRect) {
        self.ROI = rect
    }
    
    func process(
        progress: @escaping (Double) -> Void,
        completion: @escaping (Bool, Error?) -> Void
    ) async {
        guard mediaManager.isMediaAvailable else {
            await MainActor.run { completion(false, nil) }
            return
        }

        var currentBatch = 0
        var successFrames = 0
        var failedFrames: [Int] = []

        let totalFrames = mediaManager.mediaPlayerViewModel.totalFrames
        let totalBatches = Int(ceil(Double(totalFrames) / Double(batchSize)))

        for batchIndex in 0..<totalBatches {
            let startFrame = batchIndex * batchSize
            let endFrame = min(startFrame + batchSize, totalFrames)

            let (processedCount, failedIndices) = await self.batchProcess(
                startFrame: startFrame,
                endFrame: endFrame
            )

            successFrames += processedCount
            failedFrames.append(contentsOf: failedIndices)
            currentBatch += 1

            // Update progress
            let value = Double(currentBatch) / Double(totalBatches)
            await MainActor.run {
                progress(value)
            }
        }

        // Complete
        await MainActor.run {
            completion(true, nil)
        }
    }


    private func batchProcess(startFrame: Int, endFrame: Int) async -> (Int, [Int]) {
        var batchProcessedFrames = 0
        var batchFailedFrames:[Int] = []

        for frameIndex in startFrame..<endFrame {
            // Retrieve frame image
            guard let frameImage = await mediaManager.mediaPlayerViewModel.moveToFrameAsync(frameIndex) else {
                log("Error loading image at index \(frameIndex)", level: .warn)
                batchFailedFrames.append(frameIndex)
                continue
            }
            
            // Process frame for keypoints
            let cgImg = frameImage.cgImage!
            let (imageToProcess, roiOffset) = self.cropImageToROI(cgImg, roiRect: self.ROI) ?? (cgImg, .zero)
            
            // Convert callback-based API to async
            let result = await withCheckedContinuation { continuation in
                poseProcessor.offlineProcess(inputImg: imageToProcess) { result in
                    continuation.resume(returning: result)
                }
            }
            
            // Return to original image coordinates
            if !result.isEmpty {
                let detectedKeypoint = result.first!.keypoints
                let adjustedKeypoint = detectedKeypoint.map { jointData in
                    // Get Depth for each pose
                    let depth:Float = 0.0
                    if self.mediaManager.isDataLIDAR {
                        log("add depth for \(jointData.name)", level: .debug)
                    }
                    
                    // Adjust coordinates based on ROI offset
                    return KeypointData(name: jointData.name,
                                        x: jointData.x + CGFloat(roiOffset.x),
                                        y: jointData.y + CGFloat(roiOffset.y),
                                        confidence: jointData.confidence,
                                        depth: depth,
                                        frameIndex: frameIndex)
                }
                // Store results
                let adjustedBbox = CGRect(
                    x: result.first!.bbox.origin.x + roiOffset.x,
                    y: result.first!.bbox.origin.y + roiOffset.y,
                    width: result.first!.bbox.size.width,
                    height: result.first!.bbox.size.height
                )
                // Append All
                self.processedKeypoints.append(PoseBox(bbox: adjustedBbox,
                                                       confidence: result.first!.confidence,
                                                       keypoints: adjustedKeypoint))
                batchProcessedFrames += 1
            } else {
                log("No keypoints detected for frame \(frameIndex)", level: .warn)
                batchFailedFrames.append(frameIndex)
            }
        }
        return (batchProcessedFrames, batchFailedFrames)
    }

    // MARK: - Image Cropping to ROI
    private func cropImageToROI(_ cgImage: CGImage, roiRect: CGRect) -> (croppedImage: CGImage, roiOffset: CGPoint)? {
        // Ensure ROI is within image bounds
        let imageSize = CGSize(width: cgImage.width, height: cgImage.height)
        
        // Scale ROI
        let clampedROI = CGRect(
            x: max(0, min(roiRect.origin.x * imageSize.width, imageSize.width - 1)),
            y: max(0, min(roiRect.origin.y * imageSize.height, imageSize.height - 1)),
            width: min(roiRect.width * imageSize.width, imageSize.width - roiRect.origin.x),
            height: min(roiRect.height * imageSize.height, imageSize.height - roiRect.origin.y)
        )

        // Crop the image
        if let croppedCGImage = cgImage.cropping(to: clampedROI) {
            let roiOffset = CGPoint(x: clampedROI.origin.x, y: clampedROI.origin.y)
            return (croppedCGImage, roiOffset)
        }
        
        log("Error cropping image to ROI selection", level: .warn)
        return (cgImage, .zero)
    }
    
    // MARK: - File Operations
    func exportKeypoints(to fileURL: URL, sourceInfo: [String: Any]? = nil) throws {
        // Export all frames
        var frameBboxData: [String: [String: Any]] = [:]
        var framesKeyData: [String: [[String: Any]]] = [:]
        
        for poseBox in processedKeypoints {
            // Keypoint Data Parse
            let keypointData = poseBox.keypoints.map { keypoint -> [String: Any] in
                return [
                    "name": keypoint.name,
                    "x": keypoint.x,
                    "y": keypoint.y,
                    "confidence": keypoint.confidence,
                    "depth": keypoint.depth,
                    "frameIndex": keypoint.frameIndex
                ]
            }
            
            // BBox Data Parse
            var bboxData: [String: Any] = [:]
            bboxData["x"] = poseBox.bbox.origin.x
            bboxData["y"] = poseBox.bbox.origin.y
            bboxData["width"] = poseBox.bbox.size.width
            bboxData["height"] = poseBox.bbox.size.height
            bboxData["confidence"] = poseBox.confidence
            
            framesKeyData["frame_\(poseBox.keypoints.first!.frameIndex)"] = keypointData
            frameBboxData["framebbox_\(poseBox.keypoints.first!.frameIndex)"] = bboxData
            
        }
        
        var exportData: [String: Any] = [
            "frames": framesKeyData,
            "frames_bbox": frameBboxData,
            "frameCount": processedKeypoints.count,
            "exportTime": Date().timeIntervalSince1970
        ]
        
        // Add metadata
        if let metadata = sourceInfo {
            exportData["metadata"] = metadata
        }
        
        // Write JSON
        let jsonData = try JSONSerialization.data(withJSONObject: exportData, options: .prettyPrinted)
        try jsonData.write(to: fileURL)
    }
}
