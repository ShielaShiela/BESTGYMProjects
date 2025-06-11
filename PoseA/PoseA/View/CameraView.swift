//
//  CameraController.swift
//  BESTGYM
//
//  Created by Shiela Cabahug on 2024/12/18.
//

import SwiftUI
import AVFoundation
import ARKit

// Camera view that handles video capture
class CameraViewController: UIViewController {
    private var captureSession: AVCaptureSession?
    private var videoOutput: AVCaptureMovieFileOutput?
    private var previewLayer: AVCaptureVideoPreviewLayer?
    private var lidarSupported: Bool = false
    private var isRecording = false
    private var currentDevice: AVCaptureDevice?
    private let settings: VideoSettings
    
    init(settings: VideoSettings) {
        self.settings = settings
        super.init(nibName: nil, bundle: nil)
    }
    
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
    
    override func viewDidLoad() {
        super.viewDidLoad()
//        checkLiDARSupport()
        setupCaptureSession()
    }
    
    override func viewDidLayoutSubviews() {
        super.viewDidLayoutSubviews()
        updatePreviewLayerFrame()
    }
    
    private func updatePreviewLayerFrame() {
            guard let previewLayer = previewLayer else { return }
            
            // Set the preview layer to fill the entire view
            previewLayer.frame = view.bounds
            
            // Update video orientation
            if let connection = previewLayer.connection {
                let orientation = UIDevice.current.orientation
                
                if connection.isVideoOrientationSupported {
                    switch orientation {
                    case .landscapeRight:
                        connection.videoOrientation = .landscapeLeft
                    case .landscapeLeft:
                        connection.videoOrientation = .landscapeRight
                    case .portrait:
                        connection.videoOrientation = .portrait
                    case .portraitUpsideDown:
                        connection.videoOrientation = .portraitUpsideDown
                    default:
                        connection.videoOrientation = .landscapeRight
                    }
                }
            }
        }
        
        private func setupCaptureSession() {
            captureSession = AVCaptureSession()
            
            guard let videoDevice = AVCaptureDevice.default(.builtInWideAngleCamera,
                                                          for: .video,
                                                          position: .back) else { return }
            self.currentDevice = videoDevice
            
            do {
                try configureVideoFormat(device: videoDevice)
                
                let videoInput = try AVCaptureDeviceInput(device: videoDevice)
                if captureSession?.canAddInput(videoInput) == true {
                    captureSession?.addInput(videoInput)
                }
                
                if let audioDevice = AVCaptureDevice.default(for: .audio),
                   let audioInput = try? AVCaptureDeviceInput(device: audioDevice),
                   captureSession?.canAddInput(audioInput) == true {
                    captureSession?.addInput(audioInput)
                }
                
                videoOutput = AVCaptureMovieFileOutput()
                if let videoOutput = videoOutput,
                   captureSession?.canAddOutput(videoOutput) == true {
                    captureSession?.addOutput(videoOutput)
                    
                    if let connection = videoOutput.connection(with: .video) {
                        connection.videoOrientation = .landscapeRight
                    }
                }
                
                previewLayer = AVCaptureVideoPreviewLayer(session: captureSession!)
                previewLayer?.videoGravity = .resizeAspectFill // Changed to fill
                if let previewLayer = previewLayer {
                    view.layer.addSublayer(previewLayer)
                }
                
                updatePreviewLayerFrame()
                
                DispatchQueue.global(qos: .userInitiated).async { [weak self] in
                    self?.captureSession?.startRunning()
                }
                
            } catch {
                print("Error setting up camera: \(error.localizedDescription)")
            }
        }
    
    private func configureVideoFormat(device: AVCaptureDevice) throws {
        try device.lockForConfiguration()
        
        // Find the closest matching format
        let formats = device.formats.filter { format in
            let dimensions = CMVideoFormatDescriptionGetDimensions(format.formatDescription)
            return dimensions.width == Int32(settings.selectedFormat.width) &&
                   dimensions.height == Int32(settings.selectedFormat.height)
        }
        
        if let format = formats.first {
            device.activeFormat = format
            
            // Set FPS
            let targetFPS = Float64(settings.selectedFormat.fps)
            device.activeVideoMinFrameDuration = CMTime(value: 1, timescale: CMTimeScale(targetFPS))
            device.activeVideoMaxFrameDuration = CMTime(value: 1, timescale: CMTimeScale(targetFPS))
        }
        
        device.unlockForConfiguration()
    }
    
    func startRecording() {
        guard let videoOutput = videoOutput,
              !videoOutput.isRecording else { return }
        
        let documentsPath = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
        let videoName = "video-\(Date().timeIntervalSince1970).mov"
        let videoPath = documentsPath.appendingPathComponent(videoName)
        
        videoOutput.startRecording(to: videoPath, recordingDelegate: self)
        isRecording = true
    }
    
    func stopRecording() {
        guard let videoOutput = videoOutput,
              videoOutput.isRecording else { return }
        
        videoOutput.stopRecording()
        isRecording = false
    }
    
    override func viewWillTransition(to size: CGSize, with coordinator: UIViewControllerTransitionCoordinator) {
           super.viewWillTransition(to: size, with: coordinator)
           
           coordinator.animate { [weak self] _ in
               self?.updatePreviewLayerFrame()
           }
       }
}

extension CameraViewController: AVCaptureFileOutputRecordingDelegate {
    func fileOutput(_ output: AVCaptureFileOutput,
                   didFinishRecordingTo outputFileURL: URL,
                   from connections: [AVCaptureConnection],
                   error: Error?) {
        if let error = error {
            print("Error recording: \(error.localizedDescription)")
        } else {
            // Notify the app that recording is complete
            NotificationCenter.default.post(name: Notification.Name("RecordingFinished"), object: outputFileURL)
        }
    }
}

// Camera Preview View that uses UIViewRepresentable to display camera feed
struct CameraPreviewView: UIViewRepresentable {
    @ObservedObject var cameraManager: CameraLiDARManager
    
    // Create the view
    func makeUIView(context: Context) -> CameraPreviewUIView {
        let previewView = CameraPreviewUIView()
        previewView.session = cameraManager.controller.captureSession
        
        // Start the session if not already running
        // This ensures the camera is active when the view appears
        DispatchQueue.global(qos: .userInitiated).async {
            if !(previewView.session?.isRunning ?? false) {
                previewView.session?.startRunning()
            }
        }
        
        return previewView
    }
    
    // Update the view if needed
    func updateUIView(_ uiView: CameraPreviewUIView, context: Context) {
        // Make sure the session is assigned
        uiView.session = cameraManager.controller.captureSession
    }
}

// Custom UIView for camera preview to ensure better control of the AVCaptureSession
class CameraPreviewUIView: UIView {
    override class var layerClass: AnyClass {
        return AVCaptureVideoPreviewLayer.self
    }
    
    // Use main thread dispatch for layer access
    var previewLayer: AVCaptureVideoPreviewLayer {
        // Ensure we're on the main thread
        if Thread.isMainThread {
            return layer as! AVCaptureVideoPreviewLayer
        } else {
            // This should never be called off the main thread, but provide a fallback
            print("WARNING: Accessing previewLayer from background thread")
            var previewLayer: AVCaptureVideoPreviewLayer?
            DispatchQueue.main.sync {
                previewLayer = layer as? AVCaptureVideoPreviewLayer
            }
            return previewLayer!
        }
    }
    
    var session: AVCaptureSession? {
        get {
            if Thread.isMainThread {
                return previewLayer.session
            } else {
                var session: AVCaptureSession?
                DispatchQueue.main.sync {
                    session = (layer as? AVCaptureVideoPreviewLayer)?.session
                }
                return session
            }
        }
        set {
            // Always set session on main thread
            if Thread.isMainThread {
                previewLayer.session = newValue
            } else {
                DispatchQueue.main.async {
                    (self.layer as? AVCaptureVideoPreviewLayer)?.session = newValue
                }
            }
        }
    }
}
