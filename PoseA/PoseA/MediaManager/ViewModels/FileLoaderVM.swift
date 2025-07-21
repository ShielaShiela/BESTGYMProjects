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
    var isDataLIDAR: Bool = false
    var isDataLoaded: Bool = false
    var isKeyLoaded: Bool = false
    
    // MARK: - 3D LiDAR Data Loader Public Methods
    func loadVideoFolder(from url: URL) {
        log("Started load LiDAR video folder for URL: \(url.path)", level: .debug)

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
                    
                    // Set Data Status
                    self.isDataLIDAR = true
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
