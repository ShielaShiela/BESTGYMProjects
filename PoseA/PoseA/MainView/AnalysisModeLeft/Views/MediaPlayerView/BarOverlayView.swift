//
//  BoxFrameOverlayView.swift
//  PoseA
//
//  Created by Ardhika Maulidani on 7/10/25.
//

import SwiftUI

struct BarOverlayView: View {
    @Binding var barPointVM: BarPointVM
    @State private var dragOffset: CGSize = .zero
    
    let containerSize: CGSize
    let imageSize: CGSize
    
    var body: some View {
        ZStack {
            // Line between points
            if let firstPoint = barPointVM.pointsDisplay[0],
               let secondPoint = barPointVM.pointsDisplay[1] {
                Path { path in
                    path.move(to: barPointVM.currentEditingPoint == 0 ? adjustedPoint(firstPoint) : firstPoint)
                    path.addLine(to: barPointVM.currentEditingPoint == 1 ? adjustedPoint(secondPoint) : secondPoint)
                }
                .stroke(Color.green.opacity(0.8), lineWidth: 2)
            }
            
            // First point
            if let firstPoint = barPointVM.pointsDisplay[0] {
                if barPointVM.currentEditingPoint == 0 {
                    CrosshairView(at: adjustedPoint(firstPoint))
                        .simultaneousGesture(
                            DragGesture()
                                .onChanged { value in
                                    dragOffset = value.translation
                                }
                                .onEnded { value in
                                    // Update second point position
                                    let newPosition = CGPoint(
                                        x: firstPoint.x + value.translation.width,
                                        y: firstPoint.y + value.translation.height
                                    )
                                    barPointVM.movePoint(index: 0, to: newPosition)
                                    barPointVM.updateImageSpace(from: containerSize, imageSize: imageSize)
                                    dragOffset = .zero
                                }
                        )
                } else {
                    Circle()
                        .fill(Color.green.opacity(0.8))
                        .frame(width: 12, height: 12)
                        .position(firstPoint)
                        .overlay(
                            Circle()
                                .stroke(Color.white, lineWidth: 2)
                                .frame(width: 12, height: 12)
                                .position(firstPoint)
                        )
                }
            }
            
            // Second point
            if let secondPoint = barPointVM.pointsDisplay[1] {
                if barPointVM.currentEditingPoint == 1 {
                    CrosshairView(at: adjustedPoint(secondPoint))
                        .simultaneousGesture(
                            DragGesture()
                                .onChanged { value in
                                    dragOffset = value.translation
                                }
                                .onEnded { value in
                                    // Update second point position
                                    let newPosition = CGPoint(
                                        x: secondPoint.x + value.translation.width,
                                        y: secondPoint.y + value.translation.height
                                    )
                                    barPointVM.movePoint(index: 1, to: newPosition)
                                    barPointVM.updateImageSpace(from: containerSize, imageSize: imageSize)
                                    dragOffset = .zero
                                }
                        )
                } else {
                    // Regular circle when not editing
                    Circle()
                        .fill(Color.green.opacity(0.6))
                        .frame(width: 12, height: 12)
                        .position(secondPoint)
                        .overlay(
                            Circle()
                                .stroke(Color.white, lineWidth: 2)
                                .frame(width: 12, height: 12)
                                .position(secondPoint)
                        )
                }
            }
            
            // MARK: - Point Picker
            if barPointVM.isSelectMode {
                if !barPointVM.isFirstPointAvailable && barPointVM.currentEditingPoint == 0 {
                    Color.clear
                        .contentShape(Rectangle())
                        .onTapGesture { location in
                            barPointVM.addPoint(pos: 0, point: location)
                            barPointVM.isFirstPointAvailable = true
                        }
                }
                
                if barPointVM.isFirstPointAvailable && !barPointVM.isSecondPointAvailable && barPointVM.currentEditingPoint == 1 {
                    Color.clear
                        .contentShape(Rectangle())
                        .onTapGesture { location in
                            barPointVM.addPoint(pos: 1, point: location)
                            barPointVM.isSecondPointAvailable = true
                        }
                }
            }
        }
        .frame(width: containerSize.width, height: containerSize.height)
        .onAppear {
            // Update Display if Bar Imported Available
            if barPointVM.pointsDisplay.isEmpty && !barPointVM.pointsImage.isEmpty {
                barPointVM.updateDisplaySpace(from: containerSize, imageSize: imageSize)
            }
        }
        .allowsHitTesting(true)
    }
    
    // MARK: - Private Helper Functions
    private func adjustedPoint(_ point: CGPoint) -> CGPoint {
        return CGPoint(
            x: point.x + dragOffset.width,
            y: point.y + dragOffset.height
        )
    }
    
    private func CrosshairView(at position: CGPoint) -> some View {
        ZStack {
            Color.black.opacity(0.25)
            // Horizontal dashed line
            Rectangle()
                .fill(Color.green.opacity(0.8))
                .frame(width: 40, height: 1)
                .position(x: position.x, y: position.y)
                .overlay(
                    Rectangle()
                        .strokeBorder(style: StrokeStyle(lineWidth: 1, dash: [3, 3]))
                        .foregroundColor(.white)
                        .frame(width: 40, height: 1)
                        .position(x: position.x, y: position.y)
                )
            
            // Vertical dashed line
            Rectangle()
                .fill(Color.green.opacity(0.8))
                .frame(width: 1, height: 40)
                .position(x: position.x, y: position.y)
                .overlay(
                    Rectangle()
                        .strokeBorder(style: StrokeStyle(lineWidth: 1, dash: [3, 3]))
                        .foregroundColor(.white)
                        .frame(width: 1, height: 40)
                        .position(x: position.x, y: position.y)
                )
            
            // Center circle
            Circle()
                .fill(Color.green.opacity(0.8))
                .frame(width: 8, height: 8)
                .position(position)
                .overlay(
                    Circle()
                        .stroke(Color.white, lineWidth: 2)
                        .frame(width: 8, height: 8)
                        .position(position)
                )
        }
    }
}
