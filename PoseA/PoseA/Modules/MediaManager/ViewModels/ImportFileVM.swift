//
//  ImportFileVM.swift
//  PoseA
//
//  Created by Bestlab on 7/2/25.
//

import SwiftUI
import AVFoundation

@Observable
class ImportFileVM {
    // --- Data Storage ---
    var FrameImageURLs:[URL] = []
    var FrameFolderURLs: [URL] = []
    
    var keypointData: [Int : PoseBox] = [:]
    var CoMData: [Int : CGPoint] = [:]
    var featuresData: [Int : FeaturesModel] = [:]
    var barData: [Int : CGPoint] = [:]
    var eventsData: EventsModel = EventsModel(rotationDir: "")
    var postureData: [PostureData] = []
    var mediaMetadata: RecordingMetadata?
    
    // Data Availability Status Flag
    var isDataLoaded: Bool = false
    var isKeyLoaded: Bool = false
    var isCoMLoaded: Bool = false
    var isFeaturesLoaded: Bool = false
    
    // Video Data
    var FrameCounts: Int = 0
    var fps: Double = 30.0
    
    // MARK: - Video Loader Public Methods
    func loadVideoFolder(from url: URL) {
        log("Started load video folder for URL: \(url.path)", level: .debug)

        // Perform all heavy operations on background thread
        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            guard let self = self else { return }

            do {
                // Look for the color_frames directory
                let colorFramesURL = url.appendingPathComponent("color_frames")
                
                guard FileManager.default.fileExists(atPath: colorFramesURL.path) else {
                    log("color_frames directory not found at: \(colorFramesURL.path)", level: .error)
                    DispatchQueue.main.async {
                        self.isDataLoaded = false
                    }
                    return
                }
                
                // Get all files in the color_frames directory
                let frameContents = try FileManager.default.contentsOfDirectory(
                    at: colorFramesURL,
                    includingPropertiesForKeys: [.isRegularFileKey],
                    options: [.skipsHiddenFiles]
                )
                
                log("Found \(frameContents.count) frame files.", level: .debug)
                
                // Filter for color_X.jpg files and sort them by frame number
                var imageURLs: [URL] = []
                
                for fileURL in frameContents {
                    let fileName = fileURL.lastPathComponent
                    if fileName.hasPrefix("color_") && fileName.hasSuffix(".jpg") {
                        imageURLs.append(fileURL)
                    }
                }
                
                // Sort by frame number
                imageURLs.sort { (url1, url2) -> Bool in
                    let num1 = self.extractFrameNumber(from: url1.lastPathComponent)
                    let num2 = self.extractFrameNumber(from: url2.lastPathComponent)
                    return num1 < num2
                }
                
                log("Found \(imageURLs.count) valid frame images in color_frames directory.", level: .debug)
                
                // Update Published Variables
                DispatchQueue.main.async { [self] in
                    // Set Data Value
                    self.FrameImageURLs = imageURLs
                    self.FrameFolderURLs = [colorFramesURL] // Store the single color_frames directory
                    self.FrameCounts = imageURLs.count
                    
                    // Set Data Status
                    self.isDataLoaded = !imageURLs.isEmpty
                }
                
            } catch {
                log("Error scanning color_frames directory: \(error)", level: .error)
                DispatchQueue.main.async {
                    self.isDataLoaded = false
                }
            }
        }
    }
    
    // MARK: - Load 2D Video Files
    func loadVideoFile(from url: URL, to: URL, opID: String) async {
        log("Started load 2D video for URL: \(url.path)", level: .debug)

        await withCheckedContinuation { continuation in
            Task { [weak self] in
                guard let self = self else {
                    continuation.resume()
                    return
                }

                do {
                    let imageURLs = try await self.extractFrames(url: url, to: to, opID: opID)

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
    func loadKeypoints(from url: URL) {
        // Perform all heavy operations on background thread
        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            guard let self = self else { return }

            do {
                if url.pathExtension.lowercased() == "json" {
                    var keypointData: [Int : PoseBox] = [:]
                    let data = try Data(contentsOf: url)
                    
                    // Try parsing as a dictionary of KeypointData
                    if let jsonObject = try JSONSerialization.jsonObject(with: data, options: []) as? [String: Any] {
                        keypointData.removeAll()
                        
                        // Check for different JSON structures
                        if let bboxData = jsonObject["frames_bbox"] as? [String: [String: Any]] {
                            // Format with "bbox" key
                            for (key, points) in bboxData {
                                if key.hasPrefix("framebbox_"),
                                   let frameIndexString = key.split(separator: "_").last,
                                   let frameIndex = Int(frameIndexString) {
                                    let poseBoxFrame = parseBboxFromDictionary(points, frameIndex: frameIndex)
                                    keypointData[frameIndex] = poseBoxFrame
                                }
                            }
                        }
                            
                        if let framesData = jsonObject["frames"] as? [String: [[String: Any]]] {
                            // Format with "frames" key
                            for (key, points) in framesData {
                                if key.hasPrefix("frame_"),
                                   let frameIndexString = key.split(separator: "_").last,
                                   let frameIndex = Int(frameIndexString) {
                                    let keypointsFrame = parseKeypointsFromDictionary(points, frameIndex: frameIndex)
                                    keypointData[frameIndex]?.keypoints = keypointsFrame
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
                        self.keypointData = keypointData
                        // Set Data Status
                        self.isKeyLoaded = !keypointData.isEmpty
                    }
                    
                } else {
                    log("Unsupported file format: \(url.pathExtension)", level: .error)
                }
                
            } catch {
                log("Error scanning directories.", level: .error)
                DispatchQueue.main.async { [self] in
                    self.isKeyLoaded = false
                }
            }
        }
    }
    
    func loadCoM(from url: URL) throws {
        let (importedCoM, missingFrames) = try ExportImportManager.importCoM(from: url)
        
        // Update Published Variables
        DispatchQueue.main.async { [self] in
            // Set Data Value
            self.CoMData = importedCoM
            // Set Data Status
            self.isCoMLoaded = !CoMData.isEmpty
        }
        
        if !missingFrames.isEmpty {
            log("Imported CoM data with \(missingFrames.count) missing frames: \(missingFrames)", level: .info)
        }
        
        log("Successfully imported \(importedCoM.count) CoM frames", level: .info)
    }

    func loadFeatures(from url: URL) throws {
        let (importedFeatures, _) = try ExportImportManager.importFeatures(from: url)
        
        // Update Published Variables
        DispatchQueue.main.async { [self] in
            // Set Data Value
            self.featuresData = importedFeatures
            
            self.barData[0] = importedFeatures[0]!.topBarPx
            self.barData[1] = importedFeatures[0]!.bottomBarPx
            
            // Set Data Status
            self.isFeaturesLoaded = !featuresData.isEmpty
        }
        
        log("Successfully imported \(importedFeatures.count) ML features data", level: .info)
    }
    
    func loadEvents(from url: URL) throws {
        let importedEvents = try ExportImportManager.importEvents(from: url)
        
        // Update Published Variables
        DispatchQueue.main.async { [self] in
            // Set Data Value
            self.eventsData = importedEvents
        }
        
        if importedEvents.rotationDir == "" {
            log("No events data found", level: .info)
        }
        
        log("Successfully imported events frame index data", level: .info)
    }
    
    func loadPosture(from url: URL) throws {
        let importedPosture = try ExportImportManager.importPosture(from: url)
        
        // Update Published Variables
        DispatchQueue.main.async { [self] in
            // Set Data Value
            self.postureData = importedPosture
        }
        
        log("Successfully imported events frame index data", level: .info)
        
    }
    func loadMetadata(from metadataURL: URL) {
        guard FileManager.default.fileExists(atPath: metadataURL.path) else {
            log("Recording metadata file not found at: \(metadataURL.path)", level: .error)
            return
        }
        
        do {
            let data = try Data(contentsOf: metadataURL)
            let metadataJSON = try JSONDecoder().decode(RecordingMetadata.self, from: data)
            
            // Update Published Variables
            DispatchQueue.main.async { [self] in
                // Set Data Value
                self.mediaMetadata = metadataJSON
                
                // Get FPS from metadata if available
                if let mediaMetadata = self.mediaMetadata {
                    self.fps = Double(mediaMetadata.frameCount) / mediaMetadata.duration
                }
            }
            
        } catch {
            log("Failed to load recording metadata: \(error)", level: .error)
        }
    }
    
    // MARK: - Required Helper Functions
    private func extractFrameNumber(from string: String) -> Int {
        return Int(string.components(separatedBy: CharacterSet.decimalDigits.inverted).joined()) ?? 0
    }
    
    private func extractFrames(url: URL, to: URL, opID: String) async throws -> [URL] {
        // Set Files URLs
        var frameURLs: [URL] = []

        let asset = AVURLAsset(url: url)

        let generator = AVAssetImageGenerator(asset: asset)
        generator.appliesPreferredTrackTransform = true
        generator.requestedTimeToleranceBefore = .zero
        generator.requestedTimeToleranceAfter = .zero
        
        // Get Video Metadata
        let duration = try await asset.load(.duration)
        let tracks = try await asset.loadTracks(withMediaType: .video)
        guard let videoTrack = tracks.first else {
            throw NSError(domain: "FileLoaderVM", code: -2, userInfo: [NSLocalizedDescriptionKey: "No video track found"])
        }
        
        // Get FPS Estimation Value
        let frameRate = try await videoTrack.load(.nominalFrameRate)
        let effectiveFrameRate = frameRate > 0 ? frameRate : 30.0
        let durationSeconds = CMTimeGetSeconds(duration)
        self.fps = Double(effectiveFrameRate)

        let totalFramesEstimate = Int(durationSeconds * Double(effectiveFrameRate))
        
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

                let frameFileURL = to.appendingPathComponent("color_\(i+1).jpg")
                try imageData?.write(to: frameFileURL)

                frameURLs.append(frameFileURL)
                
                let progressValue = Double(i + 1) / Double(totalFramesEstimate)
                
                // Update status
                Task { @MainActor in
                    ProcessingManagerVM.shared.updateOperation(
                        id: opID,
                        status: "Extracting frame files...",
                        progress: progressValue
                    )
                }
                
            } catch {
                log("Skipping frame \(i): \(error.localizedDescription)", level: .warn)
            }
        }

        log("Extracted and saved \(frameURLs.count) frames successfully at \(to.path)", level: .info)
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
    
    private func parseBboxFromDictionary(_ point: [String: Any], frameIndex: Int) -> PoseBox {
        var output: PoseBox = PoseBox(
            bbox: .zero,
            confidence: 0.0,
            keypoints: []
        )
        
        if let x = (point["x"] as? NSNumber)?.doubleValue ?? (point["x"] as? Double),
           let y = (point["y"] as? NSNumber)?.doubleValue ?? (point["y"] as? Double),
           let width = (point["width"] as? NSNumber)?.doubleValue ?? (point["width"] as? Double),
           let height = (point["height"] as? NSNumber)?.doubleValue ?? (point["depth"] as? Double),
           let confidence = (point["confidence"] as? NSNumber)?.floatValue ?? (point["confidence"] as? Float) {
            
            let bbox = CGRect(
                x: x,
                y: y,
                width: width,
                height: height
            )
            
            output = PoseBox(
                bbox: bbox,
                confidence: confidence,
                keypoints: []
            )
        }
        
        return output
    }
}
