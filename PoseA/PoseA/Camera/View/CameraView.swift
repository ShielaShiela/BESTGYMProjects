//
//  CameraController.swift
//  BESTGYM
//
//  Created by Shiela Cabahug on 2024/12/18.
//

import SwiftUI

// Camera Preview View that uses UIViewRepresentable to display camera feed
struct CameraPreviewView: UIViewRepresentable {
    @ObservedObject var cameraManager: CameraLiDARManager
    
    // Create the view
    func makeUIView(context: Context) -> CameraPreviewViewModel {
        let previewView = CameraPreviewViewModel()
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
    func updateUIView(_ uiView: CameraPreviewViewModel, context: Context) {
        // Make sure the session is assigned
        uiView.session = cameraManager.controller.captureSession
    }
}
