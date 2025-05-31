//
//  CameraLiDARManager.swift
//  DataCaptureTest
//
//  Created by Shiela Cabahug on 2024/7/4.
//


import Foundation
import SwiftUI
import Combine
import simd
import AVFoundation
import Photos
import Metal
import MetalKit
import CoreGraphics


class CameraLiDARManager: ObservableObject, CaptureDataReceiver {
    
    var filter = true
    var capturedData: CameraCapturedData
    @Published var isFilteringDepth: Bool {
        didSet {
            controller.isFilteringEnabled = isFilteringDepth
            filter = isFilteringDepth
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
    
    @Published var tappedPoint: CGPoint?
    @Published var depthValue: Float?
    @Published var depthAtTappedPoint: Float16?
    
    @Published var currentViewMode: ViewMode = .color
    
    enum ViewMode {
        case color
        case depth
        case image
        case pointcloud
    }
    
    let controller: CameraLiDARDepthController
    var cancellables = Set<AnyCancellable>()
    var session: AVCaptureSession { controller.captureSession }
    
    
    private var assetWriter: AVAssetWriter?
    private var colorWriterInput: AVAssetWriterInput?
    private var depthWriterInput: AVAssetWriterInput?
    private var colorPixelBufferAdaptor: AVAssetWriterInputPixelBufferAdaptor?
    private var depthPixelBufferAdaptor: AVAssetWriterInputPixelBufferAdaptor?
    // Add these properties to your CameraLiDARManager class
    private var videoWriter: AVAssetWriter?
    private var videoWriterInput: AVAssetWriterInput?
    private var pixelBufferAdaptor: AVAssetWriterInputPixelBufferAdaptor?

    private let frameInterval: TimeInterval = 1.0 / 30.0 // 30 fps
    

    private var recordingStartTime: Date?
    private var recordingFolder: URL?
    private var frameCount: Int = 0
    @Published var currentFrameIndex: Int = 0
    @Published var totalFrames: Int = 0
    private var frameURLs: [URL] = []
    private var preloadedFrames: [Int: CameraCapturedData] = [:]
    private let preloadRange = 5 // Preload 5 frames ahead and behind
    @Published var isPlaying: Bool = false
    @Published var playbackTimer: Timer?
    @Published var sliderPosition: Double = 0
    
    
    private let recordingQueue = DispatchQueue(label: "com.yourapp.recordingQueue", qos: .userInitiated)
    private let processingQueue = DispatchQueue(label: "com.yourapp.processingQueue", qos: .userInteractive)
    private let sessionQueue = DispatchQueue(label: "com.bestgym.sessionQueue", qos: .userInitiated)
    
    
    // Stores the 2D image points where the user taps
    @Published var selectedImagePoints: [CGPoint] = []

    // Stores the computed 3D world coordinates corresponding to the selected image points
    @Published var selectedWorldPoints: [SIMD3<Float>] = []
    
    @Published var distanceMeasured: Float? = nil

//    @Published var annotatedPoints: [AnnotatedPoint] = []
    @Published var measuredDistance: Float?
    
    @Published var selectedPoints: [CGPoint] = []
    // Internal variables to store 3D points
    private var firstWorldPoint: SIMD3<Float>?
    private var secondWorldPoint: SIMD3<Float>?
    

    private var keypointData: [Int: [[String: Any]]] = [:] // Frame index -> keypoints
    private var keypointDataByFrame: [Int: [KeypointData]] = [:]
    private var processedImage: UIImage?
    
    private var processedImages: [Int: UIImage] = [:]
    
//    private var preloadedFrames: [Int: UIImage] = [:]
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

   


    // --- Data Storage for Playback ---
    private var lidarFrameURLs: [URL] = []        // Stores URLs for LiDAR frame folders/images
    private var videoFrames: [UIImage] = []     // Stores extracted frames for video files (Your approach)

    // Private storage
//    private var loadedRecordingMetadata: RecordingMetadata?

    // Public accessor property
    public var recordingMetadata: RecordingMetadata? {
        return loadedRecordingMetadata
    }
//    var videoFrames: [UIImage] = []
    init() {
        // Create an object to store the captured data for the views to present.
        capturedData = CameraCapturedData()
        
        // Check if LiDAR is available
        let discoverySession = AVCaptureDevice.DiscoverySession(
            deviceTypes: [.builtInLiDARDepthCamera],
            mediaType: .video,
            position: .back
        )
        useLiDAR = !discoverySession.devices.isEmpty
        
        // Initialize controller with appropriate configuration
        controller = CameraLiDARDepthController()
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
    
    
    
    func startPhotoCapture() {
        controller.capturePhoto()
        waitingForCapture = true
    }
    
    func onNewPhotoData(capturedData: CameraCapturedData) {
        // Because the views hold a reference to `capturedData`, the app updates each texture separately.
        self.capturedData.depth = capturedData.depth
        self.capturedData.colorY = capturedData.colorY
        self.capturedData.colorCbCr = capturedData.colorCbCr
        self.capturedData.cameraIntrinsics = capturedData.cameraIntrinsics
        self.capturedData.cameraReferenceDimensions = capturedData.cameraReferenceDimensions
        waitingForCapture = false
        processingCapturedResult = true
        self.capturedData.depthCenter = capturedData.depthCenter
        self.capturedData.originalDepth = capturedData.originalDepth
        self.capturedData.colorImage = capturedData.colorImage
    }
    
    // MARK: - Fix for the CameraLiDARManager onNewData method

    func onNewData(capturedData: CameraCapturedData) {
        // Always ensure we're on the main thread for @Published property updates
        if !Thread.isMainThread {
            DispatchQueue.main.async {
                self.onNewData(capturedData: capturedData)
            }
            return
        }
        
        // Update basic camera data
        self.capturedData.colorY = capturedData.colorY
        self.capturedData.colorCbCr = capturedData.colorCbCr
        self.capturedData.cameraIntrinsics = capturedData.cameraIntrinsics
        self.capturedData.cameraReferenceDimensions = capturedData.cameraReferenceDimensions
        self.capturedData.colorImage = capturedData.colorImage
        
        // Only update LiDAR-specific data if LiDAR is available
        if useLiDAR {
            self.capturedData.depth = capturedData.depth
            self.capturedData.depthCenter = capturedData.depthCenter
            self.capturedData.originalDepth = capturedData.originalDepth
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
            let width = Int(self.capturedData.cameraReferenceDimensions.width)
            let height = Int(self.capturedData.cameraReferenceDimensions.height)
            
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
    // MARK: - Improved pixelBufferFromImage method
    func pixelBufferFromImage(_ image: UIImage) -> CVPixelBuffer? {
        let width = Int(capturedData.cameraReferenceDimensions.width)
        let height = Int(capturedData.cameraReferenceDimensions.height)
        
        // Make sure we have valid dimensions
        guard width > 0 && height > 0 else {
            print("❌ Invalid dimensions for pixel buffer")
            return nil
        }
        
        // Create pixel buffer
        var pixelBuffer: CVPixelBuffer?
        let status = CVPixelBufferCreate(
            kCFAllocatorDefault,
            width,
            height,
            kCVPixelFormatType_32BGRA, // Try BGRA instead of ARGB
            [
                kCVPixelBufferCGImageCompatibilityKey: kCFBooleanTrue,
                kCVPixelBufferCGBitmapContextCompatibilityKey: kCFBooleanTrue
            ] as CFDictionary,
            &pixelBuffer
        )
        
        guard status == kCVReturnSuccess, let buffer = pixelBuffer else {
            print("❌ Failed to create pixel buffer: \(status)")
            return nil
        }
        
        // Lock buffer and get base address
        CVPixelBufferLockBaseAddress(buffer, [])
        defer { CVPixelBufferUnlockBaseAddress(buffer, []) }
        
        let baseAddress = CVPixelBufferGetBaseAddress(buffer)
        let bytesPerRow = CVPixelBufferGetBytesPerRow(buffer)
        
        // Create a CG context
        let colorSpace = CGColorSpaceCreateDeviceRGB()
        guard let context = CGContext(
            data: baseAddress,
            width: width,
            height: height,
            bitsPerComponent: 8,
            bytesPerRow: bytesPerRow,
            space: colorSpace,
            bitmapInfo: CGImageAlphaInfo.premultipliedFirst.rawValue | CGBitmapInfo.byteOrder32Little.rawValue
        ) else {
            print("❌ Failed to create context")
            return nil
        }
        
        // Draw the image
        context.clear(CGRect(x: 0, y: 0, width: width, height: height))
        
        // Scale the image to fit the context
        let drawRect = CGRect(x: 0, y: 0, width: width, height: height)
        
        if let cgImage = image.cgImage {
            // Draw using CGImage
            context.draw(cgImage, in: drawRect)
        } else {
            // Fallback to UIImage drawing
            UIGraphicsPushContext(context)
            image.draw(in: drawRect)
            UIGraphicsPopContext()
        }
        
        return buffer
    }

    
    

    func saveCapturedData(completion: @escaping (Bool) -> Void) {
        do {
            
            let documentDirectory = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first!
            try capturedData.saveCaptureData(to: documentDirectory,filter: controller.isFilteringEnabled)
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
                try self.capturedData.load(from: url, device: device)
                DispatchQueue.main.async {
                    self.dataAvailable = true
                    
//                    self.currentViewMode = .color  // Set default view mode
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
    
    func checkImageOrientation(_ image: UIImage) -> UIImage.Orientation {
        return image.imageOrientation
    }
    
    func alignDepth(coor: (x: Int, y: Int), scaleX: CGFloat, scaleY: CGFloat) -> (depthX: Int, depthY: Int) {
        let depthX = Int(CGFloat(coor.x) * scaleX)
        let depthY = Int(CGFloat(coor.y) * scaleY)
        // Assuming you want to return these values for now
        return (depthX, depthY)
    }
    
    
//    func processDepthForBlobs() {
//        guard let colorImage = self.capturedData.colorImage,
//              let depthTexture = self.capturedData.depth else {
//            print("No color image or depth data available")
//            return
//        }
//
//        let imageOrientation = colorImage.imageOrientation
//        let isLandscape = imageOrientation == .right || imageOrientation == .left
//
//        // If needed, rotate the image for blob detection
//        let orientedImage = orientImage(colorImage, orientation: imageOrientation)
//
//        guard let blobsDetected = OpenCVWrapper.detectBlobs(orientedImage) else {
//            print("No blobs detected")
//            return
//        }
//
//        let width = depthTexture.width
//        let height = depthTexture.height
//
//        var depthData = [Float16](repeating: 0, count: width * height)
//        depthTexture.getBytes(&depthData,
//                              bytesPerRow: width * MemoryLayout<Float16>.stride,
//                              from: MTLRegionMake2D(0, 0, width, height),
//                              mipmapLevel: 0)
//
//        let scaleX = CGFloat(width) / orientedImage.size.width
//        let scaleY = CGFloat(height) / orientedImage.size.height
//        var i = 0
//        for blobDict in blobsDetected {
//            guard var x = blobDict["x"] as? CGFloat,
//                  var y = blobDict["y"] as? CGFloat,
//                  let size = blobDict["size"] as? CGFloat else {
//                continue
//            }
//
//            // Adjust coordinates if the image was rotated
//            if isLandscape {
//                let temp = x
//                x = y
//                y = orientedImage.size.width - temp
//            }
//
//            let alignedDepth = alignDepth(coor: (Int(x), Int(y)), scaleX: scaleX, scaleY: scaleY)
//            let depthX = alignedDepth.depthX
//            let depthY = alignedDepth.depthY
//
//            // Use the loaded depth data
//            let depthValue = getDepthFromLoadedData(depthData: depthData, width: width, x: depthX, y: depthY)
//
//            print("Blob \(i) at (\(x), \(y)) with size \(size), depth: \(depthValue) meters")
//
//            i+=1
//        }
//    }
    
    func getDepthFromLoadedData(depthData: [Float16], width: Int, x: Int, y: Int) -> Float16 {
        let index = y * width + x
        guard index >= 0 && index < depthData.count else {
            print("Warning: Depth index out of bounds")
            return 0
        }
        return depthData[index]
    }
    
    func orientImage(_ image: UIImage, orientation: UIImage.Orientation) -> UIImage {
        if orientation == .up {
            return image
        }
        
        UIGraphicsBeginImageContextWithOptions(image.size, false, image.scale)
        defer { UIGraphicsEndImageContext() }
        
        let context = UIGraphicsGetCurrentContext()!
        context.translateBy(x: image.size.width / 2, y: image.size.height / 2)
        
        switch orientation {
        case .right, .rightMirrored:
            context.rotate(by: .pi / 2)
        case .left, .leftMirrored:
            context.rotate(by: -.pi / 2)
        case .down, .downMirrored:
            context.rotate(by: .pi)
        default:
            break
        }
        
        context.translateBy(x: -image.size.width / 2, y: -image.size.height / 2)
        image.draw(at: .zero)
        
        return UIGraphicsGetImageFromCurrentImageContext()!
    }
    
    func getDepthAdjustedForOrientation(depthMap: AVDepthData, x: Int, y: Int, orientation: UIImage.Orientation) -> Float16 {
        let depthWidth = CVPixelBufferGetWidth(depthMap.depthDataMap)
        let depthHeight = CVPixelBufferGetHeight(depthMap.depthDataMap)
        
        var adjustedX = x
        var adjustedY = y
        
        switch orientation {
        case .right, .rightMirrored:
            adjustedX = y
            adjustedY = depthWidth - 1 - x
        case .left, .leftMirrored:
            adjustedX = depthHeight - 1 - y
            adjustedY = x
        case .down, .downMirrored:
            adjustedX = depthWidth - 1 - x
            adjustedY = depthHeight - 1 - y
        default:
            break
        }
        
        return getDepth(depthMap: depthMap, coor: (adjustedX, adjustedY), depthX: adjustedX, depthY: adjustedY)
    }
    
    func getDepth(depthMap: AVDepthData,coor: (x: Int, y: Int), depthX : Int, depthY: Int ) -> (Float16){
        
        let depthMap = depthMap.depthDataMap
        CVPixelBufferLockBaseAddress(depthMap, .readOnly)
        let rowData = CVPixelBufferGetBaseAddress(depthMap)! + depthY * CVPixelBufferGetBytesPerRow(depthMap)
        let depthValue = rowData.assumingMemoryBound(to: Float16.self)[depthX]
        CVPixelBufferUnlockBaseAddress(depthMap, .readOnly)
        
        
        return depthValue
        
    }
   
    private func createUIImage(fromY yTexture: MTLTexture, CbCr cbcrTexture: MTLTexture) -> UIImage? {
        let width = yTexture.width
        let height = yTexture.height
        
        // Create a color space
        let colorSpace = CGColorSpaceCreateDeviceRGB()
        
        // Create a CIImage from the Y texture
        guard let ciImageY = CIImage(mtlTexture: yTexture, options: [CIImageOption.colorSpace: colorSpace]) else {
            print("Failed to create CIImage from Y texture")
            return nil
        }
        
        // Create a CIImage from the CbCr texture
        guard let ciImageCbCr = CIImage(mtlTexture: cbcrTexture, options: [CIImageOption.colorSpace: colorSpace]) else {
            print("Failed to create CIImage from CbCr texture")
            return nil
        }
        
        // Create a CIFilter to combine Y and CbCr
        guard let filter = CIFilter(name: "CIColorCubesMixedWithMask") else {
            print("Failed to create CIColorCubesMixedWithMask filter")
            return nil
        }
        
        filter.setValue(ciImageY, forKey: "inputImage")
        filter.setValue(ciImageCbCr, forKey: "inputMask")
        
        // Get the output CIImage
        guard let outputImage = filter.outputImage else {
            print("Failed to get output image from filter")
            return nil
        }
        
        // Create a CIContext
        let context = CIContext(options: nil)
        
        // Create a CGImage from the CIImage
        guard let cgImage = context.createCGImage(outputImage, from: outputImage.extent) else {
            print("Failed to create CGImage from CIImage")
            return nil
        }
        
        // Create and return a UIImage
        return UIImage(cgImage: cgImage)
    }
//    func loadVideoFolder(from url: URL) {
//        frameURLs.removeAll()
//        currentFrameIndex = 0
//
//        if let enumerator = FileManager.default.enumerator(at: url, includingPropertiesForKeys: [.isDirectoryKey], options: [.skipsHiddenFiles]) {
//            for case let fileURL as URL in enumerator {
//                if fileURL.lastPathComponent.hasPrefix("frame_") {
//                    frameURLs.append(fileURL)
//                }
//            }
//        }
//
//        // Sort the frame URLs based on their numeric suffix
//        frameURLs.sort { (url1, url2) -> Bool in
//            let number1 = extractFrameNumber(from: url1.lastPathComponent)
//            let number2 = extractFrameNumber(from: url2.lastPathComponent)
//            return number1 < number2
//        }
//
//        totalFrames = frameURLs.count
//
//        if !frameURLs.isEmpty {
//            loadFrame(at: 0)
//        }
//    }
    
    // Adapted from your `loadVideoFolder` logic
    // Inside class CameraLiDARManager...

    
    
    private func createTexture(from data: Data, pixelFormat: MTLPixelFormat, device: MTLDevice) throws -> MTLTexture {
        let width = Int(sqrt(Double(data.count / MemoryLayout<Float16>.size)))
        let height = width
        
        let textureDescriptor = MTLTextureDescriptor.texture2DDescriptor(pixelFormat: pixelFormat, width: width, height: height, mipmapped: false)
        textureDescriptor.usage = [.shaderRead, .shaderWrite]
        
        guard let texture = device.makeTexture(descriptor: textureDescriptor) else {
            throw NSError(domain: "CameraLiDARManager", code: 2, userInfo: [NSLocalizedDescriptionKey: "Failed to create texture"])
        }
        
        let region = MTLRegionMake2D(0, 0, width, height)
        texture.replace(region: region, mipmapLevel: 0, withBytes: [UInt8](data), bytesPerRow: width * MemoryLayout<Float16>.size)
        
        return texture
    }

    private func arrayToMatrix(_ array: [[Double]]) -> matrix_float3x3 {
        return matrix_float3x3(columns: (
            SIMD3<Float>(Float(array[0][0]), Float(array[0][1]), Float(array[0][2])),
            SIMD3<Float>(Float(array[1][0]), Float(array[1][1]), Float(array[1][2])),
            SIMD3<Float>(Float(array[2][0]), Float(array[2][1]), Float(array[2][2]))
        ))
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
            try self.capturedData.load(from: frameURL, device: MTLCreateSystemDefaultDevice()!)
            currentFrameIndex = index
            isDataLoaded = true
            
            // Load processed image if available
            if let processedImage = processedImages[index] {
                capturedData.processedImage = processedImage
                print("Loaded processed image for frame \(index)")
            } else {
                // Only clear processed image if we're not retaining them
                capturedData.processedImage = nil
            }
            
            // Apply orientation correction to the colorImage if available
            if let colorImage = capturedData.colorImage {
                capturedData.colorImage = applyCorrectOrientation(to: colorImage)
                print("Applied orientation correction to frame \(index)")
            }
            
            print("Successfully loaded frame \(index)")
        } catch {
            print("Error loading frame at index \(index): \(error)")
            isDataLoaded = false
        }
    }
    
    func reloadCurrentFrame() {
            // Only proceed if we have valid frame URLs
            guard !frameURLs.isEmpty && currentFrameIndex < frameURLs.count else {
                print("Cannot reload frame: No valid frame URLs available")
                return
            }
            
            // Force reload the current frame using the existing loadFrame method
            loadFrame(at: currentFrameIndex)
            print("Explicitly reloaded frame at index \(currentFrameIndex)")
        }
//
//    func startPlayback() {
//        stopPlayback()
//        playbackTimer = Timer.scheduledTimer(withTimeInterval: 1.0/30.0, repeats: true) { [weak self] _ in
//            self?.nextFrame()
//
//        }
//        isPlaying = true
//    }
//
//    func stopPlayback() {
//        playbackTimer?.invalidate()
//        playbackTimer = nil
//
//        isPlaying = false
//    }
    
    // In CameraLiDARManager
    
    
    
    func getDepth(at imagePoint: CGPoint) -> Float? {
        guard let depthTexture = self.capturedData.depth else {
            return nil
        }

        let depthWidth = depthTexture.width
        let depthHeight = depthTexture.height
        let imageSize = self.capturedData.colorImage?.size ?? CGSize(width: depthWidth, height: depthHeight)

        // Map imagePoint to depth data coordinates
        let depthX = Int(imagePoint.x / imageSize.width * CGFloat(depthWidth))
        let depthY = Int(imagePoint.y / imageSize.height * CGFloat(depthHeight))

        if depthX < 0 || depthX >= depthWidth || depthY < 0 || depthY >= depthHeight {
            return nil
        }

        var depthValue: Float16 = 0.0
        let region = MTLRegionMake2D(depthX, depthY, 1, 1)
        depthTexture.getBytes(&depthValue, bytesPerRow: MemoryLayout<Float16>.size, from: region, mipmapLevel: 0)

        return Float(depthValue)
    }



    func calculate3DPoint(from imagePoint: CGPoint, depthValue: Float) -> SIMD3<Float>? {
        let intrinsics = self.capturedData.cameraIntrinsics

        // Adjust intrinsics for image size differences
        let referenceSize = self.capturedData.cameraReferenceDimensions
        let imageSize = self.capturedData.colorImage?.size ?? referenceSize

        let scaleX = Float(imageSize.width / referenceSize.width)
        let scaleY = Float(imageSize.height / referenceSize.height)

        let fx = intrinsics.columns.0.x * scaleX
        let fy = intrinsics.columns.1.y * scaleY
        let cx = intrinsics.columns.2.x * scaleX
        let cy = intrinsics.columns.2.y * scaleY

        let x = Float(imagePoint.x)
        let y = Float(imagePoint.y)

        // Compute normalized image coordinates
        let X = (x - cx) * depthValue / fx
        let Y = (y - cy) * depthValue / fy
        let Z = depthValue

        return SIMD3<Float>(X, Y, Z)
    }
    
    // Helper to load raw image from file (used in LiDAR playback)
    private func loadImageFromFile(url: URL) -> UIImage? {
        guard let data = try? Data(contentsOf: url), let image = UIImage(data: data) else {
            print("❌ Failed to load image from \(url.path)")
            return nil
        }
        return image
    }

    // MARK: - Metadata Handling

   

    
    // In CameraLiDARManager

    func calculateDistanceBetweenPoints(point1: SIMD3<Float>, point2: SIMD3<Float>) -> Float {
        return length(point1 - point2)
    }

    func storeKeypointData(_ data: [[String: Any]]) {
        keypointData[currentFrameIndex] = data
        print("Stored keypoint data for frame \(currentFrameIndex): \(data.count) keypoints")
    }

    func updateDisplayImage(_ image: UIImage) {
        capturedData.processedImage = image
    }


    func stopCameraCapture() {
        controller.stopStream()
    }
}
    
extension CGImage {
    func toPixelBuffer(width: Int, height: Int) -> CVPixelBuffer? {
        var pixelBuffer: CVPixelBuffer?
        let attributes = [kCVPixelBufferCGImageCompatibilityKey: kCFBooleanTrue,
                          kCVPixelBufferCGBitmapContextCompatibilityKey: kCFBooleanTrue] as CFDictionary
        CVPixelBufferCreate(kCFAllocatorDefault, width, height, kCVPixelFormatType_32ARGB, attributes, &pixelBuffer)

        if let pixelBuffer = pixelBuffer {
            CVPixelBufferLockBaseAddress(pixelBuffer, CVPixelBufferLockFlags(rawValue: 0))
            let colorSpace = CGColorSpaceCreateDeviceRGB()
            let context = CGContext(data: CVPixelBufferGetBaseAddress(pixelBuffer),
                                    width: width,
                                    height: height,
                                    bitsPerComponent: 8,
                                    bytesPerRow: CVPixelBufferGetBytesPerRow(pixelBuffer),
                                    space: colorSpace,
                                    bitmapInfo: CGImageAlphaInfo.noneSkipFirst.rawValue)
            context?.draw(self, in: CGRect(x: 0, y: 0, width: width, height: height))
            CVPixelBufferUnlockBaseAddress(pixelBuffer, CVPixelBufferLockFlags(rawValue: 0))
            return pixelBuffer
        }
        return nil
    }
}

extension MTLTexture {
    func toPixelBuffer() -> CVPixelBuffer? {
        var pixelBuffer: CVPixelBuffer?
        let attributes = [kCVPixelBufferCGImageCompatibilityKey: kCFBooleanTrue,
                          kCVPixelBufferCGBitmapContextCompatibilityKey: kCFBooleanTrue] as CFDictionary
        CVPixelBufferCreate(kCFAllocatorDefault, width, height, kCVPixelFormatType_32BGRA, attributes, &pixelBuffer)

        if let pixelBuffer = pixelBuffer {
            CVPixelBufferLockBaseAddress(pixelBuffer, CVPixelBufferLockFlags(rawValue: 0))
            let pixelData = CVPixelBufferGetBaseAddress(pixelBuffer)

            let region = MTLRegionMake2D(0, 0, width, height)
            self.getBytes(pixelData!, bytesPerRow: CVPixelBufferGetBytesPerRow(pixelBuffer), from: region, mipmapLevel: 0)

            CVPixelBufferUnlockBaseAddress(pixelBuffer, CVPixelBufferLockFlags(rawValue: 0))
            return pixelBuffer
        }
        return nil
    }
    
    func getPixelValues<T>() -> [T] {
        let width = self.width
        let height = self.height
        let bytesPerRow = width * MemoryLayout<T>.stride
        let size = height * bytesPerRow
        var bytes = [UInt8](repeating: 0, count: size)
        
        getBytes(&bytes, bytesPerRow: bytesPerRow, from: MTLRegionMake2D(0, 0, width, height), mipmapLevel: 0)
        
        return bytes.withUnsafeBytes { buffer in
            Array(buffer.bindMemory(to: T.self))
        }
    }
}



extension CameraLiDARManager {
    func addSelectedPoint(_ imagePoint: CGPoint) {
        print("addSelectedPoint called with imagePoint: \(imagePoint)")

        // Compute the 3D point
        guard let depthValue = getDepth(at: imagePoint) else {
            print("Depth data unavailable at this point.")
            return
        }

        guard let worldPoint = calculate3DPoint(from: imagePoint, depthValue: depthValue) else {
            print("Failed to compute 3D point.")
            return
        }

        DispatchQueue.main.async {
            if self.selectedPoints.count < 2 {
                self.selectedPoints.append(imagePoint)
            } else {
                // Reset if two points are already selected
                self.selectedPoints = [imagePoint]
                self.measuredDistance = nil
                self.firstWorldPoint = nil
                self.secondWorldPoint = nil
            }
            print("selectedPoints updated: \(self.selectedPoints)")

            // Store world points internally
            if self.selectedPoints.count == 1 {
                self.firstWorldPoint = worldPoint
            } else if self.selectedPoints.count == 2 {
                self.secondWorldPoint = worldPoint

                if let distance = self.computeDistanceBetween(self.firstWorldPoint, and: self.secondWorldPoint) {
                    self.measuredDistance = distance
                    print("Measured distance: \(distance)")
                }
            }
        }
    }

    private func computeDistanceBetween(_ point1: SIMD3<Float>?, and point2: SIMD3<Float>?) -> Float? {
            guard let p1 = point1, let p2 = point2 else { return nil }
            return simd_distance(p1, p2)
        }
}


extension CameraLiDARManager {
 
    
    // Function to preload frames in a sliding window
    func preloadFramesAroundIndex(_ currentIndex: Int) {
        // Define the window of frames to keep loaded
        let framesToKeep = (currentIndex - preloadWindowSize)...(currentIndex + preloadWindowSize)
        
        // Convert to Set for easier operations
        let framesToKeepSet = Set(framesToKeep.filter { $0 >= 0 && $0 < totalFrames })
        
        // Find frames that need to be preloaded (in window but not yet loaded)
        let framesToPreload = framesToKeepSet.subtracting(preloadedFrameIndices)
        
        // Preload frames we don't already have
        for frameIndex in framesToPreload {
            // Preload this frame in the background
            DispatchQueue.global(qos: .userInitiated).async { [weak self] in
                guard let self = self else { return }
                
                // Only proceed if this frame is still within our window
                // (in case user has moved far away by now)
                if abs(frameIndex - self.currentFrameIndex) <= self.preloadWindowSize {
                    // Temporary CameraCapturedData instance for preloading
                    let tempData = CameraCapturedData()
                    
                    if frameIndex < self.frameURLs.count {
                        let frameURL = self.frameURLs[frameIndex]
                        
                        do {
                            // Load frame data into temporary object
                            if let device = MTLCreateSystemDefaultDevice() {
                                try tempData.load(from: frameURL, device: device)
                                
                                // Store in cache (could use a dictionary if you need the actual data)
                                DispatchQueue.main.async {
                                    self.preloadedFrameIndices.insert(frameIndex)
                                    print("✅ Preloaded frame \(frameIndex)")
                                }
                            }
                        } catch {
                            print("❌ Error preloading frame \(frameIndex): \(error)")
                        }
                    }
                }
            }
        }
        
        // Optionally, clear frames far outside our window to save memory
        // This could be implemented if memory usage becomes an issue
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
        if let colorImage = capturedData.colorImage {
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
              let depthTexture = self.capturedData.depth else {
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
    func loadVideoFrames(frames: [UIImage]) {
        // Clear existing data
        self.capturedData = CameraCapturedData()
        self.videoFrames = frames
        
        // Set the first frame
        if !frames.isEmpty {
            self.currentFrameIndex = 0
            self.sliderPosition = 0
            self.totalFrames = frames.count
            self.capturedData.colorImage = frames[0]
        }
        
        // Mark data as available
        self.dataAvailable = true
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
        capturedData.colorImage = videoFrames[index]
        
        // Don't clear processedImage here - let the caller decide
        
        // Notify observers
        FrameUpdatePublisher.shared.notifyFrameChanged(frameIndex: currentFrameIndex)
    }
    
    // In CameraLiDARManager class

    // Add this method to your CameraLiDARManager class
//    func clearAllFrames() {
//        // Clear all stored frames
//        videoFrames = []
//        frameURLs = []
//        totalFrames = 0
//        currentFrameIndex = 0
//        sliderPosition = 0
//        
//        // Reset current capture data
//        capturedData = CameraCapturedData()
//        
//        // Stop any ongoing playback
//        if isPlaying {
//            stopPlayback()
//        }
//        
//        // Reset other state as needed
//        dataAvailable = false
//        isDataLoaded = false
//        
//        // Clear cached data
//        preloadedFrames.removeAll()
//        keypointData.removeAll()
//        keypointDataByFrame.removeAll()
//        processedImages.removeAll()
//    }
    

    func loadVideoFolder(from url: URL) {
        print("➡️ Starting loadVideoFolder for URL: \(url.path)")

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

            // Load metadata
            print("   Loading metadata...")
            let metadata = self.loadMetadata(from: url)
                        
            // Update metadata on main thread
            DispatchQueue.main.async {
                self.loadedRecordingMetadata = metadata
                print("Loaded metadata with orientation: \(metadata?.deviceOrientation?.name ?? "unknown")")
            }
            
            print("   Finding frame directories...")
            
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
                
                print("   Found \(frameDirectories.count) frame directories.")
                
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
                        print("   ⚠️ No image found in \(frameDir.lastPathComponent)")
                    }
                }
                
                print("   Found \(imageURLs.count) frame images.")
                
                // Update state on main thread
                DispatchQueue.main.async {
                    self.lidarFrameImageURLs = imageURLs
                    self.lidarFrameURLs = frameDirectories  // Store frame directories not image URLs
                    self.totalFrames = imageURLs.count
                    
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
        // Clear any other caches (preloadedFrames, keypointData, etc.)
        // preloadedFrames.removeAll()
        // keypointData.removeAll()
        print("🔄 Playback state reset.")
    }

    /// Loads and parses the recording_metadata.json file.
    private func loadMetadata(from folderURL: URL) -> RecordingMetadata? {
        let metadataURL = folderURL.appendingPathComponent("recording_metadata.json")
        guard FileManager.default.fileExists(atPath: metadataURL.path) else {
            // It's okay if metadata doesn't exist, just return nil.
            return nil
        }
        do {
            let jsonData = try Data(contentsOf: metadataURL)
            let decoder = JSONDecoder()
            let metadata = try decoder.decode(RecordingMetadata.self, from: jsonData)
            return metadata
        } catch {
            print("❌ Error loading/parsing metadata from \(metadataURL.path): \(error)")
            return nil
        }
    }

    /// Extracts the numeric part of a frame folder/file name (e.g., "frame_123" -> 123).
    private func extractFrameNumber(from string: String) -> Int {
        return Int(string.components(separatedBy: CharacterSet.decimalDigits.inverted).joined()) ?? 0
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

    // Inside class CameraLiDARManager...

    /// Sets the current frame for playback, loads its image, applies orientation, and updates the UI.
    /// (This version is still a placeholder for the actual image loading/orientation part)
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

    // Update your setFrame method to include an emergency fix
//    func setFrame(to index: Int) {
//        // Check for live capture mode and fix it if needed
//        if isLiveCapture {
//            print("⚠️ Emergency fix: isLiveCapture was true in setFrame")
//            isLiveCapture = false
//        }
//
//        // Rest of your setFrame implementation...
//    }


    // MARK: - Other Playback Helpers (Ensure these exist)
//    func stopPlayback() {
//        playbackTimer?.invalidate()
//        playbackTimer = nil
//        isPlaying = false
//    }

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

    // Add or update this method in your CameraLiDARManager class
    func loadVideoWithMetadata(videoURL: URL, completion: @escaping (Bool, Int, Error?) -> Void) {
        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            guard let self = self else {
                DispatchQueue.main.async {
                    completion(false, 0, NSError(domain: "CameraLiDARManager", code: -1, userInfo: [NSLocalizedDescriptionKey: "Self deallocated"]))
                }
                return
            }
            
            // Reset state first
            DispatchQueue.main.sync {
                self.pauseStream()
                self.resetPlaybackState()
                self.isLiveCapture = false
                self.loadedDataURL = videoURL
                self.isLoadedDataLiDAR = false
            }
            
            // First check for metadata in same folder
            let folderURL = videoURL.deletingLastPathComponent()
            let metadataURL = folderURL.appendingPathComponent("recording_metadata.json")
            
            print("Looking for metadata at: \(metadataURL.path)")
            
            if FileManager.default.fileExists(atPath: metadataURL.path) {
                do {
                    let data = try Data(contentsOf: metadataURL)
                    let metadata = try JSONDecoder().decode(RecordingMetadata.self, from: data)
                    
                    // Update metadata on main thread
                    DispatchQueue.main.async {
                        self.loadedRecordingMetadata = metadata
                        print("✅ Loaded recording metadata with orientation: \(metadata.deviceOrientation?.name ?? "unknown")")
                    }
                } catch {
                    print("⚠️ Found metadata file but failed to parse: \(error.localizedDescription)")
                    
                    // Set a default metadata with portrait orientation as fallback
                    DispatchQueue.main.async {
                        self.loadedRecordingMetadata = RecordingMetadata.defaultMetadata()
                    }
                }
            } else {
                print("⚠️ No metadata file found, will use default orientation")
                
                // Set a default metadata with portrait orientation as fallback
                DispatchQueue.main.async {
                    self.loadedRecordingMetadata = RecordingMetadata.defaultMetadata()
                }
            }
            
            // Now load the video file
            self.loadVideoFile(videoURL, completion: completion)
        }
    }

    // Update or add the applyCorrectOrientation method
    // This is a direct replacement for the applyCorrectOrientation method
    // with special handling for your specific case

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
        
//    func startPlayback() {
//        // Must run on main thread
//        if !Thread.isMainThread {
//            DispatchQueue.main.async {
//                self.startPlayback()
//            }
//            return
//        }
//
//        // Check if we can play
//        guard !isPlaying && totalFrames > 0 else {
//            print("⚠️ Cannot start playback: isPlaying=\(isPlaying), totalFrames=\(totalFrames)")
//            return
//        }
//
//        // Set flag
//        isPlaying = true
//        print("▶️ Starting playback from frame \(currentFrameIndex)")
//
//        // Create a repeating timer for playback
//        playbackTimer = Timer.scheduledTimer(withTimeInterval: 1.0/15.0, repeats: true) { [weak self] timer in
//            guard let self = self, self.isPlaying else {
//                timer.invalidate()
//                print("⏹️ Playback timer stopped")
//                return
//            }
//
//            // Log playback progress occasionally
//            if self.currentFrameIndex % 10 == 0 {
//                print("▶️ Playing frame \(self.currentFrameIndex)/\(self.totalFrames)")
//            }
//
//            // Move to next frame
//            let nextIndex = self.currentFrameIndex + 1
//
//            // Check if we've reached the end
//            if nextIndex >= self.totalFrames {
//                // Stop playback
//                timer.invalidate()
//                self.playbackTimer = nil
//                self.isPlaying = false
//                print("⏹️ Playback complete")
//                return
//            }
//
//            // Set the frame to the next index
//            self.setFrame(to: nextIndex)
//        }
//
//        // Make sure the timer is retained and fires even during scrolling
//        RunLoop.main.add(playbackTimer!, forMode: .common)
//    }

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
    
    // Add this to your CameraLiDARManager class
//    func forceFrameUpdate(to index: Int) {
//        // Always ensure we're not in live capture mode
//        if isLiveCapture {
//            print("⚠️ ForceFrameUpdate: Disabling live capture mode")
//            controller.stopStream()
//            isLiveCapture = false
//        }
//
//        // Verify index is valid
//        guard index >= 0 && index < totalFrames else {
//            print("❌ ForceFrameUpdate: Invalid frame index: \(index) (total: \(totalFrames))")
//            return
//        }
//
//        // Update current index and slider
//        currentFrameIndex = index
//        sliderPosition = Double(index)
//
//        // Force correct frame display
//        if isLoadedDataLiDAR {
//            // Load LiDAR frame from directory
//            if index < lidarFrameURLs.count {
//                let frameDir = lidarFrameURLs[index]
//                loadLiDARFrameDirectly(from: frameDir)
//            }
//        } else if index < videoFrames.count {
//            // Load from pre-extracted video frames
//            let orientedImage = applyCorrectOrientation(to: videoFrames[index])
//            currentFrameImage = orientedImage
//            onFrameChange?(index)
//        }
//
//        print("✅ Frame updated to \(index)")
//    }
    
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

    // Helper to load LiDAR frame directly (avoid the background thread)
    private func loadLiDARFrameDirectly(from frameDir: URL) {
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
            DispatchQueue.main.async { self.currentFrameImage = nil }
            return
        }
        
        do {
            // Read the file data
            let imageData = try Data(contentsOf: imageURL)
            
            if let image = UIImage(data: imageData) {
                // Force immediate orientation correction
                let orientedImage = self.applyCorrectOrientation(to: image)
                self.currentFrameImage = orientedImage
                self.onFrameChange?(currentFrameIndex)
            } else {
                print("❌ Failed to create UIImage from data")
                self.currentFrameImage = nil
            }
        } catch {
            print("❌ Error loading image: \(error)")
            self.currentFrameImage = nil
        }
    }

}


//MARK:: All about Recording
extension CameraLiDARManager {
    
    func getCameraOrientation() -> UIDeviceOrientation {
        // Try to get orientation from the camera connection first
        if let connection = controller.captureSession.connections.first,
           connection.isVideoOrientationSupported {
            // Proper mapping of AVCaptureVideoOrientation to UIDeviceOrientation
            switch connection.videoOrientation {
            case .landscapeLeft:
                return .landscapeRight  // Camera and device orientations are opposite
            case .landscapeRight:
                return .landscapeLeft   // Camera and device orientations are opposite
            case .portraitUpsideDown:
                return .portraitUpsideDown
            case .portrait:
                return .portrait
            @unknown default:
                return .portrait
            }
        } else {
            // Fall back to device orientation
            let deviceOrientation = UIDevice.current.orientation
            if deviceOrientation == .faceUp || deviceOrientation == .faceDown || deviceOrientation == .unknown {
                return .portrait  // Default to portrait for unusable orientations
            } else {
                return deviceOrientation
            }
        }
    }
    
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


    // Replace the current startRecording method
    // Add this method to CameraLiDARManager
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
    
    func correctImageOrientation(_ image: UIImage, orientation: UIDeviceOrientation) -> UIImage {
        // If the image doesn't have a CGImage, return the original
        guard let cgImage = image.cgImage else {
            return image
        }
        
        // If orientation is unknown or the device is face up/down, use portrait orientation
        let effectiveOrientation: UIDeviceOrientation
        if orientation == .unknown || orientation == .faceUp || orientation == .faceDown {
            effectiveOrientation = .portrait
        } else {
            effectiveOrientation = orientation
        }
        
        // Get the correct orientation based on device orientation
        var targetOrientation: UIImage.Orientation
        
        switch effectiveOrientation {
        case .portrait:
            targetOrientation = .right // Portrait mode requires 90° rotation
        case .portraitUpsideDown:
            targetOrientation = .left // Portrait upside down requires -90° rotation
        case .landscapeLeft:
            targetOrientation = .down // LandscapeLeft requires 180° rotation
        case .landscapeRight:
            targetOrientation = .up // LandscapeRight is the default camera orientation (0° rotation)
        default:
            targetOrientation = .up // Default for unknown orientations
        }
        
        // If the current orientation already matches the target, return the original
        if image.imageOrientation == targetOrientation {
            return image
        }
        
        // Create a new image with the target orientation
        return UIImage(cgImage: cgImage, scale: image.scale, orientation: targetOrientation)
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
                    width = Int(self.capturedData.cameraReferenceDimensions.width)
                    height = Int(self.capturedData.cameraReferenceDimensions.height)
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
            let width = capturedData.colorImage?.size.width ?? capturedData.cameraReferenceDimensions.width
            let height = capturedData.colorImage?.size.height ?? capturedData.cameraReferenceDimensions.height
            
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
                    width: capturedData.cameraReferenceDimensions.width,
                    height: capturedData.cameraReferenceDimensions.height
                ),
                deviceOrientation: deviceOrientation,
                timestamp: Date().timeIntervalSince1970,
                distance: "Test",
                cameraIntrinsics: [
                    [Float(capturedData.cameraIntrinsics.columns.0.x), Float(capturedData.cameraIntrinsics.columns.0.y), Float(capturedData.cameraIntrinsics.columns.0.z)],
                    [Float(capturedData.cameraIntrinsics.columns.1.x), Float(capturedData.cameraIntrinsics.columns.1.y), Float(capturedData.cameraIntrinsics.columns.1.z)],
                    [Float(capturedData.cameraIntrinsics.columns.2.x), Float(capturedData.cameraIntrinsics.columns.2.y), Float(capturedData.cameraIntrinsics.columns.2.z)]
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
    
    func debugOrientationStatus() {
        print("===== ORIENTATION DEBUG =====")
        
        // Current device orientation
        print("Current device orientation: \(UIDevice.current.orientation.rawValue) (\(UIDevice.current.orientation.name))")
        
        // Current UI orientation
        print("Current interface orientation: \(UIApplication.shared.statusBarOrientation.rawValue)")
        
        // Metadata orientation if available
        if let metadata = loadedRecordingMetadata,
           let orientation = metadata.deviceOrientation {
            print("Metadata device orientation: \(orientation.rawValue) (\(orientation.name))")
            if let cameraOri = orientation.cameraOrientation {
                print("Camera orientation: \(cameraOri)")
            }
            if let width = orientation.capturedWidth, let height = orientation.capturedHeight {
                print("Captured dimensions: \(width)x\(height) (\(width > height ? "landscape" : "portrait"))")
            }
        } else {
            print("No metadata orientation available")
        }
        
        // Current frame image if available
        if let image = currentFrameImage {
            print("Current frame: \(image.size.width)x\(image.size.height) (orientation: \(image.imageOrientation.rawValue))")
            print("Is landscape: \(image.size.width > image.size.height)")
        } else {
            print("No current frame")
        }
        
        print("============================")
    }

}

// Add this extension to your CameraLiDARManager class
// Add this extension to your CameraLiDARManager class

// Add this method to your CameraLiDARManager class
extension CameraLiDARManager {
    // Thread-safe method to update current frame
    func forceFrameUpdate(to index: Int) {
        if Thread.isMainThread {
            _forceFrameUpdate(to: index)
        } else {
            DispatchQueue.main.async {
                self._forceFrameUpdate(to: index)
            }
        }
    }
    
    // Private implementation - always call on main thread
    private func _forceFrameUpdate(to index: Int) {
        // Ensure we're on the main thread
        assert(Thread.isMainThread, "Frame updates must happen on the main thread")
        
        // Bounds check
        guard index >= 0 && index < totalFrames else {
            print("Error: Frame index \(index) is out of bounds (0..\(totalFrames-1))")
            return
        }
        
        // Update the frame index
        self.currentFrameIndex = index
        
        // Notify any observers
        if let handler = onFrameChange {
            handler(index)
        }
        
        // Notify via NotificationCenter as well
        NotificationCenter.default.post(
            name: NSNotification.Name("FrameChanged"),
            object: nil,
            userInfo: ["frameIndex": index]
        )
    }
    
    // Thread-safe overlay image setter
    func setOverlayImage(_ image: UIImage) {
        DispatchQueue.main.async {
            self.currentFrameImage = image
            
            // Notify observers that the frame has been updated
            if let handler = self.onFrameChange {
                handler(self.currentFrameIndex)
            }
        }
    }
}
// Add this method to your CameraLiDARManager class
extension CameraLiDARManager {
    // Method to safely access frames by index
    func getFrame(at index: Int) -> UIImage? {
        // Check if index is valid and return the frame if so
        if index >= 0 && index < totalFrames {
            // If the current frame is loaded and matches the requested index
            if index == currentFrameIndex && currentFrameImage != nil {
                return currentFrameImage
            }
            
            // Otherwise, load the frame from storage
            // This implementation will depend on how your frames are stored
            // You might need to adapt this based on your implementation
            loadFrameIfNeeded(at: index)
            return currentFrameImage
        }
        return nil
    }
    
    // Helper method to load a specific frame
    private func loadFrameIfNeeded(at index: Int) {
        // Only load if the requested index is different from the current one
        if index != currentFrameIndex {
            // Set the frame index which should trigger your existing frame loading logic
            currentFrameIndex = index
        }
    }
}
extension UIImage.Orientation {
    var debugDescription: String {
        switch self {
        case .up: return "up (0)"
        case .down: return "down (2)"
        case .left: return "left (4)"
        case .right: return "right (3)"
        case .upMirrored: return "upMirrored (1)"
        case .downMirrored: return "downMirrored (5)"
        case .leftMirrored: return "leftMirrored (7)"
        case .rightMirrored: return "rightMirrored (6)"
        @unknown default: return "unknown (\(self.rawValue))"
        }
    }
}
extension UIDeviceOrientation {
    var name: String {
        switch self {
        case .portrait: return "portrait"
        case .portraitUpsideDown: return "portraitUpsideDown"
        case .landscapeLeft: return "landscapeLeft"
        case .landscapeRight: return "landscapeRight"
        case .faceUp: return "faceUp"
        case .faceDown: return "faceDown"
        case .unknown: return "unknown"
        @unknown default: return "unknown"
        }
    }
    
    // Convert UIDeviceOrientation to AVCaptureVideoOrientation
    var videoOrientation: AVCaptureVideoOrientation {
        switch self {
        case .portrait: return .portrait
        case .portraitUpsideDown: return .portraitUpsideDown
        case .landscapeLeft: return .landscapeRight  // They're opposite
        case .landscapeRight: return .landscapeLeft  // They're opposite
        default: return .portrait
        }
    }
}

//// Extension for RecordingMetadata.DeviceOrientation
//extension RecordingMetadata.DeviceOrientation {
//    var uiDeviceOrientation: UIDeviceOrientation {
//        return UIDeviceOrientation(rawValue: self.rawValue) ?? .portrait
//    }
//}


class CameraCapturedData {
    
    var depth: MTLTexture?
    var colorY: MTLTexture?
    var colorCbCr: MTLTexture?
    var cameraIntrinsics: matrix_float3x3
    var cameraReferenceDimensions: CGSize
    var depthCenter: Float16
    var originalDepth: AVDepthData?
    var colorImage: UIImage?
    var processedImage: UIImage?
//        let filterOn: Bool
//        let pointCloudManager = PointCloudManager()
    
    init(depth: MTLTexture? = nil,
         colorY: MTLTexture? = nil,
         colorCbCr: MTLTexture? = nil,
         cameraIntrinsics: matrix_float3x3 = matrix_float3x3(),
         cameraReferenceDimensions: CGSize = .zero,
         depthCenter: Float16 = 0,
         originalDepth: AVDepthData? = nil,
         colorImage: UIImage? = nil,
         processedImage: UIImage? = nil){
        
        self.depth = depth
        self.colorY = colorY
        self.colorCbCr = colorCbCr
        self.cameraIntrinsics = cameraIntrinsics
        self.cameraReferenceDimensions = cameraReferenceDimensions
        self.depthCenter = depthCenter
        self.originalDepth = originalDepth
        self.colorImage = colorImage
        self.processedImage = processedImage
        
        
    }
    
    
    
    private func createCaptureFolder(at url: URL) throws -> URL {
        //            let folderName = UUID().uuidString
        //            let folderURL = url.appendingPathComponent(folderName)
        //            try FileManager.default.createDirectory(at: folderURL, withIntermediateDirectories: true, attributes: nil)
        let dateFormatter = DateFormatter()
        dateFormatter.dateFormat = "yyyy-MM-dd_HH-mm-ss"
        let timestamp = dateFormatter.string(from: Date())
        
        let folderName = "Capture_\(timestamp)"
        let folderURL = url.appendingPathComponent(folderName)
        
        try FileManager.default.createDirectory(at: folderURL, withIntermediateDirectories: true, attributes: nil)
        
        print("Created folder: \(folderURL.path)")
        
        return folderURL
    }
    
    
    func matrixToArray(_ matrix: matrix_float3x3) -> [[Float]] {
        return [
            [matrix.columns.0[0], matrix.columns.0[1], matrix.columns.0[2]],
            [matrix.columns.1[0], matrix.columns.1[1], matrix.columns.1[2]],
            [matrix.columns.2[0], matrix.columns.2[1], matrix.columns.2[2]]
        ]
    }
    
    private func cameraIntrinsicsToArray() -> [[Double]] {
        return [
            [Double(cameraIntrinsics.columns.0.x), Double(cameraIntrinsics.columns.0.y), Double(cameraIntrinsics.columns.0.z)],
            [Double(cameraIntrinsics.columns.1.x), Double(cameraIntrinsics.columns.1.y), Double(cameraIntrinsics.columns.1.z)],
            [Double(cameraIntrinsics.columns.2.x), Double(cameraIntrinsics.columns.2.y), Double(cameraIntrinsics.columns.2.z)]
        ]
    }
    func saveCaptureData(to url: URL, filter depthfilter:  Bool) throws {
        let folderURL = try createCaptureFolder(at: url)
        
        try saveDepthData(to: folderURL.appendingPathComponent("depthData.dat"))
        try saveColorData(to: folderURL)
        
        if let colorImage = self.colorImage {
            try saveUIImage(colorImage, to: folderURL.appendingPathComponent("colorImage.jpg"))
        } else {
            print("Warning: colorImage is nil, cannot save")
        }
        
        let metadata: [String: Any] = [
            "cameraIntrinsics": cameraIntrinsicsToArray(),
            "cameraReferenceDimensions": [
                "width": cameraReferenceDimensions.width,
                "height": cameraReferenceDimensions.height
            ],
            "depthCenter": Double(depthCenter), // Convert Float16 to Double
            "depthfilter": depthfilter

        ]
        
        let metadataURL = folderURL.appendingPathComponent("metadata.plist")
        
        // Use FileManager to write the dictionary directly
        (metadata as NSDictionary).write(to: metadataURL, atomically: true)
        
        print("Metadata saved successfully to: \(metadataURL.path)")
        
        // Save point cloud as PLY
       
        try savePointCloudAsPLY(to: folderURL.appendingPathComponent("pointcloud.ply"))
        print("Point cloud saved successfully.")
      
        print ("yooooo")
    }
    
    private func saveUIImage(_ image: UIImage, to url: URL) throws {
        guard let imageData = image.jpegData(compressionQuality: 1.0) else {
            throw NSError(domain: "CameraCapturedData", code: 9, userInfo: [NSLocalizedDescriptionKey: "Failed to create JPEG data from UIImage"])
        }
        try imageData.write(to: url)
        print("UIImage saved successfully to: \(url.path)")
    }
    
    
    private func saveDepthData(to url: URL) throws {
        guard let depth = self.depth else {
            throw NSError(domain: "CameraCapturedData", code: 1, userInfo: [NSLocalizedDescriptionKey: "No depth data available"])
        }
        
        let width = depth.width
        let height = depth.height
        let bytesPerPixel = 2 // For R16Float format
        let bytesPerRow = width * bytesPerPixel
        
        var depthData = [Float16](repeating: 0, count: width * height)
        let region = MTLRegionMake2D(0, 0, width, height)
        
        depth.getBytes(&depthData, bytesPerRow: bytesPerRow, from: region, mipmapLevel: 0)
        
        let data = Data(bytes: depthData, count: depthData.count * MemoryLayout<Float16>.size)
        try data.write(to: url)
        
        // Save depth dimensions
        let depthInfo: [String: Any] = [
            "width": width,
            "height": height
        ]
        let depthInfoURL = url.deletingLastPathComponent().appendingPathComponent("depthInfo.plist")
        (depthInfo as NSDictionary).write(to: depthInfoURL, atomically: true)
    }
    
    private func saveColorData(to url: URL) throws {
        guard let colorY = self.colorY, let colorCbCr = self.colorCbCr else {
            throw NSError(domain: "CameraCapturedData", code: 1, userInfo: [NSLocalizedDescriptionKey: "No color data available"])
        }
        
        // Save Y plane
        try saveTexture(colorY, to: url.appendingPathComponent("colorY.dat"))
        
        // Save CbCr plane
        try saveTexture(colorCbCr, to: url.appendingPathComponent("colorCbCr.dat"))
        
        // Save texture information
        let textureInfo: [String: Any] = [
            "yWidth": colorY.width,
            "yHeight": colorY.height,
            "yPixelFormat": colorY.pixelFormat.rawValue,
            "cbcrWidth": colorCbCr.width,
            "cbcrHeight": colorCbCr.height,
            "cbcrPixelFormat": colorCbCr.pixelFormat.rawValue
        ]
        let infoURL = url.appendingPathComponent("colorTextureInfo.plist")
        let infoData = try PropertyListSerialization.data(fromPropertyList: textureInfo, format: .xml, options: 0)
        try infoData.write(to: infoURL)
        
        
        print("yehaa")
    }
    
    private func saveTexture(_ texture: MTLTexture, to url: URL) throws {
        let width = texture.width
        let height = texture.height
        let bytesPerPixel = texture.pixelFormat.bytesPerPixel
        let bytesPerRow = width * bytesPerPixel
        let dataSize = height * bytesPerRow
        
        var data = [UInt8](repeating: 0, count: dataSize)
        let region = MTLRegionMake2D(0, 0, width, height)
        texture.getBytes(&data, bytesPerRow: bytesPerRow, from: region, mipmapLevel: 0)
        
        try Data(data).write(to: url)
    }
    
    
    private func arrayToMatrix(_ array: [Float]) -> matrix_float3x3 {
        return matrix_float3x3(columns: (
            SIMD3<Float>(array[0], array[1], array[2]),
            SIMD3<Float>(array[3], array[4], array[5]),
            SIMD3<Float>(array[6], array[7], array[8])
        ))
    }
    func load(from url: URL, device: MTLDevice) throws {
        let colorCbCrURL = url.appendingPathComponent("colorCbCr.dat")
        let colorYURL = url.appendingPathComponent("colorY.dat")
        let depthDataURL = url.appendingPathComponent("depthData.dat")
        let metadataURL = url.appendingPathComponent("metadata.plist")
        let textureInfoURL = url.appendingPathComponent("colorTextureInfo.plist")
        
        let colorImageURL = url.appendingPathComponent("colorImage.jpg")
        if let imageData = try? Data(contentsOf: colorImageURL),
           let image = UIImage(data: imageData) {
            self.colorImage = image
        }
        
        
        print("Starting to load data from \(url.path)")
        
        // Load metadata
        let metadataData = try Data(contentsOf: metadataURL)
        if let metadata = try PropertyListSerialization.propertyList(from: metadataData, format: nil) as? [String: Any] {
            // Camera Intrinsics
            if let intrinsicsArray = metadata["cameraIntrinsics"] as? [[Double]] {
                self.cameraIntrinsics = arrayToMatrix(intrinsicsArray)
                print("Camera Intrinsics loaded: \(self.cameraIntrinsics)")
            } else {
                print("Warning: Failed to load camera intrinsics")
            }
            
            // Camera Reference Dimensions
            if let referenceDimensions = metadata["cameraReferenceDimensions"] as? [String: CGFloat] {
                self.cameraReferenceDimensions = CGSize(width: referenceDimensions["width"] ?? 0, height: referenceDimensions["height"] ?? 0)
            } else if let referenceDimensions = metadata["cameraReferenceDimensions"] as? [String: Double] {
                self.cameraReferenceDimensions = CGSize(width: CGFloat(referenceDimensions["width"] ?? 0), height: CGFloat(referenceDimensions["height"] ?? 0))
            } else {
                print("Warning: Failed to load camera reference dimensions")
                self.cameraReferenceDimensions = CGSize(width: 1920, height: 1080) // Example default
            }
            print("Camera Reference Dimensions: \(self.cameraReferenceDimensions)")
            
            // Depth Center
            if let depthCenter = metadata["depthCenter"] as? Double {
                self.depthCenter = Float16(depthCenter)
            } else if let depthCenter = metadata["depthCenter"] as? Float {
                self.depthCenter = Float16(depthCenter)
            } else {
                print("Warning: Failed to load depth center")
                self.depthCenter = 0.0 // Default value
            }
            print("Depth Center: \(self.depthCenter)")
        } else {
            throw NSError(domain: "MetadataError", code: 1, userInfo: [NSLocalizedDescriptionKey: "Failed to parse metadata"])
        }
        
        // Load texture information
        let textureInfoData = try Data(contentsOf: textureInfoURL)
        guard let textureInfo = try PropertyListSerialization.propertyList(from: textureInfoData, format: nil) as? [String: Any] else {
            throw NSError(domain: "CameraCapturedData", code: 4, userInfo: [NSLocalizedDescriptionKey: "Failed to load color texture info"])
        }
        
        // Load textures
        let yWidth = textureInfo["yWidth"] as? Int ?? 0
        let yHeight = textureInfo["yHeight"] as? Int ?? 0
        let yPixelFormatRaw = textureInfo["yPixelFormat"] as? UInt ?? 0
        let yPixelFormat = MTLPixelFormat(rawValue: yPixelFormatRaw) ?? .r8Unorm
        
        let cbcrWidth = textureInfo["cbcrWidth"] as? Int ?? 0
        let cbcrHeight = textureInfo["cbcrHeight"] as? Int ?? 0
        let cbcrPixelFormatRaw = textureInfo["cbcrPixelFormat"] as? UInt ?? 0
        let cbcrPixelFormat = MTLPixelFormat(rawValue: cbcrPixelFormatRaw) ?? .r8Unorm
        
        print("Loading textures...")
        do {
            self.colorY = try loadTexture(from: colorYURL, width: yWidth, height: yHeight, pixelFormat: yPixelFormat, device: device)
            print("ColorY texture loaded: \(self.colorY != nil)")
            
            self.colorCbCr = try loadTexture(from: colorCbCrURL, width: cbcrWidth, height: cbcrHeight, pixelFormat: cbcrPixelFormat, device: device)
            print("ColorCbCr texture loaded: \(self.colorCbCr != nil)")
            
            self.depth = try loadDepthTexture(from: depthDataURL, device: device)
            print("Depth texture loaded: \(self.depth != nil)")
          
            if self.colorY == nil || self.colorCbCr == nil || self.depth == nil {
                print("Warning: One or more textures are nil after loading")
                if self.colorY == nil { print("ColorY is nil") }
                if self.colorCbCr == nil { print("ColorCbCr is nil") }
                if self.depth == nil { print("Depth is nil") }
            } else {
                print("All textures loaded successfully")
            }
        } catch {
            print("Error loading textures: \(error)")
            throw error
        }
        
        
    }
    
    private func loadTexture(from url: URL, width: Int, height: Int, pixelFormat: MTLPixelFormat, device: MTLDevice) throws -> MTLTexture {
        print("Loading texture from \(url.lastPathComponent)")
        print("Texture dimensions: \(width)x\(height), PixelFormat: \(pixelFormat)")
        
        do {
            let data = try Data(contentsOf: url)
            print("Loaded \(data.count) bytes for texture")
            
            let textureDescriptor = MTLTextureDescriptor.texture2DDescriptor(pixelFormat: pixelFormat, width: width, height: height, mipmapped: false)
            textureDescriptor.usage = [.shaderRead, .shaderWrite]
            
            guard let texture = device.makeTexture(descriptor: textureDescriptor) else {
                throw NSError(domain: "CameraCapturedData", code: 5, userInfo: [NSLocalizedDescriptionKey: "Failed to create texture"])
            }
            
            let bytesPerRow = width * pixelFormat.bytesPerPixel
            let region = MTLRegionMake2D(0, 0, width, height)
            
            texture.replace(region: region, mipmapLevel: 0, withBytes: [UInt8](data), bytesPerRow: bytesPerRow)
            
            print("Texture created successfully")
            return texture
        } catch {
            print("Error loading texture: \(error)")
            throw error
        }
    }
    
    private func loadDepthTexture(from url: URL, device: MTLDevice) throws -> MTLTexture {
        let depthData = try Data(contentsOf: url)
        
        let depthInfoURL = url.deletingLastPathComponent().appendingPathComponent("depthInfo.plist")
        guard let depthInfo = NSDictionary(contentsOf: depthInfoURL) as? [String: Any],
              let width = depthInfo["width"] as? Int,
              let height = depthInfo["height"] as? Int else {
            throw NSError(domain: "CameraCapturedData", code: 7, userInfo: [NSLocalizedDescriptionKey: "Failed to load depth info"])
        }
        
        let depthValues = depthData.withUnsafeBytes { Array(UnsafeBufferPointer<Float16>(start: $0.bindMemory(to: Float16.self).baseAddress!, count: depthData.count / MemoryLayout<Float16>.size)) }
        
        let textureDescriptor = MTLTextureDescriptor.texture2DDescriptor(pixelFormat: .r16Float,
                                                                         width: width,
                                                                         height: height,
                                                                         mipmapped: false)
        textureDescriptor.usage = [.shaderRead, .shaderWrite]
        
        guard let texture = device.makeTexture(descriptor: textureDescriptor) else {
            throw NSError(domain: "CameraCapturedData", code: 8, userInfo: [NSLocalizedDescriptionKey: "Failed to create depth texture"])
        }
        
        let region = MTLRegionMake2D(0, 0, width, height)
        texture.replace(region: region, mipmapLevel: 0, withBytes: depthValues, bytesPerRow: width * MemoryLayout<Float16>.size)
        
        return texture
    }
    
    private func arrayToMatrix(_ array: [[Double]]) -> matrix_float3x3 {
        return matrix_float3x3(columns: (
            SIMD3<Float>(Float(array[0][0]), Float(array[0][1]), Float(array[0][2])),
            SIMD3<Float>(Float(array[1][0]), Float(array[1][1]), Float(array[1][2])),
            SIMD3<Float>(Float(array[2][0]), Float(array[2][1]), Float(array[2][2]))
        ))
    }
}
extension CameraCapturedData {
    func saveCaptureData(to url: URL, isVideoFrame: Bool = false, completion: @escaping (Error?) -> Void) {
        DispatchQueue.global(qos: .userInitiated).async {
            do {
                let folderURL: URL
                if isVideoFrame {
                    folderURL = url  // For video frames, use the provided URL directly
                } else {
                    folderURL = try self.createCaptureFolder(at: url)  // For single captures, create a new folder
                }
                
                try self.saveDepthData(to: folderURL.appendingPathComponent("depthData.dat"))
                try self.saveColorData(to: folderURL)
                
                if let colorImage = self.colorImage {
                    try self.saveUIImage(colorImage, to: folderURL.appendingPathComponent("colorImage.jpg"))
                } else {
                    print("Warning: colorImage is nil, cannot save")
                }
                
                let metadata: [String: Any] = [
                    "cameraIntrinsics": self.cameraIntrinsicsToArray(),
                    "cameraReferenceDimensions": [
                        "width": self.cameraReferenceDimensions.width,
                        "height": self.cameraReferenceDimensions.height
                    ],
                    "depthCenter": Double(self.depthCenter),
                    "timestamp": Date().timeIntervalSinceReferenceDate
                ]
                
                let metadataURL = folderURL.appendingPathComponent("metadata.plist")
                
                // Use FileManager to write the dictionary directly
                (metadata as NSDictionary).write(to: metadataURL, atomically: true)
                
                DispatchQueue.main.async {
                    print("Data saved successfully to: \(folderURL.path)")
                    completion(nil)
                }
            } catch {
                DispatchQueue.main.async {
                    print("Error saving capture data: \(error)")
                    completion(error)
                }
            }
        }
    }

        func savePointCloudAsPLY(to url: URL, maxDepth: Float = 10000.0, minDepth: Float = 0.1) throws {
            guard let depthTexture = self.depth,
                  let colorYTexture = self.colorY,
                  let colorCbCrTexture = self.colorCbCr else {
                throw NSError(domain: "CameraCapturedData", code: 1, userInfo: [NSLocalizedDescriptionKey: "Missing texture data"])
            }

            let width = depthTexture.width
            let height = depthTexture.height

            let depthPixels = depthTexture.getPixelValues() as [Float16]
            let colorYPixels = colorYTexture.getPixelValues() as [UInt8]
            let colorCbCrPixels = colorCbCrTexture.getPixelValues() as [SIMD2<UInt8>]

            let depthResolution = simd_float2(x: Float(width), y: Float(height))
            let scaleRes = simd_float2(x: Float(cameraReferenceDimensions.width) / depthResolution.x,
                                       y: Float(cameraReferenceDimensions.height) / depthResolution.y)
            
            var scaledIntrinsics = cameraIntrinsics
            scaledIntrinsics[0][0] /= scaleRes.x
            scaledIntrinsics[1][1] /= scaleRes.y
            scaledIntrinsics[2][0] /= scaleRes.x
            scaledIntrinsics[2][1] /= scaleRes.y

            var points: [String] = []

            for y in 0..<height {
                for x in 0..<width {
                    let depth = Float(depthPixels[y * width + x])
                    if depth > minDepth && depth < maxDepth {
                        let position = calculatePosition(x: Float(x), y: Float(y), depth: depth, intrinsics: scaledIntrinsics)
                        let color = getColor(x: x, y: y, colorYPixels: colorYPixels, colorCbCrPixels: colorCbCrPixels, width: width)
                        points.append("\(position.x) \(position.y) \(position.z) \(color.x) \(color.y) \(color.z)")
                    }
                }
            }

            var fileContent = """
            ply
            format ascii 1.0
            element vertex \(points.count)
            property float x
            property float y
            property float z
            property uchar red
            property uchar green
            property uchar blue
            end_header
            
            """

            fileContent += points.joined(separator: "\n")

            try fileContent.write(to: url, atomically: true, encoding: .utf8)
        }

        private func calculatePosition(x: Float, y: Float, depth: Float, intrinsics: simd_float3x3) -> SIMD3<Float> {
            let fx = intrinsics[0][0]
            let fy = intrinsics[1][1]
            let cx = intrinsics[2][0]
            let cy = intrinsics[2][1]

            let pointX = (x - cx) * depth / fx
            let pointY = -(y - cy) * depth / fy  // Flip Y-axis to match Metal rendering
            let pointZ = -depth  // Negate Z to match Metal rendering

            return SIMD3<Float>(pointX, pointY, pointZ)
        }

        private func getColor(x: Int, y: Int, colorYPixels: [UInt8], colorCbCrPixels: [SIMD2<UInt8>], width: Int) -> SIMD3<UInt8> {
            let yValue = Float(colorYPixels[y * width + x])
            let cbcrValue = colorCbCrPixels[(y/2) * (width/2) + (x/2)]
            let ycbcr = SIMD4<Float>(yValue, Float(cbcrValue.x), Float(cbcrValue.y), 1.0)
            
            let ycbcrToRGBTransform = simd_float4x4(
                SIMD4<Float>(+1.0000, +1.0000, +1.0000, +0.0000),
                SIMD4<Float>(+0.0000, -0.3441, +1.7720, +0.0000),
                SIMD4<Float>(+1.4020, -0.7141, +0.0000, +0.0000),
                SIMD4<Float>(-0.7010, +0.5291, -0.8860, +1.0000)
            )

            let rgbaColor = ycbcrToRGBTransform * ycbcr
            return SIMD3<UInt8>(UInt8(max(0, min(255, rgbaColor.x * 255))),
                                UInt8(max(0, min(255, rgbaColor.y * 255))),
                                UInt8(max(0, min(255, rgbaColor.z * 255))))
        }
    
}

struct RecordingMetadata: Codable {
    let personName: String
    let action: String
    let frameCount: Int
    let useLiDAR: Bool
    let duration: TimeInterval
    let resolution: Resolution
    let deviceOrientation: DeviceOrientation?
    let timestamp: TimeInterval
    let distance: String?
    let cameraIntrinsics: [[Float]]
    
    struct Resolution: Codable {
        let width: CGFloat
        let height: CGFloat
    }
    
    struct DeviceOrientation: Codable {
        let rawValue: Int
        let name: String
        
        // Add camera orientation to clarify how the image was actually captured
        var cameraOrientation: String?
        
        // Add image dimensions to help resolve orientation issues
        var capturedWidth: Int?
        var capturedHeight: Int?
        
        // Convert to UIDeviceOrientation
        var uiDeviceOrientation: UIDeviceOrientation {
            return UIDeviceOrientation(rawValue: self.rawValue) ?? .portrait
        }
        
        // Determine if device was held in portrait or landscape
        var isPortraitOrientation: Bool {
            return uiDeviceOrientation == .portrait || uiDeviceOrientation == .portraitUpsideDown
        }
    }
        

    
    // Static method to create a default metadata with portrait orientation
    static func defaultMetadata() -> RecordingMetadata {
        return RecordingMetadata(
            personName: "Unknown",
            action: "Unknown",
            frameCount: 0,
            useLiDAR: false,
            duration: 0.0,
            resolution: Resolution(width: 1920, height: 1080),
            deviceOrientation: DeviceOrientation(rawValue: UIDeviceOrientation.portrait.rawValue, name: "portrait"),
            timestamp: Date().timeIntervalSince1970,
            distance: nil,
            cameraIntrinsics: [
                [1.0, 0.0, 0.0],
                [0.0, 1.0, 0.0],
                [0.0, 0.0, 1.0]
            ]
        )
    }
}

extension CameraLiDARManager {
    
    /// Comprehensive method to clear all frames and reset state
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
        capturedData = CameraCapturedData()
        
        // Clear all caches
        preloadedFrames.removeAll()
        preloadedFrameIndices.removeAll()
        keypointData.removeAll()
        keypointDataByFrame.removeAll()
        processedImages.removeAll()
        
        // Clear depth-related data
        selectedImagePoints.removeAll()
        selectedWorldPoints.removeAll()
        selectedPoints.removeAll()
        distanceMeasured = nil
        measuredDistance = nil
        depthValue = nil
        depthAtTappedPoint = nil
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
    
    /// Pause playback without clearing data
    func pausePlayback() {
        if let timer = playbackTimer {
            timer.invalidate()
            playbackTimer = nil
        }
        isPlaying = false
    }
    
    /// Reset just the playback state without clearing frames
    func resetPlaybackPosition() {
        currentFrameIndex = 0
        sliderPosition = 0
        if totalFrames > 0 {
            setFrame(to: 0)
        }
    }
    
    /// Debug method to print current state
    func debugPrintState() {
        print("=== CameraLiDARManager State ===")
        print("Total frames: \(totalFrames)")
        print("Current frame index: \(currentFrameIndex)")
        print("Video frames count: \(videoFrames.count)")
        print("LiDAR frame URLs count: \(lidarFrameURLs.count)")
        print("Has current image: \(currentFrameImage != nil)")
        print("Is playing: \(isPlaying)")
        print("Is live capture: \(isLiveCapture)")
        print("Is recording: \(isRecording)")
        print("Is data loaded: \(isDataLoaded)")
        print("Data available: \(dataAvailable)")
        print("Loaded data is LiDAR: \(isLoadedDataLiDAR)")
        print("Has metadata: \(loadedRecordingMetadata != nil)")
        print("================================")
    }
}
