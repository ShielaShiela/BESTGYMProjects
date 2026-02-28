//
//  FrameView.swift
//  PoseA
//
//  Created by Ardhika Maulidani on 5/29/25.
//  Refactor from Shiela Cabahug's codebase

import SwiftUI

// MARK: - Frame View
struct FrameView: View {
    let image: UIImage?
    let keypoints: PoseBox?

    @ObservedObject var appState: MainAppState
    @Binding var ROIModel: ROIViewModel
    @Binding var BoxModel: BoxViewModel
    
    // New Feature
    @State private var isDataLoading = false
    @State private var zoomScale: CGFloat = 1.0
    @State private var lastZoomScale: CGFloat = 1.0
    
    @State private var offset: CGSize = .zero
    @State private var lastOffset: CGSize = .zero
    
    
    var body: some View {
        GeometryReader { geometry in
            // Define Layer
            let containerSize = geometry.size
            let imageSize = image?.size ?? CGSize.zero
            
            let mapper = CoordinateMapper(containerSize: containerSize,
                                          imageSize: imageSize,
                                          scaleMode: .aspectFit)
            let fittedSize = mapper.displaySize
            
            // Define Gesture Condition
            let zoomEnabled = appState.isZoomMode
            let childEnabled = ROIModel.isROIMode || BoxModel.isBoxMode
            
            // Define Gesture
            let magnificationGesture = MagnificationGesture()
                .onChanged { value in
                    let newZoom = lastZoomScale * value
                    withAnimation(.easeOut(duration: 0.3)) {
                        zoomScale = min(max(newZoom, 1.0), 4.0)
                    }
                }
                .onEnded { _ in
                    lastZoomScale = zoomScale

                    let maxX = (zoomScale - 1) * fittedSize.width / 2
                    let maxY = (zoomScale - 1) * fittedSize.height / 2

                    var newOffset = offset
                    newOffset.width = min(max(newOffset.width, -maxX), maxX)
                    newOffset.height = min(max(newOffset.height, -maxY), maxY)

                    withAnimation(.easeOut(duration: 0.5)) {
                        offset = newOffset
                    }
                    lastOffset = newOffset
                }

            let dragGesture = DragGesture()
                .onChanged { value in
                    // Skip updates if childEnabled is true
                    guard !childEnabled else { return }

                    var newOffset = CGSize(
                        width: lastOffset.width + value.translation.width,
                        height: lastOffset.height + value.translation.height
                    )

                    let maxX = (zoomScale - 1) * fittedSize.width / 2
                    let maxY = (zoomScale - 1) * fittedSize.height / 2
                    newOffset.width = min(max(newOffset.width, -maxX), maxX)
                    newOffset.height = min(max(newOffset.height, -maxY), maxY)

                    offset = newOffset
                }
                .onEnded { _ in
                    guard !childEnabled else { return }
                    lastOffset = offset
                }

            // UI View
            ZStack(alignment: .center) {
                Color.black  // Ensure background
                
                if let image = image {
                    ZStack {
                        // This transform applies to image and all overlays
                        Image(uiImage: image)
                            .resizable()
                            .aspectRatio(contentMode: .fit)
                            .frame(width: geometry.size.width, height: geometry.size.height)
                        
                        // Keypoints
                        if let keypoints = keypoints,
                           !keypoints.keypoints.isEmpty,
                           appState.showKeypoints {
                            PoseOverlayView(
                                poses: [keypoints],
                                videoSize: imageSize,
                                scaleMode: .aspectFit
                            )
                        }
                        
                        // ROI
                        if ROIModel.isROIMode {
                            ROIFrameOverlayView(
                                ROIModel: $ROIModel,
                                containerSize: geometry.size,
                                imageSize: imageSize
                            )
                        }
                        
                        // Box
                        if BoxModel.isBoxMode {
                            BoxFrameOverlayView(
                                BoxModel: $BoxModel,
                                containerSize: geometry.size,
                                imageSize: imageSize
                            )
                        }
                    }
                    .scaleEffect(zoomScale)
                    .offset(offset)
                    .frame(width: geometry.size.width, height: geometry.size.height)
                    .clipped()
                }
            }
            
            // Apply Gesture
            .highPriorityGesture(magnificationGesture)
            
            .conditionalGesture(dragGesture, isEnabled: !childEnabled)

            .onTapGesture(count: 2) {
                withAnimation {
                    zoomScale = 1.0
                    lastZoomScale = 1.0
                    offset = .zero
                    lastOffset = .zero
                }
            }
            

            .allowsHitTesting(zoomEnabled || childEnabled)
        }
    }
}

struct ConditionalGestureModifier<G: Gesture>: ViewModifier {
    let gesture: G
    let isEnabled: Bool
    
    func body(content: Content) -> some View {
        Group {
            if isEnabled {
                content.highPriorityGesture(gesture)
            } else {
                content
            }
        }
    }
}

extension View {
    func conditionalGesture<G: Gesture>(_ gesture: G, isEnabled: Bool) -> some View {
        self.modifier(ConditionalGestureModifier(gesture: gesture, isEnabled: isEnabled))
    }
}
