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
        // Keypoints
        let keypoints = pose.keypoints
        let pts = keypoints.map { mapNormalizedPointToCanvas(CGPoint(x: $0.x, y: $0.y), canvasSize: canvasSize) }
        
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
        let rect = mapNormalizedRectToCanvas(pose.bbox, canvasSize: canvasSize)
        ctx.stroke(Path(rect), with: .color(.green.opacity(0.5)), lineWidth: 4)
    }
    
    // MARK: - Mapping
    
    private func mapNormalizedPointToCanvas(_ p: CGPoint, canvasSize: CGSize) -> CGPoint {
        let s = max(canvasSize.width / videoSize.width, canvasSize.height / videoSize.height)
        let scaledW = videoSize.width * s
        let scaledH = videoSize.height * s
        let offsetX = (canvasSize.width - scaledW) / 2.0
        let offsetY = (canvasSize.height - scaledH) / 2.0
        return CGPoint(x: offsetX + p.x * scaledW, y: offsetY + p.y * scaledH)
    }
    
    private func mapNormalizedRectToCanvas(_ r: CGRect, canvasSize: CGSize) -> CGRect {
        let p1 = mapNormalizedPointToCanvas(CGPoint(x: r.minX, y: r.minY), canvasSize: canvasSize)
        let p2 = mapNormalizedPointToCanvas(CGPoint(x: r.maxX, y: r.maxY), canvasSize: canvasSize)
        return CGRect(x: p1.x, y: p1.y, width: p2.x - p1.x, height: p2.y - p1.y)
    }
    
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
