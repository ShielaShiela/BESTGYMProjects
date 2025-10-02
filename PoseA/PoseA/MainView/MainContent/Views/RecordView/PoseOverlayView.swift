//
//  RTPoseView.swift
//  PoseA
//
//  Created by Ardhika Maulidani on 8/22/25.
//

import SwiftUI

fileprivate let cocoConnections: [(Int, Int)] = [ (0, 1), (0, 2),
                                                  (1, 3), (2, 4),
                                                  (5, 6), (5, 7),
                                                  (7, 9), (6, 8),
                                                  (8, 10),
                                                  (5, 11), (6, 12),
                                                  (11, 12), (11, 13),
                                                  (13, 15), (12, 14),
                                                  (14, 16) ]

struct PoseOverlayView: View {
    let poses: [PoseBox]
    let videoSize: CGSize
    
    var body: some View {
        GeometryReader { geo in
            Canvas { ctx, canvasSize in
                for pose in poses {
                    drawPose(pose, in: ctx, canvasSize: canvasSize)
                }
            }
            .allowsHitTesting(false)
        }
    }
        
    private func drawPose(_ pose: PoseBox, in ctx: GraphicsContext, canvasSize: CGSize) {
        let mapper = CoordinateMapper(containerSize: canvasSize,
                                      imageSize: videoSize,
                                      scaleMode: .aspectFill)

        // Keypoints
        let keypoints = pose.keypoints
        let pts = keypoints.map { mapper.mapPoint(CGPoint(x: $0.x, y: $0.y), normalized: false) }
        
        // Skeleton lines
        for (a, b) in cocoConnections where a < pts.count && b < pts.count {
            var path = Path()
            path.move(to: pts[a])
            path.addLine(to: pts[b])
            
            ctx.stroke(path, with: .color(connectionColor(from: a, to: b)), lineWidth: 5)
        }
        
        // Joints
        for (i, p) in pts.enumerated() {
            let circle = Path(ellipseIn: CGRect(x: p.x-4, y: p.y-4, width: 8, height: 8))
            ctx.fill(circle, with: .color(dotColor(index: i)))
        }
        
        // Bounding box
        let p1 = mapper.mapPoint(CGPoint(x: pose.bbox.minX, y: pose.bbox.minY), normalized: false)
        let p2 = mapper.mapPoint(CGPoint(x: pose.bbox.maxX, y: pose.bbox.maxY), normalized: false)
        let rect = CGRect(x: p1.x, y: p1.y, width: p2.x - p1.x, height: p2.y - p1.y)
        ctx.stroke(Path(rect), with: .color(.green.opacity(0.5)), lineWidth: 4)
    }
    
    // MARK: - Mapping
    
    private func connectionColor(from: Int, to: Int) -> Color {
        if (0...4).contains(from) && (0...4).contains(to) {
            return .green.opacity(0.5)   // Head/face connections
        } else if (5...12).contains(from) && (5...12).contains(to) {
            return .blue.opacity(0.5)    // Torso/shoulders/hips
        } else {
            return .orange.opacity(0.5)  // Other limbs
        }
    }
    
    private func dotColor(index: Int) -> Color {
        if (0...4).contains(index) {
            return .green.opacity(0.5)   // Head/face connections
        } else if (5...12).contains(index) {
            return .blue.opacity(0.5)    // Torso/shoulders/hips
        } else {
            return .orange.opacity(0.5)  // Other limbs
        }
    }
}
