//
//  BoxFrameOverlayView.swift
//  PoseA
//
//  Created by Ardhika Maulidani on 7/10/25.
//

import SwiftUI
import SwiftUI

struct BoxFrameOverlayView: View {
    @Binding var BoxModel: BoxViewModel
    @State private var dragOffsets: [CGSize] = Array(repeating: .zero, count: 4)
    @State private var draggingIndex: Int? = nil
    
    let containerSize: CGSize
    let imageSize: CGSize
    
    var body: some View {
        ZStack {
            // Background dimming mask with transparent shape (when shape complete)
            if BoxModel.pointsDisplay.count == 4 {
                Path { path in
                    path.addLines(BoxModel.pointsDisplay)
                    path.closeSubpath()
                }
                .fill(Color.black.opacity(0.6), style: FillStyle(eoFill: true))
                .compositingGroup()
                .luminanceToAlpha()
                .blendMode(.destinationOut)
                .ignoresSafeArea()
            }
            
            // Shape lines and draggable points
            if BoxModel.pointsDisplay.count == 4 {
                // Line shape
                Path { path in
                    path.move(to: adjustedPoint(index: 0))
                    for i in 1..<4 {
                        path.addLine(to: adjustedPoint(index: i))
                    }
                    path.addLine(to: adjustedPoint(index: 0))
                }
                .stroke(Color.green.opacity(0.6), lineWidth: 1)
                
                // Draggable handles
                ForEach(0..<4, id: \.self) { i in
                    Circle()
                        .fill(Color.green.opacity(0.6))
                        .frame(width: 10, height: 10)
                        .position(
                            x: BoxModel.pointsDisplay[i].x + dragOffsets[i].width,
                            y: BoxModel.pointsDisplay[i].y + dragOffsets[i].height
                        )
                        .simultaneousGesture(
                            DragGesture()
                                .onChanged { value in
                                    draggingIndex = i
                                    dragOffsets[i] = value.translation
                                }
                                .onEnded { value in
                                    // Update VM
                                    BoxModel.movePoint(index: i, to: CGPoint(
                                        x: BoxModel.pointsDisplay[i].x + value.translation.width,
                                        y: BoxModel.pointsDisplay[i].y + value.translation.height
                                    ))
                                    BoxModel.updateImageSpace(from: containerSize, imageSize: imageSize)
                                    
                                    dragOffsets[i] = .zero
                                    draggingIndex = nil
                                }
                        )
                }
            }
            
            // Point-tap placement (if in selection mode)
            if BoxModel.isBoxSelectMode && BoxModel.pointsDisplay.count < 4 {
                // Instruction overlay
                VStack(spacing: 4) {
                    Text("Tap to place point \(BoxModel.pointsDisplay.count + 1)/4")
                        .font(.subheadline)
                        .fontWeight(.bold)
                    
                    Text("Define a quadrilateral region of interest.")
                        .font(.caption)
                    
                    Text("You can move points later.")
                        .font(.caption)
                        .foregroundColor(.orange)
                }
                .padding()
                .background(Color.black.opacity(0.3).background(.ultraThinMaterial.opacity(0.5)))
                .foregroundColor(.white)
                .cornerRadius(12)
                .position(x: containerSize.width / 2, y: 80)
                
                Color.clear
                    .contentShape(Rectangle())
                    .onTapGesture { location in
                        BoxModel.addPoint(location)
                    }
            }
        }
        .frame(width: containerSize.width, height: containerSize.height)
        .onChange(of: BoxModel.isBoxAvailable) {
            // Optional: Convert to image space once Box is complete
            if BoxModel.pointsDisplay.count == 4 {
                BoxModel.updateImageSpace(from: containerSize, imageSize: imageSize)
            }
        }
        .allowsHitTesting(true)
    }
        
    private func adjustedPoint(index: Int) -> CGPoint {
        if index == draggingIndex {
            return CGPoint(
                x: BoxModel.pointsDisplay[index].x + dragOffsets[index].width,
                y: BoxModel.pointsDisplay[index].y + dragOffsets[index].height
            )
        } else {
            return BoxModel.pointsDisplay[index]
        }
    }
}
