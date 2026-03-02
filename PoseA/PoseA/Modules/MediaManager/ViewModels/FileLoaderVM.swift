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
    var frameIndexMap: [Int: Int] = [:]  // array index → original video frame number
    
    var videoURL: URL? = nil
    var detectedFPS: Double = 30.0

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

    // In extractFramesAndSaveToDisk, change FrameResult to store actualTime:
    private struct FrameResult {
        let url: URL
        let frameNumber: Int      // array position (0-based)
        let actualFrameIndex: Int // real frame index computed from actualTime
    }

    func loadVideoFile(from url: URL) async {
        await withCheckedContinuation { continuation in
            Task { [weak self] in
                guard let self = self else { continuation.resume(); return }
                do {
                    let results = try await self.extractFramesAndSaveToDisk(url: url)
                    
                    await MainActor.run {
                        self.FrameImageURLs = results.map { $0.url }
                        self.FrameFolderURLs = []
                        self.FrameCounts = results.count
                        
                        // ✅ arrayIndex → actual video frame index (matches keypoints.json keys)
                        self.frameIndexMap = Dictionary(
                            uniqueKeysWithValues: results.enumerated().map { ($0.offset, $0.element.actualFrameIndex) }
                        )
                        // ✅ DELETE frameTimestampMap — no longer used
                        
                        self.isDataLoaded = !results.isEmpty
                    }
                } catch {
                    log("Error extracting video.", level: .error)
                    await MainActor.run { self.isDataLoaded = false }
                }
                continuation.resume()
            }
        }
    }

    
    func remapKeypointsToArrayIndex() {
        guard !FrameFolderURLs.isEmpty, !keypointsByFrame.isEmpty else { return }
        
        // Build a map: frameNumber -> arrayIndex
        var frameNumberToArrayIndex: [Int: Int] = [:]
        for (arrayIndex, folderURL) in FrameFolderURLs.enumerated() {
            let frameNumber = extractFrameNumber(from: folderURL.lastPathComponent)
            frameNumberToArrayIndex[frameNumber] = arrayIndex
        }
        
        // Remap keypoints from frameNumber key to arrayIndex key
        var remapped: [Int: [KeypointData]] = [:]
        for (frameNumber, keypoints) in keypointsByFrame {
            if let arrayIndex = frameNumberToArrayIndex[frameNumber] {
                remapped[arrayIndex] = keypoints
            } else {
                log("⚠️ No matching frame folder for keypoint frameNumber: \(frameNumber)", level: .debug)
            }
        }
        
        keypointsByFrame = remapped
        log("✅ Remapped \(remapped.count) keypoint frames to array indices", level: .info)
    }

    
    // MARK: - Load Keypoint Files
    // MARK: - Load Keypoint Files
//    func loadKeypoints(from MLOutput: [Int: [KeypointData]]) {
//        // Set Keypoints
//        self.keypointsByFrame = MLOutput
//        // Set Data Status
//        self.isKeyLoaded = !MLOutput.isEmpty
//    }
    func diagnoseAlignment() {
        let sortedKeys = keypointsByFrame.keys.sorted()
        print("=== ALIGNMENT DIAGNOSIS ===")
        print("Keypoint keys start: \(sortedKeys.prefix(5))")
        print("Keypoint keys end: \(sortedKeys.suffix(5))")
        print("Total keypoint frames: \(sortedKeys.count)")
        print("Total video frames: \(FrameCounts)")
        
        if FrameCounts > 0 {
            let ratio = Double(sortedKeys.last ?? 0) / Double(FrameCounts)
            print("Ratio (last key / frame count): \(ratio)")
        } else {
            print("⚠️ FrameCounts is 0 at time of diagnosis — called too early")
        }
        print("===========================")
    }
    func loadKeypoints(from keypointDict: [Int: [KeypointData]]) {
        DispatchQueue.main.async {
            self.keypointsByFrame = keypointDict
            self.isKeyLoaded = !keypointDict.isEmpty
            
            let sortedKeys = keypointDict.keys.sorted()
            print("🔑 Keypoint keys range: \(sortedKeys.first ?? -1) to \(sortedKeys.last ?? -1), total: \(keypointDict.count)")
            print("🔑 First 5 keys: \(Array(sortedKeys.prefix(5)))")
            print("🔑 Last 5 keys: \(Array(sortedKeys.suffix(5)))")
            
            // ADD THIS
            self.diagnoseAlignment()
        }
    }

    
    func loadKeypoints(from url: URL) async {
        await withCheckedContinuation { continuation in
            DispatchQueue.global(qos: .userInitiated).async { [weak self] in
                guard let self = self else { continuation.resume(); return }
                
                do {
                    let data = try Data(contentsOf: url)
                    log("📄 Loaded keypoints file: \(url.lastPathComponent), size: \(data.count) bytes", level: .info)
                    
                    guard url.pathExtension.lowercased() == "json" else {
                        log("Unsupported file format: \(url.pathExtension)", level: .error)
                        DispatchQueue.main.async { continuation.resume() }
                        return
                    }
                    
                    var keypointsByFrame: [Int: [KeypointData]] = [:]
                    var formatRecognized = false
                    
                    // FORMAT 1: [PoseFrameData] array — from raw_pose_frames.json
                    if let jsonArray = try? JSONDecoder().decode([PoseFrameData].self, from: data) {
                        formatRecognized = true
                        for frameData in jsonArray {
                            let allKeypoints = frameData.poses.flatMap { $0.keypoints }
                            if !allKeypoints.isEmpty {
                                keypointsByFrame[frameData.frameIndex] = allKeypoints
                            }
                        }
                        log("FORMAT 1 (PoseFrameData array): \(jsonArray.count) frames", level: .info)
                    }
                    // FORMAT 2: Int-keyed { "0": [...], "1": [...] } — from keypoints.json (new recordings)
                    else if let jsonObject = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                            jsonObject.keys.allSatisfy({ Int($0) != nil }) {
                        formatRecognized = true
                        for (key, value) in jsonObject {
                            guard let frameIndex = Int(key),
                                  let keypointsArray = value as? [[String: Any]] else { continue }
                            keypointsByFrame[frameIndex] = self.parseKeypointsFromDictionary(keypointsArray, frameIndex: frameIndex)
                        }
                        log("FORMAT 2 (Int-keyed): \(keypointsByFrame.count) frames", level: .info)
                    }
                    // FORMAT 3: Legacy "frames" structure
                    else if let jsonObject = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                            let framesData = jsonObject["frames"] as? [String: [[String: Any]]] {
                        formatRecognized = true
                        for (key, points) in framesData {
                            if key.hasPrefix("frame_"),
                               let frameIndex = Int(key.split(separator: "_").last ?? "") {
                                keypointsByFrame[frameIndex] = self.parseKeypointsFromDictionary(points, frameIndex: frameIndex)
                            }
                        }
                        log("FORMAT 3 (legacy frames): \(keypointsByFrame.count) frames", level: .info)
                    }
                    
                    if !formatRecognized {
                        log("Unrecognized JSON format in \(url.lastPathComponent)", level: .error)
                    }
                    
                    DispatchQueue.main.async {
                        self.keypointsByFrame = keypointsByFrame
                        self.isKeyLoaded = !keypointsByFrame.isEmpty
                        let sortedKeys = keypointsByFrame.keys.sorted()
                        log("✅ Loaded \(keypointsByFrame.count) keypoint frames, range: \(sortedKeys.first ?? -1) to \(sortedKeys.last ?? -1)", level: .info)
                        continuation.resume()
                    }
                    
                } catch {
                    log("Error loading keypoints: \(error.localizedDescription)", level: .error)
                    DispatchQueue.main.async {
                        self.isKeyLoaded = false
                        continuation.resume()
                    }
                }
            }
        }
    }

   
    
    // MARK: - Required Helper Functions
    private func extractFrameNumber(from string: String) -> Int {
        return Int(string.components(separatedBy: CharacterSet.decimalDigits.inverted).joined()) ?? 0
    }
    
    
    private func extractFramesAndSaveToDisk(url: URL) async throws -> [FrameResult] {
        var frameResults: [FrameResult] = []

        let tempDir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)

        let asset = AVURLAsset(url: url)
        let generator = AVAssetImageGenerator(asset: asset)
        generator.appliesPreferredTrackTransform = true
        // ✅ Allow slight tolerance — avoids "Cannot Open" on boundary frames
        generator.requestedTimeToleranceBefore = CMTime(value: 1, timescale: 600)
        generator.requestedTimeToleranceAfter  = CMTime(value: 1, timescale: 600)

        let duration = try await asset.load(.duration)
        let tracks   = try await asset.loadTracks(withMediaType: .video)
        guard let videoTrack = tracks.first else {
            throw NSError(domain: "FileLoaderVM", code: -2,
                          userInfo: [NSLocalizedDescriptionKey: "No video track found"])
        }

        let frameRate        = try await videoTrack.load(.nominalFrameRate)
        let effectiveFrameRate = frameRate > 0 ? Double(frameRate) : 30.0
        let durationSeconds  = CMTimeGetSeconds(duration)

        // ✅ Use floor and subtract a small epsilon to avoid requesting frames past the end
        let totalFrames = Int(floor(durationSeconds * effectiveFrameRate))
        log("video fps: \(effectiveFrameRate), duration: \(durationSeconds)s, frames: \(totalFrames)", level: .debug)

        // ✅ Generate all times upfront, capped to just before video end
        let endTime = CMTimeSubtract(duration, CMTime(value: 1, timescale: Int32(effectiveFrameRate * 2)))
        
        var times: [NSValue] = []
        for i in 0..<totalFrames {
            let t = CMTime(value: CMTimeValue(i), timescale: CMTimeScale(effectiveFrameRate))
            // Don't request frames past the actual end
            if CMTimeCompare(t, endTime) <= 0 {
                times.append(NSValue(time: t))
            }
        }

        log("Requesting \(times.count) frames from generator", level: .debug)

        // ✅ Use batch generation — more efficient and respects actual video boundaries
        return try await withCheckedThrowingContinuation { continuation in
            var results: [FrameResult] = []
            var completedCount = 0
            let totalCount = times.count
            var didResume = false

            generator.generateCGImagesAsynchronously(forTimes: times) { requestedTime, cgImage, actualTime, result, error in
                let i = completedCount
                completedCount += 1

                switch result {
                case .succeeded:
                    if let cgImage = cgImage {
                        do {
                            let uiImage  = UIImage(cgImage: cgImage)
                            let imageData = uiImage.jpegData(compressionQuality: 0.8)
                            let frameDir  = tempDir.appendingPathComponent("frame_\(i + 1)")
                            try FileManager.default.createDirectory(at: frameDir, withIntermediateDirectories: true)
                            let fileURL = frameDir.appendingPathComponent("colorImage.jpg")
                            try imageData?.write(to: fileURL)
                            let actualFrameIndex = Int(round(CMTimeGetSeconds(actualTime) * effectiveFrameRate))

                            results.append(FrameResult(url: fileURL, frameNumber: i,actualFrameIndex: actualFrameIndex))

                            if i % 20 == 0 {
                                log("Extracting: \(i)/\(totalCount) frames saved", level: .debug)
                            }
                        } catch {
                            log("Failed to save frame \(i): \(error.localizedDescription)", level: .warn)
                        }
                    }

                case .failed:
                    log("Skipping frame \(i): \(error?.localizedDescription ?? "unknown")", level: .warn)

                case .cancelled:
                    break

                @unknown default:
                    break
                }

                
                // ✅ Resume when all frames processed
                if completedCount >= totalCount && !didResume {
                    didResume = true
                    // Sort by frame number since async callbacks may arrive out of order
                    results.sort { $0.frameNumber < $1.frameNumber }
                    log("Extracted \(results.count)/\(totalCount) frames successfully", level: .info)
                    continuation.resume(returning: results)
                }
            }
        }
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
