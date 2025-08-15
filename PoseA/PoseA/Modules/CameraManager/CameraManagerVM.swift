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
import CoreVideo

// MARK: - Camera Manager
class CameraManagerVM: ObservableObject, CaptureDataReceiver {
    
    // MARK: - Published Properties
    @Published var isFilteringDepth: Bool {
        didSet {
            controller.isFilteringEnabled = isFilteringDepth
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
    @Published var isCameraReady: Bool = false

    @Published var orientation = UIDevice.current.orientation
    @Published var waitingForCapture = false
    @Published var processingCapturedResult = false
    @Published var isRecording = false
    @Published var isVideoWriterReady = false
    @Published var isPreparingRecording = false
    @Published var depthValue: Float?
    @Published var centerDepthValue: Float?
    
    // MARK: - Camera State
    @Published var cameraConfiguration: CameraConfiguration {
        didSet {
            reconfigureCamera()
        }
    }
    
    @Published var isLiDARSupported: Bool = false
    @Published var isLiDAREnabled: Bool = false
    @Published var isPoseProcessingEnabled: Bool = false
    @Published var poseProcessingModelURL: String = "yolo11n-pose"
    
    // MARK: - Internal Properties
    var capturedData: FrameDataVM
    let controller: CameraControllerUI
    var cancellables = Set<AnyCancellable>()
    var session: AVCaptureSession { controller.captureSession }
    
    // Recording properties
    private var videoWriter: AVAssetWriter?
    private var videoWriterInput: AVAssetWriterInput?
    private var pixelBufferAdaptor: AVAssetWriterInputPixelBufferAdaptor?
    private var recordingStartTime: Date?
    private var recordingFolder: URL?
    
    private var athleteName: String = "Unknown"
    private var actionType: String = "General"
    private var frameCount: Int = 0
    private var recordingOrientation: UIInterfaceOrientation = .portrait
    private let frameSemaphore = DispatchSemaphore(value: 0)

    private var frameBuffer = [FrameDataModel]()
    
    // Depth detection
    private var centerDepthTimer: Timer?

    // Image Processing
    private var poseProcessor: YOLOPoseProcessor?
    private var frameStreamCount = 0
    private var lastTimestamp = Date()
    @Published var fpsStream: Double = 0
    @Published var poseKeypoints: [PoseBox] = []
    
    // Queues
    private let sessionQueue = DispatchQueue(label: "com.bestgym.sessionQueue", qos: .userInitiated)
    private let frameBufferQueue = DispatchQueue(label: "com.bestgym.frameBufferQueue")
    private let videoWriterQueue = DispatchQueue(label: "com.bestgym.videoWriterQueue")
    
    // MARK: - Initialization
    init(configuration: CameraConfiguration = CameraConfiguration()) {
        self.cameraConfiguration = configuration
        self.capturedData = FrameDataVM()
        
        // Initialize controller
        self.controller = CameraControllerUI()
        
        // Check LiDAR support
        self.isLiDARSupported = Self.checkLiDARSupport()
        
        // Configure camera based on settings
        self.isFilteringDepth = configuration.enableDepthFiltering
        self.isLiDAREnabled = configuration.enableLiDAR && isLiDARSupported
        
        // Setup orientation monitoring
        setupOrientationMonitoring()
        
        // Set delegate
        controller.delegate = self
        
        // Init Pose
        self.poseProcessor = YOLOPoseProcessor(modelName: self.poseProcessingModelURL)
    }
    
    // MARK: - Camera Setup
    func reconfigureCamera() {
        self.isCameraReady = false
        DispatchQueue.global(qos: .userInitiated).async {
            self.controller.stopStream()
            
            self.setupCamera {
                DispatchQueue.main.async {
                    self.isCameraReady = true
                }
            }
        }
    }

    private func setupCamera(completion: @escaping () -> Void) {
        do {
            try controller.configureSession(resolution: cameraConfiguration.resolution,
                                            frameRate: cameraConfiguration.frameRate,
                                            enableLiDAR: isLiDAREnabled,
                                            enableDepthFiltering: isFilteringDepth,
                                            cameraPosition: cameraConfiguration.cameraPosition) { success in
                if success {
                    if self.isLiveCapture {
                        self.controller.startStream()
                    }
                    completion()
                }
            }
        } catch {
            log("Failed to setup camera", level: .error)
            completion()
        }
    }
    

    
    // MARK: - LiDAR Support Check
    private static func checkLiDARSupport() -> Bool {
        let discoverySession = AVCaptureDevice.DiscoverySession(
            deviceTypes: [.builtInLiDARDepthCamera],
            mediaType: .video,
            position: .back
        )
        return !discoverySession.devices.isEmpty
    }
    
    // MARK: - Orientation Monitoring
    private func setupOrientationMonitoring() {
        NotificationCenter.default.publisher(for: UIDevice.orientationDidChangeNotification)
            .sink { [weak self] _ in
                self?.orientation = UIDevice.current.orientation
            }
            .store(in: &cancellables)
    }
    
    // MARK: - Camera Control
    func startStream() {
        controller.startStream()
        isLiveCapture = true
    }
    
    func resumeStream() {
        sessionQueue.async { [weak self] in
            guard let self = self else { return }
            
            self.controller.startStream()
            
            DispatchQueue.main.async {
                self.isLiveCapture = true
            }
        }
    }
    
    func pauseStream() {
        if controller.captureSession.isRunning {
            controller.stopStream()
            DispatchQueue.main.async { 
                self.isLiveCapture = false 
            }
        }
        log("Stream paused.", level: .info)
    }
    
    // MARK: - Cycling Methods
    func cycleResolution() {
        let oldResolution = cameraConfiguration.resolution
        let newResolution = cameraConfiguration.resolution.next()
        log("Cycling resolution from \(oldResolution.description) (\(oldResolution.width)x\(oldResolution.height)) to \(newResolution.description) (\(newResolution.width)x\(newResolution.height))", level: .info)
        cameraConfiguration = cameraConfiguration.cycleResolution()
        log("Resolution updated to: \(cameraConfiguration.resolution.description) (\(cameraConfiguration.resolution.width)x\(cameraConfiguration.resolution.height))", level: .info)
    }
    
    func cycleFrameRate() {
        let oldFrameRate = cameraConfiguration.frameRate
        let newFrameRate = cameraConfiguration.frameRate.nextForResolution(cameraConfiguration.resolution)
        log("Cycling FPS from \(oldFrameRate.description) to \(newFrameRate.description) for resolution \(cameraConfiguration.resolution.description)", level: .info)
        cameraConfiguration = cameraConfiguration.cycleFrameRate()
        log("Frame rate updated to: \(cameraConfiguration.frameRate.description) FPS", level: .info)
    }
    
    func toggleLiDAR() {
        guard isLiDARSupported else {
            log("LiDAR not supported on this device", level: .info)
            return
        }
        
        cameraConfiguration = CameraConfiguration(
            resolution: cameraConfiguration.resolution,
            frameRate: cameraConfiguration.frameRate,
            enableLiDAR: !cameraConfiguration.enableLiDAR,
            enableDepthFiltering: cameraConfiguration.enableDepthFiltering,
            cameraPosition: cameraConfiguration.cameraPosition
        )
    }
    
    func toggleDepthFiltering() {
        cameraConfiguration = CameraConfiguration(
            resolution: cameraConfiguration.resolution,
            frameRate: cameraConfiguration.frameRate,
            enableLiDAR: cameraConfiguration.enableLiDAR,
            enableDepthFiltering: !cameraConfiguration.enableDepthFiltering,
            cameraPosition: cameraConfiguration.cameraPosition
        )
    }
    
    func toogleRealtimeDetection() {
        isPoseProcessingEnabled.toggle()
        log("Realtime pose processing is \(isPoseProcessingEnabled ? "enabled" : "disabled")", level: .info)
    }
    
    func setRealtimeModelVersion(_ version: String) {
        if isPoseProcessingEnabled {
            isPoseProcessingEnabled = false
            log("Realtime pose processing is disabled to reload the model", level: .info)
            
            self.poseProcessingModelURL = version
            self.poseProcessor = YOLOPoseProcessor(modelName: self.poseProcessingModelURL)
            log("Model changed to \(version)", level: .info)
            
            isPoseProcessingEnabled = true

        } else {
            self.poseProcessingModelURL = version
            self.poseProcessor = YOLOPoseProcessor(modelName: self.poseProcessingModelURL)
            log("Model changed to \(version)", level: .info)
        }
    }
}

// MARK: - CaptureDataReceiver Protocol
extension CameraManagerVM {
    func onNewData(capturedData: FrameDataModel, pixelBuffer: CVPixelBuffer?) {
        // FrameRate Benchmarking
        self.frameStreamCount += 1
        let now = Date()
        let elapsed = now.timeIntervalSince(lastTimestamp)

        if elapsed >= 1.0 {
            let fps = Double(self.frameStreamCount) / elapsed
            self.frameStreamCount = 0
            lastTimestamp = now
            
            DispatchQueue.main.async {
                self.fpsStream = fps
            }
        }
        
        // Ensure we're on the main thread for @Published property updates
        DispatchQueue.main.async {
            // Update basic camera data
            self.capturedData.database.colorY = capturedData.colorY
            self.capturedData.database.colorCbCr = capturedData.colorCbCr
            self.capturedData.database.cameraIntrinsics = capturedData.cameraIntrinsics
            self.capturedData.database.cameraReferenceDimensions = capturedData.cameraReferenceDimensions
            self.capturedData.database.colorImage = capturedData.colorImage
            
            // Only update LiDAR-specific data if LiDAR is enabled
            if self.isLiDAREnabled {
                self.capturedData.database.depth = capturedData.depth
                self.capturedData.database.depthCenter = capturedData.depthCenter
                self.capturedData.database.originalDepth = capturedData.originalDepth
            }
        }
        
        // Write frame to video if recording and video writer is ready
        if isRecording && !isLiDAREnabled && isVideoWriterReady {
            frameBufferQueue.async {
                self.frameBuffer.append(capturedData)
                self.frameSemaphore.signal()
            }
        }

        // Image Processing
        if let _pixelBuffer = pixelBuffer, isPoseProcessingEnabled {
            poseProcessor?.process(pixelBuffer: _pixelBuffer) { [weak self] poses in
                // Optional Filtering
                let filteredPose = self!.poseProcessor?.filterPoses(poses, minConfidence: 0.5, iouThreshold: 0.5)
                    
                DispatchQueue.main.async {
                    self?.poseKeypoints = filteredPose ?? []
                }
            }
        }
    }

    private func startWriterLoop() {
        videoWriterQueue.async { [weak self] in
            guard let self = self else { return }
            while self.isRecording || !self.frameBuffer.isEmpty {
                self.frameSemaphore.wait()
                self.frameBufferQueue.sync {
                    if !self.frameBuffer.isEmpty {
                        let frame = self.frameBuffer.removeFirst()
                        self.writeFrameToVideo(capturedData: frame)
                    }
                }
            }
        }
    }
    
    private func writeFrameToVideo(capturedData: FrameDataModel) {
        guard let videoWriterInput = videoWriterInput,
              let pixelBufferAdaptor = pixelBufferAdaptor,
              videoWriterInput.isReadyForMoreMediaData else {
            return
        }
        
        // Create pixel buffer from the captured image
        guard let image = capturedData.colorImage else { return }
        
        // Convert UIImage to CVPixelBuffer
        guard let pixelBuffer = imageToPixelBuffer(image) else { return }
        
        // Calculate presentation time based on actual frame rate
        let frameRate = cameraConfiguration.frameRate.rawValue
        let frameDuration = CMTime(value: 1, timescale: CMTimeScale(frameRate))
        let presentationTime = CMTimeMultiply(frameDuration, multiplier: Int32(frameCount))
        
        // Append the pixel buffer
        if pixelBufferAdaptor.append(pixelBuffer, withPresentationTime: presentationTime) {
            frameCount += 1
        } else {
            log("Failed to append pixel buffer to video", level: .error)
        }
    }
    
    private func imageToPixelBuffer(_ image: UIImage) -> CVPixelBuffer? {
        let width = Int(image.size.width)
        let height = Int(image.size.height)
        
        var pixelBuffer: CVPixelBuffer?
        let status = CVPixelBufferCreate(kCFAllocatorDefault,
                                       width,
                                       height,
                                       kCVPixelFormatType_32BGRA,
                                       nil,
                                       &pixelBuffer)
        
        guard status == kCVReturnSuccess, let buffer = pixelBuffer else {
            return nil
        }
        
        CVPixelBufferLockBaseAddress(buffer, [])
        defer { CVPixelBufferUnlockBaseAddress(buffer, []) }
        
        guard let context = CGContext(data: CVPixelBufferGetBaseAddress(buffer),
                                    width: width,
                                    height: height,
                                    bitsPerComponent: 8,
                                    bytesPerRow: CVPixelBufferGetBytesPerRow(buffer),
                                    space: CGColorSpaceCreateDeviceRGB(),
                                    bitmapInfo: CGImageAlphaInfo.premultipliedFirst.rawValue | CGBitmapInfo.byteOrder32Little.rawValue) else {
            return nil
        }
        
        // Draw the image
        context.draw(image.cgImage!, in: CGRect(x: 0, y: 0, width: width, height: height))
        
        return buffer
    }
}

// MARK: - Depth Detection
extension CameraManagerVM {
    func startCenterDepthDetection() {
        centerDepthTimer?.invalidate()
        
        centerDepthTimer = Timer.scheduledTimer(withTimeInterval: 0.5, repeats: true) { [weak self] _ in
            self?.updateCenterDepthValue()
        }
        
        updateCenterDepthValue()
    }
    
    func stopCenterDepthDetection() {
        centerDepthTimer?.invalidate()
        centerDepthTimer = nil
        
        DispatchQueue.main.async {
            self.centerDepthValue = nil
        }
    }
    
    private func updateCenterDepthValue() {
        guard isLiveCapture,
              !isRecording,
              isLiDAREnabled,
              let depthTexture = capturedData.database.depth else {
            DispatchQueue.main.async {
                self.centerDepthValue = nil
            }
            return
        }
        
        let centerX = depthTexture.width / 2
        let centerY = depthTexture.height / 2
        let region = MTLRegionMake2D(centerX, centerY, 1, 1)
        
        var depthValue: Float16 = 0.0
        depthTexture.getBytes(&depthValue, bytesPerRow: MemoryLayout<Float16>.size, from: region, mipmapLevel: 0)
        
        DispatchQueue.main.async {
            let floatValue = Float(depthValue)
            
            if floatValue > 0.05 && floatValue < 10.0 {
                self.centerDepthValue = floatValue
            } else {
                self.centerDepthValue = nil
            }
        }
    }
}

// MARK: - Data Management
extension CameraManagerVM {
//    func saveCapturedData(completion: @escaping (Bool) -> Void) {
//        do {
//            let documentDirectory = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first!
//            capturedData.saveData(to: documentDirectory, filter: controller.isFilteringEnabled)
//            completion(true)
//        } catch {
//            log("Error saving capture data: \(error)", level: .error)
//            if let nsError = error as NSError? {
//                log("Error domain: \(nsError.domain)", level: .error)
//                log("Error code: \(nsError.code)", level: .error)
//                log("Error user info: \(nsError.userInfo)", level: .error)
//                log("Error saving capture data: \(error.localizedDescription)", level: .error)
//            }
//            completion(false)
//        }
//    }
    
    func clearAllFrames() {
        log("Starting comprehensive cleanup...", level: .info)
        
        capturedData = FrameDataVM()
        depthValue = nil
        waitingForCapture = false
        processingCapturedResult = false
        
        log("Cleanup complete", level: .info)
    }
}

// MARK: - Camera Focus Control
extension CameraManagerVM {
    func setFixedFocus() {
        guard let device = AVCaptureDevice.default(.builtInWideAngleCamera, for: .video, position: .back) else {
            log("Unable to access camera device", level: .error)
            return
        }
        
        sessionQueue.async {
            do {
                try device.lockForConfiguration()
                
                if device.isFocusModeSupported(.locked) {
                    device.focusMode = .locked
                }
                
                if device.isFocusPointOfInterestSupported {
                    device.focusPointOfInterest = CGPoint(x: 0.5, y: 0.5)
                }
                
                if device.isExposureModeSupported(.locked) {
                    device.exposureMode = .locked
                }
                
                device.unlockForConfiguration()
                log("Camera focus locked", level: .info)
            } catch {
                log("Error setting fixed focus: \(error.localizedDescription)", level: .error)
            }
        }
    }
}

//MARK:: All about Recording
extension CameraManagerVM {
    
    // Start standard recording
    func startRecording(personName: String, action: String) {
        // Quick validation on main thread
        guard !isRecording else {
            log("Already recording, ignoring request", level: .warn)
            return
        }
        
        // Get the current UI connection orientation
        let UIOrientation = UIApplication.shared.connectedScenes
                                              .compactMap { $0 as? UIWindowScene }
                                              .first?
                                              .interfaceOrientation ?? .portrait
        
        log("Starting standard recording with orientation: \(getOrientationName(UIOrientation))", level: .info)
        log("Current camera configuration: \(cameraConfiguration.resolution.description) (\(cameraConfiguration.resolution.width)x\(cameraConfiguration.resolution.height)) at \(cameraConfiguration.frameRate.description) FPS", level: .info)
        log("Target frame rate: \(cameraConfiguration.frameRate.rawValue) FPS", level: .info)
        
        // Set preparing flag
        isPreparingRecording = true
        
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
            
            self.athleteName = personName.isEmpty ? "Unknown" : personName
            self.actionType = action.isEmpty ? "Unknown" : action
            
            let documentsPath = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
            let dateFolderPath = documentsPath.appendingPathComponent(dateString)
            let personFolderPath = dateFolderPath.appendingPathComponent(athleteName)
            let recordingFolder = personFolderPath.appendingPathComponent("Recording_\(actionType)_\(timeString)")
            
            do {
                // Create directories
                try FileManager.default.createDirectory(at: recordingFolder, withIntermediateDirectories: true, attributes: nil)
                
                // Save orientation information immediately (for debugging)
                let orientationPath = recordingFolder.appendingPathComponent("orientation_info.txt")
                let orientationInfo = """
                Orientation: \(self.getOrientationName(UIOrientation))
                Interface Idiom: \(UIDevice.current.userInterfaceIdiom.rawValue)
                """
                try orientationInfo.write(to: orientationPath, atomically: true, encoding: .utf8)
            
                // Update properties on main thread
                DispatchQueue.main.async {
                    self.recordingFolder = recordingFolder
                    self.recordingStartTime = Date()
                    self.frameCount = 0
                    self.recordingOrientation = UIOrientation
                    
                    log("recording started to folder: \(recordingFolder.lastPathComponent)", level: .info)
                    
                    // Setup video writer and only start recording when ready
                    if !self.isLiDAREnabled {
                        self.setupVideoWriterInBackground(at: recordingFolder) { success in
                            DispatchQueue.main.async {
                                self.isPreparingRecording = false
                                if success {
                                    self.isRecording = true
                                    self.startWriterLoop()
                                    log("Recording started successfully", level: .info)
                                } else {
                                    log("Failed to setup video writer, recording not started", level: .error)
                                }
                            }
                        }
                    }
                }
            } catch {
                log("Error creating recording folder: \(error.localizedDescription)", level: .error)
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
            self.isVideoWriterReady = false
            
            // Capture all required information before moving to background thread
            let isLiDAR = self.isLiDAREnabled
            let frameCount = self.frameCount
            let recordingOrientation = self.recordingOrientation
            
            // Process completion on background thread
            DispatchQueue.global(qos: .userInitiated).async {
                log("Stopping recording...", level: .info)
                
                // Call our improved metadata saver
                self.saveRecordingMetadata(
                    to: folder,
                    orientation: recordingOrientation,
                    frameCount: frameCount,
                    isLiDAR: self.isLiDAREnabled
                )
                
                // For standard recordings, finalize the video
                self.videoWriterQueue.async { [weak self] in
                    guard let self = self else { return }
                    while !self.frameBuffer.isEmpty {
                        usleep(1000)
                    }
                    
                    if !isLiDAR {
                        if let writer = self.videoWriter, let writerInput = self.videoWriterInput {
                            // Finish writing if input is ready
                            if writerInput.isReadyForMoreMediaData {
                                writerInput.markAsFinished()
                                writer.finishWriting {
                                    log("Video writing completed", level: .info)
                                    
                                    // Clear video writer references
                                    DispatchQueue.main.async {
                                        self.videoWriter = nil
                                        self.videoWriterInput = nil
                                        self.pixelBufferAdaptor = nil
                                        self.recordingFolder = nil
                                        // Reset recording state
                                        self.frameCount = 0
                                        self.recordingStartTime = nil
                                        completion(folder)
                                    }
                                }
                            } else {
                                log("Video writer input not ready for finalization", level: .warn)
                                DispatchQueue.main.async {
                                    self.videoWriter = nil
                                    self.videoWriterInput = nil
                                    self.pixelBufferAdaptor = nil
                                    self.recordingFolder = nil
                                    // Reset recording state
                                    self.frameCount = 0
                                    self.recordingStartTime = nil
                                    completion(folder)
                                }
                            }
                        } else {
                            // No video writer (unusual for standard recording)
                            log("No video writer available for finalization", level: .error)
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
    }
    
    private func getOrientationName(_ orientation: UIInterfaceOrientation) -> String {
            switch orientation {
            case .portrait: return "portrait"
            case .portraitUpsideDown: return "portraitUpsideDown"
            case .landscapeLeft: return "landscapeLeft"
            case .landscapeRight: return "landscapeRight"
            default: return "portrait"
            }
        }
    
    // MARK: - Improved stopRecording method
    private func setupVideoWriterInBackground(at folder: URL, completion: @escaping (Bool) -> Void) {
        // Run entirely on background thread
        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            guard let self = self else { return }
            
            log("Setting up video writer in background...", level: .info)
            
            // Create a file URL for the video
            let fileURL = folder.appendingPathComponent("recording.mp4")
            
            // Clean up any existing file
            if FileManager.default.fileExists(atPath: fileURL.path) {
                try? FileManager.default.removeItem(at: fileURL)
            }
            
            // Get dimensions and orientation before creating writer
            var width: Int = 0
            var height: Int = 0
            
            // Use a semaphore to wait for the main thread to give us values
            let semaphore = DispatchSemaphore(value: 0)
            
            DispatchQueue.main.async {
                // Use current camera configuration dimensions instead of captured data
                width = self.cameraConfiguration.resolution.width
                height = self.cameraConfiguration.resolution.height
                semaphore.signal()
            }
            
            // Wait for the values
            semaphore.wait()
            
            // Ensure we have valid dimensions
            guard width > 0 && height > 0 else {
                log("Invalid dimensions for video writer: \(width)x\(height)", level: .error)
                completion(false)
                return
            }
            
            log("Setting up video writer with dimensions: \(width)x\(height) (resolution: \(self.cameraConfiguration.resolution.description))", level: .info)
            
            // Create video writer
            do {
                self.videoWriter = try AVAssetWriter(url: fileURL, fileType: .mp4)
                
                // Configure video settings
                let videoSettings: [String: Any] = [
                    AVVideoCodecKey: AVVideoCodecType.h264,
                    AVVideoWidthKey: width,
                    AVVideoHeightKey: height
                ]
                
                // Create video writer input
                self.videoWriterInput = AVAssetWriterInput(mediaType: .video, outputSettings: videoSettings)
                self.videoWriterInput?.expectsMediaDataInRealTime = true
                
                // Create pixel buffer adaptor
                let sourcePixelBufferAttributes: [String: Any] = [
                    kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_32BGRA,
                    kCVPixelBufferWidthKey as String: width,
                    kCVPixelBufferHeightKey as String: height
                ]
                
                self.pixelBufferAdaptor = AVAssetWriterInputPixelBufferAdaptor(
                    assetWriterInput: self.videoWriterInput!,
                    sourcePixelBufferAttributes: sourcePixelBufferAttributes
                )
                
                // Add input to writer
                if let writer = self.videoWriter, let input = self.videoWriterInput {
                    if writer.canAdd(input) {
                        writer.add(input)
                        
                        // Start writing
                        if writer.startWriting() {
                            writer.startSession(atSourceTime: .zero)
                            log("Video writer setup completed successfully", level: .info)
                            DispatchQueue.main.async {
                                self.isVideoWriterReady = true
                            }
                            completion(true)
                        } else {
                            log("Failed to start video writing: \(writer.error?.localizedDescription ?? "Unknown error")", level: .error)
                            completion(false)
                        }
                    } else {
                        log("Cannot add video input to writer", level: .error)
                        completion(false)
                    }
                }
                
            } catch {
                log("Failed to create video writer: \(error.localizedDescription)", level: .error)
                completion(false)
            }
        }
    }
    
    func saveRecordingMetadata(to folder: URL, orientation: UIInterfaceOrientation, frameCount: Int, isLiDAR: Bool) {
        do {
            // Calculate duration
            var duration: TimeInterval = 0
            if let startTime = recordingStartTime {
                duration = Date().timeIntervalSince(startTime)
            }
            
            // Get image dimensions from current camera configuration
            let width = cameraConfiguration.resolution.width
            let height = cameraConfiguration.resolution.height
            
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
                personName: self.athleteName,
                action: self.actionType,
                frameCount: frameCount,
                useLiDAR: isLiDAR,
                duration: duration,
                resolution: RecordingMetadata.Resolution(
                    width: Double(cameraConfiguration.resolution.width),
                    height: Double(cameraConfiguration.resolution.height)
                ),
                deviceOrientation: deviceOrientation,
                timestamp: Date().timeIntervalSince1970,
                distance: "Test",
                cameraIntrinsics: capturedData.database.cameraIntrinsics.toArray()
            )
            
            // Encode and save
            let encoder = JSONEncoder()
            encoder.outputFormatting = .prettyPrinted
            let jsonData = try encoder.encode(metadata)
            let metadataURL = folder.appendingPathComponent("recording_metadata.json")
            try jsonData.write(to: metadataURL)
            
            let actualFPS = duration > 0 ? Double(frameCount) / duration : 0
            print("Saved metadata - Target FPS: \(cameraConfiguration.frameRate.rawValue), Actual FPS: \(String(format: "%.1f", actualFPS)), Frame Count: \(frameCount), Duration: \(String(format: "%.2f", duration))s")

        } catch {
            print("❌ Failed to save metadata: \(error)")
        }
    }
}
