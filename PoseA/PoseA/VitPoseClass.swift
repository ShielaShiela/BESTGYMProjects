//import Foundation
//import CoreML
//import UIKit
//import Metal
//import Combine
//class VitPoseProcessor {
//    // MARK: - Properties
//
//    private let modelConfig: MLModelConfiguration
//    private var vitposeModel: VitPoseh?
//
//    // Storage for processed keypoints
//    private var keypointsByFrame: [Int: [KeypointData]] = [:]
//    private var processedImages: [Int: UIImage] = [:]
//
//    // MARK: - Constants
//
//    private let modelInputSize = CGSize(width: 192, height: 256)
//
//    // Keypoint names in COCO format
//    private let keypointNames = [
//        "nose", "left_eye", "right_eye", "left_ear", "right_ear",
//        "left_shoulder", "right_shoulder", "left_elbow", "right_elbow",
//        "left_wrist", "right_wrist", "left_hip", "right_hip",
//        "left_knee", "right_knee", "left_ankle", "right_ankle"
//    ]
//
//    // Skeleton connections for visualization
//    private let skeletonConnections = [
//        ("left_shoulder", "right_shoulder"),
//        ("left_shoulder", "left_elbow"),
//        ("right_shoulder", "right_elbow"),
//        ("left_elbow", "left_wrist"),
//        ("right_elbow", "right_wrist"),
//        ("left_shoulder", "left_hip"),
//        ("right_shoulder", "right_hip"),
//        ("left_hip", "right_hip"),
//        ("left_hip", "left_knee"),
//        ("right_hip", "right_knee"),
//        ("left_knee", "left_ankle"),
//        ("right_knee", "right_ankle"),
//        ("nose", "left_eye"),
//        ("nose", "right_eye"),
//        ("left_eye", "left_ear"),
//        ("right_eye", "right_ear")
//    ]
//
//    // MARK: - Initialization
//
//    init() {
//        self.modelConfig = MLModelConfiguration()
//        self.modelConfig.computeUnits = .cpuAndGPU
//
//        do {
//            self.vitposeModel = try VitPoseh(configuration: modelConfig)
//        } catch {
//            print("Error loading VitPose model: \(error.localizedDescription)")
//        }
//    }
//
//    // MARK: - Public Methods
//
//    /// Process an image to detect pose keypoints and integrate depth data
//    func processImage(colorImage: UIImage, depthTexture: MTLTexture, frameIndex: Int) throws -> (keypointData: [KeypointData], visualizedImage: UIImage) {
//        guard let vitposeModel = self.vitposeModel else {
//            throw ProcessingError.modelNotLoaded("VitPose model is not loaded")
//        }
//
//        guard let cgImage = colorImage.cgImage else {
//            throw ProcessingError.imageConversionFailed("Failed to get CGImage from colorImage")
//        }
//
//        // Resize image for model input
//        guard let resizedImage = cgImage.resize(to: modelInputSize) else {
//            throw ProcessingError.imageResizeFailed("Failed to resize image for model input")
//        }
//
//        // Get RGB pixels from resized image
//        guard let pixels = resizedImage.toRGBPixels() else {
//            throw ProcessingError.pixelExtractionFailed("Failed to get RGB pixels from image")
//        }
//
//        // Create input MLMultiArray (1, 3, 256, 192)
//        let shape = [1, 3, 256, 192] as [NSNumber]
//        guard let input = try? MLMultiArray(shape: shape, dataType: .float32) else {
//            throw ProcessingError.inputArrayCreationFailed("Failed to create input array for model")
//        }
//
//        // Fill input array with normalized pixel values
//        for y in 0..<256 {
//            for x in 0..<192 {
//                let pixelIndex = y * 192 + x
//                for c in 0..<3 {
//                    let value = Float(pixels[pixelIndex * 4 + c]) / 255.0
//                    let index = [0, c, y, x] as [NSNumber]
//                    input[index] = NSNumber(value: value)
//                }
//            }
//        }
//
//        // Run inference
//        let prediction = try vitposeModel.prediction(input_1: input)
//
//        // Process heatmaps to get keypoints with confidence
//        let keypointPositions = processHeatmaps(prediction.var_1829)
//
//        // Map keypoints to original image coordinates and get depth
//        var mappedKeypoints = [(String, CGPoint, Float, Float)]() // name, position, confidence, depth
//        var keypointDataArray: [KeypointData] = []
//
//        for (index, (normalizedPoint, confidence)) in keypointPositions.enumerated() {
//            if index < keypointNames.count && confidence > 0.3 {
//                let name = keypointNames[index]
//                let originalX = normalizedPoint.x * CGFloat(colorImage.size.width)
//                let originalY = normalizedPoint.y * CGFloat(colorImage.size.height)
//                let originalPoint = CGPoint(x: originalX, y: originalY)
//
//                // Get depth value for this keypoint
//                let depthValue = getDepthValue(at: originalPoint, from: depthTexture, imageSize: colorImage.size)
//
//                // Store for visualization
//                mappedKeypoints.append((name, originalPoint, confidence, depthValue))
//
//                // Create structured keypoint data
//                let keypointData = KeypointData(
//                    name: name,
//                    x: originalX,
//                    y: originalY,
//                    confidence: confidence,
//                    depth: depthValue,
//                    frameIndex: frameIndex
//                )
//                keypointDataArray.append(keypointData)
//            }
//        }
//
//        // Create a visualization of the pose
//        let visualizedImage = visualizePose(colorImage: colorImage, keypoints: mappedKeypoints, connections: skeletonConnections)
//
//        // Store the data internally
//        keypointsByFrame[frameIndex] = keypointDataArray
//        processedImages[frameIndex] = visualizedImage ?? colorImage
//
//        // Return the processed data
//        return (keypointData: keypointDataArray, visualizedImage: visualizedImage ?? colorImage)
//    }
//
//    // MARK: - Keypoint Data Management
//
//    /// Get keypoints for a specific frame
//    func getKeypoints(for frameIndex: Int) -> [KeypointData]? {
//        return keypointsByFrame[frameIndex]
//    }
//
//    /// Get a list of all frame indices that have keypoint data
//    func getFrameIndicesWithKeypoints() -> [Int] {
//        return Array(keypointsByFrame.keys).sorted()
//    }
//
//    /// Get the processed image for a specific frame
//    func getProcessedImage(for frameIndex: Int) -> UIImage? {
//        return processedImages[frameIndex]
//    }
//
//    /// Store additional keypoints (for example, from an imported file)
//    func storeKeypoints(_ keypoints: [KeypointData], for frameIndex: Int) {
//        keypointsByFrame[frameIndex] = keypoints
//    }
//
//    /// Store a processed image
//    func storeProcessedImage(_ image: UIImage, for frameIndex: Int) {
//        processedImages[frameIndex] = image
//    }
//
//    /// Clear all stored keypoints and images
//    func clearAllData() {
//        keypointsByFrame.removeAll()
//        processedImages.removeAll()
//    }
//
//    /// Update a keypoint's position
//    func updateKeypoint(frameIndex: Int, keypointId: UUID, newPosition: CGPoint) {
//        guard var frameKeypoints = keypointsByFrame[frameIndex] else { return }
//
//        if let index = frameKeypoints.firstIndex(where: { $0.id == keypointId }) {
//            frameKeypoints[index].updatePosition(to: newPosition)
//            keypointsByFrame[frameIndex] = frameKeypoints
//
//            // Update the visualization
//            if let originalImage = processedImages[frameIndex],
//               let updatedImage = visualizeKeypointsForFrame(frameIndex, originalImage: originalImage) {
//                processedImages[frameIndex] = updatedImage
//            }
//        }
//    }
//
//    /// Reset a keypoint to its original position
//    func resetKeypoint(frameIndex: Int, keypointId: UUID) {
//        guard var frameKeypoints = keypointsByFrame[frameIndex] else { return }
//
//        if let index = frameKeypoints.firstIndex(where: { $0.id == keypointId }) {
//            frameKeypoints[index].resetPosition()
//            keypointsByFrame[frameIndex] = frameKeypoints
//
//            // Update the visualization
//            if let originalImage = processedImages[frameIndex],
//               let updatedImage = visualizeKeypointsForFrame(frameIndex, originalImage: originalImage) {
//                processedImages[frameIndex] = updatedImage
//            }
//        }
//    }
//
//    /// Visualize keypoints for a specific frame
//    func visualizeKeypointsForFrame(_ frameIndex: Int, originalImage: UIImage) -> UIImage? {
//        guard let keypoints = keypointsByFrame[frameIndex] else { return nil }
//
//        // Convert KeypointData to the format needed for visualization
//        let mappedKeypoints = keypoints.map { keypoint -> (String, CGPoint, Float, Float) in
//            return (keypoint.name, CGPoint(x: keypoint.x, y: keypoint.y), keypoint.confidence, keypoint.depth)
//        }
//
//        return visualizePose(colorImage: originalImage, keypoints: mappedKeypoints, connections: skeletonConnections)
//    }
//
//    // MARK: - File Operations
//
//    /// Export keypoints to a file
//    /// // Add or update this method in VitPoseProcessor class
//
//    /// Export keypoints to a file with source metadata
//    func exportKeypoints(to fileURL: URL, format: String, frameIndex: Int? = nil, sourceInfo: [String: Any]? = nil) throws {
//        if let specificFrame = frameIndex {
//            // Export only data for the specific frame
//            guard let frameKeypoints = keypointsByFrame[specificFrame] else {
//                throw ProcessingError.noKeypointData("No keypoint data for frame \(specificFrame)")
//            }
//
//            print("Exporting \(frameKeypoints.count) keypoints for frame \(specificFrame)")
//
//            if format.lowercased() == "json" {
//                // Create a dictionary with both keypoints and metadata
//                var exportData: [String: Any] = [
//                    "keypoints": frameKeypoints.map { keypoint -> [String: Any] in
//                        return [
//                            "name": keypoint.name,
//                            "x": keypoint.x,
//                            "y": keypoint.y,
//                            "confidence": keypoint.confidence,
//                            "depth": keypoint.depth,
//                            "frameIndex": keypoint.frameIndex
//                        ]
//                    }
//                ]
//
//                // Add metadata if provided
//                if let metadata = sourceInfo {
//                    exportData["metadata"] = metadata
//                }
//
//                // Add frame info
//                exportData["frameInfo"] = [
//                    "index": specificFrame,
//                    "exportTime": Date().timeIntervalSince1970
//                ]
//
//                // Export as JSON
//                let jsonData = try JSONSerialization.data(withJSONObject: exportData, options: .prettyPrinted)
//                try jsonData.write(to: fileURL)
//            } else if format.lowercased() == "xml" {
//                // XML format for a single frame
//                var xmlString = "<?xml version=\"1.0\" encoding=\"UTF-8\"?>\n<keypoints>\n"
//
//                // Add metadata if provided
//                if let metadata = sourceInfo {
//                    xmlString += "  <metadata>\n"
//                    for (key, value) in metadata {
//                        xmlString += "    <\(key)>\(value)</\(key)>\n"
//                    }
//                    xmlString += "  </metadata>\n"
//                }
//
//                xmlString += "  <frame index=\"\(specificFrame)\">\n"
//
//                for (i, keypoint) in frameKeypoints.enumerated() {
//                    xmlString += "    <keypoint id=\"\(i)\">\n"
//                    xmlString += "      <name>\(keypoint.name)</name>\n"
//                    xmlString += "      <x>\(keypoint.x)</x>\n"
//                    xmlString += "      <y>\(keypoint.y)</y>\n"
//                    xmlString += "      <confidence>\(keypoint.confidence)</confidence>\n"
//                    xmlString += "      <depth>\(keypoint.depth)</depth>\n"
//                    xmlString += "    </keypoint>\n"
//                }
//
//                xmlString += "  </frame>\n"
//                xmlString += "</keypoints>"
//
//                try xmlString.write(to: fileURL, atomically: true, encoding: .utf8)
//            } else {
//                throw ProcessingError.unsupportedFormat("Unsupported export format: \(format)")
//            }
//        } else {
//            // Export all frames
//            if format.lowercased() == "json" {
//                // Create a dictionary with frames as keys and keypoints as values
//                var framesData: [String: [[String: Any]]] = [:]
//
//                for (frameIdx, keypoints) in keypointsByFrame.sorted(by: { $0.key < $1.key }) {
//                    framesData["frame_\(frameIdx)"] = keypoints.map { keypoint -> [String: Any] in
//                        return [
//                            "name": keypoint.name,
//                            "x": keypoint.x,
//                            "y": keypoint.y,
//                            "confidence": keypoint.confidence,
//                            "depth": keypoint.depth,
//                            "frameIndex": keypoint.frameIndex
//                        ]
//                    }
//                }
//
//                // Create the export data with metadata
//                var exportData: [String: Any] = [
//                    "frames": framesData,
//                    "frameCount": keypointsByFrame.count,
//                    "exportTime": Date().timeIntervalSince1970
//                ]
//
//                // Add source metadata if provided
//                if let metadata = sourceInfo {
//                    exportData["metadata"] = metadata
//                }
//
//                // Export as JSON
//                let jsonData = try JSONSerialization.data(withJSONObject: exportData, options: .prettyPrinted)
//                try jsonData.write(to: fileURL)
//            } else if format.lowercased() == "xml" {
//                // XML format for all frames
//                var xmlString = "<?xml version=\"1.0\" encoding=\"UTF-8\"?>\n<keypoints>\n"
//
//                // Add metadata if provided
//                if let metadata = sourceInfo {
//                    xmlString += "  <metadata>\n"
//                    for (key, value) in metadata {
//                        xmlString += "    <\(key)>\(value)</\(key)>\n"
//                    }
//                    xmlString += "  </metadata>\n"
//                }
//
//                for (frameIndex, keypoints) in keypointsByFrame.sorted(by: { $0.key < $1.key }) {
//                    xmlString += "  <frame index=\"\(frameIndex)\">\n"
//
//                    for (i, keypoint) in keypoints.enumerated() {
//                        xmlString += "    <keypoint id=\"\(i)\">\n"
//                        xmlString += "      <name>\(keypoint.name)</name>\n"
//                        xmlString += "      <x>\(keypoint.x)</x>\n"
//                        xmlString += "      <y>\(keypoint.y)</y>\n"
//                        xmlString += "      <confidence>\(keypoint.confidence)</confidence>\n"
//                        xmlString += "      <depth>\(keypoint.depth)</depth>\n"
//                        xmlString += "    </keypoint>\n"
//                    }
//
//                    xmlString += "  </frame>\n"
//                }
//
//                xmlString += "</keypoints>"
//                try xmlString.write(to: fileURL, atomically: true, encoding: .utf8)
//            } else {
//                throw ProcessingError.unsupportedFormat("Unsupported export format: \(format)")
//            }
//        }
//    }
////    func exportKeypoints(to fileURL: URL, format: String, frameIndex: Int? = nil) throws {
////        if let specificFrame = frameIndex {
////            // Export only data for the specific frame
////            guard let frameKeypoints = keypointsByFrame[specificFrame] else {
////                throw ProcessingError.noKeypointData("No keypoint data for frame \(specificFrame)")
////            }
////
////            print("Exporting \(frameKeypoints.count) keypoints for frame \(specificFrame)")
////                   // Proceed with export...
////
////
////            if format.lowercased() == "json" {
////                let encoder = JSONEncoder()
////                encoder.outputFormatting = .prettyPrinted
////                let data = try encoder.encode(frameKeypoints)
////                try data.write(to: fileURL)
////            } else if format.lowercased() == "xml" {
////                // XML format for a single frame
////                var xmlString = "<?xml version=\"1.0\" encoding=\"UTF-8\"?>\n<keypoints>\n"
////                xmlString += "  <frame index=\"\(specificFrame)\">\n"
////
////                for (i, keypoint) in frameKeypoints.enumerated() {
////                    xmlString += "    <keypoint id=\"\(i)\">\n"
////                    xmlString += "      <name>\(keypoint.name)</name>\n"
////                    xmlString += "      <x>\(keypoint.x)</x>\n"
////                    xmlString += "      <y>\(keypoint.y)</y>\n"
////                    xmlString += "      <confidence>\(keypoint.confidence)</confidence>\n"
////                    xmlString += "      <depth>\(keypoint.depth)</depth>\n"
////                    xmlString += "    </keypoint>\n"
////                }
////
////                xmlString += "  </frame>\n"
////                xmlString += "</keypoints>"
////
////                try xmlString.write(to: fileURL, atomically: true, encoding: .utf8)
////            } else {
////                throw ProcessingError.unsupportedFormat("Unsupported export format: \(format)")
////            }
////        } else {
////            // Export all frames
////            if format.lowercased() == "json" {
////                // Flatten all keypoints for JSON export
////                var allKeypoints: [KeypointData] = []
////                for (_, keypoints) in keypointsByFrame {
////                    allKeypoints.append(contentsOf: keypoints)
////                }
////
////                let encoder = JSONEncoder()
////                encoder.outputFormatting = .prettyPrinted
////                let data = try encoder.encode(allKeypoints)
////                try data.write(to: fileURL)
////            } else if format.lowercased() == "xml" {
////                // XML format for all frames
////                var xmlString = "<?xml version=\"1.0\" encoding=\"UTF-8\"?>\n<keypoints>\n"
////
////                for (frameIndex, keypoints) in keypointsByFrame.sorted(by: { $0.key < $1.key }) {
////                    xmlString += "  <frame index=\"\(frameIndex)\">\n"
////
////                    for (i, keypoint) in keypoints.enumerated() {
////                        xmlString += "    <keypoint id=\"\(i)\">\n"
////                        xmlString += "      <name>\(keypoint.name)</name>\n"
////                        xmlString += "      <x>\(keypoint.x)</x>\n"
////                        xmlString += "      <y>\(keypoint.y)</y>\n"
////                        xmlString += "      <confidence>\(keypoint.confidence)</confidence>\n"
////                        xmlString += "      <depth>\(keypoint.depth)</depth>\n"
////                        xmlString += "    </keypoint>\n"
////                    }
////
////                    xmlString += "  </frame>\n"
////                }
////
////                xmlString += "</keypoints>"
////                try xmlString.write(to: fileURL, atomically: true, encoding: .utf8)
////            } else {
////                throw ProcessingError.unsupportedFormat("Unsupported export format: \(format)")
////            }
////        }
////    }
//
//    /// Import keypoints from a file
//    func importKeypoints(from fileURL: URL) throws {
//        let data = try Data(contentsOf: fileURL)
//
//        if fileURL.pathExtension.lowercased() == "json" {
//            do {
//                // First try to parse as an array of KeypointData
//                let decoder = JSONDecoder()
//                let keypoints = try decoder.decode([KeypointData].self, from: data)
//
//                // Organize by frame index
//                keypointsByFrame.removeAll()
//                for keypoint in keypoints {
//                    if keypointsByFrame[keypoint.frameIndex] == nil {
//                        keypointsByFrame[keypoint.frameIndex] = []
//                    }
//                    keypointsByFrame[keypoint.frameIndex]?.append(keypoint)
//                }
//            } catch {
//                // If that fails, try the old dictionary format
//                if let jsonObject = try JSONSerialization.jsonObject(with: data, options: []) as? [String: Any] {
//                    keypointsByFrame.removeAll()
//
//                    if let frameDataDict = jsonObject as? [String: [[String: Any]]] {
//                        // Format: {"frame_0": [{keypoint data}], "frame_1": [...]}
//                        for (key, points) in frameDataDict {
//                            if key.hasPrefix("frame_"),
//                               let frameIndexString = key.split(separator: "_").last,
//                               let frameIndex = Int(frameIndexString) {
//
//                                var keypointsForFrame: [KeypointData] = []
//
//                                for point in points {
//                                    if let name = point["name"] as? String,
//                                       let x = point["x"] as? CGFloat,
//                                       let y = point["y"] as? CGFloat,
//                                       let confidence = point["confidence"] as? Float,
//                                       let depth = point["depth"] as? Float {
//
//                                        let keypoint = KeypointData(
//                                            name: name,
//                                            x: x,
//                                            y: y,
//                                            confidence: confidence,
//                                            depth: depth,
//                                            frameIndex: frameIndex
//                                        )
//                                        keypointsForFrame.append(keypoint)
//                                    }
//                                }
//
//                                keypointsByFrame[frameIndex] = keypointsForFrame
//                            }
//                        }
//                    }
//                } else {
//                    throw ProcessingError.invalidFormat("Invalid JSON format")
//                }
//            }
//        } else if fileURL.pathExtension.lowercased() == "xml" {
//            throw ProcessingError.unsupportedFormat("XML import not implemented yet")
//        } else {
//            throw ProcessingError.unsupportedFormat("Unsupported file format: \(fileURL.pathExtension)")
//        }
//    }
//
//    // MARK: - Utility Methods
//
//    func getSkeletonConnections() -> [(String, String)] {
//        return skeletonConnections
//    }
//
//    // MARK: - Private Methods
//
//    private func processHeatmaps(_ heatmaps: MLMultiArray) -> [(CGPoint, Float)] {
//        var keypoints: [(CGPoint, Float)] = []
//
//        let numKeypoints = keypointNames.count
//        let height = heatmaps.shape[2].intValue
//        let width = heatmaps.shape[3].intValue
//
//        for k in 0..<numKeypoints {
//            var maxVal: Float = -Float.infinity
//            var maxLoc = CGPoint.zero
//
//            for y in 0..<height {
//                for x in 0..<width {
//                    // Make sure we're accessing the correct index in the heatmap
//                    let index = k * (height * width) + y * width + x
//                    if index < heatmaps.count {
//                        let value = heatmaps[index].floatValue
//
//                        if value > maxVal {
//                            maxVal = value
//                            maxLoc = CGPoint(x: Double(x) / Double(width),
//                                             y: Double(y) / Double(height))
//                        }
//                    }
//                }
//            }
//
//            // Add the keypoint even if confidence is low - we'll filter later if needed
//            keypoints.append((maxLoc, maxVal))
//        }
//
//        return keypoints
//    }
//
//    private func getDepthValue(at point: CGPoint, from depthTexture: MTLTexture, imageSize: CGSize) -> Float {
//        // Convert point from image coordinates to depth texture coordinates
//        let depthWidth = depthTexture.width
//        let depthHeight = depthTexture.height
//
//        let depthX = Int(point.x * CGFloat(depthWidth) / imageSize.width)
//        let depthY = Int(point.y * CGFloat(depthHeight) / imageSize.height)
//
//        // Make sure the point is within bounds
//        guard depthX >= 0, depthX < depthWidth, depthY >= 0, depthY < depthHeight else {
//            return 0.0
//        }
//
//        // Create a buffer to read depth value
//        var depthValue: Float16 = 0.0
//        let region = MTLRegionMake2D(depthX, depthY, 1, 1)
//        let bytesPerRow = MemoryLayout<Float16>.size
//
//        depthTexture.getBytes(&depthValue, bytesPerRow: bytesPerRow, from: region, mipmapLevel: 0)
//
//        // Convert from Float16 to Float
//        return Float(depthValue)
//    }
//
//    private func visualizePose(
//        colorImage: UIImage,
//        keypoints: [(String, CGPoint, Float, Float)],
//        connections: [(String, String)]
//    ) -> UIImage? {
//        let renderer = UIGraphicsImageRenderer(size: colorImage.size)
//
//        return renderer.image { context in
//            // Draw the original image first
//            colorImage.draw(in: CGRect(origin: .zero, size: colorImage.size))
//
//            let ctx = context.cgContext
//
//            // Create a dictionary for faster keypoint lookup
//            let keypointDict = Dictionary(uniqueKeysWithValues: keypoints.map { ($0.0, ($0.1, $0.2, $0.3)) })
//
//            // Draw skeleton connections
//            ctx.setLineWidth(3.0)
//            ctx.setStrokeColor(UIColor.green.cgColor)
//
//            for (startName, endName) in connections {
//                guard let start = keypointDict[startName],
//                      let end = keypointDict[endName] else {
//                    continue
//                }
//
//                // Only draw if both keypoints have good confidence
//                if start.1 > 0.3 && end.1 > 0.3 {
//                    ctx.move(to: start.0)
//                    ctx.addLine(to: end.0)
//                    ctx.strokePath()
//                }
//            }
//
//            // Draw keypoints
//            for (name, point, confidence, _) in keypoints {
//                if confidence > 0.3 {
//                    // Choose color based on keypoint type
//                    if name.contains("shoulder") || name.contains("hip") {
//                        ctx.setFillColor(UIColor.orange.cgColor)
//                    } else if name.contains("knee") || name.contains("elbow") {
//                        ctx.setFillColor(UIColor.yellow.cgColor)
//                    } else if name.contains("ankle") || name.contains("wrist") {
//                        ctx.setFillColor(UIColor.purple.cgColor)
//                    } else if name.contains("eye") || name.contains("ear") || name.contains("nose") {
//                        ctx.setFillColor(UIColor.blue.cgColor)
//                    } else {
//                        ctx.setFillColor(UIColor.red.cgColor)
//                    }
//
//                    // Size based on confidence
//                    let size = 8.0 + (CGFloat(confidence) * 4.0)
//                    let rect = CGRect(x: point.x - size/2, y: point.y - size/2, width: size, height: size)
//                    ctx.fillEllipse(in: rect)
//
//                    // Draw a border
//                    ctx.setStrokeColor(UIColor.white.cgColor)
//                    ctx.setLineWidth(1.0)
//                    ctx.strokeEllipse(in: rect)
//                }
//            }
//        }
//    }
//
//    // MARK: - Error Types
//
//    enum ProcessingError: Error {
//        case modelNotLoaded(String)
//        case imageConversionFailed(String)
//        case imageResizeFailed(String)
//        case pixelExtractionFailed(String)
//        case inputArrayCreationFailed(String)
//        case heatmapProcessingFailed(String)
//        case noKeypointData(String)
//        case unsupportedFormat(String)
//        case invalidFormat(String)
//    }
//}
//
//// MARK: - KeypointData Model
//
//struct KeypointData: Codable, Identifiable {
//    let id: UUID
//    let name: String
//    var x: CGFloat
//    var y: CGFloat
//    let confidence: Float
//    let depth: Float
//    let frameIndex: Int
//
//    // Store original position for reset functionality
//    private let originalX: CGFloat
//    private let originalY: CGFloat
//
//    init(name: String, x: CGFloat, y: CGFloat, confidence: Float, depth: Float, frameIndex: Int) {
//        self.id = UUID()
//        self.name = name
//        self.x = x
//        self.y = y
//        self.confidence = confidence
//        self.depth = depth
//        self.frameIndex = frameIndex
//        self.originalX = x
//        self.originalY = y
//    }
//
//    mutating func updatePosition(to newPosition: CGPoint) {
//        self.x = newPosition.x
//        self.y = newPosition.y
//    }
//
//    mutating func resetPosition() {
//        self.x = originalX
//        self.y = originalY
//    }
//}
//
//// MARK: - Extensions
//
//extension CGImage {
//    func resize(to size: CGSize) -> CGImage? {
//        let width = Int(size.width)
//        let height = Int(size.height)
//
//        let colorSpace = CGColorSpaceCreateDeviceRGB()
//        let bitmapInfo = CGBitmapInfo(rawValue: CGImageAlphaInfo.premultipliedLast.rawValue)
//
//        guard let context = CGContext(
//            data: nil,
//            width: width,
//            height: height,
//            bitsPerComponent: 8,
//            bytesPerRow: width * 4,
//            space: colorSpace,
//            bitmapInfo: bitmapInfo.rawValue
//        ) else {
//            return nil
//        }
//
//        // Draw the original image in the new size
//        context.draw(self, in: CGRect(x: 0, y: 0, width: width, height: height))
//
//        return context.makeImage()
//    }
//
//    func toRGBPixels() -> [UInt8]? {
//        let width = self.width
//        let height = self.height
//
//        // Calculate bytes per row with 4 bytes per pixel (RGBA)
//        let bytesPerPixel = 4
//        let bytesPerRow = width * bytesPerPixel
//
//        // Create buffer to hold pixel data
//        var buffer = [UInt8](repeating: 0, count: width * height * bytesPerPixel)
//
//        let colorSpace = CGColorSpaceCreateDeviceRGB()
//        let bitmapInfo = CGBitmapInfo(rawValue: CGImageAlphaInfo.premultipliedLast.rawValue)
//
//        // Create CGContext with buffer
//        guard let context = CGContext(
//            data: &buffer,
//            width: width,
//            height: height,
//            bitsPerComponent: 8,
//            bytesPerRow: bytesPerRow,
//            space: colorSpace,
//            bitmapInfo: bitmapInfo.rawValue
//        ) else {
//            return nil
//        }
//
//        // Draw image into context
//        context.draw(self, in: CGRect(x: 0, y: 0, width: width, height: height))
//
//        return buffer
//    }
//}
//// Extension for VitPoseProcessor to handle video frames without depth data
//// Extension for VitPoseProcessor to handle video frames without depth data
//
//extension VitPoseProcessor {
//    // Process a frame without depth data - 2D pose estimation only
//    func processImageWithoutDepth(colorImage: UIImage, frameIndex: Int) throws -> (visualizedImage: UIImage, keypoints: [KeypointData]) {
//        // This would call your pose estimation model
//        let keypoints = try detectKeypointsIn2D(from: colorImage, frameIndex: frameIndex)
//
//        // Convert KeypointData to the format needed for visualization
//        let mappedKeypoints = keypoints.map { keypoint -> (String, CGPoint, Float, Float) in
//            return (keypoint.name, CGPoint(x: keypoint.x, y: keypoint.y), keypoint.confidence, keypoint.depth)
//        }
//
//        // Create a visualization of the pose
//        let visualizedImage = visualizePose(colorImage: colorImage, keypoints: mappedKeypoints, connections: skeletonConnections)
//
//        // Store the keypoints and processed image
//        storeKeypoints(keypoints, for: frameIndex)
//        storeProcessedImage(visualizedImage ?? colorImage, for: frameIndex)
//
//        return (visualizedImage: visualizedImage ?? colorImage, keypoints: keypoints)
//    }
//
//    // Detect 2D keypoints using ML model
//    private func detectKeypointsIn2D(from image: UIImage, frameIndex: Int) throws -> [KeypointData] {
//        // Check if the model is loaded
//        guard let vitposeModel = self.vitposeModel else {
//            throw ProcessingError.modelNotLoaded("VitPose model is not loaded")
//        }
//
//        guard let cgImage = image.cgImage else {
//            throw ProcessingError.imageConversionFailed("Failed to get CGImage from colorImage")
//        }
//
//        // Resize image for model input
//        guard let resizedImage = cgImage.resize(to: modelInputSize) else {
//            throw ProcessingError.imageResizeFailed("Failed to resize image for model input")
//        }
//
//        // Get RGB pixels from resized image
//        guard let pixels = resizedImage.toRGBPixels() else {
//            throw ProcessingError.pixelExtractionFailed("Failed to get RGB pixels from image")
//        }
//
//        // Create input MLMultiArray (1, 3, 256, 192)
//        let shape = [1, 3, 256, 192] as [NSNumber]
//        guard let input = try? MLMultiArray(shape: shape, dataType: .float32) else {
//            throw ProcessingError.inputArrayCreationFailed("Failed to create input array for model")
//        }
//
//        // Fill input array with normalized pixel values
//        for y in 0..<256 {
//            for x in 0..<192 {
//                let pixelIndex = y * 192 + x
//                for c in 0..<3 {
//                    let value = Float(pixels[pixelIndex * 4 + c]) / 255.0
//                    let index = [0, c, y, x] as [NSNumber]
//                    input[index] = NSNumber(value: value)
//                }
//            }
//        }
//
//        // Run inference
//        let prediction = try vitposeModel.prediction(input_1: input)
//
//        // Process heatmaps to get keypoints with confidence
//        let keypointPositions = processHeatmaps(prediction.var_1829)
//
//        // Map keypoints to original image coordinates
//        var keypointDataArray: [KeypointData] = []
//
//        for (index, (normalizedPoint, confidence)) in keypointPositions.enumerated() {
//            if index < keypointNames.count && confidence > 0.3 {
//                let name = keypointNames[index]
//                let originalX = normalizedPoint.x * CGFloat(image.size.width)
//                let originalY = normalizedPoint.y * CGFloat(image.size.height)
//
//                // Create structured keypoint data (with depth set to 0 for 2D keypoints)
//                let keypointData = KeypointData(
//                    name: name,
//                    x: originalX,
//                    y: originalY,
//                    confidence: confidence,
//                    depth: 0.0, // No depth data for video frames
//                    frameIndex: frameIndex
//                )
//                keypointDataArray.append(keypointData)
//            }
//        }
//
//        return keypointDataArray
//    }
//}
//
//// MARK: - VitPoseProcessor Extension
//// This extension adds support for colored keypoints and updating keypoints
//extension VitPoseProcessor {
//    // Update a keypoint at a specific index for a frame
//    func updateKeypoint(_ keypoint: KeypointData, at index: Int, forFrame frameIndex: Int) {
//        // Check if we have keypoints for this frame
//        guard var frameKeypoints = keypointsByFrame[frameIndex],
//              index < frameKeypoints.count else {
//            print("Cannot update keypoint: Invalid frame or index")
//            return
//        }
//
//        // Store the updated keypoint
//        frameKeypoints[index] = keypoint
//
//        // Update the keypoints in the dictionary
//        keypointsByFrame[frameIndex] = frameKeypoints
//
//        // Clear the processed image for this frame so it will be regenerated
//        processedImages[frameIndex] = nil
//
//        print("Updated keypoint '\(keypoint.name)' at position (\(keypoint.x), \(keypoint.y)) for frame \(frameIndex)")
//    }
//
//    // Enhanced visualization method with different colors for left and right body parts
//    func visualizeKeypointsForFrame(
//        _ frameIndex: Int,
//        originalImage: UIImage,
//        leftColor: UIColor = .blue,
//        rightColor: UIColor = .red,
//        centerColor: UIColor = .green
//    ) -> UIImage? {
//        guard let keypoints = keypointsByFrame[frameIndex] else { return nil }
//
//        let renderer = UIGraphicsImageRenderer(size: originalImage.size)
//
//        return renderer.image { context in
//            // Draw the original image first
//            originalImage.draw(in: CGRect(origin: .zero, size: originalImage.size))
//
//            let ctx = context.cgContext
//
//            // Create a dictionary for faster keypoint lookup
//            let keypointDict = Dictionary(uniqueKeysWithValues: keypoints.map {
//                ($0.name, (CGPoint(x: $0.x, y: $0.y), $0.confidence, $0.depth))
//            })
//
//            // Draw skeleton connections
//            ctx.setLineWidth(3.0)
//
//            for (startName, endName) in skeletonConnections {
//                guard let start = keypointDict[startName],
//                      let end = keypointDict[endName] else {
//                    continue
//                }
//
//                // Only draw if both keypoints have good confidence
//                if start.1 > 0.15 && end.1 > 0.15 {
//                    // Determine line color based on keypoint names
//                    if startName.contains("left") || endName.contains("left") {
//                        ctx.setStrokeColor(leftColor.cgColor)
//                    } else if startName.contains("right") || endName.contains("right") {
//                        ctx.setStrokeColor(rightColor.cgColor)
//                    } else {
//                        ctx.setStrokeColor(centerColor.cgColor)
//                    }
//
//                    ctx.move(to: start.0)
//                    ctx.addLine(to: end.0)
//                    ctx.strokePath()
//                }
//            }
//
//            // Draw keypoints
//            for keypoint in keypoints {
//                if keypoint.confidence > 0.15 {
//                    // Choose color based on keypoint name
//                    let color: UIColor
//                    if keypoint.name.contains("left") {
//                        color = leftColor
//                    } else if keypoint.name.contains("right") {
//                        color = rightColor
//                    } else {
//                        color = centerColor
//                    }
//
//                    ctx.setFillColor(color.cgColor)
//
//                    // Size based on confidence
//                    let size = 8.0 + (CGFloat(keypoint.confidence) * 4.0)
//                    let point = CGPoint(x: keypoint.x, y: keypoint.y)
//                    let rect = CGRect(x: point.x - size/2, y: point.y - size/2, width: size, height: size)
//                    ctx.fillEllipse(in: rect)
//
//                    // Draw a white border
//                    ctx.setStrokeColor(UIColor.white.cgColor)
//                    ctx.setLineWidth(1.0)
//                    ctx.strokeEllipse(in: rect)
//
//                    // Draw keypoint index for easier identification
//                    if let index = keypoints.firstIndex(where: { $0.name == keypoint.name }) {
//                        let indexText = "\(index)" as NSString
//                        let attributes: [NSAttributedString.Key: Any] = [
//                            .font: UIFont.boldSystemFont(ofSize: 10),
//                            .foregroundColor: UIColor.white
//                        ]
//
//                        indexText.draw(at: CGPoint(x: point.x + 6, y: point.y - 5), withAttributes: attributes)
//                    }
//                }
//            }
//        }
//    }
//}
//
////// KeypointData structure if not already defined
////struct KeypointData: Identifiable {
////    let id: Int
////    let name: String
////    let x: Float
////    let y: Float
////    let depth: Float
////    let confidence: Float
////}
//class FrameUpdatePublisher {
//    static let shared = FrameUpdatePublisher()
//
//    let publisher = PassthroughSubject<Int, Never>()
//
//    func notifyFrameChanged(frameIndex: Int) {
//        publisher.send(frameIndex)
//    }
//}
//
import Foundation
import CoreML
import UIKit
import Metal
import Combine

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

    
    // Keypoint names in COCO format
    private let keypointNames = [
        "nose", "left_eye", "right_eye", "left_ear", "right_ear",
        "left_shoulder", "right_shoulder", "left_elbow", "right_elbow",
        "left_wrist", "right_wrist", "left_hip", "right_hip",
        "left_knee", "right_knee", "left_ankle", "right_ankle"
    ]
    
    // Skeleton connections for visualization
    private let skeletonConnections = [
        ("left_shoulder", "right_shoulder"),
        ("left_shoulder", "left_elbow"),
        ("right_shoulder", "right_elbow"),
        ("left_elbow", "left_wrist"),
        ("right_elbow", "right_wrist"),
        ("left_shoulder", "left_hip"),
        ("right_shoulder", "right_hip"),
        ("left_hip", "right_hip"),
        ("left_hip", "left_knee"),
        ("right_hip", "right_knee"),
        ("left_knee", "left_ankle"),
        ("right_knee", "right_ankle"),
        ("nose", "left_eye"),
        ("nose", "right_eye"),
        ("left_eye", "left_ear"),
        ("right_eye", "right_ear")
    ]
    
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
    
    // MARK: - Public Methods
    
    /// Process an image to detect pose keypoints and integrate depth data
    func processImage(colorImage: UIImage, depthTexture: MTLTexture, frameIndex: Int) throws -> (keypointData: [KeypointData], visualizedImage: UIImage) {
        guard self.vitposeModel != nil else {
            throw ProcessingError.modelNotLoaded("VitPose model is not loaded")
        }
        
        // Process the image to get keypoints
        let keypoints = try detectKeypoints(from: colorImage, frameIndex: frameIndex)
        
        // Add depth information to keypoints
        var keypointsWithDepth: [KeypointData] = []
        for keypoint in keypoints {
            let position = CGPoint(x: keypoint.x, y: keypoint.y)
            let depthValue = getDepthValue(at: position, from: depthTexture, imageSize: colorImage.size)
            
            let keypointWithDepth = KeypointData(
                name: keypoint.name,
                x: keypoint.x,
                y: keypoint.y,
                confidence: keypoint.confidence,
                depth: depthValue,
                frameIndex: frameIndex
            )
            keypointsWithDepth.append(keypointWithDepth)
        }
        
        // Create visualization
        let mappedKeypoints = keypointsWithDepth.map { keypoint -> (String, CGPoint, Float, Float) in
            return (keypoint.name, CGPoint(x: keypoint.x, y: keypoint.y), keypoint.confidence, keypoint.depth)
        }
        
        let visualizedImage = visualizePose(colorImage: colorImage, keypoints: mappedKeypoints, connections: skeletonConnections)
        
        // Store the data
        keypointsByFrame[frameIndex] = keypointsWithDepth
        processedImages[frameIndex] = visualizedImage ?? colorImage
        
        return (keypointData: keypointsWithDepth, visualizedImage: visualizedImage ?? colorImage)
    }
    
    /// Process a frame without depth data - 2D pose estimation only
//    func processImageWithoutDepth(colorImage: UIImage, frameIndex: Int) throws -> (visualizedImage: UIImage, keypoints: [KeypointData]) {
//        // Get keypoints without depth
//        let keypoints = try detectKeypoints(from: colorImage, frameIndex: frameIndex)
//
//        // Convert for visualization
//        let mappedKeypoints = keypoints.map { keypoint -> (String, CGPoint, Float, Float) in
//            return (keypoint.name, CGPoint(x: keypoint.x, y: keypoint.y), keypoint.confidence, 0.0)
//        }
//
//        // Create visualization
//        let visualizedImage = visualizePose(colorImage: colorImage, keypoints: mappedKeypoints, connections: skeletonConnections)
//
//        // Store the data
//        keypointsByFrame[frameIndex] = keypoints
//        processedImages[frameIndex] = visualizedImage ?? colorImage
//
//        return (visualizedImage: visualizedImage ?? colorImage, keypoints: keypoints)
//    }
    
    // MARK: - Keypoint Data Management
    
    /// Get keypoints for a specific frame
    func getKeypoints(for frameIndex: Int) -> [KeypointData]? {
        return keypointsByFrame[frameIndex]
    }
    
    /// Get a list of all frame indices that have keypoint data
    func getFrameIndicesWithKeypoints() -> [Int] {
        return Array(keypointsByFrame.keys).sorted()
    }
    
    /// Get the processed image for a specific frame
//    func getProcessedImage(for frameIndex: Int) -> UIImage? {
//        return processedImages[frameIndex]
//    }
    
    /// Store additional keypoints
    func storeKeypoints(_ keypoints: [KeypointData], for frameIndex: Int) {
        keypointsByFrame[frameIndex] = keypoints
    }
    
    /// Store a processed image
//    func storeProcessedImage(_ image: UIImage, for frameIndex: Int) {
//        processedImages[frameIndex] = image
//    }
//
    /// Clear all stored data
    func clearAllData() {
        keypointsByFrame.removeAll()
        processedImages.removeAll()
    }
    
    /// Update a keypoint at a specific index for a frame
//    func updateKeypoint(_ keypoint: KeypointData, at index: Int, forFrame frameIndex: Int) {
//        guard var frameKeypoints = keypointsByFrame[frameIndex],
//              index < frameKeypoints.count else {
//            print("Cannot update keypoint: Invalid frame or index")
//            return
//        }
//
//        frameKeypoints[index] = keypoint
//        keypointsByFrame[frameIndex] = frameKeypoints
//        processedImages[frameIndex] = nil
//
//        print("Updated keypoint '\(keypoint.name)' at position (\(keypoint.x), \(keypoint.y)) for frame \(frameIndex)")
//    }
//    func updateKeypoint(_ keypoint: KeypointData, at index: Int, forFrame frameIndex: Int) {
//        // Validate inputs
//        guard !keypoint.x.isNaN, !keypoint.x.isInfinite,
//              !keypoint.y.isNaN, !keypoint.y.isInfinite else {
//            print("Invalid coordinate values: x=\(keypoint.x), y=\(keypoint.y)")
//            return
//        }
//
//        // Check if we have existing keypoints for this frame
//        if var frameKeypoints = keypointsByFrame[frameIndex] {
//            // Make sure the index is valid
//            guard index < frameKeypoints.count else {
//                print("Cannot update keypoint: Index \(index) is out of bounds for frame \(frameIndex)")
//                return
//            }
//
//            // Update the specific keypoint
//            frameKeypoints[index] = keypoint
//
//            // Store updated keypoints
//            keypointsByFrame[frameIndex] = frameKeypoints
//
//            // Clear cached processed image for this frame so it gets redrawn
//            processedImages[frameIndex] = nil
//
//            print("Updated keypoint '\(keypoint.name)' at position (\(keypoint.x), \(keypoint.y)) for frame \(frameIndex)")
//        } else {
//            print("No keypoints found for frame \(frameIndex)")
//        }
//    }
    // In VitPoseProcessor
    func updateKeypoint(_ keypoint: KeypointData, at index: Int, forFrame frameIndex: Int) {
        // Check if we have keypoints for this frame
        if var frameKeypoints = keypointsByFrame[frameIndex],
           index < frameKeypoints.count {
            // Update the keypoint
            let oldKeypoint = frameKeypoints[index]
            frameKeypoints[index] = keypoint
            
            // Store the updated array back in the dictionary
            keypointsByFrame[frameIndex] = frameKeypoints
            
            print("VitPoseProcessor: Updated keypoint \(index) for frame \(frameIndex) from (\(oldKeypoint.x), \(oldKeypoint.y)) to (\(keypoint.x), \(keypoint.y))")
            
            // IMPORTANT: If you're caching visualized frames, you need to clear the cache for this frame
            visualizedFrameCache.removeObject(forKey: NSNumber(value: frameIndex))
        } else {
            print("VitPoseProcessor: Failed to update keypoint - index out of bounds or no keypoints for frame")
        }
    }
    
    // Add this method to your VitPoseProcessor class
    func clearCacheForFrame(_ frameIndex: Int) {
        visualizedFrameCache.removeObject(forKey: NSNumber(value: frameIndex))
        print("Cleared visualization cache for frame \(frameIndex)")
    }
    
    // MARK: - Visualization Methods
    
    /// Visualize keypoints with custom colors
//    func visualizeKeypointsForFrame(
//        _ frameIndex: Int,
//        originalImage: UIImage,
//        leftColor: UIColor = .blue,
//        rightColor: UIColor = .red,
//        centerColor: UIColor = .green
//    ) -> UIImage? {
//        guard let keypoints = keypointsByFrame[frameIndex] else { return nil }
//
//        let renderer = UIGraphicsImageRenderer(size: originalImage.size)
//
//        return renderer.image { context in
//            // Draw original image
//            originalImage.draw(in: CGRect(origin: .zero, size: originalImage.size))
//
//            let ctx = context.cgContext
//
//            // Create lookup dictionary
//            let keypointDict = Dictionary(uniqueKeysWithValues: keypoints.map {
//                ($0.name, (CGPoint(x: $0.x, y: $0.y), $0.confidence, $0.depth))
//            })
//
//            // Draw connections
//            ctx.setLineWidth(3.0)
//
//            for (startName, endName) in skeletonConnections {
//                guard let start = keypointDict[startName],
//                      let end = keypointDict[endName] else {
//                    continue
//                }
//
//                if start.1 > 0.15 && end.1 > 0.15 {
//                    // Determine line color
//                    if startName.contains("left") || endName.contains("left") {
//                        ctx.setStrokeColor(leftColor.cgColor)
//                    } else if startName.contains("right") || endName.contains("right") {
//                        ctx.setStrokeColor(rightColor.cgColor)
//                    } else {
//                        ctx.setStrokeColor(centerColor.cgColor)
//                    }
//
//                    ctx.move(to: start.0)
//                    ctx.addLine(to: end.0)
//                    ctx.strokePath()
//                }
//            }
//
//            // Draw keypoints
//            for keypoint in keypoints {
//                if keypoint.confidence > 0.15 {
//                    // Choose color based on name
//                    let color: UIColor
//                    if keypoint.name.contains("left") {
//                        color = leftColor
//                    } else if keypoint.name.contains("right") {
//                        color = rightColor
//                    } else {
//                        color = centerColor
//                    }
//
//                    ctx.setFillColor(color.cgColor)
//
//                    let size = 8.0 + (CGFloat(keypoint.confidence) * 4.0)
//                    let point = CGPoint(x: keypoint.x, y: keypoint.y)
//                    let rect = CGRect(x: point.x - size/2, y: point.y - size/2, width: size, height: size)
//                    ctx.fillEllipse(in: rect)
//
//                    // White border
//                    ctx.setStrokeColor(UIColor.white.cgColor)
//                    ctx.setLineWidth(1.0)
//                    ctx.strokeEllipse(in: rect)
//
//                    // Draw index for identification
//                    if let index = keypoints.firstIndex(where: { $0.name == keypoint.name }) {
//                        let indexText = "\(index)" as NSString
//                        let attributes: [NSAttributedString.Key: Any] = [
//                            .font: UIFont.boldSystemFont(ofSize: 10),
//                            .foregroundColor: UIColor.white
//                        ]
//                        indexText.draw(at: CGPoint(x: point.x + 6, y: point.y - 5), withAttributes: attributes)
//                    }
//                }
//            }
//        }
//    }
    func visualizeKeypointsForFrame(
        _ frameIndex: Int,
        originalImage: UIImage,
        leftColor: UIColor = .blue,
        rightColor: UIColor = .red,
        centerColor: UIColor = .green,
        applyRotation: Double = 0
    ) -> UIImage? {
        guard let keypoints = keypointsByFrame[frameIndex] else { return nil }
        
        // For annotation mode, the image is already rotated, so we don't need to rotate keypoints
        if applyRotation == 0 {
            // Just draw keypoints directly on the image (which might already be rotated)
            let renderer = UIGraphicsImageRenderer(size: originalImage.size)
            
            return renderer.image { context in
                // Draw original image
                originalImage.draw(in: CGRect(origin: .zero, size: originalImage.size))
                
                let ctx = context.cgContext
                
                // Create lookup dictionary for connections
                let keypointDict = Dictionary(uniqueKeysWithValues: keypoints.map {
                    ($0.name, (CGPoint(x: $0.x, y: $0.y), $0.confidence, $0.depth))
                })
                
                // Draw connections
                ctx.setLineWidth(3.0)
                
                for (startName, endName) in skeletonConnections {
                    guard let start = keypointDict[startName],
                          let end = keypointDict[endName] else {
                        continue
                    }
                    
                    if start.1 > 0.15 && end.1 > 0.15 {
                        // Determine line color
                        if startName.contains("left") || endName.contains("left") {
                            ctx.setStrokeColor(leftColor.cgColor)
                        } else if startName.contains("right") || endName.contains("right") {
                            ctx.setStrokeColor(rightColor.cgColor)
                        } else {
                            ctx.setStrokeColor(centerColor.cgColor)
                        }
                        
                        // Draw connection line
                        ctx.move(to: start.0)
                        ctx.addLine(to: end.0)
                        ctx.strokePath()
                    }
                }
                
                // Draw keypoints
                for keypoint in keypoints {
                    if keypoint.confidence > 0.15 {
                        // Choose color based on name
                        let color: UIColor
                        if keypoint.name.contains("left") {
                            color = leftColor
                        } else if keypoint.name.contains("right") {
                            color = rightColor
                        } else {
                            color = centerColor
                        }
                        
                        ctx.setFillColor(color.cgColor)
                        
                        let position = CGPoint(x: keypoint.x, y: keypoint.y)
                        let size = 8.0 + (CGFloat(keypoint.confidence) * 4.0)
                        let rect = CGRect(x: position.x - size/2, y: position.y - size/2, width: size, height: size)
                        ctx.fillEllipse(in: rect)
                        
                        // White border
                        ctx.setStrokeColor(UIColor.white.cgColor)
                        ctx.setLineWidth(1.0)
                        ctx.strokeEllipse(in: rect)
                        
                        // Draw index for identification
                        if let index = keypoints.firstIndex(where: { $0.name == keypoint.name }) {
                            let indexText = "\(index)" as NSString
                            let attributes: [NSAttributedString.Key: Any] = [
                                .font: UIFont.boldSystemFont(ofSize: 10),
                                .foregroundColor: UIColor.white
                            ]
                            indexText.draw(at: CGPoint(x: position.x + 6, y: position.y - 5), withAttributes: attributes)
                        }
                    }
                }
            }
        }
        // For normal viewing mode, we need to handle rotation of the image and keypoints together
        else {
            // For exact 90-degree rotations, use orientation-based image rotation
            if applyRotation.truncatingRemainder(dividingBy: 90) == 0 {
                guard let cgImage = originalImage.cgImage else { return nil }
                
                // Normalize rotation to 0-360
                var normalizedRotation = applyRotation.truncatingRemainder(dividingBy: 360)
                if normalizedRotation < 0 { normalizedRotation += 360 }
                
                // Map rotation angle to UIImage.Orientation
                var orientation: UIImage.Orientation
                switch Int(normalizedRotation) {
                case 90:
                    orientation = .right
                case 180:
                    orientation = .down
                case 270:
                    orientation = .left
                default:
                    orientation = .up
                }
                
                // Create rotated base image
                let rotatedImage = UIImage(cgImage: cgImage, scale: originalImage.scale, orientation: orientation)
                
                // Transform the keypoints to match the rotated image
                let centerX = originalImage.size.width / 2
                let centerY = originalImage.size.height / 2
                
                // Create a copy of keypoints to transform
                var transformedKeypoints = [KeypointData]()
                
                for keypoint in keypoints {
                    var newKeypoint = keypoint
                    
                    // Calculate offset from center
                    let offsetX = keypoint.x - centerX
                    let offsetY = keypoint.y - centerY
                    
                    // Apply appropriate transformation based on rotation angle
                    switch Int(normalizedRotation) {
                    case 90:
                        // 90° clockwise: (x,y) -> (y,-x)
                        newKeypoint.x = centerX + offsetY
                        newKeypoint.y = centerY - offsetX
                    case 180:
                        // 180° rotation: (x,y) -> (-x,-y)
                        newKeypoint.x = centerX - offsetX
                        newKeypoint.y = centerY - offsetY
                    case 270:
                        // 270° clockwise: (x,y) -> (-y,x)
                        newKeypoint.x = centerX - offsetY
                        newKeypoint.y = centerY + offsetX
                    default:
                        break
                    }
                    
                    transformedKeypoints.append(newKeypoint)
                }
                
                // Create temporary copy of keypoints for visualization
                let originalKeypointsByFrame = keypointsByFrame[frameIndex]
                keypointsByFrame[frameIndex] = transformedKeypoints
                
                // Visualize using the rotated image and transformed keypoints with no further rotation
                let result = visualizeKeypointsForFrame(
                    frameIndex,
                    originalImage: rotatedImage,
                    leftColor: leftColor,
                    rightColor: rightColor,
                    centerColor: centerColor,
                    applyRotation: 0
                )
                
                // Restore original keypoints
                keypointsByFrame[frameIndex] = originalKeypointsByFrame
                
                return result
            }
            
            // For non-90-degree rotations, use renderer-based approach
            let renderer = UIGraphicsImageRenderer(size: originalImage.size)
            
            return renderer.image { context in
                // Draw original image
                originalImage.draw(in: CGRect(origin: .zero, size: originalImage.size))
                
                let ctx = context.cgContext
                
                // Set up rotation values
                let centerX = originalImage.size.width / 2
                let centerY = originalImage.size.height / 2
                let rotationRadians = applyRotation * .pi / 180.0
                let cosAngle = cos(rotationRadians)
                let sinAngle = sin(rotationRadians)
                
                // Transform keypoints based on rotation
                let transformedKeypoints = keypoints.map { keypoint -> (KeypointData, CGPoint) in
                    // Default position
                    var position = CGPoint(x: keypoint.x, y: keypoint.y)
                    
                    // Calculate offset from center
                    let offsetX = keypoint.x - centerX
                    let offsetY = keypoint.y - centerY
                    
                    // Apply rotation transformation
                    let newOffsetX = offsetX * cosAngle - offsetY * sinAngle
                    let newOffsetY = offsetX * sinAngle + offsetY * cosAngle
                    
                    // Set rotated position
                    position = CGPoint(
                        x: centerX + newOffsetX,
                        y: centerY + newOffsetY
                    )
                    
                    return (keypoint, position)
                }
                
                // Create lookup dictionary for connections
                let keypointDict = Dictionary(uniqueKeysWithValues: transformedKeypoints.map {
                    ($0.0.name, ($0.1, $0.0.confidence, $0.0.depth))
                })
                
                // Draw connections
                ctx.setLineWidth(3.0)
                
                for (startName, endName) in skeletonConnections {
                    guard let start = keypointDict[startName],
                          let end = keypointDict[endName] else {
                        continue
                    }
                    
                    if start.1 > 0.15 && end.1 > 0.15 {
                        // Determine line color
                        if startName.contains("left") || endName.contains("left") {
                            ctx.setStrokeColor(leftColor.cgColor)
                        } else if startName.contains("right") || endName.contains("right") {
                            ctx.setStrokeColor(rightColor.cgColor)
                        } else {
                            ctx.setStrokeColor(centerColor.cgColor)
                        }
                        
                        // Use transformed positions for drawing
                        ctx.move(to: start.0)
                        ctx.addLine(to: end.0)
                        ctx.strokePath()
                    }
                }
                
                // Draw keypoints using transformed positions
                for (keypoint, position) in transformedKeypoints {
                    if keypoint.confidence > 0.15 {
                        // Choose color based on name
                        let color: UIColor
                        if keypoint.name.contains("left") {
                            color = leftColor
                        } else if keypoint.name.contains("right") {
                            color = rightColor
                        } else {
                            color = centerColor
                        }
                        
                        ctx.setFillColor(color.cgColor)
                        
                        let size = 8.0 + (CGFloat(keypoint.confidence) * 4.0)
                        let rect = CGRect(x: position.x - size/2, y: position.y - size/2, width: size, height: size)
                        ctx.fillEllipse(in: rect)
                        
                        // White border
                        ctx.setStrokeColor(UIColor.white.cgColor)
                        ctx.setLineWidth(1.0)
                        ctx.strokeEllipse(in: rect)
                        
                        // Draw index for identification
                        if let index = keypoints.firstIndex(where: { $0.name == keypoint.name }) {
                            let indexText = "\(index)" as NSString
                            let attributes: [NSAttributedString.Key: Any] = [
                                .font: UIFont.boldSystemFont(ofSize: 10),
                                .foregroundColor: UIColor.white
                            ]
                            indexText.draw(at: CGPoint(x: position.x + 6, y: position.y - 5), withAttributes: attributes)
                        }
                    }
                }
            }
        }
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
    
    /// Import keypoints from a file
    func importKeypoints(from fileURL: URL) throws {
        let data = try Data(contentsOf: fileURL)
        
        if fileURL.pathExtension.lowercased() == "json" {
            do {
                // Try parsing as an array of KeypointData
                let decoder = JSONDecoder()
                let keypoints = try decoder.decode([KeypointData].self, from: data)
                
                // Organize by frame index
                keypointsByFrame.removeAll()
                for keypoint in keypoints {
                    if keypointsByFrame[keypoint.frameIndex] == nil {
                        keypointsByFrame[keypoint.frameIndex] = []
                    }
                    keypointsByFrame[keypoint.frameIndex]?.append(keypoint)
                }
            } catch {
                // Try the dictionary format if the array format fails
                if let jsonObject = try JSONSerialization.jsonObject(with: data, options: []) as? [String: Any] {
                    keypointsByFrame.removeAll()
                    
                    // Check for different JSON structures
                    if let framesData = jsonObject["frames"] as? [String: [[String: Any]]] {
                        // Format with "frames" key
                        for (key, points) in framesData {
                            if key.hasPrefix("frame_"),
                               let frameIndexString = key.split(separator: "_").last,
                               let frameIndex = Int(frameIndexString) {
                                
                                parseKeypointsFromDictionary(points, frameIndex: frameIndex)
                            }
                        }
                    } else if let keypointsArray = jsonObject["keypoints"] as? [[String: Any]],
                              let frameInfo = jsonObject["frameInfo"] as? [String: Any],
                              let frameIndex = frameInfo["index"] as? Int {
                        // Single frame format
                        parseKeypointsFromDictionary(keypointsArray, frameIndex: frameIndex)
                    } else if jsonObject.keys.contains(where: { $0.hasPrefix("frame_") }) {
                        // Direct frame dictionary format
                        for (key, points) in jsonObject {
                            if key.hasPrefix("frame_"),
                               let frameIndexString = key.split(separator: "_").last,
                               let frameIndex = Int(frameIndexString),
                               let pointsArray = points as? [[String: Any]] {
                                
                                parseKeypointsFromDictionary(pointsArray, frameIndex: frameIndex)
                            }
                        }
                    } else {
                        throw ProcessingError.invalidFormat("Unrecognized JSON format")
                    }
                } else {
                    throw ProcessingError.invalidFormat("Invalid JSON format")
                }
            }
        } else if fileURL.pathExtension.lowercased() == "xml" {
            throw ProcessingError.unsupportedFormat("XML import not implemented yet")
        } else {
            throw ProcessingError.unsupportedFormat("Unsupported file format: \(fileURL.pathExtension)")
        }
    }
    
    // MARK: - Private Helper Methods
    
    /// Parse keypoints from dictionary array
    private func parseKeypointsFromDictionary(_ points: [[String: Any]], frameIndex: Int) {
        var keypointsForFrame: [KeypointData] = []
        
        for point in points {
            if let name = point["name"] as? String,
               let x = (point["x"] as? NSNumber)?.doubleValue ?? (point["x"] as? Double),
               let y = (point["y"] as? NSNumber)?.doubleValue ?? (point["y"] as? Double),
               let confidence = (point["confidence"] as? NSNumber)?.floatValue ?? (point["confidence"] as? Float),
               let depth = (point["depth"] as? NSNumber)?.floatValue ?? (point["depth"] as? Float) {
                
                let keypoint = KeypointData(
                    name: name,
                    x: CGFloat(x),
                    y: CGFloat(y),
                    confidence: confidence,
                    depth: depth,
                    frameIndex: frameIndex
                )
                keypointsForFrame.append(keypoint)
            }
        }
        
        keypointsByFrame[frameIndex] = keypointsForFrame
    }
    
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
    
    /// Get depth value for a point
    private func getDepthValue(at point: CGPoint, from depthTexture: MTLTexture, imageSize: CGSize) -> Float {
        // Convert point to depth texture coordinates
        let depthWidth = depthTexture.width
        let depthHeight = depthTexture.height
        
        let depthX = Int(point.x * CGFloat(depthWidth) / imageSize.width)
        let depthY = Int(point.y * CGFloat(depthHeight) / imageSize.height)
        
        // Check bounds
        guard depthX >= 0, depthX < depthWidth, depthY >= 0, depthY < depthHeight else {
            return 0.0
        }
        
        // Read depth value
        var depthValue: Float16 = 0.0
        let region = MTLRegionMake2D(depthX, depthY, 1, 1)
        let bytesPerRow = MemoryLayout<Float16>.size
        
        depthTexture.getBytes(&depthValue, bytesPerRow: bytesPerRow, from: region, mipmapLevel: 0)
        
        return Float(depthValue)
    }
    
    /// Visualize pose with keypoints and connections
    private func visualizePose(
        colorImage: UIImage,
        keypoints: [(String, CGPoint, Float, Float)],
        connections: [(String, String)]
    ) -> UIImage? {
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
    
    // In VitPoseProcessor class

    

    // Method to get a cached processed image
    func getProcessedImage(for frameIndex: Int) -> UIImage? {
        return visualizedFrameCache.object(forKey: NSNumber(value: frameIndex))
    }

    // Method to store a processed image
    func storeProcessedImage(_ image: UIImage, for frameIndex: Int) {
        visualizedFrameCache.setObject(image, forKey: NSNumber(value: frameIndex))
    }

    // Method to pre-visualize all frames with keypoints
    // Method to pre-visualize all frames with keypoints
    func preVisualizeKeypoints(originalImages: [UIImage],
                              leftColor: UIColor,
                              rightColor: UIColor,
                              centerColor: UIColor,
                              completion: @escaping () -> Void) {
        
        // Get all frame indices with keypoints
        let frameIndices = getFrameIndicesWithKeypoints()
        let totalFrames = frameIndices.count
        var processedCount = 0
        
        print("Pre-visualizing \(totalFrames) frames with keypoints")
        
        // Skip if no frames to process
        if totalFrames == 0 {
            completion()
            return
        }
        
        // Process frames in background
        DispatchQueue.global(qos: .userInitiated).async {
            for frameIndex in frameIndices {
                // Check if the frameIndex is valid for our images array
                if frameIndex < originalImages.count {
                    // Get the keypoints for this frame
                    if self.getKeypoints(for: frameIndex) != nil {
                        // Get the image without conditional binding since it's not optional
                        let originalImage = originalImages[frameIndex]
                        
                        // Only visualize if we don't already have it cached
                        if self.getProcessedImage(for: frameIndex) == nil {
                            if let visualized = self.visualizeKeypointsForFrame(
                                frameIndex,
                                originalImage: originalImage,
                                leftColor: leftColor,
                                rightColor: rightColor,
                                centerColor: centerColor
                            ) {
                                self.storeProcessedImage(visualized, for: frameIndex)
                            }
                        }
                        
                        processedCount += 1
                        if processedCount % 10 == 0 {
                            print("Pre-visualized \(processedCount)/\(totalFrames) frames")
                        }
                    }
                }
            }
            
            DispatchQueue.main.async {
                print("✅ Completed pre-visualization of \(processedCount) frames")
                completion()
            }
        }
    }
    
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
}
// In VitPoseProcessor.swift - completely rewrite processFrames with robust threading

extension VitPoseProcessor {
//    func processFrames(from cameraManager: CameraLiDARManager, progress: @escaping (Double) -> Void, completion: @escaping (Bool, Error?) -> Void) {
//        // First, verify on main thread that we have frames to process
//        DispatchQueue.main.async {
//            let totalFrames = cameraManager.totalFrames
//            guard totalFrames > 0 else {
//                print("No frames available for processing")
//                completion(false, ProcessingError.noKeypointData("No frames available for processing"))
//                return
//            }
//
//            print("Starting pose detection on \(totalFrames) frames")
//
//            // Launch background processing task
//            DispatchQueue.global(qos: .userInitiated).async {
//                // Track processed frames count
//                var processedFrames = 0
//
//                // Clear existing keypoint data before processing
//                DispatchQueue.main.sync {
//                    self.keypointsByFrame.removeAll()
//                    self.visualizedFrameCache.removeAllObjects()
//                }
//
//                // Process each frame
//                for frameIndex in 0..<totalFrames {
//                    // Thread-safe way to get frame
//                    var currentImage: UIImage?
//                    DispatchQueue.main.sync {
//                        currentImage = cameraManager.getFrame(at: frameIndex)
//                    }
//
//                    guard let image = currentImage else {
//                        print("⚠️ Could not access frame \(frameIndex)")
//                        continue
//                    }
//
//                    do {
//                        // Process this frame
//                        let result = try self.processImageWithoutDepth(colorImage: image, frameIndex: frameIndex)
//
//                        // Update processed count and calculate progress
//                        processedFrames += 1
//                        let progressValue = Double(processedFrames) / Double(totalFrames)
//
//                        // Report progress on main thread
//                        DispatchQueue.main.async {
//                            progress(progressValue)
//                        }
//
//                        // Print log updates at intervals
//                        if processedFrames % 10 == 0 || processedFrames == totalFrames {
//                            print("Processed \(processedFrames)/\(totalFrames) frames")
//                        }
//                    } catch {
//                        // Handle error
//                        print("Error processing frame \(frameIndex): \(error)")
//
//                        // Report error on main thread
//                        DispatchQueue.main.async {
//                            completion(false, error)
//                        }
//                        return
//                    }
//                }
//
//                // Successfully processed all frames
//                print("✅ Pose detection complete. Processed \(processedFrames) frames.")
//
//                // IMPORTANT: Wait a brief moment to ensure any queued UI operations complete
//                // before signaling completion
//                Thread.sleep(forTimeInterval: 0.5)
//
//                // Complete on main thread
//                DispatchQueue.main.async {
//                    completion(true, nil)
//                }
//            }
//        }
//    }
    
    // Thread-safe version of processImageWithoutDepth
    func processImageWithoutDepth(colorImage: UIImage, frameIndex: Int) throws -> (visualizedImage: UIImage, keypoints: [KeypointData]) {
        // Detect keypoints
        let keypoints = try detectKeypoints(from: colorImage, frameIndex: frameIndex)
        
        // Convert for visualization
        let mappedKeypoints = keypoints.map { keypoint -> (String, CGPoint, Float, Float) in
            return (keypoint.name, CGPoint(x: keypoint.x, y: keypoint.y), keypoint.confidence, 0.0)
        }
        
        // Create visualization
        let visualizedImage = visualizePose(colorImage: colorImage, keypoints: mappedKeypoints, connections: skeletonConnections)
        
        // Thread-safe storage of results
        DispatchQueue.main.sync {
            // Store the data
            keypointsByFrame[frameIndex] = keypoints
        }
        
        // Store into cache on main thread (if needed)
        if let image = visualizedImage {
            DispatchQueue.main.sync {
                visualizedFrameCache.setObject(image, forKey: NSNumber(value: frameIndex))
            }
        }
        
        return (visualizedImage: visualizedImage ?? colorImage, keypoints: keypoints)
    }
}

// Add this method to your VitPoseProcessor class to provide safer keypoint access
extension VitPoseProcessor {
    // Thread-safe and null-safe method to get keypoints
    func getSafeKeypoints(for frameIndex: Int) -> [KeypointData] {
        // First check if we're on the main thread - if not, use sync to safely access
        if !Thread.isMainThread {
            var result: [KeypointData] = []
            DispatchQueue.main.sync {
                result = self.getSafeKeypoints(for: frameIndex)
            }
            return result
        }
        
        // Now we're on the main thread, safely access the data
        guard let keypoints = keypointsByFrame[frameIndex],
              !keypoints.isEmpty else {
            // Return empty array instead of nil
            return []
        }
        
        return keypoints
    }
    
    // Check if a frame has valid keypoints
    func hasValidKeypoints(for frameIndex: Int) -> Bool {
        if !Thread.isMainThread {
            var result = false
            DispatchQueue.main.sync {
                result = self.hasValidKeypoints(for: frameIndex)
            }
            return result
        }
        
        return keypointsByFrame[frameIndex]?.isEmpty == false
    }
}

// Add this method to VitPoseProcessor to handle orientation more gracefully
extension VitPoseProcessor {
    // Process a frame with orientation correction and safety checks
    func processFrameWithSafetyChecks(frame: UIImage, frameIndex: Int) -> (keypoints: [KeypointData], visualizedImage: UIImage?) {
        do {
            // Log frame dimensions for debugging
            print("Processing frame \(frameIndex): \(frame.size.width)x\(frame.size.height), orientation: \(frame.imageOrientation.rawValue)")
            
            // Ensure the frame is in the correct orientation
            let correctedFrame = ensureCorrectOrientation(image: frame)
            
            // Process the corrected frame
            let result = try processImageWithoutDepth(colorImage: correctedFrame, frameIndex: frameIndex)
            
            return (result.keypoints, result.visualizedImage)
        } catch {
            print("Error processing frame \(frameIndex): \(error)")
            return ([], nil)
        }
    }
    
    // Ensure image has the correct orientation
//    private func ensureCorrectOrientation(image: UIImage) -> UIImage {
//        // Only modify if not already in up orientation
//        if image.imageOrientation != .up {
//            print("Correcting image orientation from \(image.imageOrientation.rawValue) to .up")
//            
//            // Create a new image with the correct orientation
//            if let cgImage = image.cgImage {
//                return UIImage(cgImage: cgImage, scale: image.scale, orientation: .up)
//            }
//        }
//        
//        return image
//    }
    
    // Improved frame processing with orientation handling
    func processFrames(from cameraManager: CameraLiDARManager, progress: @escaping (Double) -> Void, completion: @escaping (Bool, Error?) -> Void) {
        let totalFrames = cameraManager.totalFrames
        guard totalFrames > 0 else {
            DispatchQueue.main.async {
                completion(false, ProcessingError.noKeypointData("No frames available for processing"))
            }
            return
        }
        
        print("Starting pose detection on \(totalFrames) frames")
        var processedFrames = 0
        
        // Use a background queue with higher priority for processing
        DispatchQueue.global(qos: .userInitiated).async {
            // Clear existing data to start fresh
            DispatchQueue.main.sync {
                self.keypointsByFrame.removeAll()
                self.visualizedFrameCache.removeAllObjects()
            }
            
            // Loop through all frames
            for frameIndex in 0..<totalFrames {
                // Get the frame
                var currentImage: UIImage?
                DispatchQueue.main.sync {
                    currentImage = cameraManager.getFrame(at: frameIndex)
                }
                
                guard let image = currentImage else {
                    print("⚠️ Could not access frame \(frameIndex)")
                    continue
                }
                
                // Process with safety checks and orientation handling
                let result = self.processFrameWithSafetyChecks(frame: image, frameIndex: frameIndex)
                
                // Safety check for valid keypoints
                if !result.keypoints.isEmpty {
                    // Store keypoints on main thread
                    DispatchQueue.main.sync {
                        self.keypointsByFrame[frameIndex] = result.keypoints
                        
                        // Cache visualized image if available
                        if let visualizedImage = result.visualizedImage {
                            self.visualizedFrameCache.setObject(visualizedImage, forKey: NSNumber(value: frameIndex))
                        }
                    }
                }
                
                // Update processed count and calculate progress
                processedFrames += 1
                let progressValue = Double(processedFrames) / Double(totalFrames)
                
                // Report progress on main thread
                DispatchQueue.main.async {
                    progress(progressValue)
                }
                
                // Print log updates at intervals
                if processedFrames % 10 == 0 || processedFrames == totalFrames {
                    print("Processed \(processedFrames)/\(totalFrames) frames")
                }
            }
            
            // Successfully processed all frames
            print("✅ Pose detection complete. Processed \(processedFrames) frames.")
            
            // Complete on main thread
            DispatchQueue.main.async {
                completion(true, nil)
            }
        }
    }
}
extension VitPoseProcessor {
    // Returns whether keypoints exist and have valid data
    func validateLoadedKeypoints() -> Bool {
        // Check if keypoints exist and have frames
        let totalFrames = self.getTotalFrames()
        if totalFrames <= 0 {
            print("Warning: No frames in keypoint data")
            return false
        }
        
        // Check if first frame has valid keypoints
        guard let firstFrameKeypoints = self.getKeypoints(for: 0) else {
            print("Warning: First frame has nil keypoints")
            return false
        }
        
        if firstFrameKeypoints.isEmpty {
            print("Warning: First frame has empty keypoints array")
            return false
        }
        
        // Check validity of keypoint data in first frame
        var hasValidPositions = false
        for keypoint in firstFrameKeypoints {
            if keypoint.position.x != 0 || keypoint.position.y != 0 {
                hasValidPositions = true
                break
            }
        }
        
        if !hasValidPositions {
            print("Warning: All keypoints in first frame appear to be at (0,0)")
        }
        
        print("Keypoint validation successful: \(totalFrames) frames, \(firstFrameKeypoints.count) keypoints in first frame")
        return true
    }
}
// MARK: - KeypointData Model

//struct KeypointData: Codable, Identifiable {
//    let id: UUID
//    let name: String
//    var x: CGFloat
//    var y: CGFloat
//    let confidence: Float
//    let depth: Float
//    let frameIndex: Int
//
//    // Store original position for reset functionality
//    private let originalX: CGFloat
//    private let originalY: CGFloat
//
//    init(name: String, x: CGFloat, y: CGFloat, confidence: Float, depth: Float, frameIndex: Int) {
//        self.id = UUID()
//        self.name = name
//        self.x = x
//        self.y = y
//        self.confidence = confidence
//        self.depth = depth
//        self.frameIndex = frameIndex
//        self.originalX = x
//        self.originalY = y
//    }
//
//    mutating func updatePosition(to newPosition: CGPoint) {
//        self.x = newPosition.x
//        self.y = newPosition.y
//    }
//
//    mutating func resetPosition() {
//        self.x = originalX
//        self.y = originalY
//    }
//}
// Updated KeypointData struct with Equatable conformance
struct KeypointData: Identifiable, Codable, Equatable {
    let id: UUID
    let name: String
    var x: CGFloat
    var y: CGFloat
    let confidence: Float
    let depth: Float
    let frameIndex: Int
    
    // Store original position for reset functionality
    private let originalX: CGFloat
    private let originalY: CGFloat
    
    init(name: String, x: CGFloat, y: CGFloat, confidence: Float, depth: Float, frameIndex: Int) {
        self.id = UUID()
        self.name = name
        self.x = x
        self.y = y
        self.confidence = confidence
        self.depth = depth
        self.frameIndex = frameIndex
        self.originalX = x
        self.originalY = y
    }
    
    var position: CGPoint {
        return CGPoint(x: x, y: y)
    }
    
    mutating func updatePosition(to newPosition: CGPoint) {
        self.x = newPosition.x
        self.y = newPosition.y
    }
    
    mutating func resetPosition() {
        self.x = originalX
        self.y = originalY
    }
    
    // Implement Equatable
    static func == (lhs: KeypointData, rhs: KeypointData) -> Bool {
        return lhs.id == rhs.id &&
               lhs.name == rhs.name &&
               lhs.x == rhs.x &&
               lhs.y == rhs.y &&
               lhs.confidence == rhs.confidence &&
               lhs.depth == rhs.depth &&
               lhs.frameIndex == rhs.frameIndex
    }
}

// MARK: - Frame Update Publisher

//class FrameUpdatePublisher {
//    static let shared = FrameUpdatePublisher()
//
//    let publisher = PassthroughSubject<Int, Never>()
//
//    func notifyFrameChanged(frameIndex: Int) {
//        publisher.send(frameIndex)
//    }
//}
class FrameUpdatePublisher {
    static let shared = FrameUpdatePublisher()
    
    private init() {}
    
    // Use NotificationCenter for broadcasting frame changes
    func notifyFrameChanged(frameIndex: Int) {
        NotificationCenter.default.post(
            name: NSNotification.Name("FrameChanged"),
            object: nil,
            userInfo: ["frameIndex": frameIndex]
        )
    }
}

// Add this extension to fix the CGImage resize issue

extension CGImage {
    func resize(to size: CGSize) -> CGImage? {
        let width = Int(size.width)
        let height = Int(size.height)
        
        let colorSpace = CGColorSpaceCreateDeviceRGB()
        let bitmapInfo = CGBitmapInfo(rawValue: CGImageAlphaInfo.premultipliedLast.rawValue)
        
        guard let context = CGContext(
            data: nil,
            width: width,
            height: height,
            bitsPerComponent: 8,
            bytesPerRow: width * 4,
            space: colorSpace,
            bitmapInfo: bitmapInfo.rawValue
        ) else {
            return nil
        }
        
        // Draw the original image in the new size
        context.draw(self, in: CGRect(x: 0, y: 0, width: width, height: height))
        
        return context.makeImage()
    }
    
    func toRGBPixels() -> [UInt8]? {
        let width = self.width
        let height = self.height
        
        // Calculate bytes per row with 4 bytes per pixel (RGBA)
        let bytesPerPixel = 4
        let bytesPerRow = width * bytesPerPixel
        
        // Create buffer to hold pixel data
        var buffer = [UInt8](repeating: 0, count: width * height * bytesPerPixel)
        
        let colorSpace = CGColorSpaceCreateDeviceRGB()
        let bitmapInfo = CGBitmapInfo(rawValue: CGImageAlphaInfo.premultipliedLast.rawValue)
        
        // Create CGContext with buffer
        guard let context = CGContext(
            data: &buffer,
            width: width,
            height: height,
            bitsPerComponent: 8,
            bytesPerRow: bytesPerRow,
            space: colorSpace,
            bitmapInfo: bitmapInfo.rawValue
        ) else {
            return nil
        }
        
        // Draw image into context
        context.draw(self, in: CGRect(x: 0, y: 0, width: width, height: height))
        
        return buffer
    }
}
extension VitPoseProcessor {
    func hasKeypoints(for frameIndex: Int) -> Bool {
        return keypointsByFrame[frameIndex] != nil && !keypointsByFrame[frameIndex]!.isEmpty
    }
//
//    func getKeypoints(for frameIndex: Int) -> [KeypointData]? {
//        return keypointsByFrame[frameIndex]
//    }
    
    func getTotalFrames() -> Int {
        return keypointsByFrame.keys.max() ?? 0
    }
    

    func loadKeypoints(from url: URL, completion: @escaping (Bool, Int, Error?) -> Void) {
        do {
            try importKeypoints(from: url)
            let totalFrames = getTotalFrames()
            completion(true, totalFrames, nil)
        } catch {
            completion(false, 0, error)
        }
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
        
        // Override the existing processFrames method to handle ROI
        func processFramesWithROI(
            from cameraManager: CameraLiDARManager,
            progress: @escaping (Double) -> Void,
            completion: @escaping (Bool, Error?) -> Void
        ) {
            let totalFrames = cameraManager.totalFrames
            guard totalFrames > 0 else {
                DispatchQueue.main.async {
                    completion(false, ProcessingError.noKeypointData("No frames available for processing"))
                }
                return
            }
            
            print("Starting ROI-based pose detection on \(totalFrames) frames")
            var processedFrames = 0
            
            DispatchQueue.global(qos: .userInitiated).async {
                // Clear existing data
                DispatchQueue.main.sync {
                    self.clearAllData()
                }
                
                // Process each frame
                for frameIndex in 0..<totalFrames {
                    // Get the frame
                    var currentImage: UIImage?
                    DispatchQueue.main.sync {
                        currentImage = cameraManager.getFrame(at: frameIndex)
                    }
                    
                    guard let originalImage = currentImage else {
                        print("⚠️ Could not access frame \(frameIndex)")
                        continue
                    }
                    
                    do {
                        // Crop to ROI if ROI is set, or use original image
                        let (imageToProcess, roiOffset) = self.cropImageToROI(originalImage) ?? (originalImage, .zero)
                        
                        // Process the frame (either cropped or original)
                        let result = try self.processImageWithoutDepth(colorImage: imageToProcess, frameIndex: frameIndex)
                        
                        // If we used ROI, adjust keypoint coordinates back to original image space
                        if VitPoseProcessor.roiRect != nil {
                            let adjustedKeypoints = result.keypoints.map { keypoint in
                                KeypointData(
                                    name: keypoint.name,
                                    x: keypoint.x + roiOffset.x,
                                    y: keypoint.y + roiOffset.y,
                                    confidence: keypoint.confidence,
                                    depth: keypoint.depth,
                                    frameIndex: keypoint.frameIndex
                                )
                            }
                            
                            // Store adjusted keypoints
                            DispatchQueue.main.sync {
                                self.storeKeypoints(adjustedKeypoints, for: frameIndex)
                            }
                        }
                        
                        processedFrames += 1
                        let progressValue = Double(processedFrames) / Double(totalFrames)
                        
                        // Report progress on main thread
                        DispatchQueue.main.async {
                            progress(progressValue)
                        }
                        
                        // Print log updates at intervals
                        if processedFrames % 10 == 0 || processedFrames == totalFrames {
                            print("Processed \(processedFrames)/\(totalFrames) frames with ROI")
                        }
                        
                    } catch {
                        print("Error processing frame \(frameIndex): \(error)")
                        DispatchQueue.main.async {
                            completion(false, error)
                        }
                        return
                    }
                }
                
                print("✅ ROI-based pose detection complete. Processed \(processedFrames) frames.")
                
                // Complete on main thread
                DispatchQueue.main.async {
                    completion(true, nil)
                }
            }
        }
}


// MARK: - Enhanced Error Handling and Recovery

class ProcessingConfiguration {
    static let shared = ProcessingConfiguration()

    // Configurable parameters for optimization
    var batchSize: Int = 10 {
        didSet {
            print("Batch size updated to: \(batchSize)")
        }
    }

    var maxCacheSize: Int = 50 {
        didSet {
            print("Max cache size updated to: \(maxCacheSize)")
        }
    }

    var delayBetweenBatches: TimeInterval = 0.1 {
        didSet {
            print("Delay between batches updated to: \(delayBetweenBatches)s")
        }
    }

    var enableMemoryLogging: Bool = false

    private init() {}

    // Adjust parameters based on device capabilities
    func optimizeForDevice() {
        let processInfo = ProcessInfo.processInfo
        let physicalMemory = processInfo.physicalMemory
        let gigabytes = Double(physicalMemory) / (1024 * 1024 * 1024)

        if gigabytes >= 8 {
            // High-end device
            batchSize = 15
            maxCacheSize = 75
            delayBetweenBatches = 0.05
        } else if gigabytes >= 4 {
            // Mid-range device
            batchSize = 10
            maxCacheSize = 50
            delayBetweenBatches = 0.1
        } else {
            // Lower-end device
            batchSize = 5
            maxCacheSize = 25
            delayBetweenBatches = 0.2
        }

        print("Optimized for device with \(String(format: "%.1f", gigabytes))GB RAM")
        print("Batch size: \(batchSize), Cache size: \(maxCacheSize), Delay: \(delayBetweenBatches)s")
    }
}

extension VitPoseProcessor {

    /// Monitor memory usage during processing
    private func logMemoryUsage(context: String) {
        guard ProcessingConfiguration.shared.enableMemoryLogging else { return }

        let task = mach_task_self_
        var info = mach_task_basic_info()
        var count = mach_msg_type_number_t(MemoryLayout<mach_task_basic_info>.size)/4

        let kerr: kern_return_t = withUnsafeMutablePointer(to: &info) {
            $0.withMemoryRebound(to: integer_t.self, capacity: 1) {
                task_info(task, task_flavor_t(MACH_TASK_BASIC_INFO), $0, &count)
            }
        }

        if kerr == KERN_SUCCESS {
            let usedMemoryMB = Double(info.resident_size) / (1024 * 1024)
            print("💾 Memory usage at \(context): \(String(format: "%.1f", usedMemoryMB))MB")
        }
    }

    /// Check if we should reduce batch size due to memory pressure
    private func shouldReduceBatchSize() -> Bool {
        // Check available memory
        let task = mach_task_self_
        var info = mach_task_basic_info()
        var count = mach_msg_type_number_t(MemoryLayout<mach_task_basic_info>.size)/4

        let kerr: kern_return_t = withUnsafeMutablePointer(to: &info) {
            $0.withMemoryRebound(to: integer_t.self, capacity: 1) {
                task_info(task, task_flavor_t(MACH_TASK_BASIC_INFO), $0, &count)
            }
        }

        if kerr == KERN_SUCCESS {
            let usedMemoryGB = Double(info.resident_size) / (1024 * 1024 * 1024)
            let physicalMemoryGB = Double(ProcessInfo.processInfo.physicalMemory) / (1024 * 1024 * 1024)
            let memoryUsageRatio = usedMemoryGB / physicalMemoryGB

            return memoryUsageRatio > 0.75 // Reduce batch size if using >75% memory
        }

        return false
    }
}

// MARK: - Optimized Frame Processing with Batch Management
extension VitPoseProcessor {

    /// Optimized frame processing with batch management and memory optimization
    func processFramesOptimized(
        from cameraManager: CameraLiDARManager,
        progress: @escaping (Double) -> Void,
        completion: @escaping (Bool, Error?) -> Void
    ) {
        let totalFrames = cameraManager.totalFrames
        guard totalFrames > 0 else {
            DispatchQueue.main.async {
                completion(false, ProcessingError.noKeypointData("No frames available for processing"))
            }
            return
        }

        print("🚀 Starting optimized pose detection on \(totalFrames) frames")

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
            cameraManager: cameraManager,
            totalFrames: totalFrames,
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
        cameraManager: CameraLiDARManager,
        totalFrames: Int,
        batchSize: Int,
        delayBetweenBatches: TimeInterval,
        currentBatch: Int,
        processedFrames: Int,
        failedFrames: [Int],
        progress: @escaping (Double) -> Void,
        completion: @escaping (Bool, Error?) -> Void
    ) {
        let startFrame = currentBatch * batchSize
        let endFrame = min(startFrame + batchSize, totalFrames)

        // Check if we're done
        if startFrame >= totalFrames {
            print("✅ Completed processing all batches. Processed: \(processedFrames), Failed: \(failedFrames.count)")

            // Handle failed frames if any
            if !failedFrames.isEmpty {
                print("⚠️ Failed to process frames: \(failedFrames)")
            }

            DispatchQueue.main.async {
                completion(true, nil)
            }
            return
        }

        print("📦 Processing batch \(currentBatch + 1), frames \(startFrame) to \(endFrame - 1)")

        // Process current batch in background
        DispatchQueue.global(qos: .userInitiated).async {
            autoreleasepool {
                var batchProcessedFrames = processedFrames
                var batchFailedFrames = failedFrames

                // Process frames in this batch
                for frameIndex in startFrame..<endFrame {
                    do {
                        // Get frame with memory management
                        let frameImage = try self.getFrameWithMemoryManagement(
                            from: cameraManager,
                            at: frameIndex
                        )

                        // Process the frame
                        let result = try self.processFrameWithMemoryManagement(
                            image: frameImage,
                            frameIndex: frameIndex
                        )

                        // Store results safely
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

                        // Update progress
                        let progressValue = Double(batchProcessedFrames) / Double(totalFrames)
                        DispatchQueue.main.async {
                            progress(progressValue)
                        }

                    } catch {
                        print("❌ Error processing frame \(frameIndex): \(error)")
                        batchFailedFrames.append(frameIndex)
                    }
                }

                // Memory cleanup between batches
                self.performMemoryCleanup()

                // Log batch completion
                print("✅ Batch \(currentBatch + 1) completed. Processed: \(batchProcessedFrames - processedFrames)/\(endFrame - startFrame)")

                // Schedule next batch with delay
                DispatchQueue.main.asyncAfter(deadline: .now() + delayBetweenBatches) {
                    self.processBatches(
                        cameraManager: cameraManager,
                        totalFrames: totalFrames,
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
        }
    }

    /// Get frame with proper memory management
    private func getFrameWithMemoryManagement(
        from cameraManager: CameraLiDARManager,
        at frameIndex: Int
    ) throws -> UIImage {
        var frameImage: UIImage?

        // Get frame safely - check if already on main thread
        if Thread.isMainThread {
            frameImage = cameraManager.getFrame(at: frameIndex)
        } else {
            DispatchQueue.main.sync {
                frameImage = cameraManager.getFrame(at: frameIndex)
            }
        }

        guard let image = frameImage else {
            throw ProcessingError.imageConversionFailed("Could not access frame \(frameIndex)")
        }

        return image
    }

    /// Process frame with memory-optimized approach
    private func processFrameWithMemoryManagement(
        image: UIImage,
        frameIndex: Int
    ) throws -> (keypoints: [KeypointData], visualizedImage: UIImage?) {
        // Ensure proper image orientation
        let correctedImage = ensureCorrectOrientation(image: image)

        // Apply ROI if set
        let (imageToProcess, roiOffset) = cropImageToROI(correctedImage) ?? (correctedImage, .zero)

        // Detect keypoints
        let detectedKeypoints = try detectKeypoints(from: imageToProcess, frameIndex: frameIndex)

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
                connections: skeletonConnections
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

    /// Process frames with retry mechanism for failed frames
    func processFramesWithRetry(
        from cameraManager: CameraLiDARManager,
        maxRetries: Int = 2,
        progress: @escaping (Double) -> Void,
        completion: @escaping (Bool, Error?) -> Void
    ) {
        // First pass - normal processing
        processFramesOptimized(from: cameraManager, progress: { progressValue in
            // Report 80% progress for first pass
            progress(progressValue * 0.8)
        }) { [weak self] success, error in
            guard let self = self else {
                completion(false, NSError(domain: "VitPoseProcessor", code: -1, userInfo: [NSLocalizedDescriptionKey: "Processor deallocated"]))
                return
            }

            if success {
                // Check for gaps in processed frames
                let totalFrames = cameraManager.totalFrames
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
                        cameraManager: cameraManager,
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

    /// Retry processing failed frames
    private func retryFailedFrames(
        _ failedFrames: [Int],
        cameraManager: CameraLiDARManager,
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

        DispatchQueue.global(qos: .userInitiated).async {
            for frameIndex in failedFrames {
                autoreleasepool {
                    do {
                        let frameImage = try self.getFrameWithMemoryManagement(
                            from: cameraManager,
                            at: frameIndex
                        )

                        let result = try self.processFrameWithMemoryManagement(
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
}
