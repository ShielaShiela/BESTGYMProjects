//
//  CameraLiDARDepthController.swift
//  DataCaptureTest
//
//  Created by Shiela Cabahug on 2024/7/4.
//

/*
See LICENSE folder for this sample’s licensing information.

Abstract:
An object that configures and manages the capture pipeline to stream video and LiDAR depth data.
*/

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
    func onNewData(capturedData: CameraCapturedData)
    func onNewPhotoData(capturedData: CameraCapturedData)
}

class CameraLiDARDepthControllerUI: NSObject, ObservableObject, AVCaptureVideoDataOutputSampleBufferDelegate {
    
    enum ConfigurationError: Error {
        case lidarDeviceUnavailable
        case requiredFormatUnavailable
    }
    
    private var assetWriter: AVAssetWriter?
    private var isRecording = false
    
    
    private let preferredWidthResolution = 1920
    
    private let videoQueue = DispatchQueue(label: "com.example.apple-samplecode.VideoQueue", qos: .userInteractive)
    
    private(set) var captureSession: AVCaptureSession!
    
    private var photoOutput: AVCapturePhotoOutput!
    private var depthDataOutput: AVCaptureDepthDataOutput?
    private var videoDataOutput: AVCaptureVideoDataOutput!
    private var outputVideoSync: AVCaptureDataOutputSynchronizer?
    
    private var textureCache: CVMetalTextureCache!
    private var filterMode = false
    private var hasLiDARSupport = false



    weak var delegate: CaptureDataReceiver?
    
    var isFilteringEnabled = true {
        didSet {
            depthDataOutput?.isFilteringEnabled = isFilteringEnabled
            filterMode = isFilteringEnabled
        }
    }
    
    /**new new**/

    private var recordingStartTime: Date?
    private var recordingFolder: URL?
    private var frameCount: Int = 0
    private let sessionQueue = DispatchQueue(label: "com.example.apple-samplecode.SessionQueue", qos: .userInteractive)
    
    override init() {
        // Create a texture cache to hold sample buffer textures.
        CVMetalTextureCacheCreate(kCFAllocatorDefault,
                                  nil,
                                  MetalEnvironment.shared.metalDevice,
                                  nil,
                                  &textureCache)
        
        super.init()
        
        do {
            try setupSession()
        } catch {
            log("Unable to configure the capture session: \(error)", level: .error)
            setupBasicCamera()
        }
    }
    
    private func setupSession() throws {
        captureSession = AVCaptureSession()
        captureSession.sessionPreset = .inputPriority

        // Configure the capture session.
        captureSession.beginConfiguration()
        
        do {
            try setupCaptureInput()
            setupCaptureOutputs()
            hasLiDARSupport = true
        } catch ConfigurationError.lidarDeviceUnavailable {
            log("LiDAR not available, falling back to basic camera", level: .info)
            setupBasicCamera()
            hasLiDARSupport = false
        } catch {
            throw error
        }
        
        // Finalize capture session configuration.
        captureSession.commitConfiguration()
    }
    
    private func setupCaptureInput() throws {
        // First try to look up the LiDAR camera
        if let device = AVCaptureDevice.default(.builtInLiDARDepthCamera, for: .video, position: .back) {
            // Find a match that outputs video data in the format the app's custom Metal views require.
            guard let format = (device.formats.last { format in
                format.formatDescription.dimensions.width == preferredWidthResolution &&
                format.formatDescription.mediaSubType.rawValue == kCVPixelFormatType_420YpCbCr8BiPlanarFullRange &&
                !format.isVideoBinned &&
                !format.supportedDepthDataFormats.isEmpty
            }) else {
                throw ConfigurationError.requiredFormatUnavailable
            }
            
            // Find a match that outputs depth data in the format the app's custom Metal views require.
            guard let depthFormat = (format.supportedDepthDataFormats.last { depthFormat in
                depthFormat.formatDescription.mediaSubType.rawValue == kCVPixelFormatType_DepthFloat16
            }) else {
                throw ConfigurationError.requiredFormatUnavailable
            }
            
            // Begin the device configuration.
            try device.lockForConfiguration()

            // Configure the device and depth formats.
            device.activeFormat = format
            device.activeDepthDataFormat = depthFormat

            // Finish the device configuration.
            device.unlockForConfiguration()
            
            log("Selected video format: \(device.activeFormat)", level: .info)
            log("Selected depth format: \(String(describing: device.activeDepthDataFormat))", level: .info)
            
            // Add a device input to the capture session.
            let deviceInput = try AVCaptureDeviceInput(device: device)
            captureSession.addInput(deviceInput)
        } else {
            // If LiDAR is not available, throw the appropriate error
            throw ConfigurationError.lidarDeviceUnavailable
        }
    }
    
    private func setupCaptureOutputs() {
        log("Setting up capture outputs...", level: .info)
        
        // Create an object to output video sample buffers.
        videoDataOutput = AVCaptureVideoDataOutput()
//        captureSession.addOutput(videoDataOutput)
        
        if captureSession.canAddOutput(videoDataOutput) {
            captureSession.addOutput(videoDataOutput)
            log("Successfully added video data output", level: .info)
        } else {
            log("Failed to add video data output", level: .info)
        }
        
        // Only set up depth output if LiDAR is available
        if hasLiDARSupport {
            // Create an object to output depth data.
            depthDataOutput = AVCaptureDepthDataOutput()
            depthDataOutput?.isFilteringEnabled = isFilteringEnabled
//            captureSession.addOutput(depthDataOutput)
            if captureSession.canAddOutput(depthDataOutput!) {
                    captureSession.addOutput(depthDataOutput!)
                    log("Successfully added depth data output", level: .info)
                } else {
                    log("Failed to add depth data output", level: .info)
                }
            
            
            // Create an object to synchronize the delivery of depth and video data.
            outputVideoSync = AVCaptureDataOutputSynchronizer(dataOutputs: [depthDataOutput!, videoDataOutput])
            outputVideoSync?.setDelegate(self, queue: videoQueue)
            log("Setup data output synchronizer", level: .debug)

            // Enable camera intrinsics matrix delivery.
            guard let outputConnection = videoDataOutput.connection(with: .video) else { return }
            if outputConnection.isCameraIntrinsicMatrixDeliverySupported {
                outputConnection.isCameraIntrinsicMatrixDeliveryEnabled = true
            }
            
            if let connection = depthDataOutput!.connection(with: .depthData) {
            if connection.isEnabled {
                log("Depth data connection is enabled", level: .info)
            } else {
                log("Depth data connection is disabled", level: .info)
            }
            } else {
                log("No depth data connection available", level: .info)
            }
        }
        
        // Create an object to output photos.
        photoOutput = AVCapturePhotoOutput()
        photoOutput.maxPhotoQualityPrioritization = .quality
        captureSession.addOutput(photoOutput)

        // Only enable depth data delivery if LiDAR is available
        if hasLiDARSupport {
            photoOutput.isDepthDataDeliveryEnabled = true
        }
    }
    
    func startStream() {
        captureSession.startRunning()
        
    }
    
    func startStreamto(completion: @escaping (Bool, Error?) -> Void) {
        DispatchQueue.global(qos: .userInitiated).async {
            if self.captureSession.isRunning {
                print("Capture session is already running")
                DispatchQueue.main.async {
                    completion(true, nil)
                }
                return
            }
            
            self.captureSession.startRunning()
            
            // Wait a bit to ensure the session has time to start
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
                if self.captureSession.isRunning {
                    print("Capture session started successfully")
                    completion(true, nil)
                } else {
                    print("Failed to start capture session")
                    completion(false, NSError(domain: "CaptureSessionError", code: 0, userInfo: [NSLocalizedDescriptionKey: "Failed to start capture session"]))
                }
            }
        }
    }
    func stopStream() {
        captureSession.stopRunning()
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
    
    func setupBasicCamera() {
        // Remove any existing inputs
        for input in captureSession.inputs {
            captureSession.removeInput(input)
        }
        
        // Add basic camera input
        guard let videoDevice = AVCaptureDevice.default(.builtInWideAngleCamera, for: .video, position: .back),
              let videoDeviceInput = try? AVCaptureDeviceInput(device: videoDevice) else {
            print("Could not create video device input!")
            return
        }
        
        if captureSession.canAddInput(videoDeviceInput) {
            captureSession.addInput(videoDeviceInput)
        }
        
        // Add basic video output
        let videoOutput = AVCaptureVideoDataOutput()
        videoOutput.setSampleBufferDelegate(self, queue: sessionQueue)
        
        if captureSession.canAddOutput(videoOutput) {
            captureSession.addOutput(videoOutput)
        }
    }
}

// MARK: Output Synchronizer Delegate
extension CameraLiDARDepthControllerUI: AVCaptureDataOutputSynchronizerDelegate {
    
    func dataOutputSynchronizer(_ synchronizer: AVCaptureDataOutputSynchronizer,
                                didOutput synchronizedDataCollection: AVCaptureSynchronizedDataCollection) {
        // Only process depth data if LiDAR is available
        guard hasLiDARSupport,
              let syncedDepthData = synchronizedDataCollection.synchronizedData(for: depthDataOutput!) as? AVCaptureSynchronizedDepthData,
              let syncedVideoData = synchronizedDataCollection.synchronizedData(for: videoDataOutput) as? AVCaptureSynchronizedSampleBufferData else { return }
//        print("Received data from synchronizer")
        
        
        guard let pixelBuffer = syncedVideoData.sampleBuffer.imageBuffer,
              let cameraCalibrationData = syncedDepthData.depthData.cameraCalibrationData else { return }
        
        let colorImage = generateUIImage(from: pixelBuffer)

        // Convert the depth data to the expected format.
       let convertedDepth = syncedDepthData.depthData.converting(toDepthDataType: kCVPixelFormatType_DepthFloat16)
       
       // Package the captured data.
       let data = CameraCapturedData(depth: convertedDepth.depthDataMap.texture(withFormat: .r16Float, planeIndex: 0, addToCache: textureCache),
                                     colorY: pixelBuffer.texture(withFormat: .r8Unorm, planeIndex: 0, addToCache: textureCache),
                                     colorCbCr: pixelBuffer.texture(withFormat: .rg8Unorm, planeIndex: 1, addToCache: textureCache),
                                     cameraIntrinsics: cameraCalibrationData.intrinsicMatrix,
                                     cameraReferenceDimensions: cameraCalibrationData.intrinsicMatrixReferenceDimensions,
                                     originalDepth: syncedDepthData.depthData,
                                     colorImage: colorImage)
        

        delegate?.onNewData(capturedData: data)
        
        
    
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
    
    private func createSampleBufferFromPixelBuffer(_ pixelBuffer: CVPixelBuffer, timestamp: CMTime) -> CMSampleBuffer {
        var sampleBuffer: CMSampleBuffer?
        var timingInfo = CMSampleTimingInfo(duration: .invalid, presentationTimeStamp: timestamp, decodeTimeStamp: .invalid)
        
        var formatDescription: CMFormatDescription?
        CMVideoFormatDescriptionCreateForImageBuffer(allocator: nil, imageBuffer: pixelBuffer, formatDescriptionOut: &formatDescription)
        
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

// MARK: Photo Capture Delegate
extension CameraLiDARDepthControllerUI: AVCapturePhotoCaptureDelegate {
    
    func capturePhoto() {
        var photoSettings: AVCapturePhotoSettings
        if  photoOutput.availablePhotoPixelFormatTypes.contains(kCVPixelFormatType_420YpCbCr8BiPlanarFullRange) {
            photoSettings = AVCapturePhotoSettings(format: [
                kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_420YpCbCr8BiPlanarFullRange
            ])
        } else {
            photoSettings = AVCapturePhotoSettings()
        }
        
        // Capture depth data with this photo capture.
        photoSettings.isDepthDataDeliveryEnabled = true
        photoOutput.capturePhoto(with: photoSettings, delegate: self)
    }
    
        
    func photoOutput(_ output: AVCapturePhotoOutput, didFinishProcessingPhoto photo: AVCapturePhoto, error: Error?) {
        
        // Retrieve the image and depth data.
        guard let pixelBuffer = photo.pixelBuffer,
              let depthData = photo.depthData,
              let cameraCalibrationData = depthData.cameraCalibrationData,
              let photoData = photo.fileDataRepresentation() else { return }
        
        stopStream()
        
        measureDepth(photo: photo)
        
        // Generate UIImage
        let colorImage = generateUIImage(from: pixelBuffer)
        
        if colorImage == nil {
                    print("Warning: Failed to generate UIImage")
                }

        
        // Convert the depth data to the expected format.
        let convertedDepth = depthData.converting(toDepthDataType: kCVPixelFormatType_DepthFloat16)
        
        let depthMap = convertedDepth.depthDataMap
        
        
        let width = CVPixelBufferGetWidth(pixelBuffer)
        let height = CVPixelBufferGetHeight(pixelBuffer)
        
        let depthWidth = CVPixelBufferGetWidth(depthMap)
        let depthHeight = CVPixelBufferGetHeight(depthMap)

        
        let centerX = width / 2
        let centerY = height / 2
        
        let scaleX = CGFloat(depthWidth) / CGFloat(width)
        let scaleY = CGFloat(depthHeight) / CGFloat(height)

        
        let alignedDepth = alignDepth(coor: (centerX, centerY), scaleX: scaleX, scaleY: scaleY)
        let depthX = alignedDepth.depthX
        let depthY = alignedDepth.depthY

        let depthValue = getDepth(depthMap: convertedDepth,coor: (centerX, centerY), depthX: depthX, depthY: depthY)
        
        //Mark the center pixel coordinate
        CVPixelBufferLockBaseAddress(pixelBuffer, CVPixelBufferLockFlags(rawValue: 0))
                
                let yPlaneBaseAddress = CVPixelBufferGetBaseAddressOfPlane(pixelBuffer, 0)
                let cbCrPlaneBaseAddress = CVPixelBufferGetBaseAddressOfPlane(pixelBuffer, 1)
                
                let yBytesPerRow = CVPixelBufferGetBytesPerRowOfPlane(pixelBuffer, 0)
                let cbCrBytesPerRow = CVPixelBufferGetBytesPerRowOfPlane(pixelBuffer, 1)
                
                // Mark the center pixel in the Y plane (luminance)
                for y in max(0, centerY - 5)..<min(CVPixelBufferGetHeightOfPlane(pixelBuffer, 0), centerY + 5) {
                    let pointer = yPlaneBaseAddress!.assumingMemoryBound(to: UInt8.self) + y * yBytesPerRow
                    for x in max(0, centerX - 5)..<min(CVPixelBufferGetWidthOfPlane(pixelBuffer, 0), centerX + 5) {
                        pointer[x] = 76  // Set luminance to white for marking
                    }
                }
                
                // Mark the center pixel in the CbCr plane (chrominance)
                for y in max(0, centerY / 2 - 2)..<min(CVPixelBufferGetHeightOfPlane(pixelBuffer, 1), centerY / 2 + 2) {
                    let pointer = cbCrPlaneBaseAddress!.assumingMemoryBound(to: UInt8.self) + y * cbCrBytesPerRow
                    for x in max(0, centerX / 2 - 2)..<min(CVPixelBufferGetWidthOfPlane(pixelBuffer, 1), centerX / 2 + 2) {
                        pointer[2 * x] = 84  // Cb value
                        pointer[2 * x + 1] = 255  // Cr value
                    }
                }
                
        CVPixelBufferUnlockBaseAddress(pixelBuffer, CVPixelBufferLockFlags(rawValue: 0))
         
        // Package the captured data.
        let data = CameraCapturedData(depth: convertedDepth.depthDataMap.texture(withFormat: .r16Float, planeIndex: 0, addToCache: textureCache),
                                      colorY: pixelBuffer.texture(withFormat: .r8Unorm, planeIndex: 0, addToCache: textureCache),
                                      colorCbCr: pixelBuffer.texture(withFormat: .rg8Unorm, planeIndex: 1, addToCache: textureCache),
                                      cameraIntrinsics: cameraCalibrationData.intrinsicMatrix,
                                      cameraReferenceDimensions: cameraCalibrationData.intrinsicMatrixReferenceDimensions,
                                      depthCenter: depthValue,
                                      originalDepth: depthData,
                                      colorImage: colorImage)
        
        delegate?.onNewPhotoData(capturedData: data)
        //detectCaptureContours(photo, depthData: depthData)
    }
    
    
    
    func alignDepth(coor: (x: Int, y: Int), scaleX: CGFloat, scaleY: CGFloat) -> (depthX: Int, depthY: Int) {
        let depthX = Int(CGFloat(coor.x) * scaleX)
        let depthY = Int(CGFloat(coor.y) * scaleY)
        // Assuming you want to return these values for now
        return (depthX, depthY)
    }
    
    func getDepthDataCorners(photo: AVCapturePhoto){
        
        // Retrieve the image and depth data.
        guard let pixelBuffer = photo.pixelBuffer,
              let depthData = photo.depthData else { return }
        
        // Convert the depth data to the expected format.
        let convertedDepth = depthData.converting(toDepthDataType: kCVPixelFormatType_DepthFloat16)
        
        
        let depthMap = convertedDepth.depthDataMap
        //        let photoPixelBuffer = photo.pixelBuffer!
        
        let width = CVPixelBufferGetWidth(pixelBuffer)
        let height = CVPixelBufferGetHeight(pixelBuffer)
        
        let depthWidth = CVPixelBufferGetWidth(depthMap)
        let depthHeight = CVPixelBufferGetHeight(depthMap)
        
        let scaleX = CGFloat(depthWidth) / CGFloat(width)
        let scaleY = CGFloat(depthHeight) / CGFloat(height)
        
        
        // Define an array of coordinates, where each coordinate is a tuple (x, y)
        var depthCoordinates: [(x: Int, y: Int)] = []
        
        depthCoordinates.append((x: width / 2, y: height / 2)) //center-center
        
        // Populate the array with example coordinates
        depthCoordinates.append((x: 0, y: 0)) //top-left
        depthCoordinates.append((x: width - 1, y: 0)) //top-right
        depthCoordinates.append((x: 0, y: height - 1)) //bottom-left
        depthCoordinates.append((x: width - 1, y: height - 1)) //bottom-right
        
        depthCoordinates.append((x: width / 2, y: 0)) //top-center
        depthCoordinates.append((x: width / 2, y: height - 1)) //bottom-center
        depthCoordinates.append((x: width - 1, y: height / 2)) //right-center
        depthCoordinates.append((x: 0, y: height / 2)) //left-center
        
        
        for coordinates in depthCoordinates {
            
            let alignedDepth = alignDepth(coor: coordinates, scaleX: scaleX, scaleY: scaleY)
            let depthX = alignedDepth.depthX
            let depthY = alignedDepth.depthY
            
            let depthValue = getDepth(depthMap: convertedDepth,coor: coordinates, depthX: depthX, depthY: depthY)
            
            print("Depth value at coordinates (\(coordinates.x), \(coordinates.y)): \(depthValue) meters")
            
            
        }
        
    }
    
    func getDepth(depthMap: AVDepthData,coor: (x: Int, y: Int), depthX : Int, depthY: Int ) -> (Float16){
        
        let depthMap = depthMap.depthDataMap
        CVPixelBufferLockBaseAddress(depthMap, .readOnly)
        let rowData = CVPixelBufferGetBaseAddress(depthMap)! + depthY * CVPixelBufferGetBytesPerRow(depthMap)
        let depthValue = rowData.assumingMemoryBound(to: Float16.self)[depthX]
        CVPixelBufferUnlockBaseAddress(depthMap, .readOnly)
        
        
        return depthValue
        
    }

    
    func measureDepth(photo: AVCapturePhoto){
        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
                self?.getDepthDataCorners(photo: photo)
            }
    }
    
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
