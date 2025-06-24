//
//  AppHeader.swift
//  PoseA
//
//  Created by Bestlab on 6/2/25.
//

import SwiftUI

// MARK: - App Header
struct AppHeader: View {
    @ObservedObject var appState: MainAppState
    @ObservedObject var ROIModel: ROIViewModel
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
                        if ROIModel.isROIMode {
                            ROIModel.setROIMode(false)
                        } else {
                            ROIModel.setROIMode(true)
                        }
                    }) {
                        HStack(spacing: 4) {
                            Image(systemName: ROIModel.isROIMode ? "viewfinder.circle.fill" : "viewfinder.circle")
                            Text(ROIModel.isROIMode ? "Exit ROI" : "ROI Tools")
                        }
                        .font(.caption)
                        .padding(.horizontal, 8)
                        .padding(.vertical, 4)
                        .background(ROIModel.isROIMode ? Color.orange : Color.gray)
                        .foregroundColor(.white)
                        .cornerRadius(6)
                    }
                    
                    // Clear ROI button (only show if we have an ROI)
                    if ROIModel.isROIAvailable && ROIModel.isROIMode {
                        Button(action: {
                            ROIModel.clearROI()
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
            
            Spacer()
            
            // Detection and Analysis buttons
            let hasKeypoints = appState.hasImportedKeypoints ||
                              (appState.poseProcessor.getTotalFrames() > 0 &&
                               appState.poseProcessor.hasKeypoints(for: cameraManager.currentFrameIndex))
            
            if cameraManager.totalFrames > 0 && !hasKeypoints && !appState.isProcessing && !ROIModel.isROIMode {
                Button(action: processAction) {
                    Text(ROIModel.isROIAvailable ? "Detect Pose in ROI (All Frames)" : "Detect Pose (All Frames)")
                        .font(.subheadline)
                        .padding(.horizontal, 16)
                        .padding(.vertical, 10)
                        .background(ROIModel.isROIAvailable ? Color.orange : Color.blue)
                        .foregroundColor(.white)
                        .cornerRadius(8)
                }
                .disabled(appState.isProcessing)
            } else if hasKeypoints && !ROIModel.isROIMode {
                HStack(spacing: 12) {
                    Button(action: exportAction) {
                        Text("Export Keypoints")
                            .font(.caption)
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
                            .font(.caption)
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
