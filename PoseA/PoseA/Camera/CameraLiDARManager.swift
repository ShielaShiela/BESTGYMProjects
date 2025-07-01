//
//  CameraLiDARManager.swift
//  DataCaptureTest
//
//  Created by Shiela Cabahug on 2024/7/4.
//

import SwiftUI
import Combine
import AVFoundation
import Photos
import Metal
import MetalKit
import CoreGraphics


class CameraLiDARManager: ObservableObject, CaptureDataReceiver {
//    var filter = true
    var capturedData: FrameDataVM
    @Published var isFilteringDepth: Bool {
        didSet {
            controller.isFilteringEnabled = isFilteringDepth
//            filter = isFilteringDepth
        }
    }
    
    @Published var isLiveCapture: Bool = true {
        didSet {
            if isLiveCapture {
                resumeStream()
            } else {
                controller.stopStream()
            }
        }
    }

    @Published var orientation = UIDevice.current.orientation
    @Published var waitingForCapture = false
    @Published var processingCapturedResult = false
    @Published var dataAvailable = false
    @Published var isDataLoaded = false
    
    @Published var isRecording = false
    @Published var depthValue: Float?
    
    let controller: CameraLiDARDepthControllerUI
    var cancellables = Set<AnyCancellable>()
    var session: AVCaptureSession { controller.captureSession }
    
    // Add these properties to your CameraLiDARManager class
    private var videoWriter: AVAssetWriter?
    private var videoWriterInput: AVAssetWriterInput?
    private var pixelBufferAdaptor: AVAssetWriterInputPixelBufferAdaptor?

    private var recordingStartTime: Date?
    private var recordingFolder: URL?
    private var frameCount: Int = 0
    @Published var currentFrameIndex: Int = 0
    @Published var totalFrames: Int = 0
    private var frameURLs: [URL] = []
    private var preloadedFrames: [Int: FrameDataModel] = [:]
    private let preloadRange = 5 // Preload 5 frames ahead and behind
    @Published var isPlaying: Bool = false
    @Published var playbackTimer: Timer?
    @Published var sliderPosition: Double = 0
    
    private let sessionQueue = DispatchQueue(label: "com.bestgym.sessionQueue", qos: .userInitiated)
    

    @Published var measuredDistance: Float?
    @Published var selectedPoints: [CGPoint] = []
    
    // Internal variables to store 3D points
    private var firstWorldPoint: SIMD3<Float>?
    private var secondWorldPoint: SIMD3<Float>?
    

    private var keypointData: [Int: [[String: Any]]] = [:] // Frame index -> keypoints
    private var processedImage: UIImage?
    
    private var processedImages: [Int: UIImage] = [:]
    
    private let preloadWindowSize = 30 // How many frames to keep ahead and behind
    private var preloadedFrameIndices = Set<Int>() // Track which frames are preloaded
    var onFrameChange: ((Int) -> Void)?
    
    @Published var centerDepthValue: Float?
    private var centerDepthTimer: Timer?
    private var recordingOrientation: UIDeviceOrientation = .portrait
    
    var useLiDAR: Bool = false
    
    // --- Loaded Data Properties ---
    private var loadedRecordingMetadata: RecordingMetadata? // Store parsed metadata
    private var loadedDataURL: URL? // Store the root URL of the loaded data
    private var isLoadedDataLiDAR: Bool = false // Flag to know the type of loaded data
    
    @Published var currentFrameImage: UIImage? = nil
    @Published var lidarFrameImageURLs:[URL] = []
    @Published var _lidarFrameURLs: [URL] = []
    @Published var DataLiDARAvailable: Bool = false
    
    // --- Data Storage for Playback ---
    private var lidarFrameURLs: [URL] = []        // Stores URLs for LiDAR frame folders/images
    private var videoFrames: [UIImage] = []     // Stores extracted frames for video files (Your approach)

    // Public accessor property
    public var recordingMetadata: RecordingMetadata? {
        return loadedRecordingMetadata
    }
    init() {
        // Create an object to store the captured data for the views to present.
        capturedData = FrameDataVM()
        
        // Check if LiDAR is available
        let discoverySession = AVCaptureDevice.DiscoverySession(
            deviceTypes: [.builtInLiDARDepthCamera],
            mediaType: .video,
            position: .back
        )
        useLiDAR = !discoverySession.devices.isEmpty
        
        // Initialize controller with appropriate configuration
        controller = CameraLiDARDepthControllerUI()
        controller.isFilteringEnabled = true
        
        if useLiDAR {
            controller.startStream()
        } else {
            // Initialize with basic camera functionality
            controller.setupBasicCamera()
        }
        
        isFilteringDepth = controller.isFilteringEnabled
        
        NotificationCenter.default.publisher(for: UIDevice.orientationDidChangeNotification).sink { _ in
            self.orientation = UIDevice.current.orientation
        }.store(in: &cancellables)
        controller.delegate = self
    }
    
    
    // Protocol CaptureDataReceiver
//    func startPhotoCapture() {
//        controller.capturePhoto()
//        waitingForCapture = true
//    }
    
    // Protocol CaptureDataReceiver
    func onNewPhotoData(capturedData: FrameDataModel) {
        // Because the views hold a reference to `capturedData`, the app updates each texture separately.
        self.capturedData.database = capturedData
        waitingForCapture = false
        processingCapturedResult = true
    }
    
    // MARK: - Fix for the CameraLiDARManager onNewData method
    func onNewData(capturedData: FrameDataModel) {
        // Always ensure we're on the main thread for @Published property updates
        if !Thread.isMainThread {
            DispatchQueue.main.async {
                self.onNewData(capturedData: capturedData)
            }
            return
        }
        
        // Update basic camera data
        self.capturedData.database.colorY = capturedData.colorY
        self.capturedData.database.colorCbCr = capturedData.colorCbCr
        self.capturedData.database.cameraIntrinsics = capturedData.cameraIntrinsics
        self.capturedData.database.cameraReferenceDimensions = capturedData.cameraReferenceDimensions
        self.capturedData.database.colorImage = capturedData.colorImage
        
        // Only update LiDAR-specific data if LiDAR is available
        if useLiDAR {
            self.capturedData.database.depth = capturedData.depth
            self.capturedData.database.depthCenter = capturedData.depthCenter
            self.capturedData.database.originalDepth = capturedData.originalDepth
        }
        
        dataAvailable = true
    }
    
    // MARK: - Improved setupVideoWriter method
    private func setupVideoWriter(at folder: URL) {
        print("🎬 Setting up video writer...")
        
        // Create a file URL for the video
        let fileURL = folder.appendingPathComponent("recording.mp4")
        
        // Clean up any existing file
        if FileManager.default.fileExists(atPath: fileURL.path) {
            try? FileManager.default.removeItem(at: fileURL)
        }
        
        do {
            // Create the asset writer
            let videoWriter = try AVAssetWriter(outputURL: fileURL, fileType: .mp4)
            
            // Get dimensions from capturedData
            let width = Int(self.capturedData.database.cameraReferenceDimensions.width)
            let height = Int(self.capturedData.database.cameraReferenceDimensions.height)
            
            print("Setting up video writer with dimensions: \(width)x\(height)")
            
            // Create video settings
            let videoSettings: [String: Any] = [
                AVVideoCodecKey: AVVideoCodecType.h264,
                AVVideoWidthKey: width,
                AVVideoHeightKey: height,
                AVVideoCompressionPropertiesKey: [
                    AVVideoAverageBitRateKey: 8000000,
                    AVVideoMaxKeyFrameIntervalKey: 30,
                    AVVideoProfileLevelKey: AVVideoProfileLevelH264HighAutoLevel
                ]
            ]
            
            // Create writer input
            let writerInput = AVAssetWriterInput(mediaType: .video, outputSettings: videoSettings)
            writerInput.expectsMediaDataInRealTime = true
            
            // Create pixel buffer adaptor
            let sourcePixelBufferAttributes: [String: Any] = [
                kCVPixelBufferPixelFormatTypeKey as String: Int(kCVPixelFormatType_32ARGB),
                kCVPixelBufferWidthKey as String: width,
                kCVPixelBufferHeightKey as String: height,
                kCVPixelBufferCGImageCompatibilityKey as String: true,
                kCVPixelBufferCGBitmapContextCompatibilityKey as String: true
            ]
            
            let pixelBufferAdaptor = AVAssetWriterInputPixelBufferAdaptor(
                assetWriterInput: writerInput,
                sourcePixelBufferAttributes: sourcePixelBufferAttributes
            )
            
            if videoWriter.canAdd(writerInput) {
                videoWriter.add(writerInput)
                videoWriter.startWriting()
                videoWriter.startSession(atSourceTime: CMTime.zero)
                
                // Update properties on main thread
                DispatchQueue.main.async {
                    self.videoWriter = videoWriter
                    self.videoWriterInput = writerInput
                    self.pixelBufferAdaptor = pixelBufferAdaptor
                    print("✅ Video writer set up successfully")
                }
            } else {
                print("❌ Failed to add writer input")
            }
        } catch {
            print("❌ Failed to setup video writer: \(error)")
        }
    }

    func saveCapturedData(completion: @escaping (Bool) -> Void) {
        do {
            
            let documentDirectory = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first!
            capturedData.saveData(to: documentDirectory, filter: controller.isFilteringEnabled)
            completion(true)
        } catch {
            print("Error saving capture data: \(error)")
            if let nsError = error as NSError? {
                print("Error domain: \(nsError.domain)")
                print("Error code: \(nsError.code)")
                print("Error user info: \(nsError.userInfo)")
                print("Error saving capture data: \(error.localizedDescription)")
            }
            completion(false)
        }
    }
    
    
    
    func loadCapturedData(from url: URL, device: MTLDevice) {
        
        controller.stopStream()
        waitingForCapture = true
        
        DispatchQueue.global(qos: .userInitiated).async {
            do {
                self.capturedData.loadData(from: url, device: device)
                DispatchQueue.main.async {
                    self.dataAvailable = true
                    
                    print("Data loaded successfully and view updated")
                }
            } catch {
                DispatchQueue.main.async {
                    print("Failed to load data: \(error)")
                    self.dataAvailable = false
                }
            }
        }
    }
    
    func loadFrame(at index: Int) {
        guard index >= 0 && index < frameURLs.count else {
            print("Invalid frame index: \(index)")
            return
        }
        
        let frameURL = frameURLs[index]
        print("Loading frame at index \(index): \(frameURL.lastPathComponent)")
        
        do {
            // Load the frame data
            try self.capturedData.loadData(from: frameURL, device: MTLCreateSystemDefaultDevice()!)
            currentFrameIndex = index
            isDataLoaded = true
            
            // Load processed image if available
            if let processedImage = processedImages[index] {
                capturedData.database.processedImage = processedImage
                print("Loaded processed image for frame \(index)")
            } else {
                // Only clear processed image if we're not retaining them
                capturedData.database.processedImage = nil
            }
            
            // Apply orientation correction to the colorImage if available
            if let colorImage = capturedData.database.colorImage {
                capturedData.database.colorImage = applyCorrectOrientation(to: colorImage)
                print("Applied orientation correction to frame \(index)")
            }
            
            print("Successfully loaded frame \(index)")
        } catch {
            print("Error loading frame at index \(index): \(error)")
            isDataLoaded = false
        }
    }
}

// MARK: - Thread-Safe Camera Operations
extension CameraLiDARManager {
    func startStream() {
        controller.startStream()
        isLiveCapture = true
    }

    // Thread-safe version of resumeStream
    func resumeStream() {
        // Use session queue for thread safety
        sessionQueue.async { [weak self] in
            guard let self = self else { return }
            
            // Start capture session on background thread
            self.controller.startStream()
            
            // Update UI state on main thread
            DispatchQueue.main.async {
                self.isLiveCapture = true
            }
        }
    }
    
    /// Stops the live camera stream.
    func pauseStream() {
        // Use your existing implementation, ensuring it stops the session
        // sessionQueue.async { // If using a session queue
             if self.controller.captureSession.isRunning {
                 self.controller.stopStream()
                 // Update UI state on main thread if needed
                 DispatchQueue.main.async { self.isLiveCapture = false }
             }
        // }
        print("⏸️ Stream paused.")
    }
}


// MARK: - Debug Helpers
extension CameraLiDARManager {
    // Call this method when you're having camera display issues
    func debugCameraSetup() {
        print("===== Camera Debug Information =====")
        print("Is live capture: \(isLiveCapture)")
        print("Is recording: \(isRecording)")
        print("Total frames: \(totalFrames)")
        print("Current frame index: \(currentFrameIndex)")
        
        // Check controller
        print("Controller capture session exists: \(controller.captureSession != nil)")
        print("Controller capture session running: \(controller.captureSession.isRunning)")
        
        // Check for camera authorization
        let authStatus = AVCaptureDevice.authorizationStatus(for: .video)
        print("Camera authorization status: \(authStatus.rawValue)")
        
        // Check if camera device exists
        if let device = AVCaptureDevice.default(.builtInWideAngleCamera, for: .video, position: .back) {
            print("Camera device found: \(device.localizedName)")
        } else {
            print("ERROR: No camera device found!")
        }
        
        // Check capture session configuration
        if let session = controller.captureSession as? AVCaptureSession {
            print("Session preset: \(session.sessionPreset.rawValue)")
            print("Number of inputs: \(session.inputs.count)")
            print("Number of outputs: \(session.outputs.count)")
        }
        
        // Check current view state
        if let colorImage = capturedData.database.colorImage {
            print("Color image available: \(colorImage.size)")
        } else {
            print("No color image available")
        }
        
        print("===================================")
    }
    
}


// Add these methods to CameraLiDARManager
extension CameraLiDARManager {
    // Start measuring depth at the center of the frame
    func startCenterDepthDetection() {
        // Stop any existing timer
        centerDepthTimer?.invalidate()
        
        // Create a new timer that updates depth at regular intervals
        centerDepthTimer = Timer.scheduledTimer(withTimeInterval: 0.5, repeats: true) { [weak self] _ in
            self?.updateCenterDepthValue()
        }
        
        // Run immediately once
        updateCenterDepthValue()
    }
    
    // Stop depth detection
    func stopCenterDepthDetection() {
        centerDepthTimer?.invalidate()
        centerDepthTimer = nil
        
        // Clear the displayed value
        DispatchQueue.main.async {
            self.centerDepthValue = nil
        }
    }
    
    // Calculate the depth at the center of the frame
    private func updateCenterDepthValue() {
        // Only proceed if we're in live capture mode with available depth data
        guard isLiveCapture,
              !isRecording,
              let depthTexture = self.capturedData.database.depth else {
            // Clear the depth value if conditions aren't met
            DispatchQueue.main.async {
                self.centerDepthValue = nil
            }
            return
        }
        
        // Calculate center point of the depth texture
        let centerX = depthTexture.width / 2
        let centerY = depthTexture.height / 2
        
        // Create a small region around the center point
        let region = MTLRegionMake2D(centerX, centerY, 1, 1)
        
        // Get the depth value at that point
        var depthValue: Float16 = 0.0
        depthTexture.getBytes(&depthValue, bytesPerRow: MemoryLayout<Float16>.size, from: region, mipmapLevel: 0)
        
        // Convert to Float and update the published property
        DispatchQueue.main.async {
            let floatValue = Float(depthValue)
            
            // Filter out invalid or unreasonable depth values
            if floatValue > 0.05 && floatValue < 10.0 { // Only show depths between 5cm and 10m
                self.centerDepthValue = floatValue
            } else {
                self.centerDepthValue = nil
            }
        }
    }
}

// MARK: ALL ABOUT File Handling
extension CameraLiDARManager {
    func loadVideoFromPhotoLibrary(asset: PHAsset, completion: @escaping (Bool, Int, Error?) -> Void) {
        // Reset state
        pauseStream()
        resetPlaybackState()
        isLiveCapture = false
        isLoadedDataLiDAR = false
        
        let options = PHVideoRequestOptions()
        options.version = .original
        options.deliveryMode = .highQualityFormat
        
        PHImageManager.default().requestAVAsset(forVideo: asset, options: options) { [weak self] (avAsset, _, _) in
            guard let self = self, let avAsset = avAsset else {
                DispatchQueue.main.async {
                    completion(false, 0, NSError(domain: "CameraLiDARManager", code: -1, userInfo: [NSLocalizedDescriptionKey: "Failed to load video asset"]))
                }
                return
            }
            
            // Now process the video asset to extract frames
            Task {
                do {
                    let extractedFrames = try await self.extractFramesFromAVAsset(avAsset)
                    
                    await MainActor.run {
                        self.videoFrames = extractedFrames
                        self.totalFrames = extractedFrames.count
                        self.isDataLoaded = self.totalFrames > 0
                        self.dataAvailable = self.isDataLoaded
                        
                        if self.isDataLoaded {
                            self.currentFrameIndex = 0
                            self.setFrame(to: 0)
                            print("✅ Photo library video loaded with \(self.totalFrames) frames")
                            completion(true, self.totalFrames, nil)
                        } else {
                            print("⚠️ No frames extracted from photo library video")
                            completion(false, 0, NSError(domain: "CameraLiDARManager", code: -2, userInfo: [NSLocalizedDescriptionKey: "No frames extracted"]))
                        }
                    }
                } catch {
                    await MainActor.run {
                        print("❌ Failed to extract frames from photo library video: \(error)")
                        completion(false, 0, error)
                    }
                }
            }
        }
    }

    // Helper method for extracting frames from an AVAsset
    private func extractFramesFromAVAsset(_ asset: AVAsset) async throws -> [UIImage] {
        // Similar to extractFramesFromVideo but works with an AVAsset directly
        var frames: [UIImage] = []
        let generator = AVAssetImageGenerator(asset: asset)
        generator.appliesPreferredTrackTransform = true
        generator.requestedTimeToleranceBefore = CMTime(value: 1, timescale: 30)
        generator.requestedTimeToleranceAfter = CMTime(value: 1, timescale: 30)
        
        let duration = try await asset.load(.duration)
        let tracks = try await asset.loadTracks(withMediaType: .video)
        
        guard let videoTrack = tracks.first else {
            throw NSError(domain: "CameraLiDARManager", code: -2, userInfo: [NSLocalizedDescriptionKey: "No video track found"])
        }
        
        let frameRate = try await videoTrack.load(.nominalFrameRate)
        let durationSeconds = CMTimeGetSeconds(duration)
        let effectiveFrameRate = frameRate > 0 ? frameRate : 30.0
        let timescale = Int32(effectiveFrameRate)
        
        // Extract a reasonable number of frames
        let totalFramesEstimate = min(Int(durationSeconds * Double(effectiveFrameRate)), 300)
        
        print("   Extracting frames from photo library - Duration: \(durationSeconds)s, Rate: \(effectiveFrameRate)fps, Target Frames: \(totalFramesEstimate)")
        
        for i in 0..<totalFramesEstimate {
            let time = CMTimeMake(value: Int64(i * Int(timescale) / totalFramesEstimate), timescale: timescale)
            
            do {
                let cgImage = try generator.copyCGImage(at: time, actualTime: nil)
                frames.append(UIImage(cgImage: cgImage))
                
                if i % 20 == 0 || i == totalFramesEstimate - 1 {
                    print("   Progress: \(i+1)/\(totalFramesEstimate) frames extracted")
                }
            } catch {
                print("   ⚠️ Skipping frame \(i): \(error.localizedDescription)")
            }
        }
        
        print("   Extracted \(frames.count) frames from photo library video")
        return frames
    }
    
    // Modified version of setFrame for video files without depth
    func setVideoFrame(to index: Int) {
        guard index >= 0 && index < videoFrames.count else {
            print("Invalid frame index: \(index), total frames: \(videoFrames.count)")
            return
        }
        
        // Set current index
        currentFrameIndex = index
        sliderPosition = Double(index)
        
        // Immediately update the captured data with the current frame
        capturedData.database.colorImage = videoFrames[index]
        
        // Don't clear processedImage here - let the caller decide
        
        // Notify observers
        FrameUpdatePublisher.shared.notifyFrameChanged(frameIndex: currentFrameIndex)
    }

    func loadVideoFolder(from url: URL) {
        log("Started load LiDAR video folder for URL: \(url.path)", level: .debug)

        // Perform all heavy operations on background thread
        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            guard let self = self else { return }
            
            // Reset state safely on main thread
            DispatchQueue.main.sync {
                self.pauseStream()
                self.resetPlaybackState()
                self.isLiveCapture = false
                self.loadedDataURL = url
                self.isLoadedDataLiDAR = true
                
                // Important: Set these flags immediately to prevent race conditions
                self.isDataLoaded = true
                self.dataAvailable = true
            }

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
                
                // Check for image files with multiple possible names
                var imageURLs: [URL] = []
                
                for frameDir in frameDirectories {
                    // Check multiple possible names with and without extensions
                    let possibleImageNames = [
                        "colorImage", // Your actual file name with no extension
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
                
                // Update state on main thread
                DispatchQueue.main.async { [self] in
                    self.lidarFrameImageURLs = imageURLs
                    self.lidarFrameURLs = frameDirectories  // Store frame directories not image URLs
                    self._lidarFrameURLs = frameDirectories // Published
                    self.totalFrames = imageURLs.count
                    self.DataLiDARAvailable = self.isLoadedDataLiDAR
                    
                    // Make sure we set these flags again
                    self.isDataLoaded = !imageURLs.isEmpty
                    self.dataAvailable = !imageURLs.isEmpty
                    
                    if !imageURLs.isEmpty {
                        print("   ✅ Successfully found \(imageURLs.count) frames")
                        self.currentFrameIndex = 0
                        self.sliderPosition = 0.0
                        
                        // Give the UI a moment to update before loading the first frame
                        DispatchQueue.main.asyncAfter(deadline: .now() + 0.2) {
                            self.setFrame(to: 0)
                        }
                    } else {
                        print("   ⚠️ No valid frames found")
                        self.currentFrameImage = nil
                    }
                }
            } catch {
                print("   ❌ Error scanning directory: \(error)")
                DispatchQueue.main.async {
                    self.isDataLoaded = false
                    self.dataAvailable = false
                    self.currentFrameImage = nil
                }
            }
        }
    }

    // MARK: - Required Helper Functions (Ensure these exist)
    /// Extracts the numeric part of a frame folder/file name (e.g., "frame_123" -> 123).
    private func extractFrameNumber(from string: String) -> Int {
        return Int(string.components(separatedBy: CharacterSet.decimalDigits.inverted).joined()) ?? 0
    }

    func loadVideoFile(_ url: URL, completion: @escaping (Bool, Int, Error?) -> Void) {
        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            guard let self = self else {
                completion(false, 0, NSError(domain: "CameraLiDARManager", code: -1, userInfo: [NSLocalizedDescriptionKey: "Self deallocated"]))
                return
            }
            
            // Set state flags immediately
            DispatchQueue.main.async {
                self.pauseStream()
                self.resetPlaybackState()
                self.isLiveCapture = false
                print("📢 Live capture mode disabled for video loading")
            }
            
            // Check if file exists
            guard FileManager.default.fileExists(atPath: url.path) else {
                print("❌ Video file not found at path: \(url.path)")
                completion(false, 0, NSError(domain: "CameraLiDARManager", code: -1, userInfo: [NSLocalizedDescriptionKey: "Video file not found"]))
                return
            }
            
            // Check for metadata in same folder
            let folderURL = url.deletingLastPathComponent()
            let metadataURL = folderURL.appendingPathComponent("recording_metadata.json")
            
            // Try to load metadata if it exists
            if FileManager.default.fileExists(atPath: metadataURL.path) {
                do {
                    let data = try Data(contentsOf: metadataURL)
                    let metadata = try JSONDecoder().decode(RecordingMetadata.self, from: data)
                    
                    // Store metadata on main thread
                    DispatchQueue.main.async {
                        self.loadedRecordingMetadata = metadata
                        print("✅ Loaded video metadata with orientation: \(metadata.deviceOrientation?.name ?? "unknown")")
                    }
                } catch {
                    print("⚠️ Found metadata but failed to parse: \(error.localizedDescription)")
                }
            } else {
                print("⚠️ No metadata found for video, will use dimensions for orientation")
            }
            
            print("   Extracting frames from: \(url.lastPathComponent)")
            
            // Extract frames
            Task {
                do {
                    let extractedFrames = try await self.extractFramesFromVideo(url: url)
                    
                    DispatchQueue.main.async {
                        self.videoFrames = extractedFrames
                        self.totalFrames = extractedFrames.count
                        self.isDataLoaded = !extractedFrames.isEmpty
                        self.dataAvailable = !extractedFrames.isEmpty
                        self.loadedDataURL = url
                        
                        if !extractedFrames.isEmpty {
                            self.currentFrameIndex = 0
                            
                            // Set the first frame after a short delay
                            DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
                                self.setFrame(to: 0)
                            }
                            
                            print("✅ Successfully loaded video with \(extractedFrames.count) frames")
                            completion(true, extractedFrames.count, nil)
                        } else {
                            print("❌ Failed to extract any frames from video")
                            self.currentFrameImage = nil
                            completion(false, 0, NSError(domain: "CameraLiDARManager", code: -2, userInfo: [NSLocalizedDescriptionKey: "Failed to extract frames"]))
                        }
                    }
                } catch {
                    print("❌ Error extracting frames: \(error)")
                    DispatchQueue.main.async {
                        completion(false, 0, error)
                    }
                }
            }
        }
    }
    

        // Add your frame extraction helper (ensure it exists and returns [UIImage])
    private func extractFramesFromVideo(url: URL) async throws -> [UIImage] {
        var frames: [UIImage] = []
        
        // Make sure the file exists and is accessible
        guard FileManager.default.fileExists(atPath: url.path) else {
            throw NSError(domain: "CameraLiDARManager", code: -1, userInfo: [NSLocalizedDescriptionKey: "Video file not found"])
        }
        
        // Load the asset
        let asset = AVURLAsset(url: url)
        
        // Debug info
        print("   Video asset created for: \(url.lastPathComponent)")
        
        // Configure the generator with more forgiving settings
        let generator = AVAssetImageGenerator(asset: asset)
        generator.appliesPreferredTrackTransform = true
        
        // Use more tolerant time values to improve chances of frame extraction
        generator.requestedTimeToleranceBefore = CMTime(value: 1, timescale: 30)
        generator.requestedTimeToleranceAfter = CMTime(value: 1, timescale: 30)
        
        // Get video details
        let duration = try await asset.load(.duration)
        let tracks = try await asset.loadTracks(withMediaType: .video)
        
        guard let videoTrack = tracks.first else {
            throw NSError(domain: "CameraLiDARManager", code: -2, userInfo: [NSLocalizedDescriptionKey: "No video track found"])
        }
        
        let frameRate = try await videoTrack.load(.nominalFrameRate)
        let durationSeconds = CMTimeGetSeconds(duration)
        
        // Use a reasonable frame rate if we can't determine it
        let effectiveFrameRate = frameRate > 0 ? frameRate : 30.0
        let timescale = Int32(effectiveFrameRate)
        
        // Calculate frame count, but limit to a reasonable number (e.g., 300)
        let totalFramesEstimate = min(Int(durationSeconds * Double(effectiveFrameRate)), 300)
        
        print("   Extracting frames - Duration: \(durationSeconds)s, Rate: \(effectiveFrameRate)fps, Estimated Frames: \(totalFramesEstimate)")
        
        // Extract frames with more error handling
        for i in 0..<totalFramesEstimate {
            let time = CMTimeMake(value: Int64(i * Int(timescale) / totalFramesEstimate), timescale: timescale)
            
            do {
                // Use a safer approach - extract into a buffer with a timeout
                let cgImage = try generator.copyCGImage(at: time, actualTime: nil)
                let uiImage = UIImage(cgImage: cgImage)
                frames.append(uiImage)
                
                // Log progress occasionally
                if i % 20 == 0 || i == totalFramesEstimate - 1 {
                    print("   Progress: \(i+1)/\(totalFramesEstimate) frames extracted")
                }
            } catch {
                print("   ⚠️ Skipping frame \(i): \(error.localizedDescription)")
            }
        }
        
        print("   Extracted \(frames.count) frames successfully.")
        return frames
    }

    // Improved version of applyCorrectOrientation
    func applyCorrectOrientation(to image: UIImage) -> UIImage {
        // First check if this is a valid image
        guard let cgImage = image.cgImage else { return image }
        
        // Log original image properties
        print("Original image: \(image.size.width)x\(image.size.height), orientation: \(image.imageOrientation.rawValue)")
        
        // Try to use metadata if available
        if let metadata = loadedRecordingMetadata,
           let deviceOrientationInfo = metadata.deviceOrientation {
            
            // Get recorded device orientation
            let recordedOrientation = deviceOrientationInfo.uiDeviceOrientation
            
            // Check if we have camera orientation info
            let capturedIsLandscape = deviceOrientationInfo.cameraOrientation == "landscape" ||
                                     (deviceOrientationInfo.capturedWidth ?? 0) > (deviceOrientationInfo.capturedHeight ?? 0)
            
            // Determine if the current image is landscape
            let isLandscapeImage = image.size.width > image.size.height
            
            // Debug log
            print("Orientation analysis:")
            print("- Recorded orientation: \(deviceOrientationInfo.name) (rawValue: \(deviceOrientationInfo.rawValue))")
            print("- Camera captured in: \(capturedIsLandscape ? "landscape" : "portrait")")
            print("- Current image is: \(isLandscapeImage ? "landscape" : "portrait") (\(image.size.width)x\(image.size.height))")
            
            // DETERMINE CORRECT TRANSFORMATION
            var targetOrientation: UIImage.Orientation
            
            // Special case: Handle the mismatch between device orientation and camera storage orientation
            if recordedOrientation == .portrait || recordedOrientation == .portraitUpsideDown {
                // Device was held in portrait mode during recording
                
                if isLandscapeImage {
                    // Image is stored in landscape but device was in portrait - rotate 90°
                    targetOrientation = recordedOrientation == .portrait ? .right : .left
                    print("- Case 1: Portrait device, landscape image -> rotate to \(targetOrientation.rawValue)")
                } else {
                    // Image is already in portrait orientation
                    targetOrientation = recordedOrientation == .portrait ? .up : .down
                    print("- Case 2: Portrait device, portrait image -> no rotation needed")
                }
            } else if recordedOrientation == .landscapeLeft || recordedOrientation == .landscapeRight {
                // Device was held in landscape mode during recording
                
                if !isLandscapeImage {
                    // Image is stored in portrait but device was in landscape - needs rotation
                    targetOrientation = recordedOrientation == .landscapeLeft ? .left : .right
                    print("- Case 3: Landscape device, portrait image -> rotate to \(targetOrientation.rawValue)")
                } else {
                    // Both are landscape, but check if we need 180° rotation
                    targetOrientation = recordedOrientation == .landscapeLeft ? .down : .up
                    print("- Case 4: Landscape device, landscape image -> rotate to \(targetOrientation.rawValue)")
                }
            } else {
                // Unknown or face up/down orientation, use image dimensions as hint
                targetOrientation = isLandscapeImage ? .up : .right
                print("- Case 5: Unknown device orientation -> using default for \(isLandscapeImage ? "landscape" : "portrait")")
            }
            
            // If current orientation already matches target, return original
            if image.imageOrientation == targetOrientation {
                print("✓ No orientation change needed")
                return image
            }
            
            // Apply orientation
            print("✓ Correcting orientation from \(image.imageOrientation.rawValue) to \(targetOrientation.rawValue)")
            return UIImage(cgImage: cgImage, scale: image.scale, orientation: targetOrientation)
        }
        
        // FALLBACK LOGIC: No metadata available
        print("No metadata available, using fallback orientation logic")
        
        // Use image dimensions as hint
        let isLandscapeImage = image.size.width > image.size.height
        
        // Default orientations
        let defaultLandscapeOrientation: UIImage.Orientation = .up
        let defaultPortraitOrientation: UIImage.Orientation = .right
        
        // Apply default orientation based on image dimensions
        if isLandscapeImage && image.imageOrientation != defaultLandscapeOrientation {
            print("Applying default landscape orientation")
            return UIImage(cgImage: cgImage, scale: image.scale, orientation: defaultLandscapeOrientation)
        } else if !isLandscapeImage && image.imageOrientation != defaultPortraitOrientation {
            print("Applying default portrait orientation")
            return UIImage(cgImage: cgImage, scale: image.scale, orientation: defaultPortraitOrientation)
        }
        
        // No change needed
        return image
    }
}

// MARK:: All about playback controls
extension CameraLiDARManager {
    /// Sets the current frame for playback, loads its image, applies orientation, and updates the UI.
    func setFrame(to index: Int) {
        // Main thread check
        if !Thread.isMainThread {
            DispatchQueue.main.async {
                self.setFrame(to: index)
            }
            return
        }

        // Validate conditions
        if isLiveCapture {
            print("⚠️ setFrame: isLiveCapture was true, disabling it")
            controller.stopStream()
            isLiveCapture = false
        }
        
        if !isDataLoaded || !dataAvailable {
            print("⚠️ setFrame: No data loaded")
            return
        }
        
        if index < 0 || index >= totalFrames {
            print("⚠️ setFrame: Invalid index \(index) (total frames: \(totalFrames))")
            return
        }

        // Update state
        currentFrameIndex = index
        sliderPosition = Double(index)

        print("Setting frame to index: \(index)")

        // Load frame on background thread for better performance
        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            guard let self = self else { return }
            
            if self.isLoadedDataLiDAR {
                // Handle LiDAR data frames
                if index >= self.lidarFrameURLs.count {
                    print("❌ LiDAR frame index out of bounds")
                    DispatchQueue.main.async { self.currentFrameImage = nil }
                    return
                }
                
                // Get the frame directory
                let frameDir = self.lidarFrameURLs[index]
                
                // Use our enhanced frame loader
                if let orientedImage = self.loadLiDARFrameWithOrientation(from: frameDir) {
                    DispatchQueue.main.async {
                        self.currentFrameImage = orientedImage
                        self.onFrameChange?(index)
                        // Broadcast frame change notification
                        FrameUpdatePublisher.shared.notifyFrameChanged(frameIndex: index)
                    }
                } else {
                    print("❌ Failed to load oriented image")
                    DispatchQueue.main.async { self.currentFrameImage = nil }
                }
            } else {
                // Video frames from memory
                guard index < self.videoFrames.count else {
                    print("❌ Video frame index out of bounds")
                    DispatchQueue.main.async { self.currentFrameImage = nil }
                    return
                }
                
                // Apply orientation correction
                let orientedImage = self.applyCorrectOrientation(to: self.videoFrames[index])
                
                DispatchQueue.main.async {
                    self.currentFrameImage = orientedImage
                    self.onFrameChange?(index)
                    // Broadcast frame change notification
                    FrameUpdatePublisher.shared.notifyFrameChanged(frameIndex: index)
                }
            }
        }
    }

    /// Resets all state related to playback and loaded analysis data.
    private func resetPlaybackState() {
        stopPlayback() // Stop timer if running
        currentFrameIndex = 0
        totalFrames = 0
        sliderPosition = 0.0
        currentFrameImage = nil // Clear displayed image
        loadedDataURL = nil
        loadedRecordingMetadata = nil
        lidarFrameImageURLs.removeAll()
        videoFrames.removeAll() // Clear video frames too
        isLoadedDataLiDAR = false
        isDataLoaded = false
        dataAvailable = isLiveCapture // Reset based on expected mode

        print("🔄 Playback state reset.")
    }
 
    // Add this to your CameraLiDARManager class
    func ensurePlaybackMode() {
        if isLiveCapture {
            print("⚠️ Forcing playback mode")
            controller.stopStream()
            isLiveCapture = false
        }
    }

    // Update your startPlayback method
    func startPlayback() {
        // Make sure we're not in live capture mode
        ensurePlaybackMode()
        
        // Stop any existing playback
        stopPlayback()
        
        // Check if we have frames to play
        if totalFrames <= 0 {
            print("❌ Cannot start playback: no frames available")
            return
        }
        
        print("▶️ Starting playback from frame \(currentFrameIndex)")
        isPlaying = true
        
        // Create a timer for playback
        playbackTimer = Timer.scheduledTimer(withTimeInterval: 1.0/30.0, repeats: true) { [weak self] _ in
            guard let self = self, self.isPlaying else { return }
            
            // Make sure we're in playback mode before trying to set frames
            self.ensurePlaybackMode()
            
            // Move to next frame
            let nextIndex = self.currentFrameIndex + 1
            if nextIndex >= self.totalFrames {
                // We've reached the end, stop playback
                self.stopPlayback()
                return
            }
            
            // Update frame
            self.currentFrameIndex = nextIndex
            self.setFrame(to: nextIndex)
            
            // Log occasional progress
            if nextIndex % 10 == 0 {
                print("▶️ Playing frame \(nextIndex)/\(self.totalFrames)")
            }
        }
        
        // Make sure timer fires during scrolling or other interactions
        RunLoop.main.add(playbackTimer!, forMode: .common)
    }
    
    // Ensure this helper exists
    private func updateSliderPosition() {
        DispatchQueue.main.async {
            self.sliderPosition = Double(self.currentFrameIndex)
        }
    }
    
    func nextFrame() {
            if currentFrameIndex < totalFrames - 1 {
                // Check if we're using video source or LiDAR data
                if !videoFrames.isEmpty {
                    setVideoFrame(to: currentFrameIndex + 1)
                } else {
                    loadFrame(at: currentFrameIndex + 1)
                }
                updateSliderPosition()
            } else if isPlaying {
                // Stop playback when we reach the end
                stopPlayback()
            }
        }
        
    func stopPlayback() {
        // Must run on main thread
        if !Thread.isMainThread {
            DispatchQueue.main.async {
                self.stopPlayback()
            }
            return
        }
        
        // Invalidate timer
        if let timer = playbackTimer {
            timer.invalidate()
            self.playbackTimer = nil
            print("⏸️ Playback timer invalidated")
        }
        
        // Update state
        if isPlaying {
            isPlaying = false
            print("⏸️ Playback stopped at frame \(currentFrameIndex)")
        }
    }
        
    
    func previousFrame() {
        if currentFrameIndex > 0 {
            loadFrame(at: currentFrameIndex - 1)
            updateSliderPosition()
        }
    }
    
    func loadLiDARFrameWithOrientation(from frameDir: URL) -> UIImage? {
        // Look for image file with various possible names
        let possibleImageNames = ["colorImage.jpg", "colorImage", "color_image.jpg", "color.jpg"]
        var imageURL: URL? = nil
        
        for name in possibleImageNames {
            let testURL = frameDir.appendingPathComponent(name)
            if FileManager.default.fileExists(atPath: testURL.path) {
                imageURL = testURL
                break
            }
        }
        
        guard let imageURL = imageURL else {
            print("❌ No image file found in frame directory: \(frameDir.path)")
            return nil
        }
        
        do {
            // Read the file data
            let imageData = try Data(contentsOf: imageURL)
            
            if let image = UIImage(data: imageData) {
                // Apply orientation correction
                return applyCorrectOrientation(to: image)
            } else {
                print("❌ Failed to create UIImage from data")
                return nil
            }
        } catch {
            print("❌ Error loading image: \(error)")
            return nil
        }
    }
}


//MARK:: All about Recording
extension CameraLiDARManager {
    func startVideoRecording(personName: String, action: String, distance: String) {
        // Quick validation on main thread
        guard !isRecording else {
            print("⚠️ Already recording, ignoring request")
            return
        }
        
        // Get the current camera connection orientation
        let cameraOrientation: UIDeviceOrientation
        
        // Try to get orientation from the camera connection
        if let connection = controller.captureSession.connections.first,
           connection.isVideoOrientationSupported {
            // Map AVCaptureVideoOrientation to UIDeviceOrientation
            switch connection.videoOrientation {
            case .landscapeLeft:
                cameraOrientation = .landscapeRight  // They're inverted
            case .landscapeRight:
                cameraOrientation = .landscapeLeft   // They're inverted
            case .portraitUpsideDown:
                cameraOrientation = .portraitUpsideDown
            case .portrait:
                cameraOrientation = .portrait
            @unknown default:
                cameraOrientation = .portrait
            }
        } else {
            // Fall back to device orientation
            let deviceOrientation = UIDevice.current.orientation
            if deviceOrientation == .faceUp || deviceOrientation == .faceDown || deviceOrientation == .unknown {
                cameraOrientation = .portrait  // Default to portrait for unusable orientations
            } else {
                cameraOrientation = deviceOrientation
            }
        }
        
        print("📷 Starting LiDAR recording with orientation: \(getOrientationName(cameraOrientation))")
        
        // Set recording flags
        isRecording = true
        useLiDAR = true
        
        // Move all file operations to background
        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            guard let self = self else { return }
            
            // Create folder structure
            let dateFormatter = DateFormatter()
            dateFormatter.dateFormat = "yyyy-MM-dd"
            let dateString = dateFormatter.string(from: Date())
            
            let timeFormatter = DateFormatter()
            timeFormatter.dateFormat = "HH-mm-ss"
            let timeString = timeFormatter.string(from: Date())
            
            let personNameSafe = personName.isEmpty ? "Test" : personName
            let actionSafe = action.isEmpty ? "Test" : action
            let distanceSafe = distance.isEmpty ? "Unknown" : distance
            
            let documentsPath = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
            let dateFolderPath = documentsPath.appendingPathComponent(dateString)
            let personFolderPath = dateFolderPath.appendingPathComponent(personNameSafe)
            let recordingFolder = personFolderPath.appendingPathComponent("LiDAR_Recording_\(actionSafe)_\(timeString)")
            
            do {
                // Create directories
                try FileManager.default.createDirectory(at: recordingFolder, withIntermediateDirectories: true, attributes: nil)
                
                // Save orientation information immediately
                let orientationPath = recordingFolder.appendingPathComponent("orientation_info.txt")
                let orientationInfo = """
                Orientation: \(self.getOrientationName(cameraOrientation))
                Orientation RawValue: \(cameraOrientation.rawValue)
                UIInterfaceOrientation: \(UIApplication.shared.statusBarOrientation.rawValue)
                Interface Idiom: \(UIDevice.current.userInterfaceIdiom.rawValue)
                """
                try orientationInfo.write(to: orientationPath, atomically: true, encoding: .utf8)
                
                // Update properties on main thread
                DispatchQueue.main.async {
                    self.recordingFolder = recordingFolder
                    self.recordingStartTime = Date()
                    self.frameCount = 0
                    self.recordingOrientation = cameraOrientation
                    print("✅ LiDAR recording started to folder: \(recordingFolder.lastPathComponent)")
                }
            } catch {
                print("❌ Error creating recording folder: \(error.localizedDescription)")
                DispatchQueue.main.async {
                    self.isRecording = false
                    self.useLiDAR = false
                }
            }
        }
    }

    // Start standard recording
    func startRecording(personName: String, action: String) {
        // Quick validation on main thread
        guard !isRecording else {
            print("⚠️ Already recording, ignoring request")
            return
        }
        
        // Get the current camera connection orientation
        let cameraOrientation: UIDeviceOrientation
        
        // Try to get orientation from the camera connection first
        if let connection = controller.captureSession.connections.first,
           connection.isVideoOrientationSupported {
            // Map AVCaptureVideoOrientation to UIDeviceOrientation
            switch connection.videoOrientation {
            case .landscapeLeft:
                cameraOrientation = .landscapeRight  // They're inverted
            case .landscapeRight:
                cameraOrientation = .landscapeLeft   // They're inverted
            case .portraitUpsideDown:
                cameraOrientation = .portraitUpsideDown
            case .portrait:
                cameraOrientation = .portrait
            @unknown default:
                cameraOrientation = .portrait
            }
        } else {
            // Fall back to device orientation
            let deviceOrientation = UIDevice.current.orientation
            if deviceOrientation == .faceUp || deviceOrientation == .faceDown || deviceOrientation == .unknown {
                cameraOrientation = .portrait  // Default to portrait for unusable orientations
            } else {
                cameraOrientation = deviceOrientation
            }
        }
        
        print("📱 Starting standard recording with orientation: \(getOrientationName(cameraOrientation))")
        
        // Set recording flag
        isRecording = true
        
        // Move all file operations to background
        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            guard let self = self else { return }
            
            // Create folder structure
            let dateFormatter = DateFormatter()
            dateFormatter.dateFormat = "yyyy-MM-dd"
            let dateString = dateFormatter.string(from: Date())
            
            let timeFormatter = DateFormatter()
            timeFormatter.dateFormat = "HH-mm-ss"
            let timeString = timeFormatter.string(from: Date())
            
            let personNameSafe = personName.isEmpty ? "Test" : personName
            let actionSafe = action.isEmpty ? "Test" : action
            
            let documentsPath = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
            let dateFolderPath = documentsPath.appendingPathComponent(dateString)
            let personFolderPath = dateFolderPath.appendingPathComponent(personNameSafe)
            let recordingFolder = personFolderPath.appendingPathComponent("Standard_Recording_\(actionSafe)_\(timeString)")
            
            do {
                // Create directories
                try FileManager.default.createDirectory(at: recordingFolder, withIntermediateDirectories: true, attributes: nil)
                
                // Save orientation information immediately (for debugging)
                let orientationPath = recordingFolder.appendingPathComponent("orientation_info.txt")
                let orientationInfo = """
                Orientation: \(self.getOrientationName(cameraOrientation))
                Orientation RawValue: \(cameraOrientation.rawValue)
                UIInterfaceOrientation: \(UIApplication.shared.statusBarOrientation.rawValue)
                """
                try orientationInfo.write(to: orientationPath, atomically: true, encoding: .utf8)
                
                // Update properties on main thread
                DispatchQueue.main.async {
                    self.recordingFolder = recordingFolder
                    self.recordingStartTime = Date()
                    self.frameCount = 0
                    self.useLiDAR = false
                    self.recordingOrientation = cameraOrientation
                    
                    // Setup video writer on background
                    self.setupVideoWriterInBackground(at: recordingFolder)
                }
            } catch {
                print("❌ Error creating recording folder: \(error.localizedDescription)")
                DispatchQueue.main.async {
                    self.isRecording = false
                }
            }
        }
    }
    
    // Stop recording with proper cleanup
    func stopRecording(completion: @escaping (URL?) -> Void) {
        DispatchQueue.main.async {
            guard self.isRecording, let folder = self.recordingFolder else {
                completion(nil)
                return
            }
            
            // First mark as not recording to prevent new frames
            self.isRecording = false
            
            // Capture all required information before moving to background thread
            let isLiDAR = self.useLiDAR
            let frameCount = self.frameCount
            let recordingOrientation = self.recordingOrientation
            
            // Reset recording state
            self.frameCount = 0
            self.recordingStartTime = nil
            
            // Process completion on background thread
            DispatchQueue.global(qos: .userInitiated).async {
                print("🛑 Stopping recording...")
                
                // Call our improved metadata saver
                self.saveRecordingMetadata(
                    to: folder,
                    orientation: recordingOrientation,
                    frameCount: frameCount,
                    isLiDAR: isLiDAR
                )
                
                // For standard recordings, finalize the video
                if !isLiDAR {
                    if let writer = self.videoWriter, let writerInput = self.videoWriterInput {
                        // Finish writing if input is ready
                        if writerInput.isReadyForMoreMediaData {
                            writerInput.markAsFinished()
                            writer.finishWriting {
                                print("✅ Video writing completed")
                                
                                // Clear video writer references
                                DispatchQueue.main.async {
                                    self.videoWriter = nil
                                    self.videoWriterInput = nil
                                    self.pixelBufferAdaptor = nil
                                    self.recordingFolder = nil
                                    
                                    completion(folder)
                                }
                            }
                        } else {
                            print("⚠️ Video writer input not ready for finalization")
                            DispatchQueue.main.async {
                                self.videoWriter = nil
                                self.videoWriterInput = nil
                                self.pixelBufferAdaptor = nil
                                self.recordingFolder = nil
                                
                                completion(folder)
                            }
                        }
                    } else {
                        // No video writer (unusual for standard recording)
                        print("⚠️ No video writer available for finalization")
                        DispatchQueue.main.async {
                            self.recordingFolder = nil
                            completion(folder)
                        }
                    }
                } else {
                    // LiDAR recording doesn't need video writer finalization
                    DispatchQueue.main.async {
                        self.recordingFolder = nil
                        completion(folder)
                    }
                }
            }
        }
    }
    // Ensure stopVideoRecording delegates to the main stopRecording method for consistency
    func stopVideoRecording(completion: @escaping (URL?) -> Void) {
        // Just use the regular stop recording method for consistency
        stopRecording(completion: completion)
    }
    
    // Thread-safe method to set fixed focus
    func setFixedFocus() {
        guard let device = AVCaptureDevice.default(.builtInWideAngleCamera, for: .video, position: .back) else {
            print("Unable to access camera device")
            return
        }
        
        // Camera configuration should be on a background thread
        sessionQueue.async {
            do {
                try device.lockForConfiguration()
                
                // Disable auto focus
                if device.isFocusModeSupported(.locked) {
                    device.focusMode = .locked
                }
                
                // Set focus to the center of the image
                if device.isFocusPointOfInterestSupported {
                    device.focusPointOfInterest = CGPoint(x: 0.5, y: 0.5)
                }
                
                // Disable auto exposure if needed
                if device.isExposureModeSupported(.locked) {
                    device.exposureMode = .locked
                }
                
                device.unlockForConfiguration()
                print("Camera focus locked")
            } catch {
                print("Error setting fixed focus: \(error.localizedDescription)")
            }
        }
    }
    
    private func getOrientationName(_ orientation: UIDeviceOrientation) -> String {
            switch orientation {
            case .portrait: return "portrait"
            case .portraitUpsideDown: return "portraitUpsideDown"
            case .landscapeLeft: return "landscapeLeft"
            case .landscapeRight: return "landscapeRight"
            case .faceUp: return "faceUp"
            case .faceDown: return "faceDown"
            default: return "unknown"
            }
        }
    
    // MARK: - Improved stopRecording method
    private func setupVideoWriterInBackground(at folder: URL) {
        // Run entirely on background thread
        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            guard let self = self else { return }
            
            print("🎬 Setting up video writer in background...")
            
            // Create a file URL for the video
            let fileURL = folder.appendingPathComponent("recording.mp4")
            
            // Clean up any existing file
            if FileManager.default.fileExists(atPath: fileURL.path) {
                try? FileManager.default.removeItem(at: fileURL)
            }
            
            do {
                // Get dimensions and orientation before creating writer
                var width: Int = 0
                var height: Int = 0
                var orientation: UIDeviceOrientation = .portrait
                
                // Use a semaphore to wait for the main thread to give us values
                let semaphore = DispatchSemaphore(value: 0)
                
                DispatchQueue.main.async {
                    width = Int(self.capturedData.database.cameraReferenceDimensions.width)
                    height = Int(self.capturedData.database.cameraReferenceDimensions.height)
                    orientation = self.recordingOrientation
                    semaphore.signal()
                }
            } catch {
                print("❌ Failed to setup video writer: \(error)")
                DispatchQueue.main.async {
                    self.isRecording = false // Reset recording flag
                }
            }
        }
    }
    
    func saveRecordingMetadata(to folder: URL, orientation: UIDeviceOrientation, frameCount: Int, isLiDAR: Bool) {
        do {
            // Calculate duration
            var duration: TimeInterval = 0
            if let startTime = recordingStartTime {
                duration = Date().timeIntervalSince(startTime)
            }
            
            // Get image dimensions
            let width = capturedData.database.colorImage?.size.width ?? capturedData.database.cameraReferenceDimensions.width
            let height = capturedData.database.colorImage?.size.height ?? capturedData.database.cameraReferenceDimensions.height
            
            // Record if the width/height ratio indicates landscape or portrait
            let isImageLandscape = width > height
            
            // Create enhanced orientation information with camera info
            let deviceOrientation = RecordingMetadata.DeviceOrientation(
                rawValue: orientation.rawValue,
                name: getOrientationName(orientation),
                cameraOrientation: isImageLandscape ? "landscape" : "portrait",
                capturedWidth: Int(width),
                capturedHeight: Int(height)
            )
            
            // Create the metadata with detailed orientation
            let metadata = RecordingMetadata(
                personName: "Test", // Use actual values from recording
                action: "Test",
                frameCount: frameCount,
                useLiDAR: isLiDAR,
                duration: duration,
                resolution: RecordingMetadata.Resolution(
                    width: capturedData.database.cameraReferenceDimensions.width,
                    height: capturedData.database.cameraReferenceDimensions.height
                ),
                deviceOrientation: deviceOrientation,
                timestamp: Date().timeIntervalSince1970,
                distance: "Test",
                cameraIntrinsics: [
                    [Float(capturedData.database.cameraIntrinsics.columns.0.x), Float(capturedData.database.cameraIntrinsics.columns.0.y), Float(capturedData.database.cameraIntrinsics.columns.0.z)],
                    [Float(capturedData.database.cameraIntrinsics.columns.1.x), Float(capturedData.database.cameraIntrinsics.columns.1.y), Float(capturedData.database.cameraIntrinsics.columns.1.z)],
                    [Float(capturedData.database.cameraIntrinsics.columns.2.x), Float(capturedData.database.cameraIntrinsics.columns.2.y), Float(capturedData.database.cameraIntrinsics.columns.2.z)]
                ]
            )
            
            // Encode and save
            let encoder = JSONEncoder()
            encoder.outputFormatting = .prettyPrinted
            let jsonData = try encoder.encode(metadata)
            let metadataURL = folder.appendingPathComponent("recording_metadata.json")
            try jsonData.write(to: metadataURL)
            
            print("✅ Saved enhanced metadata with orientation: \(deviceOrientation.name), camera: \(deviceOrientation.cameraOrientation ?? "unknown")")
            
            // Save additional debug orientation file that's easier to read
            let orientationDebugURL = folder.appendingPathComponent("orientation_debug.txt")
            let debugInfo = """
            === ORIENTATION DEBUG INFO ===
            Device Orientation: \(deviceOrientation.name) (rawValue: \(deviceOrientation.rawValue))
            Camera Orientation: \(deviceOrientation.cameraOrientation ?? "unknown")
            Image Dimensions: \(Int(width))x\(Int(height)) (\(isImageLandscape ? "landscape" : "portrait"))
            Interface Orientation: \(UIApplication.shared.statusBarOrientation.rawValue)
            Expected Display: \(isImageLandscape == deviceOrientation.isPortraitOrientation ? "Needs rotation" : "No rotation needed")
            ============================
            """
            try debugInfo.write(to: orientationDebugURL, atomically: true, encoding: .utf8)
        } catch {
            print("❌ Failed to save metadata: \(error)")
        }
    }
}

// Add this method to your CameraLiDARManager class
extension CameraLiDARManager {
    // Method to safely access frames by index
    func getFrame(at index: Int) -> UIImage? {
        // Check if index is valid
        guard index >= 0 && index < totalFrames else {
            print("❌ getFrame: Index \(index) out of bounds (0..\(totalFrames-1))")
            return nil
        }
        
        // If the current frame is loaded and matches the requested index
        if index == currentFrameIndex && currentFrameImage != nil {
            return currentFrameImage
        }
        
        // If we have video frames in memory
        if !videoFrames.isEmpty && index < videoFrames.count {
            return applyCorrectOrientation(to: videoFrames[index])
        }
        
        // For LiDAR frames or any other source
        if isLoadedDataLiDAR && index < lidarFrameURLs.count {
            // This loads synchronously - might cause UI lag but ensures we get the frame
            return loadLiDARFrameWithOrientation(from: lidarFrameURLs[index])
        }
        
        // If we couldn't get the frame immediately, try to set it asynchronously
        // and return currentFrameImage as a fallback (which might be nil or the wrong frame)
        DispatchQueue.main.async {
            self.setFrame(to: index)
        }
        
        return currentFrameImage
    }
}

extension CameraLiDARManager {
    // Comprehensive method to clear all frames and reset state
    func clearAllFrames() {
        print("🧹 CameraLiDARManager: Starting comprehensive cleanup...")
        
        // Stop any ongoing playback first
        if isPlaying {
            stopPlayback()
        }
        
        // Clear frame storage
        videoFrames.removeAll()
        frameURLs.removeAll()
        lidarFrameURLs.removeAll()
        lidarFrameImageURLs.removeAll()
        
        // Reset frame counters
        totalFrames = 0
        currentFrameIndex = 0
        sliderPosition = 0
        
        // Clear current display
        currentFrameImage = nil
        
        // Reset capture data
        capturedData = FrameDataVM()
        
        // Clear all caches
        preloadedFrames.removeAll()
        preloadedFrameIndices.removeAll()
        keypointData.removeAll()
        processedImages.removeAll()
        
        // Clear depth-related data
        selectedPoints.removeAll()
        measuredDistance = nil
        depthValue = nil
        firstWorldPoint = nil
        secondWorldPoint = nil
        
        // Reset metadata and URL references
        loadedRecordingMetadata = nil
        loadedDataURL = nil
        
        // Reset state flags
        isDataLoaded = false
        dataAvailable = false
        isLoadedDataLiDAR = false
        waitingForCapture = false
        processingCapturedResult = false
        
        // Clear any frame change handlers
        onFrameChange = nil
        
        print("✅ CameraLiDARManager: Cleanup complete")
    }
}
