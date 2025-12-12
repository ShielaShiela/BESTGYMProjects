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

    // Depth detection
    @Published var depthValue: Float?
    @Published var centerDepthValue: Float?
    private var centerDepthTimer: Timer?

    // Image Processing
    @Published var poseKeypoints: [PoseBox] = []
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
    
    //Add for Keypoint Saving
    private var poseDataBuffer: [PoseFrameData] = []
    private let poseDataQueue = DispatchQueue(label: "com.yourapp.posedata", qos: .userInitiated)
    private let poseBufferLimit = 100 // Write to file every 100 frames
    
    //video writers
    private var assetWriter: AVAssetWriter?
    private var colorWriterInput: AVAssetWriterInput?
    private var depthWriterInput: AVAssetWriterInput?
    private var colorPixelBufferAdaptor: AVAssetWriterInputPixelBufferAdaptor?
    private var depthPixelBufferAdaptor: AVAssetWriterInputPixelBufferAdaptor?
    private let colorWriterQueue = DispatchQueue(label: "com.yourapp.colorwriter", qos: .userInteractive)
    private let depthWriterQueue = DispatchQueue(label: "com.yourapp.depthwriter", qos: .userInteractive)

    
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
//    func onNewDepthData(capturedData: FrameDataModel, pixelBuffer: CVPixelBuffer?, pts: CMTime) {
//        self.systemFPS.tick()
//        DispatchQueue.main.async {
//            self.fpsStream = self.systemFPS.fps
//        }
//        
//        
//        DispatchQueue.main.async {
//            self.frameCount += 1
//        }
//        
//    }
    
    func onNewDepthData(capturedData: FrameDataModel, pixelBuffer: CVPixelBuffer?, depthData: AVDepthData?, pts: CMTime) {
        if let currentBuffer = pixelBuffer {
            // Update FPS
            self.systemFPS.tick()
            DispatchQueue.main.async {
                self.fpsStream = self.systemFPS.fps
            }
            
            // Write frames to videos if recording
            if isRecording && !isPreparingRecording {
                // Increment frame count FIRST and capture it synchronously
                let currentFrameCount = self.frameCount + 1
                
                DispatchQueue.main.async {
                    // Update camera data
                    self.capturedData.database.cameraIntrinsics = capturedData.cameraIntrinsics
                    self.capturedData.database.cameraReferenceDimensions = capturedData.cameraReferenceDimensions
                    
                    // Update frame count
                    self.frameCount = currentFrameCount
                }
                
                // Track first PTS and start sessions
                // Track first PTS and start sessions
                let isFirstFrame = (self.firstPTS == nil)
                if isFirstFrame {
                    self.firstPTS = pts
                    
                    if let colorWriter = self.assetWriter {
                        colorWriter.startSession(atSourceTime: pts)  // ✅ Start at actual PTS
                        log("🎬 Started color writer session at \(CMTimeGetSeconds(pts))s", level: .info)
                    }
                    if let depthWriter = self.videoWriter {
                        depthWriter.startSession(atSourceTime: pts)  // ✅ Start at actual PTS
                        log("🎬 Started depth writer session at \(CMTimeGetSeconds(pts))s", level: .info)
                    }
                }

                // ✅ Use absolute presentation time (no subtraction)
                let presentationTime = pts

                // Write RGB frame
                // Write RGB frame
                if let colorInput = self.colorWriterInput,
                   let colorAdaptor = self.colorPixelBufferAdaptor {
                    
                    // Capture the buffer and time outside the async block
                    let bufferToWrite = currentBuffer
                    let timeToWrite = presentationTime
                    let frameNum = currentFrameCount
                    
                    colorWriterQueue.async { [weak self] in
                        guard let self = self else { return }
                        
                        // Wait for input to be ready (with timeout)
                        var waitCount = 0
                        while !colorInput.isReadyForMoreMediaData && waitCount < 100 {
                            usleep(1000) // Wait 1ms
                            waitCount += 1
                        }
                        
                        guard colorInput.isReadyForMoreMediaData else {
                            log("⚠️ Color input timeout for frame \(frameNum)", level: .warn)
                            return
                        }
                        
                        if colorAdaptor.append(bufferToWrite, withPresentationTime: timeToWrite) {
                            if frameNum % 30 == 0 || frameNum == 1 {
                                log("✅ RGB frame \(frameNum) written at \(CMTimeGetSeconds(timeToWrite))s", level: .info)
                            }
                        } else {
                            log("❌ Failed to append RGB frame \(frameNum)", level: .error)
                        }
                    }
                }

                // Write Depth frame
                if let depthInput = self.depthWriterInput,
                   let depthAdaptor = self.depthPixelBufferAdaptor,
                   let depth = depthData {
                    
                    let depthMapToConvert = depth.depthDataMap
                    let timeToWrite = presentationTime
                    let frameNum = currentFrameCount
                    
                    depthWriterQueue.async { [weak self] in
                        guard let self = self else { return }
                        
                        // Convert depth map
                        guard let depthPixelBuffer = self.convertDepthToGrayscalePixelBuffer(depthMapToConvert) else {
                            log("Failed to convert depth map for frame \(frameNum)", level: .error)
                            return
                        }
                        
                        // Wait for input to be ready
                        var waitCount = 0
                        while !depthInput.isReadyForMoreMediaData && waitCount < 100 {
                            usleep(1000) // Wait 1ms
                            waitCount += 1
                        }
                        
                        guard depthInput.isReadyForMoreMediaData else {
                            log("⚠️ Depth input timeout for frame \(frameNum)", level: .warn)
                            return
                        }
                        
                        if depthAdaptor.append(depthPixelBuffer, withPresentationTime: timeToWrite) {
                            if frameNum % 30 == 0 || frameNum == 1 {
                                log("✅ Depth frame \(frameNum) written at \(CMTimeGetSeconds(timeToWrite))s", level: .info)
                            }
                        } else {
                            log("❌ Failed to append depth frame \(frameNum)", level: .error)
                        }
                    }
                }


                // ✅ Save raw depth map for this frame
                if let depth = depthData, let folder = self.recordingFolder {
                    DispatchQueue.global(qos: .utility).async { [weak self] in
                        self?.saveRawDepthMap(depth, frameIndex: currentFrameCount, to: folder)
                    }
                }

                

                
                // BETA: - YOLO Pose Detection with Depth
                if isPoseProcessingEnabled {
                    poseProcessor?.process(pixelBuffer: currentBuffer, pts: pts) { [weak self] poses, fps, pts in
                        guard let self = self else { return }
                        
                        if !poses.isEmpty {
                            DispatchQueue.main.async {
                                self.poseKeypoints = poses
                                self.fpsModel = fps
                            }
                        } else {
                            DispatchQueue.main.async {
                                self.poseKeypoints = []
                                self.fpsModel = fps
                            }
                        }
                        
                        // Save pose data WITH depth when recording
                        if self.isRecording && !self.isPreparingRecording {
                            let timestamp = CMTimeGetSeconds(pts)
                            let intrinsics = capturedData.cameraIntrinsics
                            
                            // Extract depth map
                            var depthMap: CVPixelBuffer?
                            if let depth = depthData {
                                depthMap = depth.depthDataMap
                            }
                            
                            // Process poses with depth
                            let posesWithDepth: [PoseBox] = poses.map { pose in
                                let keypointsWithDepth = pose.keypoints.map { keypoint in
                                    var depthValue: Float = 0.0
                                    
                                    if let depthBuffer = depthMap {
                                        depthValue = self.getDepthValue(
                                            at: CGPoint(x: CGFloat(keypoint.x), y: CGFloat(keypoint.y)),
                                            from: depthBuffer,
                                            referenceDimensions: capturedData.cameraReferenceDimensions
                                        )
                                    }
                                    
                                    return KeypointData(
                                        name: keypoint.name,
                                        x: keypoint.x,
                                        y: keypoint.y,
                                        confidence: keypoint.confidence,
                                        depth: depthValue,
                                        frameIndex: currentFrameCount  // Use captured frame count
                                    )
                                }
                                
                                return PoseBox(
                                    bbox: pose.bbox,
                                    confidence: pose.confidence,
                                    keypoints: keypointsWithDepth,
                                    hasDepthData: true  // Set to true for LiDAR
                                )
                            }
                            
                            let frameData = PoseFrameData(
                                frameIndex: currentFrameCount,  // Use captured frame count
                                timestamp: timestamp,
                                poses: posesWithDepth,
                                pts: pts,
                                hasDepthData: true,  // Set to true for LiDAR
                                cameraIntrinsics: intrinsics
                            )
                            
                            self.poseDataQueue.async { [weak self] in
                                guard let self = self else { return }
                                self.poseDataBuffer.append(frameData)
                                
                                if self.poseDataBuffer.count % 30 == 0 {
                                    log("LiDAR pose buffer: \(self.poseDataBuffer.count) frames", level: .info)
                                }
                                
                                if self.poseDataBuffer.count >= self.poseBufferLimit,
                                   let folder = self.recordingFolder {
                                    self.savePoseDataBuffer(to: folder)
                                }
                            }
                        }
                    }
                } else {
                    // If pose processing is disabled but still recording
                    // Save frame info without pose data
                    if self.isRecording && !self.isPreparingRecording {
                        let timestamp = CMTimeGetSeconds(pts)
                        let intrinsics = capturedData.cameraIntrinsics
                        
                        let frameData = PoseFrameData(
                            frameIndex: currentFrameCount,  // Use captured frame count
                            timestamp: timestamp,
                            poses: [],
                            pts: pts,
                            hasDepthData: true,  // Set to true for LiDAR
                            cameraIntrinsics: intrinsics
                        )
                        
                        self.poseDataQueue.async { [weak self] in
                            guard let self = self else { return }
                            self.poseDataBuffer.append(frameData)
                            
                            if self.poseDataBuffer.count >= self.poseBufferLimit,
                               let folder = self.recordingFolder {
                                self.savePoseDataBuffer(to: folder)
                            }
                        }
                    }
                }
            }
        }
    }


//    private func convertDepthToGrayscalePixelBuffer(_ depthMap: CVPixelBuffer) -> CVPixelBuffer? {
//        CVPixelBufferLockBaseAddress(depthMap, .readOnly)
//        defer { CVPixelBufferUnlockBaseAddress(depthMap, .readOnly) }
//        
//        let width = CVPixelBufferGetWidth(depthMap)
//        let height = CVPixelBufferGetHeight(depthMap)
//        let pixelFormat = CVPixelBufferGetPixelFormatType(depthMap)
//        
//        // Create output pixel buffer (BGRA for video compatibility)
//        var outputPixelBuffer: CVPixelBuffer?
//        let options: [String: Any] = [
//            kCVPixelBufferCGImageCompatibilityKey as String: true,
//            kCVPixelBufferCGBitmapContextCompatibilityKey as String: true
//        ]
//        
//        let status = CVPixelBufferCreate(
//            kCFAllocatorDefault,
//            width,
//            height,
//            kCVPixelFormatType_32BGRA,
//            options as CFDictionary,
//            &outputPixelBuffer
//        )
//        
//        guard status == kCVReturnSuccess, let output = outputPixelBuffer else {
//            log("Failed to create output pixel buffer", level: .error)
//            return nil
//        }
//        
//        CVPixelBufferLockBaseAddress(output, [])
//        defer { CVPixelBufferUnlockBaseAddress(output, []) }
//        
//        let outputBaseAddress = CVPixelBufferGetBaseAddress(output)
//        let outputBytesPerRow = CVPixelBufferGetBytesPerRow(output)
//        
//        // ✅ Use fixed depth range (more reliable than calculating min/max)
//        let minDepthRange: Float = 0.0
//        let maxDepthRange: Float = 5.0  // Adjust based on your scene depth
//        
//        let baseAddress = CVPixelBufferGetBaseAddress(depthMap)!
//        let bytesPerRow = CVPixelBufferGetBytesPerRow(depthMap)
//        
//        if pixelFormat == kCVPixelFormatType_DepthFloat32 {
//            let floatBuffer = baseAddress.assumingMemoryBound(to: Float32.self)
//            let outputPtr = outputBaseAddress!.assumingMemoryBound(to: UInt8.self)
//            
//            for y in 0..<height {
//                for x in 0..<width {
//                    let depthIndex = y * (bytesPerRow / MemoryLayout<Float32>.stride) + x
//                    let depth = floatBuffer[depthIndex]
//                    
//                    // Normalize depth to 0-255 range
//                    let normalized: UInt8
//                    if depth > 0 && depth.isFinite {
//                        // Clamp to range
//                        let clamped = min(max(depth, minDepthRange), maxDepthRange)
//                        // Invert so closer = brighter (optional, comment out if you want far = bright)
//                        let inverted = maxDepthRange - clamped
//                        let normalizedFloat = inverted / (maxDepthRange - minDepthRange)
//                        normalized = UInt8(normalizedFloat * 255.0)
//                    } else {
//                        normalized = 0  // Invalid depth = black
//                    }
//                    
//                    // Write to BGRA output (B, G, R, A)
//                    let outputIndex = y * outputBytesPerRow + x * 4
//                    outputPtr[outputIndex] = normalized     // B
//                    outputPtr[outputIndex + 1] = normalized // G
//                    outputPtr[outputIndex + 2] = normalized // R
//                    outputPtr[outputIndex + 3] = 255        // A (full opacity)
//                }
//            }
//            
//        } else if pixelFormat == kCVPixelFormatType_DepthFloat16 {
//            let float16Buffer = baseAddress.assumingMemoryBound(to: UInt16.self)
//            let outputPtr = outputBaseAddress!.assumingMemoryBound(to: UInt8.self)
//            
//            for y in 0..<height {
//                for x in 0..<width {
//                    let depthIndex = y * (bytesPerRow / MemoryLayout<UInt16>.stride) + x
//                    let depthRaw = float16Buffer[depthIndex]
//                    
//                    // ✅ Proper Float16 to Float32 conversion
//                    // Use the bits directly with proper conversion
//                    let depth = Float(Float16(bitPattern: depthRaw))
//                    
//                    let normalized: UInt8
//                    if depth > 0 && depth.isFinite {
//                        let clamped = min(max(depth, minDepthRange), maxDepthRange)
//                        // Invert so closer = brighter
//                        let inverted = maxDepthRange - clamped
//                        let normalizedFloat = inverted / (maxDepthRange - minDepthRange)
//                        normalized = UInt8(normalizedFloat * 255.0)
//                    } else {
//                        normalized = 0
//                    }
//                    
//                    let outputIndex = y * outputBytesPerRow + x * 4
//                    outputPtr[outputIndex] = normalized
//                    outputPtr[outputIndex + 1] = normalized
//                    outputPtr[outputIndex + 2] = normalized
//                    outputPtr[outputIndex + 3] = 255
//                }
//            }
//        } else {
//            log("Unsupported depth pixel format: \(pixelFormat)", level: .error)
//            return nil
//        }
//        
//        return output
//    }
    private func convertDepthToGrayscalePixelBuffer(_ depthMap: CVPixelBuffer) -> CVPixelBuffer? {
        CVPixelBufferLockBaseAddress(depthMap, .readOnly)
        defer { CVPixelBufferUnlockBaseAddress(depthMap, .readOnly) }
        
        let width = CVPixelBufferGetWidth(depthMap)
        let height = CVPixelBufferGetHeight(depthMap)
        let pixelFormat = CVPixelBufferGetPixelFormatType(depthMap)
        
        // Create output pixel buffer (BGRA for video compatibility)
        var outputPixelBuffer: CVPixelBuffer?
        let options: [String: Any] = [
            kCVPixelBufferCGImageCompatibilityKey as String: true,
            kCVPixelBufferCGBitmapContextCompatibilityKey as String: true
        ]
        
        let status = CVPixelBufferCreate(
            kCFAllocatorDefault,
            width,
            height,
            kCVPixelFormatType_32BGRA,
            options as CFDictionary,
            &outputPixelBuffer
        )
        
        guard status == kCVReturnSuccess, let output = outputPixelBuffer else {
            log("Failed to create output pixel buffer", level: .error)
            return nil
        }
        
        CVPixelBufferLockBaseAddress(output, [])
        defer { CVPixelBufferUnlockBaseAddress(output, []) }
        
        let outputBaseAddress = CVPixelBufferGetBaseAddress(output)
        let outputBytesPerRow = CVPixelBufferGetBytesPerRow(output)
        
        let baseAddress = CVPixelBufferGetBaseAddress(depthMap)!
        let bytesPerRow = CVPixelBufferGetBytesPerRow(depthMap)
        
        // ✅ STEP 1: Calculate actual min/max from the depth data
        var minDepth: Float = Float.greatestFiniteMagnitude
        var maxDepth: Float = 0.0
        var validPixelCount = 0
        
        if pixelFormat == kCVPixelFormatType_DepthFloat32 {
            let floatBuffer = baseAddress.assumingMemoryBound(to: Float32.self)
            
            // First pass: find min/max
            for y in 0..<height {
                for x in 0..<width {
                    let index = y * (bytesPerRow / MemoryLayout<Float32>.stride) + x
                    let depth = floatBuffer[index]
                    
                    // Only consider valid depth values (0.1m to 10m range is typical for LiDAR)
                    if depth > 0.1 && depth < 10.0 && depth.isFinite {
                        minDepth = min(minDepth, depth)
                        maxDepth = max(maxDepth, depth)
                        validPixelCount += 1
                    }
                }
            }
            
            // Fallback if no valid depth found
            if validPixelCount == 0 || minDepth >= maxDepth {
                log("⚠️ No valid depth data found, using default range", level: .warn)
                minDepth = 0.0
                maxDepth = 5.0
            } else {
                // Add small margin to prevent edge cases
                let margin = (maxDepth - minDepth) * 0.05
                minDepth = max(0.1, minDepth - margin)
                maxDepth = min(10.0, maxDepth + margin)
            }
            
            log("📊 Depth range: \(String(format: "%.2f", minDepth))m - \(String(format: "%.2f", maxDepth))m (\(validPixelCount) valid pixels)", level: .debug)
            
            // Second pass: normalize to grayscale
            let outputPtr = outputBaseAddress!.assumingMemoryBound(to: UInt8.self)
            let depthRange = maxDepth - minDepth
            
            for y in 0..<height {
                for x in 0..<width {
                    let depthIndex = y * (bytesPerRow / MemoryLayout<Float32>.stride) + x
                    let depth = floatBuffer[depthIndex]
                    
                    let normalized: UInt8
                    if depth > 0.1 && depth.isFinite {
                        // Clamp to calculated range
                        let clamped = min(max(depth, minDepth), maxDepth)
                        // Invert so closer = brighter
                        let inverted = maxDepth - clamped
                        let normalizedFloat = inverted / depthRange
                        normalized = UInt8(normalizedFloat * 255.0)
                    } else {
                        normalized = 0  // Invalid = black
                    }
                    
                    // Write to BGRA
                    let outputIndex = y * outputBytesPerRow + x * 4
                    outputPtr[outputIndex] = normalized
                    outputPtr[outputIndex + 1] = normalized
                    outputPtr[outputIndex + 2] = normalized
                    outputPtr[outputIndex + 3] = 255
                }
            }
            
        } else if pixelFormat == kCVPixelFormatType_DepthFloat16 {
            let float16Buffer = baseAddress.assumingMemoryBound(to: UInt16.self)
            
            // First pass: find min/max
            for y in 0..<height {
                for x in 0..<width {
                    let index = y * (bytesPerRow / MemoryLayout<UInt16>.stride) + x
                    let depthRaw = float16Buffer[index]
                    let depth = Float(Float16(bitPattern: depthRaw))
                    
                    if depth > 0.1 && depth < 10.0 && depth.isFinite {
                        minDepth = min(minDepth, depth)
                        maxDepth = max(maxDepth, depth)
                        validPixelCount += 1
                    }
                }
            }
            
            // Fallback
            if validPixelCount == 0 || minDepth >= maxDepth {
                log("⚠️ No valid depth data found, using default range", level: .warn)
                minDepth = 0.0
                maxDepth = 5.0
            } else {
                let margin = (maxDepth - minDepth) * 0.05
                minDepth = max(0.1, minDepth - margin)
                maxDepth = min(10.0, maxDepth + margin)
            }
            
            log("📊 Depth range: \(String(format: "%.2f", minDepth))m - \(String(format: "%.2f", maxDepth))m", level: .debug)
            
            // Second pass: normalize
            let outputPtr = outputBaseAddress!.assumingMemoryBound(to: UInt8.self)
            let depthRange = maxDepth - minDepth
            
            for y in 0..<height {
                for x in 0..<width {
                    let depthIndex = y * (bytesPerRow / MemoryLayout<UInt16>.stride) + x
                    let depthRaw = float16Buffer[depthIndex]
                    let depth = Float(Float16(bitPattern: depthRaw))
                    
                    let normalized: UInt8
                    if depth > 0.1 && depth.isFinite {
                        let clamped = min(max(depth, minDepth), maxDepth)
                        let inverted = maxDepth - clamped
                        let normalizedFloat = inverted / depthRange
                        normalized = UInt8(normalizedFloat * 255.0)
                    } else {
                        normalized = 0
                    }
                    
                    let outputIndex = y * outputBytesPerRow + x * 4
                    outputPtr[outputIndex] = normalized
                    outputPtr[outputIndex + 1] = normalized
                    outputPtr[outputIndex + 2] = normalized
                    outputPtr[outputIndex + 3] = 255
                }
            }
            
        } else {
            log("Unsupported depth pixel format: \(pixelFormat)", level: .error)
            return nil
        }
        
        return output
    }




    // Helper function to extract depth value at a specific pixel location
    private func getDepthValue(at point: CGPoint, from depthMap: CVPixelBuffer, referenceDimensions: CGSize) -> Float {
        CVPixelBufferLockBaseAddress(depthMap, .readOnly)
        defer { CVPixelBufferUnlockBaseAddress(depthMap, .readOnly) }
        
        let width = CVPixelBufferGetWidth(depthMap)
        let height = CVPixelBufferGetHeight(depthMap)
        
        // Scale point from reference dimensions to depth map dimensions
        let scaleX = CGFloat(width) / referenceDimensions.width
        let scaleY = CGFloat(height) / referenceDimensions.height
        
        let scaledX = Int(point.x * scaleX)
        let scaledY = Int(point.y * scaleY)
        
        // Bounds check
        guard scaledX >= 0, scaledX < width, scaledY >= 0, scaledY < height else {
            return 0.0
        }
        
        let pixelFormat = CVPixelBufferGetPixelFormatType(depthMap)
        
        if pixelFormat == kCVPixelFormatType_DepthFloat32 {
            let baseAddress = CVPixelBufferGetBaseAddress(depthMap)
            let bytesPerRow = CVPixelBufferGetBytesPerRow(depthMap)
            let floatBuffer = baseAddress!.assumingMemoryBound(to: Float32.self)
            let index = scaledY * (bytesPerRow / MemoryLayout<Float32>.stride) + scaledX
            return floatBuffer[index]
        } else if pixelFormat == kCVPixelFormatType_DepthFloat16 {
            let baseAddress = CVPixelBufferGetBaseAddress(depthMap)
            let bytesPerRow = CVPixelBufferGetBytesPerRow(depthMap)
            let float16Buffer = baseAddress!.assumingMemoryBound(to: UInt16.self)
            let index = scaledY * (bytesPerRow / MemoryLayout<UInt16>.stride) + scaledX
            // Convert Float16 to Float32
            return Float(float16Buffer[index])
        }
        
        return 0.0
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
                    guard let self = self else { return }
                    
                    if !poses.isEmpty {
                        DispatchQueue.main.async {
                            self.poseKeypoints = poses
                            self.fpsModel = fps
                        }
                    } else {
                        DispatchQueue.main.async {
                            self.poseKeypoints = []
                            self.fpsModel = fps
                        }
                    }
                    
                    // Save pose data WITHOUT depth when recording
                    if self.isRecording && !self.isPreparingRecording {
                        let timestamp = CMTimeGetSeconds(pts)
                        let intrinsics = capturedData.cameraIntrinsics
                        let currentFrameCount = self.frameCount
                        
                        let posesWithoutDepth: [PoseBox] = poses.map { pose in
                            let keypointsWithoutDepth = pose.keypoints.map { keypoint in
                                KeypointData(
                                    name: keypoint.name,
                                    x: keypoint.x,
                                    y: keypoint.y,
                                    confidence: keypoint.confidence,
                                    depth: 0.0,  // 0.0 indicates no depth data
                                    frameIndex: currentFrameCount
                                )
                            }
                            
                            return PoseBox(
                                bbox: pose.bbox,
                                confidence: pose.confidence,
                                keypoints: keypointsWithoutDepth,
                                hasDepthData: false
                            )
                        }
                        
                        let frameData = PoseFrameData(
                            frameIndex: currentFrameCount,
                            timestamp: timestamp,
                            poses: posesWithoutDepth,
                            pts: pts,
                            hasDepthData: false,
                            cameraIntrinsics: intrinsics
                        )
                        
                        self.poseDataQueue.async { [weak self] in
                            guard let self = self else { return }
                            self.poseDataBuffer.append(frameData)
                            
                            if self.poseDataBuffer.count >= self.poseBufferLimit,
                               let folder = self.recordingFolder {
                                self.savePoseDataBuffer(to: folder)
                            }
                        }
                    }
                }
            // In onNewBasicData, after the isPoseProcessingEnabled block
            } else {
                // If pose processing is disabled but still recording
                // Save frame info without pose data
                if self.isRecording && !self.isPreparingRecording {
                    let timestamp = CMTimeGetSeconds(pts)
                    let intrinsics = capturedData.cameraIntrinsics
                    let currentFrameCount = self.frameCount
                    
                    let frameData = PoseFrameData(
                        frameIndex: currentFrameCount,
                        timestamp: timestamp,
                        poses: [],
                        pts: pts,
                        hasDepthData: false,
                        cameraIntrinsics: intrinsics
                    )
                    
                    self.poseDataQueue.async { [weak self] in
                        guard let self = self else { return }
                        self.poseDataBuffer.append(frameData)
                        
                        if self.poseDataBuffer.count >= self.poseBufferLimit,
                           let folder = self.recordingFolder {
                            self.savePoseDataBuffer(to: folder)
                        }
                    }
                }
            }

            
//            // BETA: - YOLO Pose Detection
//            if isPoseProcessingEnabled {
//                poseProcessor?.process(pixelBuffer: currentBuffer, pts: pts) { [weak self] poses, fps, pts in
//                    guard let self = self else {return}
//                    
//                    // Run tracker
//                    // Inside your process callback:
////                    let tracked = updateTracks(with: poses, roi: nil)   // barROI can be nil if unknown
////                    if let athlete = pickSwinger(from: tracked, roi: nil), shouldRender(athlete) {
////                        DispatchQueue.main.async {
////                            self?.poseKeypoints = [athlete.pose]
////                        }
////                    } else {
////                        DispatchQueue.main.async {
////                            self?.poseKeypoints = []   // don’t render stale predictions
////                        }
////                    }
//                    
//                    if !poses.isEmpty {
//                        DispatchQueue.main.async {
//                            self.poseKeypoints = poses
//                            self.fpsModel = fps
//                        }
//                    } else {
//                        DispatchQueue.main.async {
//                            self.poseKeypoints = []
//                            self.fpsModel = fps
//                        }
//                    }
//                    
//                    // 🎯 This saves pose data when recording
//                    if self.isRecording {  // 👈 NOW THIS WORKS
//                        let timestamp = CMTimeGetSeconds(pts)
//                        let frameData = PoseFrameData(
//                            frameIndex: self.frameCount,
//                            timestamp: timestamp,
//                            poses: poses,
//                            pts: pts
//                        )
//                        
//                        self.poseDataQueue.async { [weak self] in
//                            guard let self = self else { return }
//                            self.poseDataBuffer.append(frameData)
//                            
//                            // Auto-save every 100 frames
//                            if self.poseDataBuffer.count >= self.poseBufferLimit,
//                               let folder = self.recordingFolder {
//                                self.savePoseDataBuffer(to: folder)
//                            }
//                        }
//                    }
//                }
//            }


        }
    }
    
    // Optimized batch depth extraction (avoids repeated texture access)
    private func extractBatchDepthOptimized(
        for points: [CGPoint],
        depthTexture: MTLTexture?,
        imageSize: CGSize
    ) -> [Float?] {
        guard let depthTexture = depthTexture else {
            return Array(repeating: nil, count: points.count)
        }
        
        let depthWidth = depthTexture.width
        let depthHeight = depthTexture.height
        
        return points.map { point in
            let depthX = Int(point.x / imageSize.width * CGFloat(depthWidth))
            let depthY = Int(point.y / imageSize.height * CGFloat(depthHeight))
            
            guard depthX >= 0, depthX < depthWidth, depthY >= 0, depthY < depthHeight else {
                return nil
            }
            
            var depthValue = Float16(0)
            let region = MTLRegionMake2D(depthX, depthY, 1, 1)
            depthTexture.getBytes(&depthValue, bytesPerRow: 0, from: region, mipmapLevel: 0)
            
            let depth = Float(depthValue)
            // Filter invalid values
            return (depth > 0.1 && depth < 20.0) ? depth : nil
        }
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
        log("LiDAR enabled: \(isLiDAREnabled)", level: .info)
        
        // Set preparing flag
        isPreparingRecording = true
        
        // Clear pose data buffer for new recording
        poseDataQueue.async { [weak self] in
            self?.poseDataBuffer.removeAll()
        }
        
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
            let personFolderPath = dateFolderPath.appendingPathComponent(self.athleteName)
            
            // Different folder naming for LiDAR vs standard recording
            let folderName: String
            if self.isLiDAREnabled {
                folderName = "LiDAR_Recording_\(self.actionType)_\(timeString)"
            } else {
                folderName = "Recording_\(self.actionType)_\(timeString)"
            }
            let recordingFolder = personFolderPath.appendingPathComponent(folderName)
            
            do {
                // Create directories
                try FileManager.default.createDirectory(at: recordingFolder, withIntermediateDirectories: true, attributes: nil)
                
                // Save orientation information immediately (for debugging)
                let orientationPath = recordingFolder.appendingPathComponent("orientation_info.txt")
                let orientationInfo = """
                Orientation: \(OrientationCache.shared.orientation)
                Interface Idiom: \(UIDevice.current.userInterfaceIdiom.rawValue)
                LiDAR Enabled: \(self.isLiDAREnabled)
                """
                try orientationInfo.write(to: orientationPath, atomically: true, encoding: .utf8)
            
                // Update properties on main thread
                DispatchQueue.main.async {
                    self.recordingFolder = recordingFolder
                    self.recordingStartTime = Date()
                    self.frameCount = 0
                    self.firstPTS = nil  // Reset firstPTS for new recording
                    self.recordingOrientation = OrientationCache.shared.orientation
                    
                    log("Recording started to folder: \(recordingFolder.lastPathComponent)", level: .info)
                    
                    // Setup video writer and only start recording when ready
                    if !self.isLiDAREnabled {
                        // Standard recording
                        self.setupVideoWriterInBackground(at: recordingFolder) { success in
                            DispatchQueue.main.async {
                                self.isPreparingRecording = false
                                if success {
                                    self.isRecording = true
                                    self.startWriterLoop()
                                    log("Standard recording started successfully", level: .info)
                                } else {
                                    log("Failed to setup video writer, recording not started", level: .error)
                                }
                            }
                        }
                    } else {
                        // LiDAR recording - setup writers first, then start
                        self.setupLiDARVideoWriters(at: recordingFolder) { success in
                            DispatchQueue.main.async {
                                self.isPreparingRecording = false
                                if success {
                                    self.isRecording = true
                                    log("LiDAR recording started successfully (dual video mode)", level: .info)
                                } else {
                                    log("Failed to setup LiDAR video writers", level: .error)
                                }
                            }
                        }
                    }
                }
            } catch {
                log("Error creating recording folder: \(error.localizedDescription)", level: .error)
                DispatchQueue.main.async {
                    self.isRecording = false
                    self.isPreparingRecording = false
                }
            }
        }
    }

    
    // Stop recording with proper cleanup
//    func stopRecording(completion: @escaping (URL?) -> Void) {
//        DispatchQueue.main.async {
//            guard self.isRecording, let folder = self.recordingFolder else {
//                completion(nil)
//                return
//            }
//            
//            // First mark as not recording to prevent new frames
//            self.isRecording = false
//            self.frameSemaphore.signal()
//
//            // Capture all required information before moving to background thread
//            let isLiDAR = self.isLiDAREnabled
//            let frameCount = self.frameCount
//            let recordingOrientation = self.recordingOrientation
//            
//            // Process completion on background thread
//            DispatchQueue.global(qos: .userInitiated).async {
//                log("Stopping recording...", level: .info)
//                
//                // In your recording stop function, add this AFTER saving the buffer:
//                self.savePoseDataBuffer(to: folder)
//
//                // Wait for pose data queue to finish
//                self.poseDataQueue.sync {
//                    log("All pose data saved", level: .info)
//                }
//
//                // NEW: Consolidate all pose data into single keypoint.json
//                self.consolidatePoseData(in: folder)
//                
//                // Call our improved metadata saver
//                self.saveRecordingMetadata(
//                    to: folder,
//                    orientation: recordingOrientation,
//                    frameCount: frameCount,
//                    isLiDAR: self.isLiDAREnabled
//                )
//                
//                self.videoWriterQueue.async { [weak self] in
//                    guard let self = self else { return }
//                    
//                    // Wait until frameWriterQueue is finished
//                    self.frameWriterQueue.sync {
//                        // all frames processed
//                    }
//                    
//                    // For standard recordings, finalize the video
//                    if !isLiDAR {
//                        if let writer = self.videoWriter, let writerInput = self.videoWriterInput {
//                            writerInput.markAsFinished()
//                            writer.finishWriting {
//                                log("Video writing completed", level: .info)
//                                
//                                DispatchQueue.main.async {
//                                    self.videoWriter = nil
//                                    self.videoWriterInput = nil
//                                    self.pixelBufferAdaptor = nil
//                                    self.recordingFolder = nil
//                                    self.frameCount = 0
//                                    self.firstPTS = nil
//                                    self.recordingStartTime = nil
//                                    completion(folder)
//                                }
//                            }
//                        } else {
//                            log("No video writer available for finalization", level: .error)
//                            DispatchQueue.main.async {
//                                self.recordingFolder = nil
//                                completion(folder)
//                            }
//                        }
//                    }
//                }
//            }
//        }
//    }
    
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
    
    // MARK: - Pose Data Saving
    private func savePoseDataBuffer(to folder: URL) {
        guard !poseDataBuffer.isEmpty else { return }
        
        poseDataQueue.async { [weak self] in
            guard let self = self else { return }
            
            let encoder = JSONEncoder()
            encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
            
            do {
                // Save the buffer to a timestamped file
                let timestamp = Int(Date().timeIntervalSince1970)
                let filename = "pose_data_\(timestamp).json"
                let fileURL = folder.appendingPathComponent(filename)
                
                let jsonData = try encoder.encode(self.poseDataBuffer)
                try jsonData.write(to: fileURL)
                log("Saved \(self.poseDataBuffer.count) pose frames to \(filename)", level: .info)
                
                // Clear buffer after saving
                self.poseDataBuffer.removeAll()
            } catch {
                log("Error saving pose data: \(error.localizedDescription)", level: .error)
            }
        }
    }
    
    // NEW: Final consolidation after recording stops
    private func consolidatePoseData(in folder: URL) {
        log("Consolidating pose data files...", level: .info)
        
        let fileManager = FileManager.default
        
        do {
            // Find all pose_data_*.json files
            let files = try fileManager.contentsOfDirectory(at: folder, includingPropertiesForKeys: nil)
            let poseFiles = files.filter { $0.lastPathComponent.hasPrefix("pose_data_") && $0.pathExtension == "json" }
            
            guard !poseFiles.isEmpty else {
                log("No pose data files to consolidate", level: .info)
                return
            }
            
            log("Found \(poseFiles.count) pose data files to consolidate", level: .info)
            
            // Collect all frame data from all files
            var allFrames: [PoseFrameData] = []
            
            for file in poseFiles {
                do {
                    let data = try Data(contentsOf: file)
                    let frames = try JSONDecoder().decode([PoseFrameData].self, from: data)
                    allFrames.append(contentsOf: frames)
                } catch {
                    log("Error reading pose file \(file.lastPathComponent): \(error)", level: .error)
                }
            }
            
            // Sort by frame index to ensure proper order
            allFrames.sort { $0.frameIndex < $1.frameIndex }
            
            log("Consolidated \(allFrames.count) total frames", level: .info)
            
            // Save consolidated data as keypoint.json
            let consolidatedURL = folder.appendingPathComponent("keypoint.json")
            let encoder = JSONEncoder()
            encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
            
            let consolidatedData = try encoder.encode(allFrames)
            try consolidatedData.write(to: consolidatedURL)
            
            log("Saved consolidated keypoint.json", level: .info)
            
            // ✅ DELETE the individual pose_data_*.json files after consolidation
            for file in poseFiles {
                try? fileManager.removeItem(at: file)
                log("Deleted temporary file: \(file.lastPathComponent)", level: .debug)
            }
            
        } catch {
            log("Error consolidating pose data: \(error)", level: .error)
        }
    }

}
//MARK :: for getting depth data for the point
extension CameraManagerVM {
    /// Batch extract depth for multiple keypoints (more efficient)
    func getBatchDepth(for keypoints: [CGPoint], from frameData: FrameDataModel) -> [Float?] {
        guard let depthTexture = frameData.depth else {
            return Array(repeating: nil, count: keypoints.count)
        }
        
        let depthWidth = depthTexture.width
        let depthHeight = depthTexture.height
        let imageSize = frameData.colorImage?.size ?? CGSize(width: depthWidth, height: depthHeight)
        
        return keypoints.map { point in
            let depthX = Int(point.x / imageSize.width * CGFloat(depthWidth))
            let depthY = Int(point.y / imageSize.height * CGFloat(depthHeight))
            
            guard depthX >= 0, depthX < depthWidth, depthY >= 0, depthY < depthHeight else {
                return nil
            }
            
            var depthValue = Float16(0)
            let region = MTLRegionMake2D(depthX, depthY, 1, 1)
            depthTexture.getBytes(&depthValue, bytesPerRow: 0, from: region, mipmapLevel: 0)
            
            let depth = Float(depthValue)
            return (depth > 0.1 && depth < 20.0) ? depth : nil
        }
    }
    
    /// Get average depth around a point (more robust to noise)
    func getAverageDepth(at imagePoint: CGPoint, radius: Int = 2, from frameData: FrameDataModel) -> Float? {
        guard let depthTexture = frameData.depth else {
            return nil
        }
        
        let depthWidth = depthTexture.width
        let depthHeight = depthTexture.height
        let imageSize = frameData.colorImage?.size ?? CGSize(width: depthWidth, height: depthHeight)
        
        let centerX = Int(imagePoint.x / imageSize.width * CGFloat(depthWidth))
        let centerY = Int(imagePoint.y / imageSize.height * CGFloat(depthHeight))
        
        var validDepths: [Float] = []
        
        for dy in -radius...radius {
            for dx in -radius...radius {
                let x = centerX + dx
                let y = centerY + dy
                
                guard x >= 0, x < depthWidth, y >= 0, y < depthHeight else { continue }
                
                var depthValue = Float16(0)
                let region = MTLRegionMake2D(x, y, 1, 1)
                depthTexture.getBytes(&depthValue, bytesPerRow: 0, from: region, mipmapLevel: 0)
                
                let depth = Float(depthValue)
                if depth > 0.1 && depth < 20.0 {
                    validDepths.append(depth)
                }
            }
        }
        
        guard !validDepths.isEmpty else { return nil }
        return validDepths.reduce(0, +) / Float(validDepths.count)
    }
}


extension CameraManagerVM {
    private func setupLiDARVideoWriters(at folder: URL, completion: @escaping (Bool) -> Void) {
        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            guard let self = self else {
                completion(false)
                return
            }
            
            let colorURL = folder.appendingPathComponent("color_video.mp4")
            let depthURL = folder.appendingPathComponent("depth_video.mp4")
            
            do {
                // Create RGB video writer
                let colorWriter = try AVAssetWriter(outputURL: colorURL, fileType: .mp4)
                
                // Create Depth video writer
                let depthWriter = try AVAssetWriter(outputURL: depthURL, fileType: .mp4)
                
                // Get dimensions from camera configuration (not from capturedData which isn't available yet)
                let width = self.cameraConfiguration.resolution.width
                let height = self.cameraConfiguration.resolution.height
                
                log("Setting up LiDAR video writers with dimensions: \(width)x\(height)", level: .info)
                
                // Validate dimensions
                guard width > 0 && height > 0 else {
                    log("Invalid dimensions for video writer: \(width)x\(height)", level: .error)
                    completion(false)
                    return
                }
                
                // RGB video settings
                let colorSettings: [String: Any] = [
                    AVVideoCodecKey: AVVideoCodecType.h264,
                    AVVideoWidthKey: width,
                    AVVideoHeightKey: height,
                    AVVideoCompressionPropertiesKey: [
                        AVVideoAverageBitRateKey: 10000000,
                        AVVideoMaxKeyFrameIntervalKey: 30,
                        AVVideoProfileLevelKey: AVVideoProfileLevelH264HighAutoLevel
                    ]
                ]
                
                // Depth video settings (grayscale, higher bitrate for precision)
                let depthSettings: [String: Any] = [
                    AVVideoCodecKey: AVVideoCodecType.h264,
                    AVVideoWidthKey: width,
                    AVVideoHeightKey: height,
                    AVVideoCompressionPropertiesKey: [
                        AVVideoAverageBitRateKey: 12000000,
                        AVVideoMaxKeyFrameIntervalKey: 30,
                        AVVideoProfileLevelKey: AVVideoProfileLevelH264HighAutoLevel
                    ]
                ]
                
                // Create RGB writer input
                let colorInput = AVAssetWriterInput(mediaType: .video, outputSettings: colorSettings)
                colorInput.expectsMediaDataInRealTime = true
                
                // Create Depth writer input
                let depthInput = AVAssetWriterInput(mediaType: .video, outputSettings: depthSettings)
                depthInput.expectsMediaDataInRealTime = true
                
                // Create RGB pixel buffer adaptor
                let colorBufferAttributes: [String: Any] = [
                    kCVPixelBufferPixelFormatTypeKey as String: Int(kCVPixelFormatType_32BGRA),
                    kCVPixelBufferWidthKey as String: width,
                    kCVPixelBufferHeightKey as String: height,
                    kCVPixelBufferCGImageCompatibilityKey as String: true,
                    kCVPixelBufferCGBitmapContextCompatibilityKey as String: true
                ]
                
                let colorAdaptor = AVAssetWriterInputPixelBufferAdaptor(
                    assetWriterInput: colorInput,
                    sourcePixelBufferAttributes: colorBufferAttributes
                )
                
                // Create Depth pixel buffer adaptor
                let depthBufferAttributes: [String: Any] = [
                    kCVPixelBufferPixelFormatTypeKey as String: Int(kCVPixelFormatType_32BGRA),
                    kCVPixelBufferWidthKey as String: width,
                    kCVPixelBufferHeightKey as String: height,
                    kCVPixelBufferCGImageCompatibilityKey as String: true,
                    kCVPixelBufferCGBitmapContextCompatibilityKey as String: true
                ]
                
                let depthAdaptor = AVAssetWriterInputPixelBufferAdaptor(
                    assetWriterInput: depthInput,
                    sourcePixelBufferAttributes: depthBufferAttributes
                )
                
                // Add inputs to writers
                guard colorWriter.canAdd(colorInput) && depthWriter.canAdd(depthInput) else {
                    log("Cannot add inputs to writers", level: .error)
                    completion(false)
                    return
                }
                
                colorWriter.add(colorInput)
                depthWriter.add(depthInput)
                
                // Start writing sessions
                colorWriter.startWriting()
//                colorWriter.startSession(atSourceTime: .zero)
                
                depthWriter.startWriting()
//                depthWriter.startSession(atSourceTime: .zero)
                
                // Update properties on main thread
                DispatchQueue.main.async {
                    self.assetWriter = colorWriter
                    self.colorWriterInput = colorInput
                    self.colorPixelBufferAdaptor = colorAdaptor
                    
                    self.videoWriter = depthWriter
                    self.depthWriterInput = depthInput
                    self.depthPixelBufferAdaptor = depthAdaptor
                    
                    log("LiDAR video writers set up successfully", level: .info)
                    completion(true)
                }
                
            } catch {
                log("Failed to setup LiDAR video writers: \(error)", level: .error)
                completion(false)
            }
        }
    }

    private func finalizeLiDARVideos(completion: (() -> Void)?) {
        let group = DispatchGroup()
        
        // Finalize RGB video
        if let colorInput = self.colorWriterInput,
           let colorWriter = self.assetWriter {
            group.enter()
            colorInput.markAsFinished()
            colorWriter.finishWriting {
                log("RGB video finalized: \(colorWriter.status.rawValue)", level: .info)
                group.leave()
            }
        }
        
        // Finalize Depth video
        if let depthInput = self.depthWriterInput,
           let depthWriter = self.videoWriter {
            group.enter()
            depthInput.markAsFinished()
            depthWriter.finishWriting {
                log("Depth video finalized: \(depthWriter.status.rawValue)", level: .info)
                group.leave()
            }
        }
        
        group.notify(queue: .main) {
            self.assetWriter = nil
            self.colorWriterInput = nil
            self.colorPixelBufferAdaptor = nil
            self.videoWriter = nil
            self.depthWriterInput = nil
            self.depthPixelBufferAdaptor = nil
            
            log("LiDAR recording stopped and saved", level: .info)
            completion?()
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
                
                // Save any remaining pose data buffer
                self.savePoseDataBuffer(to: folder)

                // Wait for pose data queue to finish
                self.poseDataQueue.sync {
                    log("All pose data saved", level: .info)
                }

                // Consolidate all pose data into single keypoint.json
                self.consolidatePoseData(in: folder)
                
                // ✅ Save depth metadata
                if isLiDAR {
                    self.saveDepthMetadata(to: folder, frameCount: frameCount)
                }
                
                // Save recording metadata
                self.saveRecordingMetadata(
                    to: folder,
                    orientation: recordingOrientation,
                    frameCount: frameCount,
                    isLiDAR: isLiDAR
                )
                
                // Handle video finalization based on recording type
                if isLiDAR {
                    // LiDAR mode: Finalize both RGB and Depth videos
                    self.finalizeLiDARVideos(folder: folder, completion: completion)
                } else {
                    // Standard mode: Finalize single video
                    self.finalizeStandardVideo(folder: folder, completion: completion)
                }
            }
        }
    }

    // MARK: - Video Finalization Helpers

    private func finalizeLiDARVideos(folder: URL, completion: @escaping (URL?) -> Void) {
        let group = DispatchGroup()
        
        var colorFinalized = false
        var depthFinalized = false
        
        // Finalize RGB video
        if let colorInput = self.colorWriterInput,
           let colorWriter = self.assetWriter {
            group.enter()
            colorInput.markAsFinished()
            colorWriter.finishWriting {
                if colorWriter.status == .completed {
                    log("RGB video finalized successfully", level: .info)
                    colorFinalized = true
                } else {
                    log("RGB video finalization failed: \(colorWriter.error?.localizedDescription ?? "Unknown error")", level: .error)
                }
                group.leave()
            }
        }
        
        // Finalize Depth video
        if let depthInput = self.depthWriterInput,
           let depthWriter = self.videoWriter {
            group.enter()
            depthInput.markAsFinished()
            depthWriter.finishWriting {
                if depthWriter.status == .completed {
                    log("Depth video finalized successfully", level: .info)
                    depthFinalized = true
                } else {
                    log("Depth video finalization failed: \(depthWriter.error?.localizedDescription ?? "Unknown error")", level: .error)
                }
                group.leave()
            }
        }
        
        group.notify(queue: .main) {
            log("LiDAR recording stopped. RGB: \(colorFinalized ? "✅" : "❌"), Depth: \(depthFinalized ? "✅" : "❌")", level: .info)
            
            // Clean up
            self.assetWriter = nil
            self.colorWriterInput = nil
            self.colorPixelBufferAdaptor = nil
            self.videoWriter = nil
            self.depthWriterInput = nil
            self.depthPixelBufferAdaptor = nil
            self.recordingFolder = nil
            self.frameCount = 0
            self.firstPTS = nil
            self.recordingStartTime = nil
            
            completion(folder)
        }
    }

    private func finalizeStandardVideo(folder: URL, completion: @escaping (URL?) -> Void) {
        self.videoWriterQueue.async { [weak self] in
            guard let self = self else {
                DispatchQueue.main.async {
                    completion(nil)
                }
                return
            }
            
            // Wait until frameWriterQueue is finished
            self.frameWriterQueue.sync {
                // All frames processed
            }
            
            // Finalize the video
            if let writer = self.videoWriter, let writerInput = self.videoWriterInput {
                writerInput.markAsFinished()
                writer.finishWriting {
                    if writer.status == .completed {
                        log("Video writing completed successfully", level: .info)
                    } else {
                        log("Video writing failed: \(writer.error?.localizedDescription ?? "Unknown error")", level: .error)
                    }
                    
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
                    self.frameCount = 0
                    self.firstPTS = nil
                    self.recordingStartTime = nil
                    completion(folder)
                }
            }
        }
    }

    private func saveRawDepthMap(_ depthData: AVDepthData, frameIndex: Int, to folder: URL) {
        let depthMap = depthData.depthDataMap
        
        CVPixelBufferLockBaseAddress(depthMap, .readOnly)
        defer { CVPixelBufferUnlockBaseAddress(depthMap, .readOnly) }
        
        let width = CVPixelBufferGetWidth(depthMap)
        let height = CVPixelBufferGetHeight(depthMap)
        let pixelFormat = CVPixelBufferGetPixelFormatType(depthMap)
        
        // Create depth frames subfolder
        let depthFramesFolder = folder.appendingPathComponent("depth_frames")
        try? FileManager.default.createDirectory(at: depthFramesFolder, withIntermediateDirectories: true)
        
        let filename = String(format: "depth_%06d.bin", frameIndex)
        let depthFileURL = depthFramesFolder.appendingPathComponent(filename)
        
        // Save as binary file with header
        var data = Data()
        
        // Write header (width, height, format)
        withUnsafeBytes(of: Int32(width)) { data.append(contentsOf: $0) }
        withUnsafeBytes(of: Int32(height)) { data.append(contentsOf: $0) }
        withUnsafeBytes(of: pixelFormat) { data.append(contentsOf: $0) }
        
        // Write depth values
        let baseAddress = CVPixelBufferGetBaseAddress(depthMap)!
        let bytesPerRow = CVPixelBufferGetBytesPerRow(depthMap)
        
        if pixelFormat == kCVPixelFormatType_DepthFloat32 {
            let floatBuffer = baseAddress.assumingMemoryBound(to: Float32.self)
            let totalPixels = width * height
            let floatData = Data(bytes: floatBuffer, count: totalPixels * MemoryLayout<Float32>.stride)
            data.append(floatData)
            
        } else if pixelFormat == kCVPixelFormatType_DepthFloat16 {
            let float16Buffer = baseAddress.assumingMemoryBound(to: UInt16.self)
            let totalPixels = width * height
            let float16Data = Data(bytes: float16Buffer, count: totalPixels * MemoryLayout<UInt16>.stride)
            data.append(float16Data)
        }
        
        // Write to file
        do {
            try data.write(to: depthFileURL)
            if frameIndex % 30 == 0 {
                log("💾 Saved raw depth frame \(frameIndex) (\(data.count / 1024) KB)", level: .info)
            }
        } catch {
            log("Failed to save depth frame \(frameIndex): \(error)", level: .error)
        }
    }
    
    private func saveDepthMetadata(to folder: URL, frameCount: Int) {
        let depthFramesFolder = folder.appendingPathComponent("depth_frames")
        let metadataURL = depthFramesFolder.appendingPathComponent("README.txt")
        
        let metadata = """
        Depth Frame Format
        ==================
        
        Total frames: \(frameCount)
        File pattern: depth_XXXXXX.bin (6-digit zero-padded frame index)
        
        Binary Format:
        --------------
        Header (12 bytes):
          - Width (4 bytes, Int32)
          - Height (4 bytes, Int32)
          - Pixel Format (4 bytes, OSType/FourCC)
        
        Data:
          - Float32 array (width × height elements) if format = 1717855600 (kCVPixelFormatType_DepthFloat32)
          - Float16 array (width × height elements) if format = 1751411059 (kCVPixelFormatType_DepthFloat16)
          - Values represent distance in meters
        
        Reading Example (Python):
        ------------------------
        import numpy as np
        import struct
        
        with open('depth_000001.bin', 'rb') as f:
            width = struct.unpack('i', f.read(4))[0]
            height = struct.unpack('i', f.read(4))[0]
            fmt = struct.unpack('I', f.read(4))[0]
            
            if fmt == 1717855600:  # Float32
                depth_data = np.frombuffer(f.read(), dtype=np.float32)
            else:  # Float16
                depth_data = np.frombuffer(f.read(), dtype=np.float16)
            
            depth_map = depth_data.reshape((height, width))
            print(f"Depth range: {depth_map.min():.3f}m to {depth_map.max():.3f}m")
        
        Camera Intrinsics:
        ------------------
        See keypoint.json for per-frame camera intrinsics matrix
        """
        
        do {
            try metadata.write(to: metadataURL, atomically: true, encoding: .utf8)
            log("Saved depth frames metadata", level: .info)
        } catch {
            log("Failed to save depth metadata: \(error)", level: .error)
        }
    }

}

