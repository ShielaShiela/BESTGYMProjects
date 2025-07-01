//
//  VideoContentView.swift
//  PoseA
//
//  Created by Ardhika Maulidani on 6/25/25.
//

import SwiftUI

extension MainContentView {
    var VideoViewerModeContent: some View {
        ZStack {
            if cameraManager.totalFrames > 0 {
                // Display load ed frame with keypoint overlay and ROI support
                FrameView(
                    image: cameraManager.currentFrameImage,
                    keypoints: appState.showKeypoints ? appState.poseProcessor.getKeypoints(for: cameraManager.currentFrameIndex) : nil,
                    rotation: appState.imageRotation,
                    appState: appState,
                    ROIModel: ROIModel
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
}    

