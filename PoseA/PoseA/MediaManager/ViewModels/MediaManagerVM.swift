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

    var currentFrameImage: UIImage? {
        mediaPlayerViewModel.currentFrameImage
    }

    var currentFrameIndex: Int {
        mediaPlayerViewModel.currentFrameIndex
    }
    
    // Media Player Variable
    var isPlaying: Bool = false
    
    // MARK: - Public Function of Media Loader
    
    func loadMedia(url: URL) -> String? {
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
            // Start accessing the main folder - keep it alive for all operations
            do {
                // Get all items in the folder (no need to access each individually)
                let contents = try fileManager.contentsOfDirectory(
                    at: url,
                    includingPropertiesForKeys: [.isDirectoryKey, .contentAccessDateKey],
                    options: [.skipsHiddenFiles]
                )

                log("Found \(contents.count) items in folder \(url.lastPathComponent)", level: .debug)
                                
                // Analyze folder contents
                let videoFiles = contents.filter {
                    ["mp4", "mov", "m4v"].contains($0.pathExtension.lowercased())
                }
                
                let keypointFiles = contents.filter {
                    let filename = $0.lastPathComponent.lowercased()
                    return $0.pathExtension.lowercased() == "json" &&
                           (filename.contains("keypoint") || filename.contains("pose"))
                }
                
                // Check for frame directories (LiDAR recording)
                let frameDirectories = contents.filter {
                    var isDir: ObjCBool = false
                    return fileManager.fileExists(atPath: $0.path, isDirectory: &isDir) &&
                           isDir.boolValue &&
                           $0.lastPathComponent.hasPrefix("frame_")
                }
                
                // Check for direct depth data files
                let hasDepthData = contents.contains { $0.lastPathComponent == "depthData.dat" }

                if !frameDirectories.isEmpty {
                    // Load LiDAR recording with frame folders
                    self.fileLoaderViewModel.loadVideoFolder(from: url)

                    // Check for keypoints in LiDAR folder
                    if !keypointFiles.isEmpty {
                        let keypointURL = keypointFiles.first!
                        log("Found keypoint file in LiDAR folder: \(keypointURL.lastPathComponent)", level: .debug)
                        
                        self.fileLoaderViewModel.loadKeypoints(from: keypointURL)
                    }
                    
                }
            } catch {
                log("Error loading folder: \(error.localizedDescription)", level: .error)
            }
            
            Task {
                await self.watchMediaAvailability()
            }

        } else {
            // It's a file - check extension and process
            let fileExtension = url.pathExtension.lowercased()
            switch fileExtension {
            case "json":
                self.fileLoaderViewModel.loadKeypoints(from: url)
//            case "mp4", "mov", "m4v":
//                loadVideo(from: url)
            default:
                return "Unsupported file format: \(fileExtension)"
            }
        }
        
        return nil
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
    func watchMediaAvailability() {
        // Task is required because we use `await`/delay
        Task {
            while !isKeypointAvailable {
                if fileLoaderViewModel.isKeyLoaded {
                    isKeypointAvailable = true
                    log("Successfully loaded Keypoints frame data.", level: .debug)
                }
                try? await Task.sleep(nanoseconds: 100_000_000) // 100ms polling
            }
        }

        Task {
            while !isMediaAvailable {
                if fileLoaderViewModel.isDataLoaded {
                    isMediaAvailable = true
                    log("Successfully loaded LiDAR frame data.", level: .debug)

                    if fileLoaderViewModel.isDataLIDAR {
                        mediaPlayerViewModel.updateMedia(
                            imageURLs: fileLoaderViewModel.FrameImageURLs,
                            folderURLs: fileLoaderViewModel.FrameFolderURLs
                        )
                    }
                }
                try? await Task.sleep(nanoseconds: 100_000_000)
            }
        }
    }
}
     
