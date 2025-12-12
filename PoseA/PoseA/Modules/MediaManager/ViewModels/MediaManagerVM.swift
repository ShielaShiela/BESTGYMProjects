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
    

    // MARK: - Cleaner
    func clearAllData() {
        fileLoaderViewModel.isDataLoaded = false
        fileLoaderViewModel.isKeyLoaded = false
        
        fileLoaderViewModel.keypointsByFrame.removeAll()
        fileLoaderViewModel.FrameImageURLs = []
        fileLoaderViewModel.FrameFolderURLs = []
        
        fileLoaderViewModel.FrameCounts = 0
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

        // If destination folder exists, open the project
        if fileManager.fileExists(atPath: destinationDir.path) {
            log("Found video in project folder \(destinationDir.lastPathComponent)", level: .debug)
            
            // Open Project
            let ret = self.loadMedia(url: destinationDir, autoDetectKeypoints: autoDetectKeypoints)
            self.isDataLIDAR = false
            self.isDataTemp = false
            completion(ret)
            
            return
        }
        
        // Proceed to extract frames if not processed yet.
        Task {
            await self.fileLoaderViewModel.loadVideoFile(from: url)

            await self.watchMediaAvailability(expectKeypoints: false)
            
            if fileLoaderViewModel.isDataLoaded {
                self.isDataTemp = true
                completion(nil)
            } else {
                self.isDataTemp = false
                completion("Failed to load video.")
            }
        }
    }

    func loadMedia(url: URL, autoDetectKeypoints: Bool) -> String? {
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
            // It's a folder
            do {
                // Get all items in the folder
                let contents = try fileManager.contentsOfDirectory(
                    at: url,
                    includingPropertiesForKeys: [.isDirectoryKey, .contentAccessDateKey],
                    options: [.skipsHiddenFiles]
                )
                
                let keypointFiles = contents.filter {
                    let filename = $0.lastPathComponent.lowercased()
                    log("\(filename)", level: .debug)
                    return $0.pathExtension.lowercased() == "json" &&
                    (filename.contains("keypoint"))
                }
                
                log("\(keypointFiles)Found \(contents.count) items in folder \(url.lastPathComponent)", level: .debug)
                
                // Check for frame directories
                let frameDirectories = contents.filter {
                    var isDir: ObjCBool = false
                    return fileManager.fileExists(atPath: $0.path, isDirectory: &isDir) &&
                    isDir.boolValue &&
                    $0.lastPathComponent.hasPrefix("frame_")
                }
                
                // Check for video files in the folder
                let videoFiles = contents.filter {
                    let ext = $0.pathExtension.lowercased()
                    return ext == "mp4" || ext == "mov" || ext == "m4v"
                }
                
                // If Data Structure Detected (LiDAR with frame folders)
                if !frameDirectories.isEmpty {
                    // Load LiDAR recording with frame folders
                    self.fileLoaderViewModel.loadVideoFolder(from: url)
                    
                    // Check for keypoints in LiDAR folder
                    if !keypointFiles.isEmpty && autoDetectKeypoints {
                        let keypointURL = keypointFiles.first!
                        log("Found keypoint file in folder: \(keypointURL.lastPathComponent)", level: .debug)
                        
                        self.fileLoaderViewModel.loadKeypoints(from: keypointURL)
                    }
                    
                    // Check for Depth Data
                    for frameDir in frameDirectories {
                        let depthDataURL = frameDir.appendingPathComponent("depthData.dat")
                        if fileManager.fileExists(atPath: depthDataURL.path) {
                            self.isDataLIDAR = true
                            break // Exit early if found
                        }
                    }
                    
                    if self.isDataLIDAR {
                        log("Depth data found in at least one frame directory.", level: .info)
                    } else {
                        log("No depth data found in any frame directory.", level: .info)
                    }
                    
                    // Single watchMediaAvailability call for LiDAR data
                    Task {
                        await self.watchMediaAvailability(expectKeypoints: (!keypointFiles.isEmpty && autoDetectKeypoints))
                        self.isDataTemp = false
                    }
                }
                // Regular video folder (no frame directories, but has video file)
                else if !videoFiles.isEmpty {
                    let videoURL = videoFiles.first!
                    log("Found video file in folder: \(videoURL.lastPathComponent)", level: .debug)
                    self.isDataLIDAR = false
                    self.isDataTemp = false
                    
                    // Prepare keypoint URL before Task if needed
                    let keypointURL: URL? = if !keypointFiles.isEmpty && autoDetectKeypoints {
                        keypointFiles.first
                    } else {
                        nil
                    }
                    
                    // Load video and wait for it to complete before checking availability
                    Task {
                        // IMPORTANT: Wait for video to load first
                        await self.fileLoaderViewModel.loadVideoFile(from: videoURL)
                        
                        log("Video file loaded, checking for keypoints...", level: .debug)
                        
                        // Check for keypoints AFTER video is loaded
                        if let keypointURL = keypointURL {
                            log("Loading keypoint file: \(keypointURL.lastPathComponent)", level: .debug)
                            self.fileLoaderViewModel.loadKeypoints(from: keypointURL)
                        } else {
                            log("No keypoint file to load", level: .debug)
                        }
                        
                        // Add a small delay to ensure keypoints are processed
                        try? await Task.sleep(nanoseconds: 100_000_000) // 0.1 seconds
                        
                        // Now check media availability with correct expectKeypoints value
                        await self.watchMediaAvailability(expectKeypoints: (keypointURL != nil))
                        self.isDataTemp = false
                        
                        log("Media availability check completed", level: .debug)
                    }
                }
                else {
                    return "No valid video data found in folder"
                }
        
            } catch {
                log("Error loading folder: \(error.localizedDescription)", level: .error)
                return "Error loading folder: \(error.localizedDescription)"
            }

        } else {
            // It's a file - check extension and process
            let fileExtension = url.pathExtension.lowercased()
            switch fileExtension {
            case "json":
                self.fileLoaderViewModel.loadKeypoints(from: url)
            case "mp4", "mov", "m4v":
                Task {
                    await self.fileLoaderViewModel.loadVideoFile(from: url)
                    // Watch for media availability after loading
                    await self.watchMediaAvailability(expectKeypoints: false)
                    self.isDataTemp = false
                }
                break
            default:
                return "Unsupported file format: \(fileExtension)"
            }
        }
        
        return nil
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
        if fileLoaderViewModel.isKeyLoaded {
            return self.getKeypointsByIndex(self.mediaPlayerViewModel.currentFrameIndex)
        } else { return nil }
    }
    
    func getKeypointsByIndex(_ index: Int) -> [KeypointData]? {
        if fileLoaderViewModel.isKeyLoaded {
            return self.fileLoaderViewModel.keypointsByFrame[index] ?? nil
        } else { return nil }
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
    
    // MARK: - Required Helper Functions

    @MainActor
    func watchMediaAvailability(expectKeypoints: Bool) {
        // Task is required because we use `await`/delay
        Task {
            while !isKeypointAvailable {
                if !expectKeypoints { break }
                if fileLoaderViewModel.isKeyLoaded {
                    isKeypointAvailable = true
                    log("Successfully loaded Keypoints frame data.", level: .debug)
                }
                try? await Task.sleep(nanoseconds: 100_000_000) // 100ms polling
            }
            
            while !isMediaAvailable {
                if fileLoaderViewModel.isDataLoaded {
                    isMediaAvailable = true
                    log("Successfully loaded LiDAR frame data.", level: .debug)

                    mediaPlayerViewModel.updateMedia(
                        imageURLs: fileLoaderViewModel.FrameImageURLs
                    )
                }
                try? await Task.sleep(nanoseconds: 100_000_000)
            }
        }
    }
   
}
     
