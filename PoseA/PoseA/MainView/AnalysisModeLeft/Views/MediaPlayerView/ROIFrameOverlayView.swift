//
//  ROISelectionOverlay.swift
//  PoseA
//
//  Created by Ardhika Maulidani on 6/2/25.
//  Refactor from Shiela Cabahug's codebase

import SwiftUI

struct ROIFrameOverlayView: View {
    @Binding var ROIModel: ROIViewModel
    let containerSize: CGSize
    let imageSize: CGSize
    
    @State private var startPoint: CGPoint = .zero
    @State private var currentPoint: CGPoint = .zero
    @State private var isDragging = false
    @State private var isROIActive: Bool = false

    var body: some View {
        ZStack {
            // Show existing ROI if available
            if !ROIModel.isROISelectMode && ROIModel.isROIAvailable {
                // Parse ROI in Display Space
                let roiRect = ROIModel.roiDisplaySpace!
                
                // View
                ZStack {
                    // Background mask with dynamic cut-out
                    InvertedMaskShape(holeRect: roiRect)
                        .fill(Color.black.opacity(0.6), style: FillStyle(eoFill: true))
                    
                    ZStack(alignment: .top) {
                        // ROI Rectangle with semi-transparent fill
                        Rectangle()
                            .stroke(Color.orange, lineWidth: 3)
                            .background(Color.orange.opacity(0.1))
                        
                        // ROI Label pinned inside top edge
                        Text("ROI (Applied to All Frames)")
                            .font(.caption)
                            .fontWeight(.medium)
                            .padding(.vertical, 4)
                            .frame(maxWidth: .infinity)
                            .background(Color.orange)
                            .foregroundColor(.white)
                            .minimumScaleFactor(0.5)
                            .lineLimit(1)
                    }
                    .frame(width: roiRect.width, height: roiRect.height)
                    .position(x: roiRect.midX, y: roiRect.midY)
                }
            } else {
                GeometryReader { geometry in
                    ZStack {
                        // Background mask with dynamic cut-out
                        InvertedMaskShape(holeRect: CGRect(
                            x: min(startPoint.x, currentPoint.x),
                            y: min(startPoint.y, currentPoint.y),
                            width: abs(currentPoint.x - startPoint.x),
                            height: abs(currentPoint.y - startPoint.y)
                        ))
                        .fill(Color.black.opacity(0.6), style: FillStyle(eoFill: true))
                        .animation(.easeInOut(duration: 0.2), value: currentPoint)
                        .allowsHitTesting(false)
                        .ignoresSafeArea()
                        
                        // ROI rectangle
                        Rectangle()
                            .stroke(Color.orange, lineWidth: 3)
                            .background(Color.orange.opacity(0.1))
                            .frame(
                                width: abs(currentPoint.x - startPoint.x),
                                height: abs(currentPoint.y - startPoint.y)
                            )
                            .position(
                                x: (startPoint.x + currentPoint.x) / 2,
                                y: (startPoint.y + currentPoint.y) / 2
                            )
                            .opacity(isDragging ? 1.0 : 0.0)
                    }
                }
            }
            
            // Instructions Overlay
            if ROIModel.isROISelectMode {
                VStack {
                    Text("Select Region of Interest")
                        .font(.subheadline)
                        .fontWeight(.bold)
                        .padding(.bottom, 4)
                    
                    Text("Draw a rectangle around the person to focus on")
                        .font(.caption)
                    
                    Text("This ROI will be applied to all frames in the video")
                        .font(.caption)
                        .foregroundColor(.orange)
                }
                .padding()
                
                .background(Color.black.opacity(0.3)
                    .background(.ultraThinMaterial.opacity(0.5)))
                .foregroundColor(.white)
                .cornerRadius(12)
                .position(x: containerSize.width / 2, y: 80)
            }
            
            // A full-screen transparent layer that captures all drag gestures
            Color.clear
                .contentShape(Rectangle()) // Makes the entire area tappable
                .gesture(
                    LongPressGesture(minimumDuration: 1.0, maximumDistance: 30)
                        .sequenced(before: DragGesture(minimumDistance: 0))
                        .onChanged { value in
                            switch value {
                            case .second(true, let drag?):
                                if !isDragging {
                                    startPoint = drag.startLocation
                                    isDragging = true
                                }
                                currentPoint = drag.location
                            default:
                                break
                            }
                        }
                        .onEnded { value in
                            switch value {
                            case .second(true, let drag?):
                                if isDragging {
                                    let displayRect = CGRect(
                                        x: min(startPoint.x, currentPoint.x),
                                        y: min(startPoint.y, currentPoint.y),
                                        width: abs(currentPoint.x - startPoint.x),
                                        height: abs(currentPoint.y - startPoint.y)
                                    )
                                    
                                    if displayRect.width > 50 && displayRect.height > 50 {
                                        ROIModel.updateROI(
                                            displaySpace: displayRect,
                                            containerSize: containerSize,
                                            imageSize: imageSize
                                        )
                                    } else {
                                        ROIModel.setROIMode(false)
                                        log("ROI is too small. ROI mode disabled.", level: .warn)
                                    }
                                    
                                    isDragging = false
                                }
                            default:
                                isDragging = false
                            }
                        }
                )

        }
        .onChange(of: ROIModel.isROIAvailable){
            // Reset Gesture Point at Startup
            log("Generated ROI Overlay, gesture points reseted.", level: .debug)
            startPoint = .zero
            currentPoint = .zero
        }
        .allowsHitTesting(ROIModel.isROISelectMode)
    }
}
