//
//  CameraLiDARDepthController.swift
//  DataCaptureTest
//
//  Created by Shiela Cabahug on 2024/7/4.
//

import Foundation
import AVFoundation
import CoreImage
import Photos
import UIKit
import Vision
import Metal

import os.log

protocol CaptureDataReceiver: AnyObject {
    func onNewBasicData(capturedData: FrameDataModel, pixelBuffer: CVPixelBuffer?, pts: CMTime)
}

class CameraControllerUI: NSObject, ObservableObject, AVCaptureVideoDataOutputSampleBufferDelegate {
    enum ConfigurationError: Error {
        case lidarDeviceUnavailable
        case requiredFormatUnavailable
        case basicCameraSetupFailed
        case sessionConfigurationFailed
    }
    
    // MARK: - Properties
    private var assetWriter: AVAssetWriter?
    private var isRecording = false
    
    private let videoQueue = DispatchQueue(label: "com.example.apple-samplecode.VideoQueue", qos: .userInteractive)
    private let sessionQueue = DispatchQueue(label: "com.example.apple-samplecode.SessionQueue", qos: .userInteractive)
    
    private(set) var captureSession: AVCaptureSession!
    
    private var depthDataOutput: AVCaptureDepthDataOutput?
    private var videoDataOutput: AVCaptureVideoDataOutput!
    private var outputVideoSync: AVCaptureDataOutputSynchronizer?
    
    private var textureCache: CVMetalTextureCache!
    private var filterMode = false
    private var hasLiDARSupport = false
    private var isUsingLiDAR = false

    // Configuration state
    private var currentResolution: CameraConfiguration.Resolution = .hd1080p
    private var currentCameraPosition: AVCaptureDevice.Position = .back

    weak var delegate: CaptureDataReceiver?
    
    var isFilteringEnabled = true {
        didSet {
            depthDataOutput?.isFilteringEnabled = isFilteringEnabled
            filterMode = isFilteringEnabled
        }
    }

    private var recordingStartTime: Date?
    private var recordingFolder: URL?
    private var frameCount: Int = 0
    
    
    private var lastFrameTimestamp: CFTimeInterval?
    private var deliveredFrameCount: Int = 0
    
    // Metal Environment
    private var converter: NV12ToBGRAMetalConverter?
    
    // MARK: - Initialization
    override init() {
        // Create a texture cache to hold sample buffer textures.
        CVMetalTextureCacheCreate(kCFAllocatorDefault,
                                  nil,
                                  MetalEnvironment.shared.metalDevice,
                                  nil,
                                  &textureCache)
        
        super.init()
        
        // Initialize capture session
        captureSession = AVCaptureSession()
        captureSession.sessionPreset = .inputPriority
        
        // Metal
        do {
            converter = try NV12ToBGRAMetalConverter(device: MTLCreateSystemDefaultDevice()!)
        } catch {
            log("Failed to create NV12 converter: \(error)", level: .error)
        }
    }
    
    // MARK: - Public Configuration
    func configureSession(resolution: CameraConfiguration.Resolution,
                         frameRate: CameraConfiguration.FrameRate,
                         enableLiDAR: Bool,
                         enableDepthFiltering: Bool,
                         cameraPosition: AVCaptureDevice.Position,
                         completion: @escaping (Bool) -> Void) throws {
        
        // Store configuration
        currentResolution = resolution
        currentCameraPosition = cameraPosition
        isFilteringEnabled = enableDepthFiltering
        
        // Configure session on background queue
        sessionQueue.async { [weak self] in
            guard let self = self else { return }
            
            do {
                try self.setupSession(enableLiDAR: enableLiDAR, frameRate: frameRate)
            } catch {
                print("❌ Session configuration failed: \(error)")
            }
            
            // Small delay to ensure commitConfiguration is fully applied (camera drivers can lag)
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.05) {
                completion(true)
                self.startStream()
            }
        }
    }
    
    // MARK: - Public Functions
    func startStream() {
        sessionQueue.async { [weak self] in
            guard let self = self else { return }
            // Only start if not already running
            if !self.captureSession.isRunning {
                self.captureSession.startRunning()
            }
        }
    }
    
    func stopStream() {
        sessionQueue.async { [weak self] in
            guard let self = self else { return }
            self.captureSession.stopRunning()
            
            // remove delegate to stop callbacks
            self.videoDataOutput?.setSampleBufferDelegate(nil, queue: nil)
            
            // Remove outputs
            if let output = self.videoDataOutput,
               self.captureSession.outputs.contains(output) {
                self.captureSession.removeOutput(output)
            }
            
            // Remove inputs
            for input in self.captureSession.inputs {
                self.captureSession.removeInput(input)
            }
        }
    }
    
    // MARK: - Private Setup Functions
    private func setupSession(enableLiDAR: Bool, frameRate: CameraConfiguration.FrameRate) throws {
        // Stop session if running
        if captureSession.isRunning {
            captureSession.stopRunning()
        }
        
        // Clear existing configuration
        captureSession.beginConfiguration()
        
        // Remove existing inputs and outputs
        for input in captureSession.inputs {
            captureSession.removeInput(input)
        }
        for output in captureSession.outputs {
            captureSession.removeOutput(output)
        }
        
        // Check LiDAR support
        hasLiDARSupport = checkLiDARSupport()
        isUsingLiDAR = enableLiDAR
        
        // Setup based on configuration
        if enableLiDAR && hasLiDARSupport {
            try setupLiDARInput(frameRate: frameRate)
            setupLiDAROutputs()
        } else {
            setupBasicCameraInternal(frameRate: frameRate)
        }
        
        // Finalize configuration
        captureSession.commitConfiguration()
    }
    
    private func checkLiDARSupport() -> Bool {
        let discoverySession = AVCaptureDevice.DiscoverySession(
            deviceTypes: [.builtInLiDARDepthCamera],
            mediaType: .video,
            position: currentCameraPosition
        )
        return !discoverySession.devices.isEmpty
    }
    
    private func findBestFormat(for device: AVCaptureDevice, resolution: CameraConfiguration.Resolution, frameRate: CameraConfiguration.FrameRate) -> AVCaptureDevice.Format? {
        // Prefer exact resolution match first
        let exactFormats = device.formats.filter { format in
            let dimensions = format.formatDescription.dimensions
            let hasExactResolution = dimensions.width == resolution.width && dimensions.height == resolution.height
            let hasRequiredPixelFormat = format.formatDescription.mediaSubType.rawValue == kCVPixelFormatType_420YpCbCr8BiPlanarFullRange
            let isNotBinned = !format.isVideoBinned
            let hasRequiredFrameRate = format.videoSupportedFrameRateRanges.contains { range in
                range.maxFrameRate >= Double(frameRate.rawValue) && range.minFrameRate <= Double(frameRate.rawValue)
            }
            if isUsingLiDAR {
                let hasDepthSupport = !format.supportedDepthDataFormats.isEmpty
                return hasExactResolution && hasRequiredPixelFormat && isNotBinned && hasRequiredFrameRate && hasDepthSupport
            } else {
                return hasExactResolution && hasRequiredPixelFormat && isNotBinned && hasRequiredFrameRate
            }
        }
        if let format = exactFormats.first {
            return format
        }
        // Fallback: closest lower resolution that supports frame rate
        let fallbackFormats = device.formats.filter { format in
            let dimensions = format.formatDescription.dimensions
            let hasLowerOrEqualResolution = dimensions.width <= resolution.width && dimensions.height <= resolution.height
            let hasRequiredPixelFormat = format.formatDescription.mediaSubType.rawValue == kCVPixelFormatType_420YpCbCr8BiPlanarFullRange
            let isNotBinned = !format.isVideoBinned
            let hasRequiredFrameRate = format.videoSupportedFrameRateRanges.contains { range in
                range.maxFrameRate >= Double(frameRate.rawValue) && range.minFrameRate <= Double(frameRate.rawValue)
            }
            if isUsingLiDAR {
                let hasDepthSupport = !format.supportedDepthDataFormats.isEmpty
                return hasLowerOrEqualResolution && hasRequiredPixelFormat && isNotBinned && hasRequiredFrameRate && hasDepthSupport
            } else {
                return hasLowerOrEqualResolution && hasRequiredPixelFormat && isNotBinned && hasRequiredFrameRate
            }
        }.sorted { $0.formatDescription.dimensions.width > $1.formatDescription.dimensions.width }
        return fallbackFormats.first
    }
    
    private func findBestDepthFormat(for format: AVCaptureDevice.Format) -> AVCaptureDevice.Format? {
        return format.supportedDepthDataFormats.first { depthFormat in
            depthFormat.formatDescription.mediaSubType.rawValue == kCVPixelFormatType_DepthFloat16
        }
    }
}

extension CameraControllerUI: AVCaptureDataOutputSynchronizerDelegate {
    func dataOutputSynchronizer(_ synchronizer: AVCaptureDataOutputSynchronizer,
                                didOutput synchronizedDataCollection: AVCaptureSynchronizedDataCollection) {
        // Only process depth data if LiDAR is available
        guard hasLiDARSupport,
              let syncedDepthData = synchronizedDataCollection.synchronizedData(for: depthDataOutput!) as? AVCaptureSynchronizedDepthData,
              let syncedVideoData = synchronizedDataCollection.synchronizedData(for: videoDataOutput) as? AVCaptureSynchronizedSampleBufferData else { return }
        
        guard let pixelBuffer = syncedVideoData.sampleBuffer.imageBuffer,
              let cameraCalibrationData = syncedDepthData.depthData.cameraCalibrationData else { return }
        
        let colorImage = generateUIImage(from: pixelBuffer)
        let pts = CMSampleBufferGetPresentationTimeStamp(syncedVideoData.sampleBuffer)

        // Convert the depth data to the expected format.
        let convertedDepth = syncedDepthData.depthData.converting(toDepthDataType: kCVPixelFormatType_DepthFloat16)
       
       // Package the captured data.
        let data = FrameDataModel(depth: convertedDepth.depthDataMap.texture(withFormat: .r16Float, planeIndex: 0, addToCache: textureCache),
                                  colorY: pixelBuffer.texture(withFormat: .r8Unorm, planeIndex: 0, addToCache: textureCache),
                                  colorCbCr: pixelBuffer.texture(withFormat: .rg8Unorm, planeIndex: 1, addToCache: textureCache),
                                  cameraIntrinsics: cameraCalibrationData.intrinsicMatrix,
                                  cameraReferenceDimensions: cameraCalibrationData.intrinsicMatrixReferenceDimensions,
                                  originalDepth: syncedDepthData.depthData,
                                  colorImage: colorImage)
    

        delegate?.onNewBasicData(capturedData: data, pixelBuffer: pixelBuffer, pts: pts)
        
        
    
        if let assetWriter = assetWriter, assetWriter.status == .writing {
            if let videoInput = assetWriter.inputs.first,
               let depthInput = assetWriter.inputs.last,
               videoInput.isReadyForMoreMediaData && depthInput.isReadyForMoreMediaData {
                
                videoInput.append(syncedVideoData.sampleBuffer)
                
                // Convert the depth data to a suitable format for writing
                let depthDataMap = syncedDepthData.depthData.depthDataMap
                let depthWidth = CVPixelBufferGetWidth(depthDataMap)
                let depthHeight = CVPixelBufferGetHeight(depthDataMap)
                let depthFormat = kCVPixelFormatType_DepthFloat32
                
                var depthPixelBuffer: CVPixelBuffer?
                CVPixelBufferCreate(kCFAllocatorDefault, depthWidth, depthHeight, depthFormat, nil, &depthPixelBuffer)
                
                if let depthPixelBuffer = depthPixelBuffer {
                    CVPixelBufferLockBaseAddress(depthPixelBuffer, [])
                    let depthPtr = CVPixelBufferGetBaseAddress(depthPixelBuffer)
                    let depthSize = CVPixelBufferGetDataSize(depthDataMap)
                    memcpy(depthPtr, CVPixelBufferGetBaseAddress(depthDataMap), depthSize)
                    CVPixelBufferUnlockBaseAddress(depthPixelBuffer, [])
                    
                    let depthSampleBuffer = createSampleBuffer(from: depthPixelBuffer, timestamp: syncedDepthData.timestamp)
                    depthInput.append(depthSampleBuffer)
                }
            }
        }
    }
    
    private func setupLiDARInput(frameRate: CameraConfiguration.FrameRate) throws {
        guard let device = AVCaptureDevice.default(.builtInLiDARDepthCamera, for: .video, position: currentCameraPosition) else {
            throw ConfigurationError.lidarDeviceUnavailable
        }
        
        // Find format matching our resolution and frame rate requirements
        guard let format = findBestFormat(for: device, resolution: currentResolution, frameRate: frameRate) else {
            throw ConfigurationError.requiredFormatUnavailable
        }
        
        // Find depth format
        guard let depthFormat = findBestDepthFormat(for: format) else {
            throw ConfigurationError.requiredFormatUnavailable
        }
        
        // Configure device
        try device.lockForConfiguration()
        device.activeFormat = format
        device.activeDepthDataFormat = depthFormat
        
        // Set frame rate
        let frameDuration = CMTimeMake(value: 1, timescale: CMTimeScale(frameRate.rawValue))
        device.activeVideoMinFrameDuration = frameDuration
        device.activeVideoMaxFrameDuration = frameDuration
        
        device.unlockForConfiguration()
        
        log("Selected video format: \(device.activeFormat)", level: .info)
        log("Selected depth format: \(String(describing: device.activeDepthDataFormat))", level: .info)
        log("Set frame rate to: \(frameRate.rawValue) FPS", level: .info)
        
        // Add device input
        let deviceInput = try AVCaptureDeviceInput(device: device)
        if captureSession.canAddInput(deviceInput) {
            captureSession.addInput(deviceInput)
        } else {
            throw ConfigurationError.sessionConfigurationFailed
        }
    }
    
    private func setupLiDAROutputs() {
        log("Setting up LiDAR capture outputs...", level: .info)
        
        // Video output
        videoDataOutput = AVCaptureVideoDataOutput()
        if captureSession.canAddOutput(videoDataOutput) {
            captureSession.addOutput(videoDataOutput)
            log("Successfully added video data output", level: .info)
        } else {
            log("Failed to add video data output", level: .error)
        }
        
        // Depth output
        depthDataOutput = AVCaptureDepthDataOutput()
        depthDataOutput?.isFilteringEnabled = isFilteringEnabled
        
        if let depthOutput = depthDataOutput, captureSession.canAddOutput(depthOutput) {
            captureSession.addOutput(depthOutput)
            log("Successfully added depth data output", level: .info)
        } else {
            log("Failed to add depth data output", level: .error)
        }
        
        // Synchronizer
        if let depthOutput = depthDataOutput {
            outputVideoSync = AVCaptureDataOutputSynchronizer(dataOutputs: [depthOutput, videoDataOutput])
            outputVideoSync?.setDelegate(self, queue: videoQueue)
            log("Setup data output synchronizer", level: .debug)
        }
        
        // Enable camera intrinsics
        if let outputConnection = videoDataOutput.connection(with: .video),
           outputConnection.isCameraIntrinsicMatrixDeliverySupported {
            outputConnection.isCameraIntrinsicMatrixDeliveryEnabled = true
        }
    }
    
    private func createSampleBuffer(from pixelBuffer: CVPixelBuffer, timestamp: CMTime) -> CMSampleBuffer {
        var sampleBuffer: CMSampleBuffer?
        var timingInfo = CMSampleTimingInfo(duration: .invalid, presentationTimeStamp: timestamp, decodeTimeStamp: .invalid)
        
        var formatDescription: CMFormatDescription?
        CMVideoFormatDescriptionCreateForImageBuffer(allocator: kCFAllocatorDefault,
                                                     imageBuffer: pixelBuffer,
                                                     formatDescriptionOut: &formatDescription)
        
        CMSampleBufferCreateForImageBuffer(allocator: kCFAllocatorDefault,
                                           imageBuffer: pixelBuffer,
                                           dataReady: true,
                                           makeDataReadyCallback: nil,
                                           refcon: nil,
                                           formatDescription: formatDescription!,
                                           sampleTiming: &timingInfo,
                                           sampleBufferOut: &sampleBuffer)
        
        return sampleBuffer!
    }
}

// MARK: - Basic Camera Stuff
extension CameraControllerUI {
    func captureOutput(_ output: AVCaptureOutput, didOutput sampleBuffer: CMSampleBuffer, from connection: AVCaptureConnection) {
        // Handle basic camera output (non-LiDAR)
        guard !isUsingLiDAR,
              let pixelBuffer = sampleBuffer.imageBuffer else { return }
        
        // Get presentation timestamp
        let pts = CMSampleBufferGetPresentationTimeStamp(sampleBuffer)
        
        // Get camera intrinsics from sample buffer if available
        var cameraIntrinsics = matrix_float3x3()
        let cameraReferenceDimensions = CGSize(
            width: CGFloat(CVPixelBufferGetWidth(pixelBuffer)),
            height: CGFloat(CVPixelBufferGetHeight(pixelBuffer))
        )
        
        if let cameraIntrinsicMatrix = CMGetAttachment(sampleBuffer, key: kCMSampleBufferAttachmentKey_CameraIntrinsicMatrix, attachmentModeOut: nil) as? Data {
            let matrixSize = MemoryLayout<matrix_float3x3>.size
            if cameraIntrinsicMatrix.count >= matrixSize {
                cameraIntrinsics = cameraIntrinsicMatrix.withUnsafeBytes { $0.load(as: matrix_float3x3.self) }
            }
        }
        
        // Create basic frame data without depth
        let data = FrameDataModel(
            cameraIntrinsics: cameraIntrinsics,
            cameraReferenceDimensions: cameraReferenceDimensions
        )
                
        // Determine current device orientation and map to rotation
        let rotation:UInt = {
            switch OrientationCache.shared.orientation {
            case .portrait: return 90
            case .landscapeRight: return 0
            case .landscapeLeft: return 180
            case .portraitUpsideDown: return 270
            }
        }()
        // Use Metal to convert NV12 -> BGRA with rotation
        let BGRAPixelBuffer = converter?.nv12ToBGRAPixelBuffer(nv12PixelBuffer: pixelBuffer, rotation: rotation)
        // Send to delegate
        delegate?.onNewBasicData(capturedData: data, pixelBuffer: BGRAPixelBuffer, pts: pts)
    }
    
    private func setupBasicCameraInternal(frameRate: CameraConfiguration.FrameRate) {
        log("Setting up basic camera...", level: .info)
        
        guard let device = AVCaptureDevice.default(.builtInWideAngleCamera, for: .video, position: currentCameraPosition) else {
            log("No suitable camera device found", level: .error)
            return
        }
        
        // Find best format for resolution and frame rate
        if let format = findBestFormat(for: device, resolution: currentResolution, frameRate: frameRate) {
            do {
                try device.lockForConfiguration()
                device.activeFormat = format

                // Set frame rate
                if device.activeFormat.videoSupportedFrameRateRanges[0].maxFrameRate >= Double(frameRate.rawValue) {
                    device.activeVideoMinFrameDuration = CMTime(value: 1, timescale: CMTimeScale(frameRate.rawValue))
                    device.activeVideoMaxFrameDuration = CMTime(value: 1, timescale: CMTimeScale(frameRate.rawValue))
                } else {
                    device.activeVideoMinFrameDuration = CMTime(value: 1, timescale: CMTimeScale(device.activeFormat.videoSupportedFrameRateRanges[0].maxFrameRate))
                    device.activeVideoMaxFrameDuration = CMTime(value: 1, timescale: CMTimeScale(device.activeFormat.videoSupportedFrameRateRanges[0].maxFrameRate))
                }
                
                // Set

                device.unlockForConfiguration()
                
                log("Set frame rate to: \(frameRate.rawValue) FPS", level: .info)
                log("Device active format: \(device.activeFormat)", level: .info)
            } catch {
                log("Failed to configure basic camera format: \(error)", level: .error)
            }
        }
        
        // Add device input
        do {
            let deviceInput = try AVCaptureDeviceInput(device: device)
            if captureSession.canAddInput(deviceInput) {
                captureSession.addInput(deviceInput)
                log("Successfully added basic camera input", level: .info)
            } else {
                log("Failed to add basic camera input", level: .error)
            }
        } catch {
            log("Failed to create basic camera input: \(error)", level: .error)
        }
        
        // Video output
        videoDataOutput = AVCaptureVideoDataOutput()
        videoDataOutput.setSampleBufferDelegate(self, queue: sessionQueue)
        
        if captureSession.canAddOutput(videoDataOutput) {
            captureSession.addOutput(videoDataOutput)
            log("Successfully added basic video output", level: .info)
            
            // Enable camera intrinsics for basic camera
            if let outputConnection = videoDataOutput.connection(with: .video),
               outputConnection.isCameraIntrinsicMatrixDeliverySupported {
                outputConnection.isCameraIntrinsicMatrixDeliveryEnabled = true
                log("Enabled camera intrinsics delivery for basic camera", level: .info)
            } else {
                log("Camera intrinsics delivery not supported for basic camera", level: .warn)
            }
        } else {
            log("Failed to add basic video output", level: .error)
        }
    }
}

// MARK: Photo Capture Delegate
extension CameraControllerUI: AVCapturePhotoCaptureDelegate {
    func generateUIImage(from pixelBuffer: CVPixelBuffer) -> UIImage? {
        let ciImage = CIImage(cvPixelBuffer: pixelBuffer)
        let context = CIContext(options: nil)
        guard let cgImage = context.createCGImage(ciImage, from: ciImage.extent) else {
            print("Failed to create CGImage from CIImage")
            return nil
        }
        return UIImage(cgImage: cgImage)
    }
}
