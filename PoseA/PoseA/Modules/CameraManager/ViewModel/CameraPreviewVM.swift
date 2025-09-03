//
//  CameraPreviewViewModel.swift
//  PoseA
//
//  Created by Ardhika Maulidani on 5/27/25.
//  Refactor from Shiela's codebase

import SwiftUI
import AVFoundation

class CameraPreviewVM: UIView {
    // MARK: - Camera Preview Layer
    override class var layerClass: AnyClass { AVCaptureVideoPreviewLayer.self }
    var videoPreviewLayer: AVCaptureVideoPreviewLayer { layer as! AVCaptureVideoPreviewLayer }
    
    var session: AVCaptureSession? {
        get { videoPreviewLayer.session }
        set {
            videoPreviewLayer.session = newValue
            videoPreviewLayer.videoGravity = .resizeAspectFill
            updateRotation()
            updateCameraResolution()
        }
    }
    
    // MARK: - Camera Resolution
    private var cameraResolution: CGSize = .zero
    
    // MARK: - Init
    override init(frame: CGRect) {
        super.init(frame: frame)
    }
    
    required init?(coder: NSCoder) {
        super.init(coder: coder)
    }
    
    // MARK: - Layout & Rotation
    override func layoutSubviews() {
        super.layoutSubviews()
        videoPreviewLayer.frame = bounds
        updateRotation()
    }
    
    private func updateRotation() {
        guard let connection = videoPreviewLayer.connection else { return }
        
        connection.videoRotationAngle = {
            switch OrientationCache.shared.orientation {
            case .portrait: return 90
            case .landscapeRight: return 0
            case .landscapeLeft: return 180
            case .portraitUpsideDown: return 270
            }
        }()
    }
    
    private func updateCameraResolution() {
        guard let deviceInput = session?.inputs
            .compactMap({ $0 as? AVCaptureDeviceInput }).first else { return }
        let desc = deviceInput.device.activeFormat.formatDescription
        let dimensions = CMVideoFormatDescriptionGetDimensions(desc)
        cameraResolution = CGSize(width: CGFloat(dimensions.width),
                                  height: CGFloat(dimensions.height))
    }
}
