//
//  FrameView.swift
//  PoseA
//
//  Created by Bestlab on 5/29/25.
//

import SwiftUI

// MARK: - Fixed Frame View (Simplified)
struct FrameView: View {
    let image: UIImage?
    let keypoints: [KeypointData]?
    let isAnnotationMode: Bool
    let rotation: Int
    let appState: AppState
    @Binding var selectedKeypointIndex: Int?
    
    var body: some View {
        GeometryReader { geometry in
            ZStack {
                // Background image
                if let image = image {
                    Image(uiImage: image)
                        .resizable()
                        .aspectRatio(contentMode: .fit)
                        .rotationEffect(.degrees(Double(rotation) * 90))
                        .clipped()
                } else {
                    Rectangle()
                        .fill(Color.black)
                }
                
                // ROI Selection Overlay
                if appState.isROIMode {
                    ROISelectionOverlay(
                        appState: appState,
                        containerSize: geometry.size,
                        imageSize: image?.size ?? CGSize(width: 1920, height: 1440),
                        rotation: rotation
                    )
                }
                
                // Keypoint Overlay - only show when not selecting ROI
                if let keypoints = keypoints,
                   !keypoints.isEmpty,
                   appState.showKeypoints,
                   !appState.isSelectingROI {
                    
                    FixedKeypointOverlay(
                        keypoints: keypoints,
                        containerSize: geometry.size,
                        imageSize: image?.size ?? CGSize(width: 1920, height: 1440),
                        rotation: rotation,
                        isAnnotationMode: isAnnotationMode,
                        selectedKeypointIndex: $selectedKeypointIndex
                    )
                }
            }
        }
    }
}
