//
//  RecordLandscapeView.swift
//  PoseA
//
//  Created by Ardhika Maulidani on 7/21/25.
//

import SwiftUI

struct RecordLandscapeView: View {
    @ObservedObject var appState: MainAppState
    @ObservedObject var cameraManager: CameraManagerVM
    
    @State var showInfoView: Bool = false
    @State var pointPickerVM: PointPickerViewModel = PointPickerViewModel()
    @State var rtPoseJointVM: RealtimePoseJointViewModel
    
    init(appState: MainAppState, cameraManager: CameraManagerVM) {
        self.appState = appState
        self.cameraManager = cameraManager
        self._rtPoseJointVM = State(wrappedValue: RealtimePoseJointViewModel(cameraManager: cameraManager))
    }
    
    var body: some View {
        ZStack {
            Color.black
            // Get Orientation
            let isLandscape = OrientationCache.shared.orientation == .landscapeLeft || OrientationCache.shared.orientation == .landscapeRight
            
            GeometryReader { geometry in
                Group {
                    // Left black area
                    ZStack {
                        GeometryReader { geo in
                            // Background Fill
                            Rectangle().fill(Color.black)
                            
                            // Information Button
                            Button(action: {
                                self.showInfoView = true
                            }) {
                                Image(systemName: "info.circle")
                                    .font(.body)
                                    .foregroundStyle(Color.white)
                            }
                            .contentShape(Rectangle())
                            .frame(width: isLandscape ? geo.size.width * 0.8 : geo.size.width * 0.25,
                                   height: isLandscape ? geo.size.height * 0.25 : geo.size.height * 0.8)
                            .position(x: isLandscape ? geo.size.width * 0.5 : geo.size.width * 0.125,
                                      y: isLandscape ? geo.size.height * 0.875 : geo.size.height * 0.75 )
                            .popover(isPresented: $showInfoView) {
                                // Status indicator
                                VStack(alignment: .leading, spacing: 8) {
                                    Text("Information")
                                        .font(.body)
                                        .fontWeight(.bold)
                                    
                                    HStack(spacing: 4) {
                                        // Display Resolution Status
                                        Circle()
                                            .fill(.green)
                                            .frame(width: 8, height: 8)
                                        
                                        Text("Resolution: \(cameraManager.cameraConfiguration.resolution.width) x \(cameraManager.cameraConfiguration.resolution.height)")
                                            .font(.caption)
                                            .foregroundColor(.secondary)
                                            .lineLimit(1)
                                            .truncationMode(.middle)
                                    }
                                    
                                    Divider()
                                    
                                    HStack(spacing: 4) {
                                        // Display Frame Rate Status
                                        Circle()
                                            .fill(.green)
                                            .frame(width: 8, height: 8)
                                        
                                        Text("Frame Rate Set: \(cameraManager.cameraConfiguration.frameRate.rawValue) FPS")
                                            .font(.caption)
                                            .foregroundColor(.secondary)
                                            .lineLimit(1)
                                            .truncationMode(.middle)
                                    }
                                    
                                    Divider()

                                    HStack(spacing: 4) {
                                        // Display Lidar Support
                                        Circle()
                                            .fill(cameraManager.isLiDARSupported ? .green : .red)
                                            .frame(width: 8, height: 8)
                                        
                                        Text("LiDAR Support: \(cameraManager.isLiDARSupported ? "Yes" : "No")")
                                            .font(.caption)
                                            .foregroundColor(.secondary)
                                            .lineLimit(1)
                                            .truncationMode(.middle)
                                    }
                                    
                                    Divider()
                                        
                                    HStack(spacing: 4) {
                                        // Display Lidar Status
                                        Circle()
                                            .fill(cameraManager.isLiDAREnabled ? .green : .red)
                                            .frame(width: 8, height: 8)
                                        
                                        Text("LiDAR Enabled: \(cameraManager.isLiDAREnabled ? "Yes" : "No")")
                                            .font(.caption)
                                            .foregroundColor(.secondary)
                                            .lineLimit(1)
                                            .truncationMode(.middle)
                                    }
                                    
                                    Divider()
                                    
                                    // Keypoint Status Indicator
                                    HStack(spacing: 4) {
                                        // Display Lidar Status
                                        Circle()
                                            .fill(cameraManager.isFilteringDepth ? .green : .red)
                                            .frame(width: 8, height: 8)
                                        
                                        Text("LiDAR Filtering: \(cameraManager.isFilteringDepth ? "Yes" : "No")")
                                            .font(.caption)
                                            .foregroundColor(.secondary)
                                            .lineLimit(1)
                                            .truncationMode(.middle)
                                    }
                                    
                                    Divider()
                                    
                                    // Stream FPS Status Indicator
                                    HStack(spacing: 4) {
                                        // Display FPS Status
                                        Circle()
                                            .fill(cameraManager.fpsStream > 20 ? .green : .red)
                                            .frame(width: 8, height: 8)
                                        
                                        Text("FPS Benchmark: \(cameraManager.fpsModel, specifier: "%.1f") / \(cameraManager.fpsStream, specifier: "%.1f")")
                                            .font(.caption)
                                            .foregroundColor(.secondary)
                                            .lineLimit(1)
                                            .truncationMode(.middle) 
                                    }
                                }
                                .padding()
                                .presentationCompactAdaptation(.popover)
                            }

                            // Setting Button
                            Button(action: {
                                appState.showSettingsView = true
                            }) {
                                Image(systemName: "gear")
                                    .font(.body)
                                    .foregroundStyle(Color.white)
                            }
                            .contentShape(Rectangle())
                            .frame(width: isLandscape ? geo.size.width * 0.8 : geo.size.width * 0.25,
                                   height: isLandscape ? geo.size.height * 0.25 : geo.size.height * 0.8)
                            .position(x: isLandscape ? geo.size.width * 0.5 : geo.size.width * 0.375,
                                      y: isLandscape ? geo.size.height * 0.625 : geo.size.height * 0.75 )
                            
                            // FPS Button
                            Button(action: {
                                cameraManager.cycleFrameRate()
                            }) {
                                Text(cameraManager.cameraConfiguration.frameRate.description)
                                    .font(.body)
                                    .fontWeight(.medium)
                                    .foregroundStyle(Color.white)
                            }
                            .contentShape(Rectangle())
                            .frame(width: isLandscape ? geo.size.width * 0.8 : geo.size.width * 0.25,
                                   height: isLandscape ? geo.size.height * 0.25 : geo.size.height * 0.8)
                            .position(x: isLandscape ? geo.size.width * 0.5 : geo.size.width * 0.625,
                                      y: isLandscape ? geo.size.height * 0.375 : geo.size.height * 0.75 )
                            
                            // Resolution Button
                            Button(action: {
                                cameraManager.cycleResolution()
                            }) {
                                Text(cameraManager.cameraConfiguration.resolution.shortDescription)
                                    .font(.body)
                                    .fontWeight(.medium)
                                    .foregroundStyle(Color.white)
                            }
                            .contentShape(Rectangle())
                            .frame(width: isLandscape ? geo.size.width * 0.8 : geo.size.width * 0.25,
                                   height: isLandscape ? geo.size.height * 0.25 : geo.size.height * 0.8)
                            .position(x: isLandscape ? geo.size.width * 0.5 : geo.size.width * 0.875,
                                      y: isLandscape ? geo.size.height * 0.125 : geo.size.height * 0.75 )
                            
                        }
                    }
                        
                        .frame(width: isLandscape ? geometry.size.width * 0.1 : geometry.size.width,
                               height: isLandscape ? geometry.size.height : geometry.size.height * 0.1)
                        .position(x: isLandscape ? geometry.size.width * 0.05 : geometry.size.width * 0.5,
                                  y: isLandscape ? geometry.size.height * 0.5 : geometry.size.height * 0.05)

                    // Camera view
                    if cameraManager.isCameraReady {
                        ZStack {
                            // Camera Preview
                            CameraPreviewView(appState: self.appState, cameraManager: self.cameraManager)
                            
                            // Pose Information Overlay
                            PoseInformationView(rtPoseJointVM: rtPoseJointVM)
                            
                            // Realtime Detection
                            if appState.realtimeDetection {
                                // Pose Overlay
                                if let nearest = rtPoseJointVM.nearestPose {
                                    PoseOverlayView(poses: [nearest],
                                                    videoSize: isLandscape ? CGSize(width: self.cameraManager.cameraConfiguration.resolution.width,
                                                                                    height: self.cameraManager.cameraConfiguration.resolution.height) :
                                                                            CGSize(width: self.cameraManager.cameraConfiguration.resolution.height,
                                                                                   height: self.cameraManager.cameraConfiguration.resolution.width))
                                } else {
                                    PoseOverlayView(poses: self.cameraManager.poseKeypoints,
                                                    videoSize: isLandscape ? CGSize(width: self.cameraManager.cameraConfiguration.resolution.width,
                                                                                    height: self.cameraManager.cameraConfiguration.resolution.height) :
                                                                            CGSize(width: self.cameraManager.cameraConfiguration.resolution.height,
                                                                                   height: self.cameraManager.cameraConfiguration.resolution.width))
                                }
                                
//                                // Pose Information Overlay
//                                PoseInformationView()
                                
                                // Point Picker Overlay for Horizontal Bar
                                if appState.realtimeViewMode == "side-view" {
                                    PointPickerView(pointPickerVM: $pointPickerVM,
                                                    imageSize: isLandscape ? CGSize(width: self.cameraManager.cameraConfiguration.resolution.width,
                                                                                    height: self.cameraManager.cameraConfiguration.resolution.height) :
                                                                            CGSize(width: self.cameraManager.cameraConfiguration.resolution.height,
                                                                                   height: self.cameraManager.cameraConfiguration.resolution.width))
                                    .allowsHitTesting(true)
                                }
                            }
                        }
                        .frame(width: isLandscape ? geometry.size.width * 0.7 : geometry.size.width,
                               height: isLandscape ? geometry.size.height : geometry.size.height * 0.7)
                        
                        .position(x: isLandscape ? geometry.size.width * 0.45 : geometry.size.width * 0.5,
                                  y: isLandscape ? geometry.size.height * 0.5 : geometry.size.height * 0.45)
                    
                        .onChange(of: appState.realtimeDetection) {
                            cameraManager.toogleRealtimeDetection()
                        }
                        .onChange(of: appState.realtimeModel) { oldValue, newValue in
                            cameraManager.setRealtimeModelVersion(newValue)
                        }
                        .onChange(of: pointPickerVM.pointImage) { _, newPoint in
                            rtPoseJointVM.updatePoint(point: newPoint)
                        }
                        .transition(.opacity) // Optional smooth fade-in
                    }

                    // Right black area + button
                    ZStack {
                        GeometryReader { geo in
                            // Background Fill
                            Rectangle().fill(Color.black)
                            
                            // Record Button
                            Button(action: {
                                if cameraManager.isRecording {
                                    // Stop recording
                                    cameraManager.stopRecording { recordingURL in
                                        if let url = recordingURL {
                                            print("Recording saved to: \(url)")
                                        } else {
                                            print("Failed to save recording")
                                        }
                                    }
                                } else {
                                    // Start recording
                                    cameraManager.startRecording(personName: appState.athleteName,
                                                                 action: appState.actionType)
                                }
                            }) {
                                ZStack {
                                    Circle()
                                        .fill(cameraManager.isRecording ? Color.white : Color.red)
                                        .overlay(
                                            Circle()
                                                .stroke(Color.white, lineWidth: 4)
                                        )
                                    if cameraManager.isRecording {
                                        // Stop icon (square)
                                        Rectangle()
                                            .fill(Color.red)
                                            .frame(width: 20, height: 20)
                                    } else if cameraManager.isPreparingRecording {
                                        // Loading indicator when preparing video writer
                                        ProgressView()
                                            .progressViewStyle(CircularProgressViewStyle(tint: .white))
                                            .scaleEffect(0.8)
                                    }
                                }
                            }
                            .disabled(cameraManager.isPreparingRecording)
                            .frame(width: 60, height: 60)
                            .position(x: geo.size.width * 0.5, y: geo.size.height * 0.5)

                            // LiDAR Option Buttons
                            Text("LiDAR")
                                .foregroundColor(.white)
                                .font(.caption)
                                .position(x: isLandscape ? geo.size.width * 0.5 : geo.size.width * 0.15,
                                          y: isLandscape ? geo.size.height * 0.75 : geo.size.height * 0.35 )
                            
                            Toggle("", isOn: $appState.useLiDAR)
                                .labelsHidden()
                                .toggleStyle(SwitchToggleStyle(tint: .yellow.opacity(0.7)))
                                .position(x: isLandscape ? geo.size.width * 0.5 : geo.size.width * 0.15,
                                          y: isLandscape ? geo.size.height * 0.85 : geo.size.height * 0.55 )
                                .onChange(of: appState.useLiDAR) { old_value, new_value in
                                    cameraManager.toggleLiDAR()
                                    if old_value == true && new_value == false {
                                        appState.isLidarDepthView = false
                                    }
                                }
                                .disabled(!cameraManager.isLiDARSupported)
                            
                            // Analysis Mode Buttons
                            Button {
                                // Switching FROM Record Mode TO Analysis Mode
                                appState.isRecordMode = false
                                
                                // First stop any recording
                                if cameraManager.isRecording {
                                    cameraManager.stopRecording { _ in }
                                }
                                
                                // Important: Make sure live capture is disabled
                                DispatchQueue.global(qos: .userInitiated).async {
                                    self.cameraManager.pauseStream()
                                    
                                    // Make extra sure isLiveCapture is set to false
                                    DispatchQueue.main.async {
                                        self.cameraManager.isLiveCapture = false
                                        log("Camera preview disabled.", level: .info)
                                    }
                                }
                            } label: {
                                    Image(systemName: "waveform")
                                    .resizable()
                                    .aspectRatio(contentMode: .fit)
                                    .foregroundStyle(Color.white)
                                    .padding()
                            }
                            .frame(width: 70, height: 70)
                            .position(x: isLandscape ? geo.size.width * 0.5 : geo.size.width * 0.85,
                                      y: isLandscape ? geo.size.height * 0.15 : geo.size.height * 0.5)

                        }
                    }
                    .frame(width: isLandscape ? geometry.size.width * 0.2 : geometry.size.width,
                           height: isLandscape ? geometry.size.height : geometry.size.height * 0.2)
                    .position(x: isLandscape ? geometry.size.width * 0.9 : geometry.size.width * 0.5,
                              y: isLandscape ? geometry.size.height * 0.5 : geometry.size.height * 0.9)
                }
                .animation(.easeInOut(duration: 0.3), value: appState.orientation)
            }
        }
        .edgesIgnoringSafeArea(.all)
        .onAppear {
            cameraManager.reconfigureCamera()
        }
    }
}
