import Foundation
import CoreML
import UIKit
import Metal
import Combine

final class FrameDataCache {
    static let shared = FrameDataCache()
    
    private let cache = NSCache<NSNumber, FrameDataModel>()
    
    private init() {
        cache.countLimit = 150 // Tune based on device memory
    }
    
    func getFrame(at index: Int, from frameDir: URL, device: MTLDevice) throws -> FrameDataModel {
        if let cached = cache.object(forKey: NSNumber(value: index)) {
            return cached
        }
        
        // Load and cache
        let frameLoader = FrameDataVM()
        frameLoader.loadData(from: frameDir, device: device)
        
        let model = frameLoader.database
        
        cache.setObject(model, forKey: NSNumber(value: index))
        return model
    }
    
    func getMetadata(at index: Int, from frameDir: URL) throws -> FrameDataModel  {
        if let cached = cache.object(forKey: NSNumber(value: index)) {
            return cached
        }
        
        // Load and cache
        let frameLoader = FrameDataVM()
        frameLoader.loadMetadata(from: frameDir.appendingPathComponent("metadata.plist"))
        
        let model = frameLoader.database
        
        cache.setObject(model, forKey: NSNumber(value: index))
        return model
    }
}

class VitPoseProcessor {
    // MARK: - Properties
    private let modelConfig: MLModelConfiguration
    private var vitposeModel: VitPoseh?
    
    // Storage for processed keypoints
    private var keypointsByFrame: [Int: [KeypointData]] = [:]
    private var processedImages: [Int: UIImage] = [:]
    
    // MARK: - Constants
    private let modelInputSize = CGSize(width: 192, height: 256)
    private var visualizedFrameCache = NSCache<NSNumber, UIImage>()
    private static var roiRect: CGRect? = nil
    
    // MARK: - Error Types
    enum ProcessingError: Error {
        case modelNotLoaded(String)
        case imageConversionFailed(String)
        case imageResizeFailed(String)
        case pixelExtractionFailed(String)
        case inputArrayCreationFailed(String)
        case heatmapProcessingFailed(String)
        case noKeypointData(String)
        case unsupportedFormat(String)
        case invalidFormat(String)
    }
    
    // MARK: - Initialization
    init() {
        self.modelConfig = MLModelConfiguration()
        self.modelConfig.computeUnits = .cpuAndGPU
        
        do {
            self.vitposeModel = try VitPoseh(configuration: modelConfig)
        } catch {
            print("Error loading VitPose model: \(error.localizedDescription)")
        }
    }
    
    // MARK: - Public Process Function
    
    // Process frames with retry mechanism for failed frames
    func processFrames (from mediaManager: MediaManagerVM,
                        maxRetries: Int = 2,
                        progress: @escaping (Double) -> Void,
                        completion: @escaping (Bool, Error?) -> Void) {
            
        // First pass - normal processing
        processFramesOptimized(from: mediaManager,
                               progress: { progressValue in progress(progressValue * 0.8)}) { [weak self] success, error in
            
            guard let self = self else {
                completion(false, NSError(domain: "VitPoseProcessor", code: -1, userInfo: [NSLocalizedDescriptionKey: "Processor deallocated"]))
                return
            }
            
            if success {
                // Check for gaps in processed frames
                let totalFrames = mediaManager.mediaPlayerViewModel.totalFrames
                let processedFrameIndices = Set(self.getFrameIndicesWithKeypoints())
                let expectedFrameIndices = Set(0..<totalFrames)
                let missingFrames = Array(expectedFrameIndices.subtracting(processedFrameIndices)).sorted()
                
                if missingFrames.isEmpty {
                    // All frames processed successfully
                    progress(1.0)
                    completion(true, nil)
                } else {
                    print("🔄 Retrying \(missingFrames.count) failed frames: \(missingFrames.prefix(10))...")
                    
                    // Retry failed frames
                    self.retryFailedFrames(
                        missingFrames,
                        mediaManager: mediaManager,
                        maxRetries: maxRetries,
                        totalFrames: totalFrames,
                        progress: { retryProgress in
                            // Report remaining 20% progress for retry
                            progress(0.8 + (retryProgress * 0.2))
                        },
                        completion: completion
                    )
                }
            } else {
                completion(false, error)
            }
        }
    }
    
    // MARK: - Keypoint Data Management
    /// Get keypoints for a specific frame
    func getKeypoints() -> [Int: [KeypointData]] {
        return keypointsByFrame
    }
    
    /// Get a list of all frame indices that have keypoint data
    func getFrameIndicesWithKeypoints() -> [Int] {
        return Array(keypointsByFrame.keys).sorted()
    }
    
    /// Store additional keypoints
    func storeKeypoints(_ keypoints: [KeypointData], for frameIndex: Int) {
        keypointsByFrame[frameIndex] = keypoints
    }
    
    /// Clear all stored data
    func clearAllData() {
        keypointsByFrame.removeAll()
        processedImages.removeAll()
    }
    func clearAllKeypoints() {
        keypointsByFrame.removeAll()
        visualizedFrameCache.removeAllObjects()
        processedImages.removeAll()
        VitPoseProcessor.roiRect = nil
    }
    
    // MARK: - File Operations
    /// Export keypoints to a file
    func exportKeypoints(to fileURL: URL, format: String, frameIndex: Int? = nil, sourceInfo: [String: Any]? = nil) throws {
        if let specificFrame = frameIndex {
            // Export single frame
            guard let frameKeypoints = keypointsByFrame[specificFrame] else {
                throw ProcessingError.noKeypointData("No keypoint data for frame \(specificFrame)")
            }
            
            print("Exporting \(frameKeypoints.count) keypoints for frame \(specificFrame)")
            
            if format.lowercased() == "json" {
                // JSON export for single frame
                var exportData: [String: Any] = [
                    "keypoints": frameKeypoints.map { keypoint -> [String: Any] in
                        return [
                            "name": keypoint.name,
                            "x": keypoint.x,
                            "y": keypoint.y,
                            "confidence": keypoint.confidence,
                            "depth": keypoint.depth,
                            "frameIndex": keypoint.frameIndex
                        ]
                    }
                ]
                
                // Add metadata
                if let metadata = sourceInfo {
                    exportData["metadata"] = metadata
                }
                
                exportData["frameInfo"] = [
                    "index": specificFrame,
                    "exportTime": Date().timeIntervalSince1970
                ]
                
                // Write JSON
                let jsonData = try JSONSerialization.data(withJSONObject: exportData, options: .prettyPrinted)
                try jsonData.write(to: fileURL)
            } else if format.lowercased() == "xml" {
                // XML export for single frame
                var xmlString = "<?xml version=\"1.0\" encoding=\"UTF-8\"?>\n<keypoints>\n"
                
                // Add metadata
                if let metadata = sourceInfo {
                    xmlString += "  <metadata>\n"
                    for (key, value) in metadata {
                        xmlString += "    <\(key)>\(value)</\(key)>\n"
                    }
                    xmlString += "  </metadata>\n"
                }
                
                xmlString += "  <frame index=\"\(specificFrame)\">\n"
                
                for (i, keypoint) in frameKeypoints.enumerated() {
                    xmlString += "    <keypoint id=\"\(i)\">\n"
                    xmlString += "      <name>\(keypoint.name)</name>\n"
                    xmlString += "      <x>\(keypoint.x)</x>\n"
                    xmlString += "      <y>\(keypoint.y)</y>\n"
                    xmlString += "      <confidence>\(keypoint.confidence)</confidence>\n"
                    xmlString += "      <depth>\(keypoint.depth)</depth>\n"
                    xmlString += "    </keypoint>\n"
                }
                
                xmlString += "  </frame>\n"
                xmlString += "</keypoints>"
                
                try xmlString.write(to: fileURL, atomically: true, encoding: .utf8)
            } else {
                throw ProcessingError.unsupportedFormat("Unsupported export format: \(format)")
            }
        } else {
            // Export all frames
            if format.lowercased() == "json" {
                // JSON export for all frames
                var framesData: [String: [[String: Any]]] = [:]
                
                for (frameIdx, keypoints) in keypointsByFrame.sorted(by: { $0.key < $1.key }) {
                    framesData["frame_\(frameIdx)"] = keypoints.map { keypoint -> [String: Any] in
                        return [
                            "name": keypoint.name,
                            "x": keypoint.x,
                            "y": keypoint.y,
                            "confidence": keypoint.confidence,
                            "depth": keypoint.depth,
                            "frameIndex": keypoint.frameIndex
                        ]
                    }
                }
                
                var exportData: [String: Any] = [
                    "frames": framesData,
                    "frameCount": keypointsByFrame.count,
                    "exportTime": Date().timeIntervalSince1970
                ]
                
                // Add metadata
                if let metadata = sourceInfo {
                    exportData["metadata"] = metadata
                }
                
                // Write JSON
                let jsonData = try JSONSerialization.data(withJSONObject: exportData, options: .prettyPrinted)
                try jsonData.write(to: fileURL)
            } else if format.lowercased() == "xml" {
                // XML export for all frames
                var xmlString = "<?xml version=\"1.0\" encoding=\"UTF-8\"?>\n<keypoints>\n"
                
                // Add metadata
                if let metadata = sourceInfo {
                    xmlString += "  <metadata>\n"
                    for (key, value) in metadata {
                        xmlString += "    <\(key)>\(value)</\(key)>\n"
                    }
                    xmlString += "  </metadata>\n"
                }
                
                for (frameIndex, keypoints) in keypointsByFrame.sorted(by: { $0.key < $1.key }) {
                    xmlString += "  <frame index=\"\(frameIndex)\">\n"
                    
                    for (i, keypoint) in keypoints.enumerated() {
                        xmlString += "    <keypoint id=\"\(i)\">\n"
                        xmlString += "      <name>\(keypoint.name)</name>\n"
                        xmlString += "      <x>\(keypoint.x)</x>\n"
                        xmlString += "      <y>\(keypoint.y)</y>\n"
                        xmlString += "      <confidence>\(keypoint.confidence)</confidence>\n"
                        xmlString += "      <depth>\(keypoint.depth)</depth>\n"
                        xmlString += "    </keypoint>\n"
                    }
                    
                    xmlString += "  </frame>\n"
                }
                
                xmlString += "</keypoints>"
                try xmlString.write(to: fileURL, atomically: true, encoding: .utf8)
            } else {
                throw ProcessingError.unsupportedFormat("Unsupported export format: \(format)")
            }
        }
    }
    
    
    // MARK: - Private Helper Methods
    
    /// Detect keypoints in an image
    private func detectKeypoints(from image: UIImage, frameIndex: Int) throws -> [KeypointData] {
        guard let vitposeModel = self.vitposeModel else {
            throw ProcessingError.modelNotLoaded("VitPose model is not loaded")
        }
        
        guard let cgImage = image.cgImage else {
            throw ProcessingError.imageConversionFailed("Failed to get CGImage from colorImage")
        }
        
        // Resize image for model input
        guard let resizedImage = cgImage.resize(to: modelInputSize) else {
            throw ProcessingError.imageResizeFailed("Failed to resize image for model input")
        }
        
        // Get RGB pixels from resized image
        guard let pixels = resizedImage.toRGBPixels() else {
            throw ProcessingError.pixelExtractionFailed("Failed to get RGB pixels from image")
        }
        
        // Create input MLMultiArray (1, 3, 256, 192)
        let shape = [1, 3, 256, 192] as [NSNumber]
        guard let input = try? MLMultiArray(shape: shape, dataType: .float32) else {
            throw ProcessingError.inputArrayCreationFailed("Failed to create input array for model")
        }
        
        // Fill input array with normalized pixel values
        for y in 0..<256 {
            for x in 0..<192 {
                let pixelIndex = y * 192 + x
                for c in 0..<3 {
                    let value = Float(pixels[pixelIndex * 4 + c]) / 255.0
                    let index = [0, c, y, x] as [NSNumber]
                    input[index] = NSNumber(value: value)
                }
            }
        }
        
        // Run inference
        let prediction = try vitposeModel.prediction(input_1: input)
        
        // Process heatmaps to get keypoints with confidence
        let keypointPositions = processHeatmaps(prediction.var_1829)
        
        // Map keypoints to original image coordinates
        var keypointDataArray: [KeypointData] = []
        
        for (index, (normalizedPoint, confidence)) in keypointPositions.enumerated() {
            if index < keypointNames.count && confidence > 0.3 {
                let name = keypointNames[index]
                let originalX = normalizedPoint.x * CGFloat(image.size.width)
                let originalY = normalizedPoint.y * CGFloat(image.size.height)
                
                // Create keypoint data
                let keypointData = KeypointData(
                    name: name,
                    x: originalX,
                    y: originalY,
                    confidence: confidence,
                    depth: 0.0, // Depth will be added later if available
                    frameIndex: frameIndex
                )
                keypointDataArray.append(keypointData)
            }
        }
        
        return keypointDataArray
    }
    
    /// Process heatmaps from model output
    private func processHeatmaps(_ heatmaps: MLMultiArray) -> [(CGPoint, Float)] {
        var keypoints: [(CGPoint, Float)] = []
        
        let numKeypoints = keypointNames.count
        let height = heatmaps.shape[2].intValue
        let width = heatmaps.shape[3].intValue
        
        for k in 0..<numKeypoints {
            var maxVal: Float = -Float.infinity
            var maxLoc = CGPoint.zero
            
            // Find maximum value in heatmap for this keypoint
            for y in 0..<height {
                for x in 0..<width {
                    let index = k * (height * width) + y * width + x
                    if index < heatmaps.count {
                        let value = heatmaps[index].floatValue
                        
                        if value > maxVal {
                            maxVal = value
                            maxLoc = CGPoint(x: Double(x) / Double(width),
                                           y: Double(y) / Double(height))
                        }
                    }
                }
            }
            
            keypoints.append((maxLoc, maxVal))
        }
        
        return keypoints
    }
    
    /// Visualize pose with keypoints and connections
    private func visualizePose(colorImage: UIImage,
                               keypoints: [(String, CGPoint, Float, Float)],
                               connections: [(String, String)]) -> UIImage? {
        
        let renderer = UIGraphicsImageRenderer(size: colorImage.size)
        
        return renderer.image { context in
            // Draw original image
            colorImage.draw(in: CGRect(origin: .zero, size: colorImage.size))
            
            let ctx = context.cgContext
            
            // Create lookup dictionary
            let keypointDict = Dictionary(uniqueKeysWithValues: keypoints.map { ($0.0, ($0.1, $0.2, $0.3)) })
            
            // Draw connections
            ctx.setLineWidth(3.0)
            ctx.setStrokeColor(UIColor.green.cgColor)
            
            for (startName, endName) in connections {
                guard let start = keypointDict[startName],
                      let end = keypointDict[endName] else {
                    continue
                }
                
                if start.1 > 0.3 && end.1 > 0.3 {
                    ctx.move(to: start.0)
                    ctx.addLine(to: end.0)
                    ctx.strokePath()
                }
            }
            
            // Draw keypoints
            for (name, point, confidence, _) in keypoints {
                if confidence > 0.3 {
                    // Choose color based on keypoint type
                    if name.contains("shoulder") || name.contains("hip") {
                        ctx.setFillColor(UIColor.orange.cgColor)
                    } else if name.contains("knee") || name.contains("elbow") {
                        ctx.setFillColor(UIColor.yellow.cgColor)
                    } else if name.contains("ankle") || name.contains("wrist") {
                        ctx.setFillColor(UIColor.purple.cgColor)
                    } else if name.contains("eye") || name.contains("ear") || name.contains("nose") {
                        ctx.setFillColor(UIColor.blue.cgColor)
                    } else {
                        ctx.setFillColor(UIColor.red.cgColor)
                    }
                    
                    // Size based on confidence
                    let size = 8.0 + (CGFloat(confidence) * 4.0)
                    let rect = CGRect(x: point.x - size/2, y: point.y - size/2, width: size, height: size)
                    ctx.fillEllipse(in: rect)
                    
                    // Draw border
                    ctx.setStrokeColor(UIColor.white.cgColor)
                    ctx.setLineWidth(1.0)
                    ctx.strokeEllipse(in: rect)
                }
            }
        }
        
    }

    // Method to get a cached processed image
    func getProcessedImage(for frameIndex: Int) -> UIImage? {
        return visualizedFrameCache.object(forKey: NSNumber(value: frameIndex))
    }

    // Method to store a processed image
    func storeProcessedImage(_ image: UIImage, for frameIndex: Int) {
        visualizedFrameCache.setObject(image, forKey: NSNumber(value: frameIndex))
    }
}

// Add this extension to fix the CGImage resize issue
extension VitPoseProcessor {
    func getTotalFrames() -> Int {
        return keypointsByFrame.keys.max() ?? 0
    }
    
    func setROI(_ rect: CGRect) {
            VitPoseProcessor.roiRect = rect
            print("ROI set for pose processor: \(rect)")
    }
        
    func clearROI() {
        VitPoseProcessor.roiRect = nil
        print("ROI cleared from pose processor")
    }
        
    // Method to crop image to ROI before processing
    private func cropImageToROI(_ image: UIImage) -> (croppedImage: UIImage, roiOffset: CGPoint)? {
        guard let roiRect = VitPoseProcessor.roiRect else { return (image, .zero) }
        
        guard let cgImage = image.cgImage else { return (image, .zero) }
        
        // Ensure ROI is within image bounds
        let imageSize = CGSize(width: cgImage.width, height: cgImage.height)
        let clampedROI = CGRect(
            x: max(0, min(roiRect.origin.x, imageSize.width - 1)),
            y: max(0, min(roiRect.origin.y, imageSize.height - 1)),
            width: min(roiRect.width, imageSize.width - roiRect.origin.x),
            height: min(roiRect.height, imageSize.height - roiRect.origin.y)
        )
        
        // Crop the image
        if let croppedCGImage = cgImage.cropping(to: clampedROI) {
            let croppedImage = UIImage(cgImage: croppedCGImage)
            let roiOffset = CGPoint(x: clampedROI.origin.x, y: clampedROI.origin.y)
            return (croppedImage, roiOffset)
        }
        
        return (image, .zero)
    }
}

// MARK: - Optimized Frame Processing with Batch Management
extension VitPoseProcessor {
    // Optimized frame processing with batch management and memory optimization
    private func processFramesOptimized(from mediaManager: MediaManagerVM,
                                        progress: @escaping (Double) -> Void,
                                        completion: @escaping (Bool, Error?) -> Void) {
        
        // Guard If Media is Unavailable
        guard mediaManager.isMediaAvailable else {
            DispatchQueue.main.async {
                completion(false, ProcessingError.noKeypointData("No frames available for processing"))
            }
            return
        }
        
        // Configuration for batch processing
        let batchSize = 10 // Process 10 frames at a time
        let delayBetweenBatches: TimeInterval = 0.1 // Small delay to prevent memory issues
        
        // Clear existing data safely
        if Thread.isMainThread {
            self.clearAllData()
        } else {
            DispatchQueue.main.sync {
                self.clearAllData()
            }
        }
        
        // Process frames in batches
        self.processBatches(
            mediaManager: mediaManager,
            batchSize: batchSize,
            delayBetweenBatches: delayBetweenBatches,
            currentBatch: 0,
            processedFrames: 0,
            failedFrames: [],
            progress: progress,
            completion: completion
        )
    }
    
    /// Process frames in batches with memory management
    private func processBatches(
        mediaManager: MediaManagerVM,
        batchSize: Int,
        delayBetweenBatches: TimeInterval,
        currentBatch: Int,
        processedFrames: Int,
        failedFrames: [Int],
        progress: @escaping (Double) -> Void,
        completion: @escaping (Bool, Error?) -> Void
    ) {
        let startFrame = currentBatch * batchSize
        let endFrame = min(startFrame + batchSize, mediaManager.mediaPlayerViewModel.totalFrames)
        let totalFrames = mediaManager.mediaPlayerViewModel.totalFrames

        if startFrame >= totalFrames {
            log("Completed processing all batches. Processed: \(processedFrames), Failed: \(failedFrames.count)", level: .info)
            if !failedFrames.isEmpty {
                log("Failed to process frames: \(failedFrames)", level: .warn)
            }
            DispatchQueue.main.async {
                completion(true, nil)
            }
            return
        }

        Task {
            var batchProcessedFrames = processedFrames
            var batchFailedFrames = failedFrames

            for frameIndex in startFrame..<endFrame {
                do {
                    guard let frameImage = try await mediaManager.mediaPlayerViewModel.moveToFrameAsync(frameIndex) else {
                        print("Error loading image")
                        batchFailedFrames.append(frameIndex)
                        continue
                    }
                    let result = try self.processFrameWithMemoryManagement(
                        from: mediaManager,
                        image: frameImage,
                        frameIndex: frameIndex
                    )
                    if !result.keypoints.isEmpty {
                        self.storeKeypointsWithMemoryManagement(
                            result.keypoints,
                            visualizedImage: result.visualizedImage,
                            for: frameIndex
                        )
                        batchProcessedFrames += 1
                    } else {
                        print("⚠️ No keypoints detected for frame \(frameIndex)")
                        batchFailedFrames.append(frameIndex)
                    }
                    let progressValue = Double(batchProcessedFrames) / Double(totalFrames)
                    await MainActor.run { progress(progressValue) }
                } catch {
                    print("Error loading image: \(error.localizedDescription)")
                    batchFailedFrames.append(frameIndex)
                }
                self.performMemoryCleanup()
            }

            // Schedule next batch after delay
            try? await Task.sleep(nanoseconds: UInt64(delayBetweenBatches * 1_000_000_000))
            self.processBatches(
                mediaManager: mediaManager,
                batchSize: batchSize,
                delayBetweenBatches: delayBetweenBatches,
                currentBatch: currentBatch + 1,
                processedFrames: batchProcessedFrames,
                failedFrames: batchFailedFrames,
                progress: progress,
                completion: completion
            )
        }
    }
    
    /// Process frame with memory-optimized approach
    private func processFrameWithMemoryManagement(from mediaManager: MediaManagerVM,
                                                  image: UIImage,
                                                  frameIndex: Int) throws -> (keypoints: [KeypointData], visualizedImage: UIImage?) {
        
        // Ensure proper image orientation
        let correctedImage = ensureCorrectOrientation(image: image)
        
        // Apply ROI if set
        let (imageToProcess, roiOffset) = cropImageToROI(correctedImage) ?? (correctedImage, .zero)
        
        // Detect keypoints
        var detectedKeypoints = try detectKeypoints(from: imageToProcess, frameIndex: frameIndex)
        
        // Check if has LiDAR depth data
        if mediaManager.isDataLIDAR {
            // Get Depth Data
            let frameDir = mediaManager.fileLoaderViewModel.FrameFolderURLs[frameIndex]
            do {
                let device = MTLCreateSystemDefaultDevice()!
                let frameData = try FrameDataCache.shared.getFrame(at: frameIndex, from: frameDir, device: device)
                
                // Parse Depth on Keypoints
                for j in detectedKeypoints.indices {
                    if VitPoseProcessor.roiRect != nil {
                        guard let depth = self.getDepth(at: CGPoint(x: detectedKeypoints[j].x + roiOffset.x,
                                                                    y: detectedKeypoints[j].y + roiOffset.y),
                                                                    from: frameData) else {
                            log("No depth data found at point (\(detectedKeypoints[j].x), \(detectedKeypoints[j].y))", level: .warn)
                            continue
                        }
                        // Add Depth Value
                        detectedKeypoints[j].depth = depth
                        
                    } else {
                        guard let depth = self.getDepth(at: CGPoint(x: detectedKeypoints[j].x,
                                                                    y: detectedKeypoints[j].y),
                                                                    from: frameData) else {
                            log("No depth data found at point (\(detectedKeypoints[j].x), \(detectedKeypoints[j].y))", level: .warn)
                            continue
                        }
                        // Add Depth Value
                        detectedKeypoints[j].depth = depth
                    }
                }
            } catch {
                log("Error fetching frame data at frame \(frameIndex): \(error)")
            }
        }
        
        // Adjust keypoints for ROI if needed
        let adjustedKeypoints: [KeypointData]
        if VitPoseProcessor.roiRect != nil {
            adjustedKeypoints = detectedKeypoints.map { keypoint in
                KeypointData(
                    name: keypoint.name,
                    x: keypoint.x + roiOffset.x,
                    y: keypoint.y + roiOffset.y,
                    confidence: keypoint.confidence,
                    depth: keypoint.depth,
                    frameIndex: keypoint.frameIndex
                )
            }
        } else {
            adjustedKeypoints = detectedKeypoints
        }
        
        // Create visualization if keypoints exist
        var visualizedImage: UIImage?
        if !adjustedKeypoints.isEmpty {
            let mappedKeypoints = adjustedKeypoints.map { keypoint -> (String, CGPoint, Float, Float) in
                return (keypoint.name, CGPoint(x: keypoint.x, y: keypoint.y), keypoint.confidence, 0.0)
            }
            visualizedImage = visualizePose(
                colorImage: correctedImage,
                keypoints: mappedKeypoints,
                connections: jointConnections
            )
        }
        
        return (adjustedKeypoints, visualizedImage)
    }
    
    /// Store keypoints with memory management (thread-safe)
    private func storeKeypointsWithMemoryManagement(
        _ keypoints: [KeypointData],
        visualizedImage: UIImage?,
        for frameIndex: Int
    ) {
        // Use a thread-safe approach to store keypoints
        DispatchQueue.main.async {
            // Store keypoints
            self.keypointsByFrame[frameIndex] = keypoints
            
            // Store visualized image in cache with size limit check
            if let image = visualizedImage {
                // Check cache size and clear if needed
                if self.visualizedFrameCache.countLimit == 0 {
                    self.visualizedFrameCache.countLimit = 50 // Limit cache to 50 frames
                }
                self.visualizedFrameCache.setObject(image, forKey: NSNumber(value: frameIndex))
            }
        }
    }
    
    /// Perform memory cleanup between batches
    private func performMemoryCleanup() {
        // Force garbage collection
        autoreleasepool {
            // Clear temporary caches if they get too large
            if visualizedFrameCache.countLimit > 0 {
                // Keep only recent frames in cache
                let maxCacheSize = 30
                if visualizedFrameCache.countLimit > maxCacheSize {
                    // This will trigger automatic eviction of older items
                    visualizedFrameCache.countLimit = maxCacheSize
                }
            }
        }
    }
    
    /// Ensure image has correct orientation
    private func ensureCorrectOrientation(image: UIImage) -> UIImage {
        if image.imageOrientation != .up {
            UIGraphicsBeginImageContextWithOptions(image.size, false, image.scale)
            image.draw(in: CGRect(origin: .zero, size: image.size))
            let correctedImage = UIGraphicsGetImageFromCurrentImageContext()
            UIGraphicsEndImageContext()
            return correctedImage ?? image
        }
        return image
    }
}

// MARK: - Enhanced Error Handling and Recovery
extension VitPoseProcessor {
    /// Retry processing failed frames
    private func retryFailedFrames(
        _ failedFrames: [Int],
        mediaManager: MediaManagerVM,
        maxRetries: Int,
        totalFrames: Int,
        progress: @escaping (Double) -> Void,
        completion: @escaping (Bool, Error?) -> Void
    ) {
        guard !failedFrames.isEmpty else {
            progress(1.0)
            completion(true, nil)
            return
        }
        
        var processedRetries = 0
        let totalRetries = failedFrames.count
        var frameImage: UIImage?

        DispatchQueue.global(qos: .userInitiated).async {
            for frameIndex in failedFrames {
                autoreleasepool {
                    do {
                        // Get frame with memory management
                        Task {
                            do {
                                frameImage = try await mediaManager.mediaPlayerViewModel.moveToFrameAsync(frameIndex)
                            } catch {
                                print("Error loading image: \(error.localizedDescription)")
                            }
                        }
                        
                        // Process the frame
                        guard let frameImage = frameImage else {
                            throw NSError(domain: "retryFailedFrame", code: 0, userInfo: nil)
                        }
                        
                        let result = try self.processFrameWithMemoryManagement(
                            from: mediaManager,
                            image: frameImage,
                            frameIndex: frameIndex
                        )
                        
                        if !result.keypoints.isEmpty {
                            self.storeKeypointsWithMemoryManagement(
                                result.keypoints,
                                visualizedImage: result.visualizedImage,
                                for: frameIndex
                            )
                            print("✅ Retry successful for frame \(frameIndex)")
                        }
                        
                    } catch {
                        print("❌ Retry failed for frame \(frameIndex): \(error)")
                    }
                    
                    processedRetries += 1
                    let retryProgress = Double(processedRetries) / Double(totalRetries)
                    DispatchQueue.main.async {
                        progress(retryProgress)
                    }
                }
            }
            
            DispatchQueue.main.async {
                completion(true, nil)
            }
        }
    }
    
    func debugPrintState() {
            print("=== VitPoseProcessor State ===")
            print("Total frames with keypoints: \(keypointsByFrame.count)")
            print("Frame indices: \(Array(keypointsByFrame.keys).sorted().prefix(10))...")
            print("Visualization cache size: \(visualizedFrameCache.name)")
            print("Processed images count: \(processedImages.count)")
            print("ROI set: \(VitPoseProcessor.roiRect != nil)")
            if let roi = VitPoseProcessor.roiRect {
                print("ROI rect: \(roi)")
            }
            print("=============================")
        }
    
    func getDepth(at imagePoint: CGPoint, from: FrameDataModel) -> Float? {
        guard let depthTexture = from.depth else {
            return nil
        }

        assert(depthTexture.pixelFormat == .r16Float, "Expected r16Float pixel format")

        let depthWidth = depthTexture.width
        let depthHeight = depthTexture.height
        let imageSize = from.colorImage?.size ?? CGSize(width: depthWidth, height: depthHeight)

        // Map image point to depth coordinates
        let depthX = Int(imagePoint.x / imageSize.width * CGFloat(depthWidth))
        let depthY = Int(imagePoint.y / imageSize.height * CGFloat(depthHeight))

        guard depthX >= 0, depthX < depthWidth, depthY >= 0, depthY < depthHeight else {
            return nil
        }

        var depthValue = Float16(0)
        let region = MTLRegionMake2D(depthX, depthY, 1, 1)

        depthTexture.getBytes(&depthValue, bytesPerRow: 0, from: region, mipmapLevel: 0)

        return Float(depthValue)
    }
}
