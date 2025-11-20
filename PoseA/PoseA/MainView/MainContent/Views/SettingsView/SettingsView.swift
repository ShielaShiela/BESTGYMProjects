//
//  SettingsView.swift
//  PoseA
//
//  Created by Ardhika Maulidani on 5/27/25.
//  Refactor from Shiela Cabahug's codebase

import SwiftUI

struct SettingsView: View {
    @ObservedObject var appState: MainAppState
    @Environment(\.presentationMode) var presentationMode
    
    var body: some View {
        NavigationView {
            if !appState.isRecordMode {
                Form {
                    Section(header: Text("Media Settings")) {
                        Toggle("Auto-detect keypoints when loading video", isOn: $appState.autoDetectKeypoints)
                            .onChange(of: appState.autoDetectKeypoints) {
                                appState.saveUserPreferences()
                            }
                        
                        Toggle("Auto-load default data on startup", isOn: .constant(UserDefaults.standard.bool(forKey: "AutoLoadEnabled")))
                            .onChange(of: UserDefaults.standard.bool(forKey: "AutoLoadEnabled")) { oldValue, newValue in
                                UserDefaults.standard.set(newValue, forKey: "AutoLoadEnabled")
                            }
                    }
                    
                    Section(header: Text("ML Model Options")) {
                        Picker("Choose CoreML Model", selection: $appState.realtimeModel) {
                            Text("YOLO11n").tag("yolo11n-pose")
                            Text("YOLO11l").tag("yolo11l-pose")
                            Text("YOLO11x").tag("yolo11x-pose")
                            Text("YOLO_TF").tag("yolotf")
                        }
                        .onChange(of: appState.realtimeModel) {
                            appState.saveUserPreferences()
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
                .navigationBarItems(trailing: Button("Done") {
                    presentationMode.wrappedValue.dismiss()
                })

            } else {
                Form {
                    Section(header: Text("Recording Options")) {
                        HStack {
                            Text("Athlete Name:")
                            Spacer()
                            TextField("Required", text: $appState.athleteName)
                                .onChange(of: appState.athleteName) {
                                    appState.saveUserPreferences()
                                }
                        }

                        HStack {
                            Text("Athlete Action:")
                            Spacer()
                            TextField("Required", text: $appState.actionType)
                                .onChange(of: appState.actionType) {
                                    appState.saveUserPreferences()
                                }
                        }
                    }
                    
                    if appState.useLiDAR {
                        Section(header: Text("LiDAR Options")) {
                            Toggle("LiDAR Depth View", isOn: $appState.isLidarDepthView)
                                .onChange(of: appState.isLidarDepthView) {
                                    appState.saveUserPreferences()
                                }
                        }
                    }
                    
                    Section(header: Text("Real-Time Options")) {
                        Toggle("Real-time Pose Detection (BETA)", isOn: $appState.realtimeDetection)
                            .onChange(of: appState.realtimeDetection) {
                                appState.saveUserPreferences()
                            }
                        
                        if appState.realtimeDetection {
                            Picker("Choose View", selection: $appState.realtimeViewMode) {
                                Text("General").tag("general")
                                Text("Side View").tag("side-view")
                                Text("Front View").tag("front-view")
                                Text("Corner View").tag("corner-view")
                            }
                        }
                    }
                    
                    Section(header: Text("ML Model Options")) {
                        Picker("Choose CoreML Model", selection: $appState.realtimeModel) {
                            Text("YOLO11n").tag("yolo11n-pose")
                            Text("YOLO11l").tag("yolo11l-pose")
                            Text("YOLO11x").tag("yolo11x-pose")
                            Text("YOLO_TF").tag("yolotf")
                        }
                        .onChange(of: appState.realtimeModel) {
                            appState.saveUserPreferences()
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
                .navigationBarItems(trailing: Button("Done") {
                    presentationMode.wrappedValue.dismiss()
                })
            }
        }
    }
}
