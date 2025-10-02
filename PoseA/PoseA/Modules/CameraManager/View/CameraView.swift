//
//  CameraController.swift
//  BESTGYM
//
//  Created by Shiela Cabahug on 2024/12/18.
//

import SwiftUI
import AVFoundation

struct CameraPreviewView: UIViewRepresentable {
    @ObservedObject var appState: MainAppState
    @ObservedObject var cameraManager: CameraManagerVM
    
    func makeUIView(context: Context) -> CameraPreviewVM {
        let previewView = CameraPreviewVM()
        previewView.session = cameraManager.controller.captureSession
        return previewView
    }

    func updateUIView(_ uiView: CameraPreviewVM, context: Context) {
        uiView.session = cameraManager.controller.captureSession

        // Render depth if available
        uiView.toggleDepthView(status: !appState.isLidarDepthView)
        if let texture = cameraManager.depthTexture {
            uiView.renderDepth(texture: texture, maxDepth: 5.0)
        }
    }
}
