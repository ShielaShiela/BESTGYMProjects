//
//  FileLoaderVM.swift
//  PoseA
//
//  Created by Bestlab on 7/2/25.
//

import SwiftUI
import AVFoundation

@Observable
class FileLoaderVM: ObservableObject {
    // --- Data Storage for Analysis ---
    private var frameData = FrameDataVM()
    var mediaMetadata: [MetadataInfo] = []
    
    // --- Data Storage for Playback ---
    var FrameImageURLs:[URL] = []
    var FrameFolderURLs: [URL] = []
    var keypointsByFrame: [Int: [KeypointData]] = [:]
    
    // Data Availability Status Flag
    var isDataLoaded: Bool = false
    var isKeyLoaded: Bool = false
    
    // Video Data
    var FrameCounts: Int = 0
    
    // MARK: - 3D LiDAR Data Loader Public Methods
    
    func loadVideoFolder(from url: URL) {
        log("Started load video folder for URL: \(url.path)", level: .debug)

        // Perform all heavy operations on background thread
        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            guard let self = self else { return }

            do {
                // Get all direct children of the folder
                let contents = try FileManager.default.contentsOfDirectory(
                    at: url,
                    includingPropertiesForKeys: [.isDirectoryKey],
                    options: [.skipsHiddenFiles]
                )
                
                // Filter for frame_X directories
                var frameDirectories: [URL] = []
                for item in contents {
                    var isDir: ObjCBool = false
                    if FileManager.default.fileExists(atPath: item.path, isDirectory: &isDir),
                       isDir.boolValue,
                       item.lastPathComponent.hasPrefix("frame_") {
                        frameDirectories.append(item)
                    }
                }
                log("Found \(frameDirectories.count) frame directories.", level: .debug)
                
                // Sort by frame number
                frameDirectories.sort { (url1, url2) -> Bool in
                    let num1 = self.extractFrameNumber(from: url1.lastPathComponent)
                    let num2 = self.extractFrameNumber(from: url2.lastPathComponent)
                    return num1 < num2
                }
                
                // Get Image URLs
                var imageURLs: [URL] = []
                
                for frameDir in frameDirectories {
                    // Check multiple possible names with and without extensions
                    let possibleImageNames = [
                        "colorImage",
                        "colorImage.jpg",
                        "color_image.jpg",
                        "color.jpg"
                    ]
                    
                    var foundImage = false
                    for imageName in possibleImageNames {
                        let imageURL = frameDir.appendingPathComponent(imageName)
                        if FileManager.default.fileExists(atPath: imageURL.path) {
                            imageURLs.append(imageURL)
                            foundImage = true
                            break
                        }
                    }
                    
                    if !foundImage {
                        log("No image is found in \(frameDir.lastPathComponent).", level: .debug)
                    }
                }
                log("Found \(imageURLs.count) vaild frame images.", level: .debug)
                
                // Update Published Variables
                DispatchQueue.main.async { [self] in
                    // Set Data Value
                    self.FrameImageURLs = imageURLs
                    self.FrameFolderURLs = frameDirectories
                    self.FrameCounts = imageURLs.count
                    
                    // Set Data Status
                    self.isDataLoaded = !imageURLs.isEmpty
                }
            } catch {
                log("Error scanning directories.", level: .error)
                DispatchQueue.main.async {
                    self.isDataLoaded = false
                }
            }
        }
    }
    
    // MARK: - Load 2D Video Files

    func loadVideoFile(from url: URL) async {
        log("Started load 2D video for URL: \(url.path)", level: .debug)

        await withCheckedContinuation { continuation in
            Task { [weak self] in
                guard let self = self else {
                    continuation.resume()
                    return
                }

                do {
                    let imageURLs = try await self.extractFramesAndSaveToDisk(url: url)

                    await MainActor.run {
                        // Set Data Value
                        self.FrameImageURLs = imageURLs
                        self.FrameFolderURLs = []
                        self.FrameCounts = imageURLs.count
                        
                        // Set Data Status
                        self.isDataLoaded = !imageURLs.isEmpty
                    }
                } catch {
                    log("Error extracting video.", level: .error)
                    await MainActor.run {
                        self.isDataLoaded = false
                    }
                }

                // Resume continuation when done
                continuation.resume()
            }
        }
    }


    // MARK: - Load Keypoint Files
    func loadKeypoints(from MLOutput: [Int: [KeypointData]]) {
        // Set Keypoints
        self.keypointsByFrame = MLOutput
        // Set Data Status
        self.isKeyLoaded = !MLOutput.isEmpty
    }
    
    func loadKeypoints(from url: URL) {
        // Perform all heavy operations on background thread
        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            guard let self = self else { return }

            do {
                if url.pathExtension.lowercased() == "json" {
                    var keypointsFrame: [Int: [KeypointData]] = [:]
                    let data = try Data(contentsOf: url)
                    
                    // Try parsing as a dictionary of KeypointData
                    if let jsonObject = try JSONSerialization.jsonObject(with: data, options: []) as? [String: Any] {
                        keypointsFrame.removeAll()
                        
                        // Check for different JSON structures
                        if let framesData = jsonObject["frames"] as? [String: [[String: Any]]] {
                            // Format with "frames" key
                            for (key, points) in framesData {
                                if key.hasPrefix("frame_"),
                                   let frameIndexString = key.split(separator: "_").last,
                                   let frameIndex = Int(frameIndexString) {
                                    
                                    keypointsFrame[frameIndex] = parseKeypointsFromDictionary(points, frameIndex: frameIndex)
                                }
                            }
                        } else {
                            log("Unrecognized JSON format", level: .error)
                        }
                    } else {
                        log("Invalid JSON format", level: .error)
                    }
                    
                    // Update Published Variables
                    DispatchQueue.main.async { [self] in
                        // Set Data Value
                        self.keypointsByFrame = keypointsFrame
                        // Set Data Status
                        self.isKeyLoaded = !keypointsFrame.isEmpty
                    }
                    
                } else {
                    log("Unsupported file format: \(url.pathExtension)", level: .error)
                }
                
            } catch {
                // Removing old "double try methods" -> REDUNDANT
                log("Error scanning directories.", level: .error)
                DispatchQueue.main.async { [self] in
                    self.isKeyLoaded = false
                }
            }
        }
    }
    
    
    
    // MARK: - Required Helper Functions
    private func extractFrameNumber(from string: String) -> Int {
        return Int(string.components(separatedBy: CharacterSet.decimalDigits.inverted).joined()) ?? 0
    }
    
    private func extractFramesAndSaveToDisk(url: URL) async throws -> [URL] {
        var frameURLs: [URL] = []

        let tempDir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)

        let asset = AVURLAsset(url: url)

        let generator = AVAssetImageGenerator(asset: asset)
        generator.appliesPreferredTrackTransform = true
        generator.requestedTimeToleranceBefore = .zero  // More accurate
        generator.requestedTimeToleranceAfter = .zero   // More accurate

        let duration = try await asset.load(.duration)
        let tracks = try await asset.loadTracks(withMediaType: .video)
        guard let videoTrack = tracks.first else {
            throw NSError(domain: "FileLoaderVM", code: -2, userInfo: [NSLocalizedDescriptionKey: "No video track found"])
        }

        let frameRate = try await videoTrack.load(.nominalFrameRate)
        let effectiveFrameRate = frameRate > 0 ? frameRate : 30.0
        let durationSeconds = CMTimeGetSeconds(duration)

        let totalFramesEstimate = Int(durationSeconds * Double(effectiveFrameRate))
        log("video fps: \(effectiveFrameRate)", level: .debug)
        log("estimated total frames: \(totalFramesEstimate)", level: .debug)

        let frameInterval = CMTime(value: 1, timescale: Int32(effectiveFrameRate))

        for i in 0..<totalFramesEstimate {
            let time = CMTimeMultiply(frameInterval, multiplier: Int32(i))

            do {
                let cgImage = try await withCheckedThrowingContinuation { continuation in
                    generator.generateCGImageAsynchronously(for: time) { cgImage, actualTime, error in
                        if let cgImage = cgImage {
                            continuation.resume(returning: cgImage)
                        } else if let error = error {
                            continuation.resume(throwing: error)
                        } else {
                            continuation.resume(throwing: NSError(domain: "FrameExtraction", code: -1, userInfo: [NSLocalizedDescriptionKey: "Unknown error generating frame"]))
                        }
                    }
                }

                let uiImage = UIImage(cgImage: cgImage)
                let imageData = uiImage.jpegData(compressionQuality: 0.8)

                let frameDir = tempDir.appendingPathComponent("frame_\(i+1)")
                try FileManager.default.createDirectory(at: frameDir, withIntermediateDirectories: true)

                let frameFileURL = frameDir.appendingPathComponent("colorImage.jpg")
                try imageData?.write(to: frameFileURL)

                frameURLs.append(frameFileURL)

                if i % 20 == 0 || i == totalFramesEstimate - 1 {
                    log("Extracting: \(i+1)/\(totalFramesEstimate) frames saved to disk", level: .debug)
                }

            } catch {
                log("Skipping frame \(i): \(error.localizedDescription)", level: .warn)
            }
        }

        log("Extracted and saved \(frameURLs.count) frames successfully at \(tempDir.path)", level: .info)
        return frameURLs
    }


    private func parseKeypointsFromDictionary(_ points: [[String: Any]], frameIndex: Int) -> [KeypointData] {
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
        
        return keypointsForFrame
    }
}
