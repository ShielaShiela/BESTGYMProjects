//
//  BoxFrameOverlayView.swift
//  PoseA
//
//  Created by Ardhika Maulidani on 7/10/25.
//

import SwiftUI
import SwiftUI

struct BoxFrameOverlayView: View {
    @ObservedObject var BoxModel: BoxViewModel
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
                    path.move(to: BoxModel.pointsDisplay[0])
                    for i in 1..<4 {
                        path.addLine(to: BoxModel.pointsDisplay[i])
                    }
                    path.addLine(to: BoxModel.pointsDisplay[0])
                }
                .stroke(Color.green.opacity(0.6), lineWidth: 1)
                
                // Draggable handles
                ForEach(0..<4, id: \.self) { i in
                    Circle()
                        .fill(Color.green.opacity(0.6))
                        .frame(width: 7, height: 7)
                        .position(BoxModel.pointsDisplay[i])
                        .gesture(
                            DragGesture()
                                .onChanged { value in
                                    BoxModel.movePoint(index: i, to: value.location)
                                    BoxModel.updateImageSpace(from: containerSize, imageSize: imageSize)
                                    log("Box updated: \(BoxModel.pointsImage)", level: .debug)
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
            // Optional: Convert to image space once ROI is complete
            if BoxModel.pointsDisplay.count == 4 {
                BoxModel.updateImageSpace(from: containerSize, imageSize: imageSize)
                log("Box updated: \(BoxModel.pointsImage)", level: .debug)
            }
        }
        .allowsHitTesting(BoxModel.isBoxSelectMode || BoxModel.isBoxAvailable)
    }
}
