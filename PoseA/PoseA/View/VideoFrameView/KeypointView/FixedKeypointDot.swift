//
//  FixedKeypointDot.swift
//  PoseA
//
//  Created by Ardhika Maulidani on 5/29/25.
//  Refactor from Shiela Cabahug's codebase

import SwiftUI

// MARK: - Fixed Keypoint Dot
struct FixedKeypointDot: View {
    let keypoint: KeypointData
    let index: Int
    let containerSize: CGSize
    let imageSize: CGSize
    let rotation: Int
    let isSelected: Bool
    let isAnnotationMode: Bool
    
    var body: some View {
        let position = transformPoint(
            x: keypoint.x,
            y: keypoint.y,
            containerSize: containerSize,
            imageSize: imageSize,
            rotation: rotation
        )
        
        let color = keypointColor(name: keypoint.name)
        // Fix: Convert Float to CGFloat explicitly
        let size = 8.0 + (CGFloat(keypoint.confidence) * 6.0)
        
        ZStack {
            // Main keypoint circle
            Circle()
                .fill(color)
                .frame(width: size, height: size)
            
            // White border
            Circle()
                .stroke(Color.white, lineWidth: isSelected ? 3 : 1)
                .frame(width: size, height: size)
            
            // Selection indicator
            if isSelected {
                Circle()
                    .stroke(Color.yellow, lineWidth: 2)
                    .frame(width: size + 8, height: size + 8)
            }
        }
        .position(position)
    }
    
    private func keypointColor(name: String) -> Color {
        if name.contains("left") {
            return .blue
        } else if name.contains("right") {
            return .red
        } else {
            return .green
        }
    }
}
