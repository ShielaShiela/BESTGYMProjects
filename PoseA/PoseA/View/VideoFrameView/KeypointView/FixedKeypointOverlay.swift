//
//  FixedKeypointOverlay.swift
//  PoseA
//
//  Created by Ardhika Maulidani on 5/29/25.
//  Refactor from Shiela Cabahug's codebase

import SwiftUI

// MARK: - Fixed Keypoint Overlay (Simplified)
struct FixedKeypointOverlay: View {
    let keypoints: [KeypointData]
    let containerSize: CGSize
    let imageSize: CGSize
    let rotation: Int
    let isAnnotationMode: Bool
    @Binding var selectedKeypointIndex: Int?
    
    // Simplified connections
    private let connections: [(String, String)] = [
        // Torso
        ("left_shoulder", "right_shoulder"),
        ("left_shoulder", "left_hip"),
        ("right_shoulder", "right_hip"),
        ("left_hip", "right_hip"),
        
        // Arms
        ("left_shoulder", "left_elbow"),
        ("left_elbow", "left_wrist"),
        ("right_shoulder", "right_elbow"),
        ("right_elbow", "right_wrist"),
        
        // Legs
        ("left_hip", "left_knee"),
        ("left_knee", "left_ankle"),
        ("right_hip", "right_knee"),
        ("right_knee", "right_ankle"),
        
        // Face
        ("nose", "left_eye"),
        ("nose", "right_eye")
    ]
    
    var body: some View {
        ZStack {
            // Draw connections first
            ForEach(connections.indices, id: \.self) { index in
                FixedConnectionLine(
                    from: connections[index].0,
                    to: connections[index].1,
                    keypoints: keypoints,
                    containerSize: containerSize,
                    imageSize: imageSize,
                    rotation: rotation
                )
            }
            
            // Draw keypoints on top
            ForEach(keypoints.indices, id: \.self) { index in
                let keypoint = keypoints[index]
                
                if keypoint.confidence > 0.3 {
                    FixedKeypointDot(
                        keypoint: keypoint,
                        index: index,
                        containerSize: containerSize,
                        imageSize: imageSize,
                        rotation: rotation,
                        isSelected: selectedKeypointIndex == index,
                        isAnnotationMode: isAnnotationMode
                    )
                    .onTapGesture {
                        if isAnnotationMode {
                            selectedKeypointIndex = index
                        }
                    }
                }
            }
        }
    }
}
