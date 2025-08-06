//
//  CameraPreviewViewModel.swift
//  PoseA
//
//  Created by Ardhika Maulidani on 5/27/25.
//  Refactor from Shiela's codebase

import SwiftUI
import AVFoundation

class CameraPreviewVM: UIView {
    override class var layerClass: AnyClass {
        return AVCaptureVideoPreviewLayer.self
    }

    var videoPreviewLayer: AVCaptureVideoPreviewLayer {
        if Thread.isMainThread {
            return layer as! AVCaptureVideoPreviewLayer
        } else {
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
                return videoPreviewLayer.session
            } else {
                var session: AVCaptureSession?
                DispatchQueue.main.sync {
                    session = videoPreviewLayer.session
                }
                return session
            }
        }
        set {
            DispatchQueue.main.async {
                self.videoPreviewLayer.session = newValue
                self.videoPreviewLayer.videoGravity = .resizeAspectFill
                self.updateRotation()
            }
        }
    }

    override func layoutSubviews() {
        super.layoutSubviews()
        videoPreviewLayer.frame = bounds
        updateRotation()
    }

    private func updateRotation() {
        guard let connection = videoPreviewLayer.connection else { return }

        let orientation = currentInterfaceOrientation()

        if #available(iOS 17.0, *) {
            // 🔁 Correct angles manually
            connection.videoRotationAngle = {
                switch orientation {
                case .portrait: return 90       // Portrait
                case .landscapeRight: return 0 // Home button on left
                case .landscapeLeft: return 180  // Home button on right
                case .portraitUpsideDown: return 270
                default: return 0
                }
            }()
        } else if connection.isVideoOrientationSupported {
            connection.videoOrientation = {
                switch orientation {
                case .portrait: return .portrait
                case .landscapeRight: return .landscapeLeft
                case .landscapeLeft: return .landscapeRight
                case .portraitUpsideDown: return .portraitUpsideDown
                default: return .portrait
                }
            }()
        }
    }

    private func currentInterfaceOrientation() -> UIInterfaceOrientation {
        UIApplication.shared
            .connectedScenes
            .compactMap { $0 as? UIWindowScene }
            .first?
            .interfaceOrientation ?? .portrait
    }
}

