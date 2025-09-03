//
//  CameraController.swift
//  BESTGYM
//
//  Created by Shiela Cabahug on 2024/12/18.
//

import SwiftUI
import AVFoundation


struct CameraPreviewView: UIViewRepresentable {
    @ObservedObject var cameraManager: CameraManagerVM
    
    // Create the view
    func makeUIView(context: Context) -> CameraPreviewVM {
        let previewView = CameraPreviewVM()
        previewView.session = cameraManager.controller.captureSession
        return previewView
    }
    
    // Update the view if needed
    func updateUIView(_ uiView: CameraPreviewVM, context: Context) {
        // Make sure the session is assigned
        uiView.session = cameraManager.controller.captureSession
    }
}

