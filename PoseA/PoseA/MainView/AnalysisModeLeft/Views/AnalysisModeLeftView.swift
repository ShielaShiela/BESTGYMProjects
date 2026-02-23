//
//  MainContentView.swift
//  PoseA
//
//  Created by Ardhika Maulidani on 7/8/25.
//

import SwiftUI
//
//struct AnalysisModeLeftView: View {
//    @ObservedObject var appState: MainAppState
//    @Binding var ROIModel: ROIViewModel
//    @Binding var BoxModel: BoxViewModel
//    @State var mediaManager: MediaManagerVM
//    @State var calibrationModel: CalibrationModel
//    var body: some View {
//        GeometryReader { geometry in
//            VStack(spacing: 0) {
//                ZStack {
//                    Color.black
//                        .edgesIgnoringSafeArea(.bottom)
//                    
//                    if mediaManager.isMediaAvailable {
//                        FrameView(
//                            image: mediaManager.currentFrameImage,
//                            keypoints: mediaManager.getKeypointsCurrent(),
//                            appState: appState,
//                            ROIModel: $ROIModel,
//                            BoxModel: $BoxModel,
//                            calibrationModel: $calibrationModel
//                            
//                        )
//                        .frame(height: geometry.size.height * 0.75)
//                        .overlay(
//                            // Debug info overlay
//                            VStack {
//                                HStack {
//                                    Text("Frame: \(mediaManager.currentFrameIndex + 1)/\(mediaManager.mediaPlayerViewModel.totalFrames)")
//                                        .font(.caption)
//                                        .padding(6)
//                                        .background(Color.black.opacity(0.7))
//                                        .foregroundColor(.white)
//                                        .cornerRadius(4)
//                                    
//                                    Spacer()
//                                    
//                                    if let keypoints = mediaManager.getKeypointsCurrent() {
//                                        Text("Keypoints: \(keypoints.count)")
//                                            .font(.caption)
//                                            .padding(6)
//                                            .background(keypoints.count == 17 ? Color.green.opacity(0.7) : Color.red.opacity(0.7))
//                                            .foregroundColor(.white)
//                                            .cornerRadius(4)
//                                    }
//                                }
//                                .padding(.horizontal)
//                                .padding(.top, 8)
//                                
//                                Spacer()
//                            }
//                        )
//                    } else {
//                        // Placeholder view
//                        VStack(spacing: 20) {
//                            Text("No File Selected")
//                                .font(.title2)
//                                .multilineTextAlignment(.center)
//                                .foregroundColor(.secondary)
//                            
//                            Image(systemName: "folder.fill")
//                                .font(.system(size: 50))
//                                .foregroundColor(.secondary)
//                            
//                            Text("Open a file or video to analyze")
//                                .font(.body)
//                                .foregroundColor(.secondary)
//                                .padding(.top, 10)
//                            
//                            Button(action: {
//                                appState.isFilePickerPresented = true
//                            }) {
//                                Text("Select File")
//                                    .font(.headline)
//                                    .padding()
//                                    .background(Color.blue)
//                                    .foregroundColor(.white)
//                                    .cornerRadius(8)
//                            }
//                            .padding(.top, 20)
//                        }
//                        .frame(height: geometry.size.height)
//                        .frame(maxWidth: .infinity)
//                        .background(Color(.systemGray6))
//                    }
//                }
//                .cornerRadius(16)
//                .padding(.horizontal, 8)
//                
//                if mediaManager.isMediaAvailable {
//                    PlaybackControlLandscapeView(mediaManager: mediaManager)
//                        .background(Color.clear.contentShape(Rectangle()))
//                        .frame(height: geometry.size.height * 0.25 - 10)
//                        .padding(.top, 10)
//                }
//            }
//        }
//    }
//}
struct AnalysisModeLeftView: View {
    @ObservedObject var appState: MainAppState
    @Binding var ROIModel: ROIViewModel
    @Binding var BoxModel: BoxViewModel
    @State var mediaManager: MediaManagerVM
    @State var calibrationModel: CalibrationModel

    var body: some View {
        GeometryReader { geometry in
            ZStack(alignment: .topLeading) {

                // ── Main content ─────────────────────────────────────────
                VStack(spacing: 0) {
                    ZStack {
                        Color.black.edgesIgnoringSafeArea(.bottom)

                        if mediaManager.isMediaAvailable {
                            FrameView(
                                image: mediaManager.currentFrameImage,
                                keypoints: mediaManager.getKeypointsCurrent(),
                                appState: appState,
                                ROIModel: $ROIModel,
                                BoxModel: $BoxModel
                            )
                            .frame(height: geometry.size.height * 0.75)
                            .overlay(
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
                            // Placeholder
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

                // ── Calibration overlay (outside clipped ZStack) ─────────
                if mediaManager.isMediaAvailable {
                    CalibrationOverlayView(
                        calibrationModel: $calibrationModel,
                        containerSize: CGSize(
                            width: geometry.size.width - 16,
                            height: geometry.size.height * 0.75
                        ),
                        imageSize: mediaManager.currentFrameImage?.size ?? .zero
                    )
                    .frame(
                        width: geometry.size.width - 16,
                        height: geometry.size.height * 0.75
                    )
                    .offset(x: 8, y: 0)
                    .allowsHitTesting(calibrationModel.isCalibrationMode)
                }

            } // end outer ZStack
        }
    }
}
