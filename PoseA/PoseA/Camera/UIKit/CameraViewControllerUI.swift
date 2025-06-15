//
//  CameraViewControllerUI.swift
//  PoseA
//
//  Created by Ardhika Maulidani on 5/27/25.
//  Refactor from Shiela's codebase

import SwiftUI
import AVFoundation

// Camera view that handles video capture
class CameraViewControllerUI: UIViewController {
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
        log("init(coder:) has not been implemented", level: .error)
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
                log("Error setting up camera: \(error.localizedDescription)", level: .error)
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

extension CameraViewControllerUI: AVCaptureFileOutputRecordingDelegate {
    func fileOutput(_ output: AVCaptureFileOutput,
                   didFinishRecordingTo outputFileURL: URL,
                   from connections: [AVCaptureConnection],
                   error: Error?) {
        if let error = error {
            log("Error recording: \(error.localizedDescription)", level: .error)
        } else {
            // Notify the app that recording is complete
            NotificationCenter.default.post(name: Notification.Name("RecordingFinished"), object: outputFileURL)
        }
    }
}

