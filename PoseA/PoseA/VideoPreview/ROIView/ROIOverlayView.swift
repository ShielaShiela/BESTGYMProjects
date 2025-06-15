//
//  ROISelectionOverlay.swift
//  PoseA
//
//  Created by Bestlab on 6/2/25.
//

import SwiftUI

struct InvertedMaskShape: Shape {
    let holeRect: CGRect

    func path(in rect: CGRect) -> Path {
        var path = Path()

        // Outer full rectangle
        path.addRect(rect)

        // Inner rectangle to cut out
        path.addRect(holeRect)

        // Just return the path normally; fill rule is applied during rendering
        return path
    }
}


struct ROISelectionOverlay: View {
    @ObservedObject var appState: AppState
    let containerSize: CGSize
    let imageSize: CGSize
    let rotation: Int
    
    @State private var startPoint: CGPoint = .zero
    @State private var currentPoint: CGPoint = .zero
    @State private var isDragging = false
    
    var body: some View {
        ZStack {
            // ROI selection area
            if appState.isSelectingROI {
                let b = print("is selecting ROI")
                let a = print(startPoint.x, startPoint.y, currentPoint.x, currentPoint.y)
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
            
            // Show existing ROI if available
            if let roiRect = appState.roiRect, !appState.isSelectingROI {
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

            // Instructions Overlay
            if appState.isSelectingROI {
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
        }
        .onAppear{
            // Reset Gesture Point at Startup
            log("Generated ROI Overlay, gesture points reseted.", level: .debug)
            startPoint = .zero
            currentPoint = .zero
        }
        .allowsHitTesting(appState.isSelectingROI)
        .gesture(
            DragGesture(minimumDistance: 0)
                .onChanged { value in
                    if !isDragging {
                        startPoint = value.startLocation
                        isDragging = true
                    }
                    currentPoint = value.location
                }
                .onEnded { value in
                    if isDragging {
                        let displayRect = CGRect(
                            x: min(startPoint.x, currentPoint.x),
                            y: min(startPoint.y, currentPoint.y),
                            width: abs(currentPoint.x - startPoint.x),
                            height: abs(currentPoint.y - startPoint.y)
                        )
                        
                        // Only set ROI if the rectangle is large enough
                        if displayRect.width > 50 && displayRect.height > 50 {
                            // Convert display coordinates to image coordinates
                            let imageRect = convertDisplayRectToImageRect(
                                displayRect: displayRect,
                                containerSize: containerSize,
                                imageSize: imageSize
                            )
                            appState.setROI(displayRect, imageCoordinates: imageRect)
                            log("ROI set to: \(imageRect)", level: .debug)
                        } else {
                            appState.disableROIMode()
                        }
                        
                        isDragging = false
                    }
                }
        )
    }
    
    // Convert display rectangle to image coordinates
    private func convertDisplayRectToImageRect(
        displayRect: CGRect,
        containerSize: CGSize,
        imageSize: CGSize
    ) -> CGRect {
        // Calculate the actual display size of the image within the container
        let imageAspectRatio = imageSize.width / imageSize.height
        let containerAspectRatio = containerSize.width / containerSize.height
        
        var displaySize: CGSize
        var offsetX: CGFloat = 0
        var offsetY: CGFloat = 0
        
        if imageAspectRatio > containerAspectRatio {
            // Image is wider than container - fit to width
            displaySize = CGSize(
                width: containerSize.width,
                height: containerSize.width / imageAspectRatio
            )
            offsetY = (containerSize.height - displaySize.height) / 2
        } else {
            // Image is taller than container - fit to height
            displaySize = CGSize(
                width: containerSize.height * imageAspectRatio,
                height: containerSize.height
            )
            offsetX = (containerSize.width - displaySize.width) / 2
        }
        
        // Convert display coordinates to image coordinates
        let scaleX = imageSize.width / displaySize.width
        let scaleY = imageSize.height / displaySize.height
        
        return CGRect(
            x: (displayRect.origin.x - offsetX) * scaleX,
            y: (displayRect.origin.y - offsetY) * scaleY,
            width: displayRect.width * scaleX,
            height: displayRect.height * scaleY
        )
    }
}
