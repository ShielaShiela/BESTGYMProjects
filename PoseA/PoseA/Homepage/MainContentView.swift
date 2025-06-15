//
//  MainContentView.swift
//  PoseA
//
//  Created by Ardhika Maulidani on 5/27/25.
//  Refactor from Shiela Cabahug's codebase

import SwiftUI

struct MainContentView: View {
    @ObservedObject var appState: AppState
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
            .cornerRadius(appState.isRecordMode ? 0 : 8)
            .padding(.horizontal, appState.isRecordMode ? 0 : 16)
            
            // Playback controls (hide in record mode)
            if !appState.isRecordMode {
                if cameraManager.totalFrames > 0 && !cameraManager.isRecording {
                    PlaybackControlView(
                        cameraManager: cameraManager,
                        totalFrames: cameraManager.totalFrames
                    )
                    .padding()
                }
                
                // Analysis button
//                if cameraManager.totalFrames > 0 && appState.poseProcessor.hasKeypoints(for: cameraManager.currentFrameIndex) {
//                    Button(action: {
//                        appState.showAnalysisView = true
//                    }) {
//                        Text("Show Analysis")
//                            .font(.headline)
//                            .padding(.horizontal, 16)
//                            .padding(.vertical, 12)
//                            .background(Color.blue)
//                            .foregroundColor(.white)
//                            .cornerRadius(8)
//                    }
//                    .padding(.bottom)
//                }
            }
        }
    }
    
    // MARK: - Mode-Specific Content
    
    private var recordModeContent: some View {
        ZStack {
            // Live camera view
            CameraPreviewView(cameraManager: cameraManager)
                .edgesIgnoringSafeArea(.all)
                .overlay(alignment: .topTrailing) {
                // LiDAR Toggle
                HStack {
                    Text("LiDAR")
                        .foregroundColor(.white)
                        .font(.caption)
                    Toggle("", isOn: $appState.useLiDAR)
                        .labelsHidden()
                        .toggleStyle(SwitchToggleStyle(tint: .blue))
                }
                .padding(.horizontal, 8)
                .padding(.vertical, 4)
                .background(Color.black.opacity(0.5))
                .cornerRadius(8)
                .padding(.top, 10)
                .padding(.trailing, 10)
                }
               .onAppear {
                   // Start center depth detection when view appears
                   cameraManager.startCenterDepthDetection()
               }
               .onDisappear {
                   // Stop depth detection when view disappears
                   cameraManager.stopCenterDepthDetection()
               }
                
                    // Depth center overlay - new code
                       if let depthValue = cameraManager.centerDepthValue {
                           VStack {
                               Spacer()
                               
                               // Centered depth indicator with crosshair
                               VStack(spacing: 4) {
                                   // Crosshair
                                   ZStack {
                                       Circle()
                                           .stroke(Color.white, lineWidth: 1)
                                           .frame(width: 30, height: 30)
                                       
                                       // Crosshair lines
                                       Group {
                                           Rectangle()
                                               .fill(Color.white)
                                               .frame(width: 20, height: 1)
                                           
                                           Rectangle()
                                               .fill(Color.white)
                                               .frame(width: 1, height: 20)
                                       }
                                   }
                                   
                                   // Depth value display
                                   Text("\(String(format: "%.2f", depthValue))m")
                                       .font(.system(size: 14, weight: .bold, design: .monospaced))
                                       .foregroundColor(.white)
                                       .padding(.horizontal, 8)
                                       .padding(.vertical, 4)
                                       .background(Color.black.opacity(0.6))
                                       .cornerRadius(4)
                               }
                               .padding(.bottom, 80) // Position above record button
                               
                               Spacer()
                           }
                       }
            
        
            // Capture button overlay
            VStack {
                Spacer()
                captureButton()
                    .padding(.bottom, 30)
            }
        }
    }
    
    private var VideoViewerModeContent: some View {
        ZStack {
            if cameraManager.totalFrames > 0 {
                // Display load ed frame with keypoint overlay and ROI support
                FrameView(
                    image: cameraManager.currentFrameImage,
                    keypoints: appState.showKeypoints ? appState.poseProcessor.getKeypoints(for: cameraManager.currentFrameIndex) : nil,
                    isAnnotationMode: appState.isAnnotationMode,
                    rotation: appState.imageRotation,
                    appState: appState,
                    selectedKeypointIndex: $appState.selectedKeypointIndex
                )
                .overlay(
                    // Debug info overlay
                    VStack {
                        HStack {
                            Text("Frame: \(cameraManager.currentFrameIndex + 1)/\(cameraManager.totalFrames)")
                                .font(.caption)
                                .padding(6)
                                .background(Color.black.opacity(0.7))
                                .foregroundColor(.white)
                                .cornerRadius(4)
                            
                            Spacer()
                            
                            if let keypoints = appState.poseProcessor.getKeypoints(for: cameraManager.currentFrameIndex) {
                                Text("Keypoints: \(keypoints.count)")
                                    .font(.caption)
                                    .padding(6)
                                    .background(appState.showKeypoints ? Color.green : Color.red)
                                    .foregroundColor(.white)
                                    .cornerRadius(4)
                            }
                        }
                        .padding(.horizontal)
                        .padding(.top, 8)
                        
                        Spacer()
                    }
                )
            } else {
                // No content placeholder
                VStack(spacing: 20) {
                    Text("No File Selected")
                        .font(.title2)
                        .multilineTextAlignment(.center)
                        .foregroundColor(.secondary)
                    
                    Image(systemName: "folder.fill")
                        .font(.system(size: 50))
                        .foregroundColor(.secondary)
                    
                    Text("Open a file or video to analyze")
                        .font(.body)
                        .foregroundColor(.secondary)
                        .padding(.top, 10)
                        
                    Button(action: {
                        appState.isFilePickerPresented = true
                    }) {
                        Text("Select File")
                            .font(.headline)
                            .padding()
                            .background(Color.blue)
                            .foregroundColor(.white)
                            .cornerRadius(8)
                    }
                    .padding(.top, 20)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .background(Color(.systemGray6))
            }
        }
    }

    
    @ViewBuilder
    private func captureButton() -> some View {
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
    
    private func toggleRecording() {
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
