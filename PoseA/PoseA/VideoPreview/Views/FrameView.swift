//
//  FrameView.swift
//  PoseA
//
//  Created by Ardhika Maulidani on 5/29/25.
//  Refactor from Shiela Cabahug's codebase

import SwiftUI

// MARK: - Fixed Frame View (Simplified)
struct FrameView: View {
    let image: UIImage?
    let keypoints: [KeypointData]?
    let rotation: Int
    @ObservedObject var appState: MainAppState
    @ObservedObject var ROIModel: ROIViewModel
    @ObservedObject var BoxModel: BoxViewModel
    
    // New Feature
    @State private var isDataLoading = false
    @State private var zoomScale: CGFloat = 1.0
    @State private var lastZoomScale: CGFloat = 1.0
    
    @State private var offset: CGSize = .zero
    @State private var lastOffset: CGSize = .zero
    
    // MARK: - Init
    init(image: UIImage?,
         keypoints: [KeypointData]?,
         appState: MainAppState,
         ROIModel: ROIViewModel,
         BoxModel: BoxViewModel) {
        self.image = image
        self.keypoints = keypoints
        self.rotation = appState.imageRotation
        self.appState = appState
        self.ROIModel = ROIModel
        self.BoxModel = BoxModel
    }
    
    var body: some View {
        GeometryReader { geometry in
            // Define Layer
            let containerSize = geometry.size
            let imageSize = image?.size ?? CGSize.zero
            let fittedSize = fittedImageSize(imageSize: imageSize, containerSize: containerSize)
            
            // Define Gesture Condition
            let zoomEnabled = appState.isZoomMode
            let childEnabled = ROIModel.isROIMode || BoxModel.isBoxMode
            ZStack(alignment: .center) {
                Color.black  // Ensure background
                
                if let image = image {
                    ZStack {
                        // This transform applies to image and all overlays
                        Image(uiImage: image)
                            .resizable()
                            .aspectRatio(contentMode: .fit)
                            .rotationEffect(.degrees(Double(rotation) * 90))
                            .frame(width: geometry.size.width, height: geometry.size.height)
                        
                        // Keypoints
                        if let keypoints = keypoints,
                           !keypoints.isEmpty,
                           appState.showKeypoints,
                           !ROIModel.isROIMode {
                            KeypointOverlayView(
                                keypoints: keypoints,
                                containerSize: geometry.size,
                                imageSize: imageSize,
                                rotation: rotation
                            )
                        }
                        
                        // ROI
                        if ROIModel.isROIMode {
                            ROIFrameOverlayView(
                                ROIModel: ROIModel,
                                containerSize: geometry.size,
                                imageSize: imageSize
                            )
                        }
                        
                        // Box
                        if BoxModel.isBoxMode {
                            BoxFrameOverlayView(
                                BoxModel: BoxModel,
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
            
            .highPriorityGesture(
                SimultaneousGesture(
                    MagnificationGesture()
                        .onChanged { value in
                            let newZoom = lastZoomScale * value
                            withAnimation(.easeOut(duration: 0.3)) {
                                zoomScale = min(max(newZoom, 1.0), 4.0)
                            }
                        }
                        .onEnded { _ in
                            lastZoomScale = zoomScale

                            // Clamp offset after zoom ends
                            let maxX = (zoomScale - 1) * fittedSize.width / 2
                            let maxY = (zoomScale - 1) * fittedSize.height / 2

                            var newOffset = offset
                            newOffset.width = min(max(newOffset.width, -maxX), maxX)
                            newOffset.height = min(max(newOffset.height, -maxY), maxY)

                            // Animate back into bounds if needed
                            withAnimation(.easeOut(duration: 0.5)) {
                                offset = newOffset
                            }
                            lastOffset = newOffset
                        },

                    DragGesture()
                        .onChanged { value in
                            // Clamp offset during drag
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
                            lastOffset = offset
                        }
                )
            )
            
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
    
    func fittedImageSize(imageSize: CGSize, containerSize: CGSize) -> CGSize {
        let imageAspect = imageSize.width / imageSize.height
        let containerAspect = containerSize.width / containerSize.height

        if imageAspect > containerAspect {
            let width = containerSize.width
            let height = width / imageAspect
            return CGSize(width: width, height: height)
        } else {
            let height = containerSize.height
            let width = height * imageAspect
            return CGSize(width: width, height: height)
        }
    }
}
