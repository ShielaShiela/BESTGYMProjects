//
//  SettingsView.swift
//  PoseA
//
//  Created by Ardhika Maulidani on 5/27/25.
//  Refactor from Shiela Cabahug's codebase

import SwiftUI

struct SettingsView: View {
    @ObservedObject var appState: MainAppState
    @ObservedObject var cameraManager: CameraManagerVM
    @Environment(\.presentationMode) var presentationMode
    
    var body: some View {
        NavigationView {
            if !appState.isRecordMode {
                
                // ── ANALYSIS MODE SETTINGS ──────────────────────────────────
                Form {
                    Section(header: Text("Media Settings")) {
                        Toggle("Auto-detect keypoints when loading video", isOn: $appState.autoDetectKeypoints)
                            .onChange(of: appState.autoDetectKeypoints) {
                                appState.saveUserPreferences()
                            }
                        
                        Toggle("Auto-load default data on startup", isOn: .constant(UserDefaults.standard.bool(forKey: "AutoLoadEnabled")))
                            .onChange(of: UserDefaults.standard.bool(forKey: "AutoLoadEnabled")) { _, newValue in
                                UserDefaults.standard.set(newValue, forKey: "AutoLoadEnabled")
                            }
                    }
                    
                    Section(header: Text("Analysis Settings")) {
                        Picker("Angle Unit", selection: $appState.angleUnit) {
                            ForEach(AngleUnit.allCases) { unit in
                                Text(unit.rawValue).tag(unit)
                            }
                        }
                        
                        Picker("Distance Unit", selection: $appState.distanceUnit) {
                            ForEach(DistanceUnit.allCases) { unit in
                                Text(unit.rawValue).tag(unit)
                            }
                        }
                        
                        Picker("Time Unit", selection: $appState.timeUnit) {
                            ForEach(TimeUnit.allCases) { unit in
                                Text(unit.rawValue).tag(unit)
                            }
                        }

                        Toggle("Analysis Data Smoothing", isOn: $appState.analysisFilterMode)
                            .onChange(of: appState.analysisFilterMode) {
                                appState.saveUserPreferences()
                            }
                    }
                }
                .navigationTitle("Settings")
                .navigationBarItems(trailing: doneButton)
                
            } else {
                
                // ── RECORD MODE SETTINGS ────────────────────────────────────
                Form {
                    Section(header: Text("Recording Options")) {
                        HStack {
                            Text("Athlete Name:")
                            Spacer()
                            TextField("Required", text: $appState.athleteName)
                                .multilineTextAlignment(.trailing)
                                .autocorrectionDisabled()
                                .onChange(of: appState.athleteName) {
                                    appState.saveUserPreferences()
                                }
                        }

                        HStack {
                            Text("Athlete Action:")
                            Spacer()
                            TextField("Required", text: $appState.actionType)
                                .multilineTextAlignment(.trailing)
                                .autocorrectionDisabled()
                                .onChange(of: appState.actionType) {
                                    appState.saveUserPreferences()
                                }
                        }
                    }
                    
                    Section(header: Text("Camera Options")) {
                        // Frame Rate
                        Picker("Frame Rate", selection: Binding(
                            get: { cameraManager.cameraConfiguration.frameRate },
                            set: { _ in cameraManager.cycleFrameRate() }
                        )) {
                            ForEach(CameraConfiguration.FrameRate.allCases, id: \.self) { rate in
                                Text(rate.description).tag(rate)
                            }
                        }

                        // Resolution
                        Picker("Resolution", selection: Binding(
                            get: { cameraManager.cameraConfiguration.resolution },
                            set: { _ in cameraManager.cycleResolution() }
                        )) {
                            ForEach(CameraConfiguration.Resolution.allCases, id: \.self) { res in
                                Text(res.shortDescription).tag(res)
                            }
                        }
                    }
                    
                    Section(header: Text("Pose Detection")) {
                        Toggle("Real-time Pose Detection (BETA)", isOn: $appState.realtimeDetection)
                            .onChange(of: appState.realtimeDetection) {
                                if appState.realtimeDetection {
                                    appState.realtimeModel = "yolo11l-pose"
                                }
                                appState.saveUserPreferences()
                            }
                        
                        // Model picker — shown always so user can override the auto-set
                        Picker("YOLO Model", selection: $appState.realtimeModel) {
                            Text("YOLO11n (Fast)").tag("yolo11n-pose")
                            Text("YOLO11l (Default)").tag("yolo11l-pose")
                            Text("YOLO11x (Accurate)").tag("yolo11x-pose")
                            Text("YOLO_TF").tag("yolotf")
                        }
                        .onChange(of: appState.realtimeModel) {
                            appState.saveUserPreferences()
                        }
                        
                        if appState.realtimeDetection {
                            Picker("View Mode", selection: $appState.realtimeViewMode) {
                                Text("General").tag("general")
                                Text("Side View").tag("side-view")
                                Text("Front View").tag("front-view")
                                Text("Corner View").tag("corner-view")
                            }
                        }
                    }
                }
                .navigationTitle("Settings")
                .navigationBarItems(trailing: doneButton)
            }
        }
    }
    
    private var doneButton: some View {
        Button("Done") {
            presentationMode.wrappedValue.dismiss()
        }
    }
}
