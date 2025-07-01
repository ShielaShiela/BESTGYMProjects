//
//  MainContentView.swift
//  PoseA
//
//  Created by Ardhika Maulidani on 5/27/25.
//  Refactor from Shiela Cabahug's codebase

import SwiftUI

struct MainContentView: View {
    @ObservedObject var appState: MainAppState
    @ObservedObject var ROIModel: ROIViewModel
    @ObservedObject var cameraManager: CameraLiDARManager
    
    var body: some View {
        VStack(spacing: 0) {
            // Main display area
            ZStack {
                // Background Color for the ZStack
                Color.black
                    .edgesIgnoringSafeArea(.bottom)
                
                // --- Content Views based on mode ---
                if appState.isRecordMode {
                    // RECORD MODE: Camera Preview with Capture Button
                    recordModeContent
                } else {
                    // ANALYSIS MODE: Frame viewer or placeholder
                    VideoViewerModeContent
                }
            }
            .cornerRadius(appState.isRecordMode ? 0 : 16)
            .padding(.horizontal, appState.isRecordMode ? 0 : 16)
            
            // Playback controls (hide in record mode)
            if !appState.isRecordMode {
                if cameraManager.totalFrames > 0 && !cameraManager.isRecording {
                    PlaybackControlView(
                        cameraManager: cameraManager,
                        totalFrames: cameraManager.totalFrames
                    )
                    .padding(.horizontal)
                    .padding(.vertical, appState.orientation == .landscape ? 4 : 12)
                }
            }
        }
    }

    @ViewBuilder
    func captureButton() -> some View {
        Button(action: toggleRecording) {
            ZStack {
                // Outer ring
                Circle()
                    .strokeBorder(Color.white, lineWidth: 4)
                    .frame(width: 70, height: 70)
                
                // Inner circle (changes color/shape when recording)
                Circle()
                    .fill(cameraManager.isRecording ? Color.red : Color.white)
                    .frame(width: cameraManager.isRecording ? 35 : 58, height: cameraManager.isRecording ? 35 : 58)
                    .animation(.spring(response: 0.3, dampingFraction: 0.6), value: cameraManager.isRecording)
            }
        }
        .disabled(appState.isProcessing)
    }
    
    func toggleRecording() {
        if cameraManager.isRecording {
            // Stop Recording
            print("Stopping recording...")
            if appState.useLiDAR {
                cameraManager.stopVideoRecording { url in
                    if let url = url {
                        print("LiDAR recording saved to: \(url.path)")
                        
                        // Post notification with the URL for the main app to handle
                        NotificationCenter.default.post(
                            name: Notification.Name("RecordingFinished"),
                            object: url
                        )
                    } else {
                        appState.errorMessage = "Failed to save LiDAR recording."
                    }
                }
            } else {
                cameraManager.stopRecording { url in
                    if let url = url {
                        print("Standard recording saved to: \(url.path)")
                        
                        // Post notification with the URL for the main app to handle
                        NotificationCenter.default.post(
                            name: Notification.Name("RecordingFinished"),
                            object: url
                        )
                    } else {
                        appState.errorMessage = "Failed to save recording."
                    }
                }
            }
        } else {
            // Start Recording - do focus locking on background thread
            DispatchQueue.global(qos: .userInitiated).async {
                // Set fixed focus before starting recording
                self.cameraManager.setFixedFocus()
                
                DispatchQueue.main.async {
                    print("Starting recording...")
                    // Start Recording based on LiDAR toggle
                    if self.appState.useLiDAR {
                        // Start LiDAR video recording with athlete info and distance
                        self.cameraManager.startVideoRecording(
                            personName: self.appState.athleteName.isEmpty ? "Test" : self.appState.athleteName,
                            action: self.appState.actionType.isEmpty ? "Test" : self.appState.actionType,
                            distance: self.appState.distanceValue ?? "Test"
                        )
                    } else {
                        // Start standard video recording with the same athlete info (no distance)
                        self.cameraManager.startRecording(
                            personName: self.appState.athleteName.isEmpty ? "Test" : self.appState.athleteName,
                            action: self.appState.actionType.isEmpty ? "Test" : self.appState.actionType
                        )
                    }
                }
            }
        }
    }
}
