//
//  CameraPreviewViewModel.swift
//  PoseA
//
//  Created by Ardhika Maulidani on 5/27/25.
//  Refactor from Shiela's codebase

import SwiftUI
import AVFoundation

// Custom UIView for camera preview to ensure better control of the AVCaptureSession
class CameraPreviewViewModel: UIView {
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
            log("Accessing previewLayer from background thread", level: .warn)
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
