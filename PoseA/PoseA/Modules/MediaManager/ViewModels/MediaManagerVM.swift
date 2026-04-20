//
//  MediaManagerVM.swift
//  PoseA
//
//  Created by Ardhika Maulidani on 7/3/25.
//

import Combine
import SwiftUI
import AVFoundation

@Observable
class MediaManagerVM {
    // View Model
    var importFileVM: ImportFileVM = ImportFileVM()
    var mediaPlayerVM: MediaPlayerVM = MediaPlayerVM()
    
    // Frame Update
    var isMediaAvailable: Bool = false
    var isKeypointAvailable: Bool = false
    var isDataLIDAR: Bool = false
    var isDataTemp: Bool = false
    
    // Media Player Variable
    var isPlaying: Bool = false
    var fps: Double = 30.0 {
        didSet {
            mediaPlayerVM.setFPS(fps)
        }
    }
    
    // MARK: - Unified Data Storage
    // Single source of truth for keypoints data
    private var _keypointData: [Int: PoseBox] = [:]
    var keypointData: [Int: PoseBox] { _keypointData }
    
    // Single source of truth for CoM data
    private var _CoMData: [Int: CGPoint] = [:]
    var CoMData: [Int: CGPoint] { _CoMData }

    // Single source of truth for CoM data
    private var _FeaturesData: [Int: FeaturesModel] = [:]
    var FeaturesData: [Int: FeaturesModel] { _FeaturesData }
    
    // Single source of truth for bar reference points
    private var _BarReferenceData: [Int: CGPoint] = [:]
    var BarReferenceData: [Int: CGPoint] { _BarReferenceData }
    
    // Single source of truth for event frame index
    private var _EventsData: EventsModel = EventsModel(rotationDir: "")
    var EventsData: EventsModel { _EventsData }
    
    var currentFrameImage: UIImage? { mediaPlayerVM.currentFrameImage }
    var currentFrameIndex: Int { mediaPlayerVM.currentFrameIndex }

    // MARK: - Data Source Management
    enum DataSource {
        case file
        case processing
    }
    
    // Updates keypoints data from any source
    func updateKeypointsData(_ data: [Int: PoseBox], source: DataSource) {
        _keypointData = data
        isKeypointAvailable = !data.isEmpty
        
        log("Updated keypoints data from \(source) with \(data.count) frames", level: .info)
    }
    
    // Updates CoM data from any source
    func updateCoMData(_ data: [Int: CGPoint], source: DataSource) {
        _CoMData = data
        
        log("Updated CoM data from \(source) with \(data.count) frames", level: .info)
    }

    // Updates CoM data from any source
    func updateFeaturesData(_ data: [Int: FeaturesModel], source: DataSource) {
        _FeaturesData = data
        
        log("Updated ML features data from \(source) with \(data.count) frames", level: .info)
    }
    
    // Updates bar reference points from any source
    func updateBarData(_ data: [Int: CGPoint], source: DataSource) {
        _BarReferenceData = data
        log("Updated bar reference points from \(source) with \(data.count) points", level: .info)
    }
    
    func syncBarPointVM (barPointVM: BarPointVM) {
        if !_BarReferenceData.isEmpty {
            // Update BarPointVM with loaded data
            barPointVM.pointsImage = _BarReferenceData
            barPointVM.isFirstPointAvailable = _BarReferenceData[0] != nil
            barPointVM.isSecondPointAvailable = _BarReferenceData[1] != nil
        }
    }
    
    // Updates events frame index data from any source
    func updateEventsData(_ data: EventsModel, source: DataSource) {
        _EventsData = data
        
        log("Updated Event data from \(source)", level: .info)
    }
    
    // Clears all processed data (useful when switching between file/processing modes)
    func clearProcessedData() {
        _keypointData.removeAll()
        _CoMData.removeAll()
        _FeaturesData.removeAll()
        _BarReferenceData.removeAll()
        isKeypointAvailable = false
        
        log("Cleared all processed data", level: .info)
    }

    // MARK: - Cleaner
    func clearAllData() {
        importFileVM.isDataLoaded = false
        importFileVM.isKeyLoaded = false
        
        // Clear file-based data
        importFileVM.keypointData.removeAll()
        importFileVM.CoMData.removeAll()
        importFileVM.featuresData.removeAll()
        importFileVM.barData.removeAll()
        
        importFileVM.FrameImageURLs = []
        importFileVM.FrameFolderURLs = []
        importFileVM.FrameCounts = 0
        
        // Clear unified processed data
        clearProcessedData()
    }
    
    // MARK: - Public Function of Media Loader
    func loadGalleryFile(url: URL, opID: String, autoDetectKeypoints: Bool) -> String? {
        // Initialize Processsing Manager
        let operationId = opID
        
        // Start tracking loadMedia process
        Task { @MainActor in
            ProcessingManagerVM.shared.startOperation(
                id: operationId,
                status: "Checking file availability...",
                isPrimary: true
            )
        }
        
        // Initialize File Manager
        let fileManager = FileManager.default
        var isDirectory: ObjCBool = false

        // Proceed to check if file exists
        guard fileManager.fileExists(atPath: url.path, isDirectory: &isDirectory), !isDirectory.boolValue else {
            return "Selected file or folder doesn't exist"
        }
        
        // Semaphore to wait
        let semaphore = DispatchSemaphore(value: 0)
        var loadResult: String?
        
        // Mkdir frame folder
        do {
            let tempDir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
            try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
            
            // Proceed to extract frames
            self.loadVideoFrames(videoURL: url, to: tempDir, opID: operationId) { result in
                loadResult = result
                semaphore.signal()
            }
        } catch {
            log("Error creating temporary directory: \(error.localizedDescription)", level: .error)
            return "Error creating temporary directory: \(error.localizedDescription)"
        }
        
        semaphore.wait()
        if let error = loadResult {
            return error
        }
        
        // Wait for media availability synchronously
        let group = DispatchGroup()
        group.enter()
        
        Task {
            await self.watchMediaAvailability(expectKeypoints: false)
            self.isDataTemp = false
            group.leave()
        }
        
        group.wait()
        
        return nil
    }

    func loadMedia(url: URL, opID: String, autoDetectKeypoints: Bool) async -> String? {
        // Initialize Processsing Manager
        let operationId = opID
        
        // Initialize File Manager
        let fileManager = FileManager.default
        var isDirectory: ObjCBool = false
        
        // Start accessing the selected resource
        guard SecurityScopedResourceManager.shared.startAccessing(url) else {
            // Return Error Message
            return "Permission denied: Cannot access selected file or folder"
        }
        
        // Check File Availability
        guard fileManager.fileExists(atPath: url.path, isDirectory: &isDirectory) else {
            // Return Error Message
            return "Selected file or folder doesn't exist"
        }
        
        // Load File
        if isDirectory.boolValue {
            // Start accessing the main folder - keep it alive for all operations
            do {
                // Get all items in the folder (no need to access each individually)
                let contents = try fileManager.contentsOfDirectory(
                    at: url,
                    includingPropertiesForKeys: [.isDirectoryKey, .contentAccessDateKey],
                    options: [.skipsHiddenFiles]
                )

                // Check for app files
                let videoURL = findFile(named: "color_video.mp4", in: contents)
                let keypointURL = findFile(named: "keypoints.json", in: contents)
                let comURL = findFile(named: "com.json", in: contents)
                let featuresURL = findFile(named: "features.json", in: contents)
                let eventsURL = findFile(named: "events.json", in: contents)
                let recordingMetadataURL = findFile(named: "recording_metadata.json", in: contents)
                
                // Check for frame directories
                let frameDirectories = contents.filter {
                    var isDir: ObjCBool = false
                    return fileManager.fileExists(atPath: $0.path, isDirectory: &isDir) &&
                    isDir.boolValue &&
                    $0.lastPathComponent.hasPrefix("color_frame")
                }

                let depthDirectories = contents.filter {
                    var isDir: ObjCBool = false
                    return fileManager.fileExists(atPath: $0.path, isDirectory: &isDir) &&
                    isDir.boolValue &&
                    $0.lastPathComponent.hasPrefix("depth_frame")
                }
                
                // MARK: - If Data Structure Detected (Processed)
                if !frameDirectories.isEmpty {
                    // Load recording with frame folders
                    self.importFileVM.loadVideoFolder(from: url)
                } else {
                    // MARK: If Video File Detected (Not Processed)
                    if let videoURL = videoURL {
                        // Update Processing Manager
                        Task { @MainActor in
                            ProcessingManagerVM.shared.updateOperation(
                                id: operationId,
                                status: "Processing video frames...",
                                progress: 0.2
                            )
                        }
                        
                        // Mkdir frame folder
                        let frameDir = url.appendingPathComponent("color_frames")
                        try FileManager.default.createDirectory(at: frameDir, withIntermediateDirectories: true)
                        
                        // Expand Video By Frames
                        let loadResult = await withCheckedContinuation { continuation in
                            self.loadVideoFrames(videoURL: videoURL, to: frameDir, opID: operationId) { result in
                                continuation.resume(returning: result)
                            }
                        }

                        if let error = loadResult {
                            return error
                        }
                    }
                }
                
                // Check & Load keypoints in folder
                if let keypointURL = keypointURL,
                   let comURL = comURL,
                   let featuresURL = featuresURL,
                   let eventsURL = eventsURL,
                   autoDetectKeypoints{
                    log("Found APP file in folder.", level: .debug)
                    
                    // Update Processing Manager
                    Task { @MainActor in
                        ProcessingManagerVM.shared.updateOperation(
                            id: operationId,
                            status: "Loading keypoints, CoM, features..."
                        )
                    }
                    
                    self.importFileVM.loadKeypoints(from: keypointURL)
                    try self.importFileVM.loadCoM(from: comURL)
                    try self.importFileVM.loadFeatures(from: featuresURL)
                    try self.importFileVM.loadEvents(from: eventsURL)
                }
                
                // Load metadata from folders
                if let recordingMetadataURL = recordingMetadataURL {
                    log("Found metadata file in folder: \(recordingMetadataURL.lastPathComponent)", level: .debug)
                    self.importFileVM.loadMetadata(from: recordingMetadataURL)
                }
                
                // Check for Depth Data
                if !depthDirectories.isEmpty {
                    self.isDataLIDAR = true
                }
                
                // Wait for media availability
                await self.watchMediaAvailability(expectKeypoints: ((keypointURL != nil) && autoDetectKeypoints))
                self.isDataTemp = false
                self.fps = self.importFileVM.fps
                
            } catch {
                log("Error loading folder: \(error.localizedDescription)", level: .error)
                return "Error loading folder: \(error.localizedDescription)"
            }

        } else {
            // It's a file - check extension and process
            let fileExtension = url.pathExtension.lowercased()
            switch fileExtension {
            case "json":
                self.importFileVM.loadKeypoints(from: url)
            case "mp4", "mov", "m4v":
                do {
                    let tempDir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
                    try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
                    
                    // Expand Video By Frames
                    let loadResult = await withCheckedContinuation { continuation in
                        self.loadVideoFrames(videoURL: url, to: tempDir) { result in
                            continuation.resume(returning: result)
                        }
                    }

                    if let error = loadResult {
                        return error
                    }
                    
                } catch {
                    log("Error creating temporary directory: \(error.localizedDescription)", level: .error)
                    return "Error creating temporary directory: \(error.localizedDescription)"
                }
                
            default:
                return "Unsupported file format: \(fileExtension)"
            }
        }
        
        return nil
    }
    
    // Loader for color_frame folder
    func loadVideoFrames(videoURL: URL, to: URL, opID: String? = nil, completion: @escaping (String?) -> Void) {
         Task {
             // Start tracking loadVideoFrames process
             if let operationId = opID {
                 Task { @MainActor in
                     ProcessingManagerVM.shared.startOperation(
                        id: operationId,
                        status: "Checking file availability...",
                        isPrimary: true
                     )
                 }
             }
             
             let operationId = opID ?? "loadVideoFrames_\(UUID().uuidString)"
             
             await self.importFileVM.loadVideoFile(from: videoURL, to: to, opID: operationId)

             await self.watchMediaAvailability(expectKeypoints: false)
             
             if importFileVM.isDataLoaded {
                 self.isDataTemp = true
                 completion(nil)
             } else {
                 self.isDataTemp = false
                 completion("Failed to load video.")
             }
         }
    }
    
    // MARK: - File Export
    func exportFramesContentsToAppDirectory(originalFileURL: URL) throws -> URL {
        // Get Temp Dir
        let fileManager = FileManager.default
        let tempDirURL = importFileVM.FrameImageURLs.first!.deletingLastPathComponent().deletingLastPathComponent()
        
        // Destination directory in Documents
        guard let documentsDir = fileManager.urls(for: .documentDirectory, in: .userDomainMask).first else {
            throw NSError(domain: "ExportFrames", code: -1, userInfo: [NSLocalizedDescriptionKey: "Failed to access Documents directory"])
        }

        // Create destination folder name based on original video file name
        let folderName = originalFileURL.deletingPathExtension().lastPathComponent
        let destinationDir = documentsDir.appendingPathComponent(folderName)

        // If destination folder exists, remove it (optional: handle duplicates if you want)
        if fileManager.fileExists(atPath: destinationDir.path) {
            try fileManager.removeItem(at: destinationDir)
        }

        // Create destination folder
        try fileManager.createDirectory(at: destinationDir, withIntermediateDirectories: true)

        // List subfolders/files in tempDir (this will be your frame_0, frame_1, etc.)
        let subItems = try fileManager.contentsOfDirectory(at: tempDirURL, includingPropertiesForKeys: nil, options: .skipsHiddenFiles)

        for subItem in subItems {
            let destinationSubItem = destinationDir.appendingPathComponent(subItem.lastPathComponent)

            // Copy each subfolder into destinationDir
            try fileManager.copyItem(at: subItem, to: destinationSubItem)
        }
        
        return destinationDir
    }

    
    
    // MARK: - Public Function for Media Player
    func getCoMCurrent() -> CGPoint? {
        if isKeypointAvailable {
            return self.getCoMByIndex(self.mediaPlayerVM.currentFrameIndex)
        } else { return nil }
    }
    
    func getCoMByIndex(_ index: Int) -> CGPoint? {
        if isKeypointAvailable {
            return self.CoMData[index] ?? nil
        } else { return nil }
    }
    
    func getKeypointsCurrent() -> PoseBox? {
        if isKeypointAvailable {
            return self.getKeypointsByIndex(self.mediaPlayerVM.currentFrameIndex)
        } else { return nil }
    }
    
    func getKeypointsByIndex(_ index: Int) -> PoseBox? {
        if isKeypointAvailable {
            return self.keypointData[index] ?? nil
        } else { return nil }
    }
    
    func getCurrentIndex() -> Int {
        if isKeypointAvailable {
            return self.mediaPlayerVM.currentFrameIndex
        } else { return 0 }
    }
    
    func tooglePlayback() {
        // Check if the player is Done
        if self.mediaPlayerVM.currentFrameIndex + 1 == self.mediaPlayerVM.totalFrames {
            // Reset Button if Done
            isPlaying = false
            self.mediaPlayerVM.firstFrame()
        } else {
            // Play/Pause Button if False
            if isPlaying {
                isPlaying = false
                self.mediaPlayerVM.stopPlayback()
            } else {
                isPlaying = true
                self.mediaPlayerVM.startPlayback()
            }
        }
    }
    
    // MARK: - Required Helper Functions
    @MainActor
    func watchMediaAvailability(expectKeypoints: Bool) async {
        while !isKeypointAvailable {
            if !expectKeypoints { break }

            if importFileVM.isKeyLoaded &&
               importFileVM.isCoMLoaded &&
               importFileVM.isFeaturesLoaded {

                updateKeypointsData(importFileVM.keypointData, source: .file)
                updateCoMData(importFileVM.CoMData, source: .file)
                updateFeaturesData(importFileVM.featuresData, source: .file)
                updateBarData(importFileVM.barData, source: .file)
                updateEventsData(importFileVM.eventsData, source: .file)
                
                isKeypointAvailable = true
                log("Successfully loaded Keypoints frame data.", level: .debug)
            }

            try? await Task.sleep(nanoseconds: 100_000_000)
        }

        while !isMediaAvailable {
            if importFileVM.isDataLoaded {
                isMediaAvailable = true
                log("Successfully loaded LiDAR frame data.", level: .debug)

                mediaPlayerVM.updateMedia(
                    imageURLs: importFileVM.FrameImageURLs
                )
            }

            try? await Task.sleep(nanoseconds: 100_000_000)
        }
    }
    
    private func findFile(named name: String, in contents: [URL]) -> URL? {
        return contents.first {
            $0.lastPathComponent.lowercased() == name.lowercased()
        }
    }
}
     
