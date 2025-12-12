//
//  FixedKeypointOverlay.swift
//  PoseA
//
//  Created by Ardhika Maulidani on 5/29/25.
//  Refactor from Shiela Cabahug's codebase

import SwiftUI

// MARK: - Fixed Keypoint Overlay (Simplified)
struct KeypointOverlayView: View {
    let keypoints: [KeypointData]
    let containerSize: CGSize
    let imageSize: CGSize
    
    var body: some View {
        ZStack {
            // Draw connections first
            ForEach(jointConnections.indices, id: \.self) { index in
                KeypointLineVM(
                    from: jointConnections[index].0,
                    to: jointConnections[index].1,
                    keypoints: keypoints,
                    containerSize: containerSize,
                    imageSize: imageSize
                )
            }
            
            // Draw keypoints on top
            ForEach(keypoints.indices, id: \.self) { index in
                let keypoint = keypoints[index]
                
                if keypoint.confidence > 0.3 {
                    KeypointDotVM(
                        keypoint: keypoint,
                        index: index,
                        containerSize: containerSize,
                        imageSize: imageSize
                    )
                }
            }
        }
    }
}
