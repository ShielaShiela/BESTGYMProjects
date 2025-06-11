//
//  FixedConnectionLine.swift
//  PoseA
//
//  Created by Ardhika Maulidani on 5/29/25.
//  Refactor from Shiela Cabahug's codebase

import SwiftUI

// MARK: - Fixed Connection Line
struct FixedConnectionLine: View {
    let from: String
    let to: String
    let keypoints: [KeypointData]
    let containerSize: CGSize
    let imageSize: CGSize
    let rotation: Int
    
    var body: some View {
        Path { path in
            guard let fromKeypoint = keypoints.first(where: { $0.name == from }),
                  let toKeypoint = keypoints.first(where: { $0.name == to }),
                  fromKeypoint.confidence > 0.3 && toKeypoint.confidence > 0.3 else {
                return
            }
            
            let fromPoint = transformPoint(
                x: fromKeypoint.x,
                y: fromKeypoint.y,
                containerSize: containerSize,
                imageSize: imageSize,
                rotation: rotation
            )
            
            let toPoint = transformPoint(
                x: toKeypoint.x,
                y: toKeypoint.y,
                containerSize: containerSize,
                imageSize: imageSize,
                rotation: rotation
            )
            
            path.move(to: fromPoint)
            path.addLine(to: toPoint)
        }
        .stroke(connectionColor(from: from, to: to), lineWidth: 2)
    }
    
    private func connectionColor(from: String, to: String) -> Color {
        if from.contains("left") || to.contains("left") {
            return .blue
        } else if from.contains("right") || to.contains("right") {
            return .red
        } else {
            return .green
        }
    }
}
