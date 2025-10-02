//
//  CameraLiDARManager.swift
//  DataCaptureTest
//
//  Created by Shiela Cabahug on 2024/7/4.
//

import SwiftUI
import AVFoundation

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
    @Published var isRecording = false
    @Published var isPreparingRecording = false

    
    // MARK: - Camera State
    @Published var cameraConfiguration: CameraConfiguration {
        didSet {
            reconfigureCamera()
        }
    }
    
    @Published var isLiDARSupported: Bool = false
    @Published var isLiDAREnabled: Bool = false
    @Published var isLiDARViewEnabled: Bool = false
    @Published var isPoseProcessingEnabled: Bool = false
    @Published var poseProcessingModelURL: String = "yolo11n-pose"
    
    // MARK: - Internal Properties
    var capturedData: FrameDataVM
    let controller: CameraControllerUI
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
    private var recordingOrientation: DeviceOrientationModel = .portrait
    private let frameSemaphore = DispatchSemaphore(value: 0)

    private var firstPTS: CMTime? = nil
    private var frameBuffer = [(CVPixelBuffer, CMTime)]()

    // Image Processing
    @Published var poseKeypoints: [PoseBox] = []
    @Published var camIntrinsics: matrix_float3x3 = matrix_identity_float3x3
    @Published var depthMap: CVPixelBuffer? = nil
    @Published var depthTexture: MTLTexture? = nil
    
    private var poseProcessor: YOLOPoseProcessor?
    private var isProcessingPose = false // Mutex Lock

    // FPS Tracker
    @Published var fpsStream: Double = 0
    @Published var fpsModel: Double = 0
    private let systemFPS = FPSMeter(label: "System")

    // Queues
    private let sessionQueue = DispatchQueue(label: "com.bestgym.sessionQueue", qos: .userInitiated)
    private let frameBufferQueue = DispatchQueue(label: "com.bestgym.frameBufferQueue")
    private let frameWriterQueue = DispatchQueue(label: "com.bestgym.frameWriterQueue")
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
     
        // Set delegate
        controller.delegate = self
        
        // Init Pose
        self.poseProcessor = YOLOPoseProcessor()
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
    
    // MARK: - Camera Stream Control
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
            log("Stream paused.", level: .info)
        }
    }
    
    // MARK: - Cycling Methods
    func cycleResolution() {
        let oldResolution = cameraConfiguration.resolution
        let newResolution = oldResolution.next()
        
        log("Cycling resolution from \(oldResolution.description) (\(oldResolution.width)x\(oldResolution.height)) " +
            "to \(newResolution.description) (\(newResolution.width)x\(newResolution.height))", level: .info)
        
        cameraConfiguration = cameraConfiguration.cycleResolution()
        
        log("Resolution updated to: \(cameraConfiguration.resolution.description) " +
            "(\(cameraConfiguration.resolution.width)x\(cameraConfiguration.resolution.height))", level: .info)
    }

    func cycleFrameRate() {
        guard !cameraConfiguration.enableLiDAR else {
            log("Frame rate cycling disabled while LiDAR is active", level: .info)
            return
        }
        
        let oldFrameRate = cameraConfiguration.frameRate
        let newFrameRate = oldFrameRate.nextForResolution(cameraConfiguration.resolution)
        
        log("Cycling FPS from \(oldFrameRate.description) to \(newFrameRate.description) " +
            "for resolution \(cameraConfiguration.resolution.description)", level: .info)
        
        cameraConfiguration = cameraConfiguration.cycleFrameRate()
        
        log("Frame rate updated to: \(cameraConfiguration.frameRate.description) FPS", level: .info)
    }

    func toggleLiDAR() {
        guard isLiDARSupported else {
            log("LiDAR not supported on this device", level: .info)
            return
        }
        
        isLiDAREnabled.toggle()
        
        cameraConfiguration = cameraConfiguration.withLiDAR(isLiDAREnabled)
        
        if isLiDAREnabled {
            log("LiDAR enabled → frame rate forced to 30 FPS", level: .info)
        } else {
            log("LiDAR disabled → restored frame rate: \(cameraConfiguration.frameRate.description) FPS", level: .info)
        }
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
        
        // Load Model if On
        if isPoseProcessingEnabled {
            self.setRealtimeModelVersion(self.poseProcessingModelURL)
        }
    }
    
    func setRealtimeModelVersion(_ version: String) {
        if isPoseProcessingEnabled {
            isPoseProcessingEnabled = false
            log("Realtime pose processing is disabled to reload the model", level: .info)
            
            self.poseProcessingModelURL = version
            poseProcessor?.loadModel(named: self.poseProcessingModelURL) { success in
                if success {
                    log("Model changed to \(version)", level: .info)
                    self.isPoseProcessingEnabled = true
                }
            }
        } else {
            self.poseProcessingModelURL = version
        }
    }
}

// MARK: - CaptureDataReceiver Protocol
extension CameraManagerVM {
    // TODO: - onNewDepthData implementation for LiDAR Camera
    func onNewDepthData(capturedData: FrameDataModel, pixelBuffer: CVPixelBuffer?, depthPixelBuffer: CVPixelBuffer?, pts: CMTime) {
        if let currentBuffer = pixelBuffer {
            // Update FPS
            self.systemFPS.tick()
            DispatchQueue.main.async {
                self.fpsStream = self.systemFPS.fps
                self.depthTexture = capturedData.depth
            }
            
            // BETA: - YOLO Pose Detection
            if isPoseProcessingEnabled {
                poseProcessor?.process(pixelBuffer: currentBuffer, pts: pts) { [weak self] poses, fps, pts in
                    DispatchQueue.main.async {
                        if !poses.isEmpty {
                            self?.poseKeypoints = poses
                        } else {
                            self?.poseKeypoints = []
                        }
                        self?.fpsModel = fps
                        self?.camIntrinsics = capturedData.cameraIntrinsics
                        self?.depthMap = depthPixelBuffer
                    }
                }
            }
        }
    }
    
    // onNewBasicData implementation for Basic Camera
    func onNewBasicData(capturedData: FrameDataModel, pixelBuffer: CVPixelBuffer?, pts: CMTime) {
        if let currentBuffer = pixelBuffer {
            // Update FPS
            self.systemFPS.tick()
            DispatchQueue.main.async {
                self.fpsStream = self.systemFPS.fps
            }
            
            // Write frame to video if recording is true
            if isRecording && !isPreparingRecording {
                DispatchQueue.main.async {
                    // Update basic camera data
                    self.capturedData.database.cameraIntrinsics = capturedData.cameraIntrinsics
                    self.capturedData.database.cameraReferenceDimensions = capturedData.cameraReferenceDimensions
                }
                
                frameBufferQueue.async {
                    self.frameBuffer.append((currentBuffer, pts))
                    self.frameSemaphore.signal()
                }
            }
            
            // BETA: - YOLO Pose Detection
            if isPoseProcessingEnabled {
                poseProcessor?.process(pixelBuffer: currentBuffer, pts: pts) { [weak self] poses, fps, pts in
                    if !poses.isEmpty {
                        DispatchQueue.main.async {
                            self?.poseKeypoints = poses
                            self?.fpsModel = fps
                            self?.camIntrinsics = capturedData.cameraIntrinsics
                        }
                    } else {
                        DispatchQueue.main.async {
                            self?.poseKeypoints = []
                            self?.fpsModel = fps
                            self?.camIntrinsics = capturedData.cameraIntrinsics
                        }
                    }
                }
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
        capturedData = FrameDataVM()
        log("Cleanup complete", level: .info)
    }
}

// MARK: - All about Recording
extension CameraManagerVM {
    // Start standard recording
    func startRecording(personName: String, action: String) {
        // Quick validation on main thread
        guard !isRecording else {
            log("Already recording, ignoring request", level: .warn)
            return
        }
        
        log("Starting standard recording with orientation: \(getOrientationName(OrientationCache.shared.orientation))", level: .info)
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
                Orientation: \(OrientationCache.shared.orientation)
                Interface Idiom: \(UIDevice.current.userInterfaceIdiom.rawValue)
                """
                try orientationInfo.write(to: orientationPath, atomically: true, encoding: .utf8)
            
                // Update properties on main thread
                DispatchQueue.main.async {
                    self.recordingFolder = recordingFolder
                    self.recordingStartTime = Date()
                    self.frameCount = 0
                    self.recordingOrientation = OrientationCache.shared.orientation
                    
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
                    } else {
                        DispatchQueue.main.async {
                            self.isPreparingRecording = false
                            self.isRecording = true
                        }
                        log("Recording started successfully", level: .info)
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
            self.frameSemaphore.signal()

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
                
                self.videoWriterQueue.async { [weak self] in
                    guard let self = self else { return }
                    
                    // Wait until frameWriterQueue is finished
                    self.frameWriterQueue.sync {
                        // all frames processed
                    }
                    
                    // For standard recordings, finalize the video
                    if !isLiDAR {
                        if let writer = self.videoWriter, let writerInput = self.videoWriterInput {
                            writerInput.markAsFinished()
                            writer.finishWriting {
                                log("Video writing completed", level: .info)
                                
                                DispatchQueue.main.async {
                                    self.videoWriter = nil
                                    self.videoWriterInput = nil
                                    self.pixelBufferAdaptor = nil
                                    self.recordingFolder = nil
                                    self.frameCount = 0
                                    self.firstPTS = nil
                                    self.recordingStartTime = nil
                                    completion(folder)
                                }
                            }
                        } else {
                            log("No video writer available for finalization", level: .error)
                            DispatchQueue.main.async {
                                self.recordingFolder = nil
                                completion(folder)
                            }
                        }
                    }
                }
            }
        }
    }
    
    private func startWriterLoop() {
        frameWriterQueue.async { [weak self] in
            guard let self = self else { return }
            
            while true {
                // Wait until a frame is ready
                self.frameSemaphore.wait()
                
                if !self.isRecording && self.frameBuffer.isEmpty {
                    break // exit loop cleanly
                }
                
                // Drain one frame if available
                if let (frame, pts) = self.frameBufferQueue.sync(execute: {
                    return self.frameBuffer.isEmpty ? nil : self.frameBuffer.removeFirst()
                }) {
                    // Guard against nil video writer or input
                    guard let input = self.videoWriterInput,
                          let adaptor = self.pixelBufferAdaptor,
                          let writer = self.videoWriter else { return }

                    // Set Timestamp
                    if firstPTS == nil {
                        firstPTS = pts
                        writer.startSession(atSourceTime: pts)
                    }
                    
                    // Get a buffer from the adaptor’s pool
                    guard input.isReadyForMoreMediaData else { return }

                    // Use append to adaptor pool
                    if !adaptor.append(frame, withPresentationTime: pts) {
                        log("Failed to append pixel buffer to video", level: .error)
                    } else {
                        self.frameCount += 1
                    }
                }
            }
            
            log("Frame writer loop exited", level: .info)
        }
    }
    
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
                if self.recordingOrientation == .portrait || self.recordingOrientation == .portraitUpsideDown {
                    width = self.cameraConfiguration.resolution.height
                    height = self.cameraConfiguration.resolution.width
                } else {
                    width = self.cameraConfiguration.resolution.width
                    height = self.cameraConfiguration.resolution.height
                }
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
                    kCVPixelBufferHeightKey as String: height,
                    // iOS requires this empty dictionary to back by IOSurface for realtime
                    kCVPixelBufferIOSurfacePropertiesKey as String: [:]
                ]
                
                self.pixelBufferAdaptor = AVAssetWriterInputPixelBufferAdaptor(
                    assetWriterInput: self.videoWriterInput!,
                    sourcePixelBufferAttributes: sourcePixelBufferAttributes
                )
                
                // Add input to writer
                if let writer = self.videoWriter, let input = self.videoWriterInput,
                    writer.canAdd(input) {
                        writer.add(input)
                        if writer.startWriting() {
                            log("Writer ready, waiting for first PTS…", level: .info)
                            completion(true)
                        } else {
                            log("Failed to start writing: \(writer.error?.localizedDescription ?? "unknown")", level: .error)
                            completion(false)
                        }
                } else {
                    completion(false)
                }

                
            } catch {
                log("Failed to create video writer: \(error.localizedDescription)", level: .error)
                completion(false)
            }
        }
    }
    
    private func getOrientationName(_ orientation: DeviceOrientationModel) -> String {
            switch orientation {
            case .portrait: return "portrait"
            case .portraitUpsideDown: return "portraitUpsideDown"
            case .landscapeLeft: return "landscapeLeft"
            case .landscapeRight: return "landscapeRight"
            }
        }
    
    private func saveRecordingMetadata(to folder: URL, orientation: DeviceOrientationModel, frameCount: Int, isLiDAR: Bool) {
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
                rawValue: 0,
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

        } catch {
            log("Failed to save metadata: \(error)", level: .error)
        }
    }
}
