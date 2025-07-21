//
//  MainContentView.swift
//  PoseA
//
//  Created by Ardhika Maulidani on 7/8/25.
//

import SwiftUI

struct MainContentLeftView: View {
    @ObservedObject var appState: MainAppState
    @ObservedObject var ROIModel: ROIViewModel
    @ObservedObject var BoxModel: BoxViewModel
    @State var mediaManager: MediaManagerVM
    
    var body: some View {
        GeometryReader { geometry in
            VStack(spacing: 0) {
                ZStack {
                    Color.black
                        .edgesIgnoringSafeArea(.bottom)
                    
                    if mediaManager.isMediaAvailable {
                        FrameView(
                            image: mediaManager.currentFrameImage,
                            keypoints: mediaManager.getKeypointsCurrent(),
                            appState: appState,
                            ROIModel: ROIModel,
                            BoxModel: BoxModel
                        )
                        .frame(height: geometry.size.height * 0.75)
                        .overlay(
                            // Debug info overlay
                            VStack {
                                HStack {
                                    Text("Frame: \(mediaManager.currentFrameIndex + 1)/\(mediaManager.mediaPlayerViewModel.totalFrames)")
                                        .font(.caption)
                                        .padding(6)
                                        .background(Color.black.opacity(0.7))
                                        .foregroundColor(.white)
                                        .cornerRadius(4)
                                    
                                    Spacer()
                                    
                                    if let keypoints = mediaManager.getKeypointsCurrent() {
                                        Text("Keypoints: \(keypoints.count)")
                                            .font(.caption)
                                            .padding(6)
                                            .background(keypoints.count == 17 ? Color.green.opacity(0.7) : Color.red.opacity(0.7))
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
                        // Placeholder view
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
                        .frame(height: geometry.size.height)
                        .frame(maxWidth: .infinity)
                        .background(Color(.systemGray6))
                    }
                }
                .cornerRadius(16)
                .padding(.horizontal, 8)
                
                if mediaManager.isMediaAvailable {
                    PlaybackControlLandscapeView(mediaManager: mediaManager)
                        .background(Color.clear.contentShape(Rectangle()))
                        .frame(height: geometry.size.height * 0.25 - 10)
                        .padding(.top, 10)
                }
            }
        }
    }
}
