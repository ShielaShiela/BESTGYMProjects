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
    var fileLoaderViewModel: FileLoaderVM = FileLoaderVM()
    var mediaPlayerViewModel: MediaPlayerVM = MediaPlayerVM()
    
    // Frame Update
    var isMediaAvailable: Bool = false
    var isKeypointAvailable: Bool = false
    var isDataLIDAR: Bool = false
    var isDataTemp: Bool = false
    
    var currentFrameImage: UIImage? {
        mediaPlayerViewModel.currentFrameImage
    }

    var currentFrameIndex: Int {
        mediaPlayerViewModel.currentFrameIndex
    }
    
    // Media Player Variable
    var isPlaying: Bool = false
    
    
    private var loadingTask: Task<Void, Never>?  // ADD THIS


    // MARK: Shiela change it
    func clearAllData() {
        // Cancel any in-flight loading FIRST
        loadingTask?.cancel()
        loadingTask = nil
        
        isMediaAvailable = false
        isKeypointAvailable = false
        isDataLIDAR = false
        isDataTemp = false
        
        mediaPlayerViewModel.resetAll()
        
        fileLoaderViewModel.isDataLoaded = false
        fileLoaderViewModel.isKeyLoaded = false
        fileLoaderViewModel.keypointsByFrame.removeAll()
        fileLoaderViewModel.FrameImageURLs = []
        fileLoaderViewModel.FrameFolderURLs = []
        fileLoaderViewModel.FrameCounts = 0
        fileLoaderViewModel.frameIndexMap = [:]
    }
    
    func seekToFrame(_ index: Int) {
        let clamped = max(0, min(index, mediaPlayerViewModel.totalFrames - 1))
        mediaPlayerViewModel.moveToFrame(clamped)
    }
    
    // MARK: - Public Function of Media Loader
        
    func loadGalleryFile(url: URL, autoDetectKeypoints: Bool, completion: @escaping (String?) -> Void) {
        // Initialize File Manager
        let fileManager = FileManager.default
        var isDirectory: ObjCBool = false

        // Proceed to check if file exists
        guard fileManager.fileExists(atPath: url.path, isDirectory: &isDirectory), !isDirectory.boolValue else {
            completion("Invalid file URL: \(url.lastPathComponent)")
            return
        }
        
        // Check if the same file is already saved in project
        // Destination directory in Documents
        guard let documentsDir = fileManager.urls(for: .documentDirectory, in: .userDomainMask).first else {
            return
        }

        // Lookup for destination folder name based on original video file name
        let folderName = url.deletingPathExtension().lastPathComponent
        let destinationDir = documentsDir.appendingPathComponent(folderName)

        loadingTask = Task {
            guard !Task.isCancelled else { return }
            await self.fileLoaderViewModel.loadVideoFile(from: url)
            guard !Task.isCancelled else { return }
            await self.watchMediaAvailability(expectKeypoints: false)
            guard !Task.isCancelled else { return }
            if fileLoaderViewModel.isDataLoaded {
                self.isDataTemp = true
                completion(nil)
            } else {
                self.isDataTemp = false
                completion("Failed to load video.")
            }
        }

    }
    func loadMedia(url: URL, autoDetectKeypoints: Bool, completion: @escaping (String?) -> Void) {
        let fileManager = FileManager.default
        var isDirectory: ObjCBool = false
        
        guard SecurityScopedResourceManager.shared.startAccessing(url) else {
            completion("Permission denied: Cannot access selected file or folder")
            return
        }
        
        guard fileManager.fileExists(atPath: url.path, isDirectory: &isDirectory) else {
            completion("Selected file or folder doesn't exist")
            return
        }
        
        if isDirectory.boolValue {
            do {
                let contents = try fileManager.contentsOfDirectory(
                    at: url,
                    includingPropertiesForKeys: [.isDirectoryKey, .contentAccessDateKey],
                    options: [.skipsHiddenFiles]
                )
                
                let keypointFiles = contents.filter {
                    let filename = $0.lastPathComponent.lowercased()
                    return $0.pathExtension.lowercased() == "json" && filename.contains("keypoint")
                }
                
                let frameDirectories = contents.filter {
                    var isDir: ObjCBool = false
                    return fileManager.fileExists(atPath: $0.path, isDirectory: &isDir) &&
                        isDir.boolValue && $0.lastPathComponent.hasPrefix("frame_")
                }
                
                let videoFiles = contents.filter {
                    let ext = $0.pathExtension.lowercased()
                    return ext == "mp4" || ext == "mov" || ext == "m4v"
                }
                
                if !frameDirectories.isEmpty {
                    self.fileLoaderViewModel.loadVideoFolder(from: url)
                    
                    
                    
                    for frameDir in frameDirectories {
                        let depthDataURL = frameDir.appendingPathComponent("depthData.dat")
                        if fileManager.fileExists(atPath: depthDataURL.path) {
                            self.isDataLIDAR = true
                            break
                        }
                    }
                    
                    loadingTask = Task {
                        guard !Task.isCancelled else { return }
                        
                        if !keypointFiles.isEmpty && autoDetectKeypoints {
                            await self.fileLoaderViewModel.loadKeypoints(from: keypointFiles.first!)
                        }
                        await self.watchMediaAvailability(expectKeypoints: (!keypointFiles.isEmpty && autoDetectKeypoints))
                        guard !Task.isCancelled else { return }
                        self.isDataTemp = false
                        await MainActor.run { completion(nil) }
                    }
                    
                } else if !videoFiles.isEmpty {
                    let videoURL = videoFiles.first!
                    self.isDataLIDAR = false
                    self.isDataTemp = false
                    
                    let keypointURL: URL? = keypointFiles.first
//                    let keypointURL: URL? = (!keypointFiles.isEmpty && autoDetectKeypoints) ? keypointFiles.first : nil
                    
                    
                    // ADD THESE:
                    log("🎬 Video files found: \(videoFiles.map { $0.lastPathComponent })", level: .info)
                    log("🔑 Keypoint files found: \(keypointFiles.map { $0.lastPathComponent })", level: .info)
                    log("🔑 autoDetectKeypoints: \(autoDetectKeypoints)", level: .info)
                    log("🔑 keypointURL resolved: \(String(describing: keypointURL?.lastPathComponent))", level: .info)
                    
                    
                    loadingTask = Task {
                        guard !Task.isCancelled else { return }
                        await self.fileLoaderViewModel.loadVideoFile(from: videoURL)
                        guard !Task.isCancelled else { return }
                        
                        // ✅ Await keypoints BEFORE watchMediaAvailability
                        if let keypointURL = keypointURL {
                            await self.fileLoaderViewModel.loadKeypoints(from: keypointURL)  // now awaited
                        }
                        
                        // ✅ Remove the arbitrary sleep — no longer needed
                        guard !Task.isCancelled else { return }
                        
                        await self.watchMediaAvailability(expectKeypoints: (keypointURL != nil))
                        guard !Task.isCancelled else { return }
                        self.isDataTemp = false
                        await MainActor.run { completion(nil) }
                    }
                    
                } else {
                    completion("No valid video data found in folder")
                    return
                }
                
            } catch {
                completion("Error loading folder: \(error.localizedDescription)")
                return
            }
            
        } else {
            let fileExtension = url.pathExtension.lowercased()
            switch fileExtension {
            case "json":
                Task {
                       await self.fileLoaderViewModel.loadKeypoints(from: url)
                       await MainActor.run { completion(nil) }
                   }
            case "mp4", "mov", "m4v":
                loadingTask = Task {
                    guard !Task.isCancelled else { return }
                    await self.fileLoaderViewModel.loadVideoFile(from: url)
                    guard !Task.isCancelled else { return }
                    await self.watchMediaAvailability(expectKeypoints: false)
                    guard !Task.isCancelled else { return }
                    self.isDataTemp = false
                    await MainActor.run { completion(nil) }
                }
            default:
                completion("Unsupported file format: \(fileExtension)")
            }
        }
    }

    
    // MARK: - File Export
    func exportFramesContentsToAppDirectory(originalFileURL: URL) throws -> URL {
        // Get Temp Dir
        let fileManager = FileManager.default
        let tempDirURL = fileLoaderViewModel.FrameImageURLs.first!.deletingLastPathComponent().deletingLastPathComponent()
        
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
   
    func getKeypointsCurrent() -> [KeypointData]? {
        guard fileLoaderViewModel.isKeyLoaded else { return nil }
        let playerIndex = mediaPlayerViewModel.currentFrameIndex
        let frameKey = fileLoaderViewModel.frameIndexMap[playerIndex] ?? playerIndex
        return fileLoaderViewModel.keypointsByFrame[frameKey]
    }

    func getKeypointsByIndex(_ index: Int) -> [KeypointData]? {
        guard fileLoaderViewModel.isKeyLoaded else { return nil }
        
        // FrameFolderURLs is empty for 2D video, use direct index lookup
        // JSON keys ARE the original video frame numbers which match extractFramesAndSaveToDisk index
        return fileLoaderViewModel.keypointsByFrame[index]
    }
    func getCurrentIndex() -> Int {
        if fileLoaderViewModel.isKeyLoaded {
            return self.mediaPlayerViewModel.currentFrameIndex
        } else { return 0 }
    }
    
    func tooglePlayback() {
        // Check if the player is Done
        if self.mediaPlayerViewModel.currentFrameIndex + 1 == self.mediaPlayerViewModel.totalFrames {
            // Reset Button if Done
            isPlaying = false
            self.mediaPlayerViewModel.firstFrame()
        } else {
            // Play/Pause Button if False
            if isPlaying {
                isPlaying = false
                self.mediaPlayerViewModel.stopPlayback()
            } else {
                isPlaying = true
                self.mediaPlayerViewModel.startPlayback()
            }
        }
    }
    
    @MainActor
    func watchMediaAvailability(expectKeypoints: Bool) async {
        if expectKeypoints {
            if !fileLoaderViewModel.isKeyLoaded {
                var keypointTimeout = 0
                while !fileLoaderViewModel.isKeyLoaded && keypointTimeout < 50 {
                    guard !Task.isCancelled else { return }
                    try? await Task.sleep(nanoseconds: 100_000_000)
                    keypointTimeout += 1
                }
            }
            isKeypointAvailable = fileLoaderViewModel.isKeyLoaded
        }

        var mediaTimeout = 0
        while !fileLoaderViewModel.isDataLoaded && mediaTimeout < 100 {
            guard !Task.isCancelled else { return }
            try? await Task.sleep(nanoseconds: 100_000_000)
            mediaTimeout += 1
        }

        guard !Task.isCancelled else { return }

        if fileLoaderViewModel.isDataLoaded {
            if !fileLoaderViewModel.FrameFolderURLs.isEmpty && fileLoaderViewModel.isKeyLoaded {
                fileLoaderViewModel.remapKeypointsToArrayIndex()  // LiDAR only
            }
            
            // 2D video: no remap, JSON keys match frame indices directly
            mediaPlayerViewModel.updateMedia(imageURLs: fileLoaderViewModel.FrameImageURLs)
            isMediaAvailable = true
        } else {
            log("Timed out waiting for media.", level: .error)
        }
    }
}
     
