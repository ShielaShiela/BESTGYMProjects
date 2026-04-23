//
//  InformationView.swift
//  PoseA
//
//  Created by Ardhika Maulidani on 7/13/25.
//

import SwiftUI

struct InformationView: View {
    @ObservedObject var appState: MainAppState
    @State var ROIModel: ROIViewModel
    @State var barPointVM: BarPointVM
    @State var mediaManager: MediaManagerVM
    
    var body: some View {
        TabView {
            VideoInfoView
            if appState.isAnalysisAvailable {
                GymnasticsInfoView
            }
        }
        .tabViewStyle(PageTabViewStyle())
        .indexViewStyle(.page(backgroundDisplayMode: .always))
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
    
    @ViewBuilder
    private var VideoInfoView: some View {
        // Status indicator
        VStack(alignment: .leading, spacing: 8) {
            Text("Video Information")
                .font(.title)
                .fontWeight(.bold)
                .padding(.bottom, 4)
            
            HStack(spacing: 4) {
                // Display File Name with proper handling
                if !appState.sourceFileName.isEmpty {
                    // Use the explicit source file name if available
                    Circle()
                        .fill(.green)
                        .frame(width: 8, height: 8)
                    
                    Text("Filename: \(appState.sourceFileName)")
                        .font(.caption)
                        .foregroundColor(.secondary)
                        .lineLimit(1)
                        .truncationMode(.middle)
                } else if let sourceURL = appState.sourceURL ?? appState.originalKeypointFileURL {
                    // Fall back to URL's filename if sourceFileName is not set
                    Circle()
                        .fill(.green)
                        .frame(width: 8, height: 8)
                    
                    Text("Filename: \(sourceURL.lastPathComponent)")
                        .font(.caption)
                        .foregroundColor(.secondary)
                        .lineLimit(1)
                        .truncationMode(.middle)
                } else {
                    Circle()
                        .fill(.red)
                        .frame(width: 8, height: 8)
                    
                    Text("Filename: No file loaded")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
            }
            
            Divider()
            
            // Display Data Source Type
            HStack(spacing: 4) {
                Circle()
                    .fill(appState.sourceFileName.isEmpty ? .red : appState.isVideoSource ? .gray : .green)
                    .frame(width: 8, height: 8)
                
                Text(appState.sourceFileName.isEmpty ? "Source: No file loaded" : appState.isVideoSource ? "Source: Video (2D pose)" : "Source: Video+LiDAR (3D pose)")
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
            
            Divider()
            
            // Keypoint Status Indicator
            HStack(spacing: 4) {
                // Check if keypoints actually exist
                Circle()
                    .fill(mediaManager.isKeypointAvailable ? Color.green : Color.red)
                    .frame(width: 8, height: 8)
                
                Text(mediaManager.isKeypointAvailable ? "Keypoints: Available" : "Keypoints: Not Detected")
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
            
            Divider()
            
            // ROI Status
            HStack(spacing: 4) {
                Circle()
                    .fill(ROIModel.isROIAvailable ? Color.green : Color.gray)
                    .frame(width: 8, height: 8)
                
                Text(ROIModel.isROIAvailable ? "ROI Status: ROI Set" : "ROI Status: ROI Unavailable")
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
            
            Divider()
            
            // ROI Status
            HStack(spacing: 4) {
                Circle()
                    .fill(barPointVM.isFirstPointAvailable && barPointVM.isSecondPointAvailable ? Color.green : Color.gray)
                    .frame(width: 8, height: 8)
                
                Text(barPointVM.isFirstPointAvailable && barPointVM.isSecondPointAvailable ? "Bar Status: Available" : "Bar Status: Unavailable")
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
            
            Spacer()
        }
    }
    
    @ViewBuilder
    private var GymnasticsInfoView: some View {
        // Status indicator
        VStack(alignment: .leading, spacing: 8) {
            Text("Gymnastics Information")
                .font(.title)
                .fontWeight(.bold)
                .padding(.bottom, 4)
            
     
            // Display Movement Type
            HStack(spacing: 4) {
                Circle()
                    .fill(.gray)
                    .frame(width: 8, height: 8)
                
                Text("Routine Type: Tkatchev Piked")
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
            
            Divider()
            
            // Movement Class
            HStack(spacing: 4) {
                // Check if keypoints actually exist
                Circle()
                    .fill(.gray)
                    .frame(width: 8, height: 8)
                
                Text("Routine Class: D")
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
            
            Divider()
            
            // Flight Time
            if let startIdx = mediaManager.EventsData.flightStartPoseIdx, let endIdx = mediaManager.EventsData.flightEndPoseIdx {
                HStack(spacing: 4) {
                    Circle()
                        .fill(.green)
                        .frame(width: 8, height: 8)
                    
                    let flightTimeMs = Double(endIdx - startIdx) / mediaManager.fps * 1000
                    Text("Flight Time: \(String(format: "%.1f", flightTimeMs)) ms")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
            }
            
            Divider()
            
            // Flight Height
            if let peakIdx = mediaManager.EventsData.peakFlightIdx {
                HStack(spacing: 4) {
                    Circle()
                        .fill(.green)
                        .frame(width: 8, height: 8)
                    
                    let flightHeight = mediaManager.FeaturesData[peakIdx]?.headHeightM ?? 0.0
                    Text("Flight Height: \(String(format: "%.2f", flightHeight)) m")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
            }
            
            Divider()
            
            // Flight Height
            if mediaManager.EventsData.rotationDir != "" {
                HStack(spacing: 4) {
                    Circle()
                        .fill(.green)
                        .frame(width: 8, height: 8)
                    
                    Text("Swing Rotation: \(mediaManager.EventsData.rotationDir)")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
            }
            Spacer()
        }
    }
}
