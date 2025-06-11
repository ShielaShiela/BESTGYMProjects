//
//  AppHeader.swift
//  PoseA
//
//  Created by Bestlab on 6/2/25.
//

import SwiftUI

// MARK: - App Header
struct AppHeader: View {
    @ObservedObject var appState: AppState
    @ObservedObject var cameraManager: CameraLiDARManager
    var processAction: () -> Void
    var exportAction: () -> Void
    
    var body: some View {
        VStack(spacing: 0) {
            // Row 1: Title and mode selector
            HStack {
                Text("BESTGYM PoseAPP")
                    .font(.title2)
                    .fontWeight(.bold)
                
                Spacer()
                
                // Mode selector
                Picker("Mode", selection: $appState.isRecordMode) {
                    Text("Analysis").tag(false)
                    Text("Record").tag(true)
                }
                .pickerStyle(SegmentedPickerStyle())
                .frame(width: 200)
                .onChange(of: appState.isRecordMode) { newValue in
                    handleModeChange(isRecordMode: newValue)
                }
            }
            .padding()
            .background(Color(.secondarySystemBackground))
            
            // Row 2: Mode-specific controls
            if appState.isRecordMode {
                // RECORD MODE: Athlete info fields
                recordModeHeaderControls
            } else {
                // ANALYSIS MODE: Detect Pose / Analyze buttons
                analysisModeHeaderControls
            }
            
            // Row 3: File information bar (hide in record mode)
            if !appState.isRecordMode && (cameraManager.totalFrames > 0 || appState.hasImportedKeypoints) {
                fileInfoBar
            }
        }
    }
    
    // MARK: - Header Components
    
    private var recordModeHeaderControls: some View {
        HStack(spacing: 8) {
            HStack {
                Text("Athlete:")
                    .foregroundColor(.white)
                    .fontWeight(.bold)
                    .font(.system(size: 12))
                TextField("Test", text: $appState.athleteName)
                    .textFieldStyle(RoundedBorderTextFieldStyle())
                    .foregroundColor(.black)
                    .font(.system(size: 12))
                    .background(Color.white.opacity(0.8))
                    .cornerRadius(5)
            }
            
            HStack {
                Text("Action:")
                    .foregroundColor(.white)
                    .fontWeight(.bold)
                    .font(.system(size: 12))
                TextField("Test", text: $appState.actionType)
                    .textFieldStyle(RoundedBorderTextFieldStyle())
                    .foregroundColor(.black)
                    .font(.system(size: 12))
                    .background(Color.white.opacity(0.8))
                    .cornerRadius(5)
            }
            
            HStack {
                Text("Distance:")
                    .foregroundColor(.white)
                    .fontWeight(.bold)
                    .font(.system(size: 12))
                TextField("Test", text: Binding(
                    get: { appState.distanceValue ?? "Test" },
                    set: { appState.distanceValue = $0 }
                ))
                .textFieldStyle(RoundedBorderTextFieldStyle())
                .foregroundColor(.black)
                .font(.system(size: 12))
                .background(Color.white.opacity(0.8))
                .cornerRadius(5)
            }
        }
        .padding(.horizontal)
        .padding(.vertical, 8)
        .background(Color.black.opacity(0.7))
    }
    
    private var analysisModeHeaderControls: some View {
        HStack {
            Spacer()
            
            // ROI Controls - only show when we have frames loaded
            if cameraManager.totalFrames > 0 {
                HStack(spacing: 8) {
                    // ROI Mode Toggle
                    Button(action: {
                        if appState.isROIMode {
                            appState.disableROIMode()
                        } else {
                            appState.enableROIMode()
                        }
                    }) {
                        HStack(spacing: 4) {
                            Image(systemName: appState.isROIMode ? "viewfinder.circle.fill" : "viewfinder.circle")
                            Text(appState.isROIMode ? "Exit ROI" : "Select ROI")
                        }
                        .font(.caption)
                        .padding(.horizontal, 8)
                        .padding(.vertical, 4)
                        .background(appState.isROIMode ? Color.orange : Color.gray)
                        .foregroundColor(.white)
                        .cornerRadius(6)
                    }
                    
                    // Clear ROI button (only show if we have an ROI)
                    if appState.hasROI {
                        Button(action: {
                            appState.clearROI()
                        }) {
                            HStack(spacing: 4) {
                                Image(systemName: "trash")
                                Text("Clear ROI")
                            }
                            .font(.caption)
                            .padding(.horizontal, 8)
                            .padding(.vertical, 4)
                            .background(Color.red)
                            .foregroundColor(.white)
                            .cornerRadius(6)
                        }
                    }
                }
                .padding(.trailing, 8)
            }
            
            // Status indicator
            if cameraManager.totalFrames > 0 {
                HStack(spacing: 8) {
                    // ROI Status
                    if appState.hasROI {
                        HStack(spacing: 4) {
                            Circle()
                                .fill(Color.orange)
                                .frame(width: 8, height: 8)
                            Text("ROI Set for All Frames")
                                .font(.caption)
                                .foregroundColor(.orange)
                        }
                    }
                    
                    // Keypoint Status
                    let hasKeypoints = appState.hasImportedKeypoints ||
                                      (appState.showKeypoints && appState.poseProcessor.getTotalFrames() > 0)
                    
                    HStack(spacing: 4) {
                        Circle()
                            .fill(hasKeypoints ? Color.green : Color.orange)
                            .frame(width: 8, height: 8)
                        
                        Text(hasKeypoints ? "Keypoints available" : "Keypoints needed")
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                }
                .padding(.horizontal, 12)
                .padding(.vertical, 6)
                .background(Color(.tertiarySystemBackground))
                .cornerRadius(12)
            }
            
            Spacer()
            
            // Detection and Analysis buttons
            let hasKeypoints = appState.hasImportedKeypoints ||
                              (appState.poseProcessor.getTotalFrames() > 0 &&
                               appState.poseProcessor.hasKeypoints(for: cameraManager.currentFrameIndex))
            
            if cameraManager.totalFrames > 0 && !hasKeypoints && !appState.isProcessing && !appState.isSelectingROI {
                Button(action: processAction) {
                    Text(appState.hasROI ? "Detect Pose in ROI (All Frames)" : "Detect Pose (All Frames)")
                        .font(.headline)
                        .padding(.horizontal, 16)
                        .padding(.vertical, 10)
                        .background(appState.hasROI ? Color.orange : Color.blue)
                        .foregroundColor(.white)
                        .cornerRadius(8)
                }
                .disabled(appState.isProcessing)
            } else if hasKeypoints && !appState.isSelectingROI {
                HStack(spacing: 12) {
                    Button(action: exportAction) {
                        Text("Export Keypoints")
                            .font(.headline)
                            .padding(.horizontal, 16)
                            .padding(.vertical, 10)
                            .background(Color.green)
                            .foregroundColor(.white)
                            .cornerRadius(8)
                    }
                    
                    Button {
                        appState.showAnalysisView = true
                    } label: {
                        Text("Analyze")
                            .font(.headline)
                            .padding(.horizontal, 20)
                            .padding(.vertical, 10)
                            .background(Color.purple)
                            .foregroundColor(.white)
                            .cornerRadius(8)
                    }
                }
            } else {
                Spacer()
            }
        }
        .padding(.horizontal)
        .padding(.vertical, 8)
        .frame(height: 60) // Increased height to accommodate ROI controls
    }
    
    private var fileInfoBar: some View {
        HStack(spacing: 8) {
            // Display Data Source Type
            Image(systemName: appState.isVideoSource ? "video.fill" : "cube.transparent.fill")
                .foregroundColor(appState.isVideoSource ? .blue : .green)
            
            Text(appState.isVideoSource ? "Video Source (2D pose only)" : "LiDAR Data Source (3D pose)")
                .font(.caption)
                .fontWeight(.medium)
                .foregroundColor(.secondary)
                
            Divider().frame(height: 15)
                
            // Keypoint status indicator
            if cameraManager.totalFrames > 0 {
                HStack(spacing: 4) {
                    // Check if keypoints actually exist by checking the processor
                    let hasKeypoints = appState.hasImportedKeypoints ||
                                      (appState.poseProcessor.getTotalFrames() > 0 &&
                                       appState.poseProcessor.hasKeypoints(for: cameraManager.currentFrameIndex))
                    
                    Circle()
                        .fill(hasKeypoints ? Color.green : Color.orange)
                        .frame(width: 8, height: 8)
                    
                    Text(hasKeypoints ?
                         "Keypoints: Available" :
                         "Keypoints: Not Detected")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
                
                Divider().frame(height: 15)
            }

            // Display File Name with proper handling
            if !appState.sourceFileName.isEmpty {
                // Use the explicit source file name if available
                Text(appState.sourceFileName)
                    .font(.caption)
                    .lineLimit(1)
                    .truncationMode(.middle)
            } else if let sourceURL = appState.sourceURL ?? appState.originalKeypointFileURL {
                // Fall back to URL's filename if sourceFileName is not set
                Text(sourceURL.lastPathComponent)
                    .font(.caption)
                    .lineLimit(1)
                    .truncationMode(.middle)
            } else {
                Text("No file loaded")
                    .font(.caption)
            }

            Spacer()
        }
        .font(.caption)
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .background(Color(.tertiarySystemBackground))
    }
    // MARK: - Helper Functions
    
    private func handleModeChange(isRecordMode: Bool) {
        if isRecordMode {
            // Switching to Record Mode
            DispatchQueue.global(qos: .userInitiated).async {
                // Use self directly, not weak self (since this is a struct)
                self.cameraManager.resumeStream()
            }
            
            // Reset states
            appState.resetFileAndKeypointState()
            appState.resetStatusState()
        } else {
            // Switching to Analysis Mode
            if cameraManager.isRecording {
                // Stop recording if switching during recording
                if appState.useLiDAR {
                    cameraManager.stopVideoRecording { _ in }
                } else {
                    cameraManager.stopRecording { _ in }
                }
            }
            
            // Stop camera stream (this is safe to call even if not streaming)
            DispatchQueue.global(qos: .userInitiated).async {
                // Use self directly, not weak self (since this is a struct)
                self.cameraManager.pauseStream()
            }
        }
    }

}
