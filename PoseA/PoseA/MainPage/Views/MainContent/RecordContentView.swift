
//
//  MainRecordContentView.swift
//  PoseA
//
//  Created by Ardhika Maulidani on 6/25/25.
//

import SwiftUI

extension MainContentView {
    // MARK: - Mode-Specific Content
    var recordModeContent: some View {
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
}
