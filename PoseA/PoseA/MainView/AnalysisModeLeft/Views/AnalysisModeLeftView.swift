//
//  MainContentView.swift
//  PoseA
//
//  Created by Ardhika Maulidani on 7/8/25.
//

import SwiftUI

struct AnalysisModeLeftView: View {
    @ObservedObject var appState: MainAppState
    @Binding var ROIModel: ROIViewModel
    @Binding var BoxModel: BoxViewModel
    @State var mediaManager: MediaManagerVM
    @State var calibrationModel: CalibrationModel

    @Binding var annotationVM: ManualAnnotationVM
    @Binding var selectedRightView: RightViewModel
    @State private var labelCounter: Int = 1
    @State private var nextLabel: String = "P1"

    @Binding var showKeypointOverlay: Bool
    @Binding var showBoxOverlay: Bool
    @Bindable var quadCalibrationModel: QuadCalibrationModel

    // Track the rendered size of the frame area for calibration overlays
    @State private var frameViewSize: CGSize = .zero

    var body: some View {
        GeometryReader { geometry in
            ZStack(alignment: .topLeading) {

                VStack(spacing: 0) {
                    ZStack {
                        Color.black.edgesIgnoringSafeArea(.bottom)

                        if mediaManager.isMediaAvailable {
                            FrameView(
                                image: mediaManager.currentFrameImage,
                                keypoints: showKeypointOverlay
                                    ? mediaManager.getKeypointsCurrent() : nil,
                                appState: appState,
                                ROIModel: $ROIModel,
                                BoxModel: showBoxOverlay
                                    ? $BoxModel : .constant(BoxViewModel())
                            )
                            .frame(height: geometry.size.height * 0.75)
                            // Capture the actual rendered size so overlays align correctly
                            .background(
                                GeometryReader { frameGeo in
                                    Color.clear
                                        .onAppear {
                                            frameViewSize = frameGeo.size
                                           
                                        }
                                        .onChange(of: frameGeo.size) { _, newSize in
                                            frameViewSize = newSize
                                        }
                                }
                            )
                            .overlay(alignment: .top) {
                                // Frame counter + keypoint badge
                                HStack {
                                    Text("Frame: \(mediaManager.currentFrameIndex + 1)/\(mediaManager.mediaPlayerViewModel.totalFrames)")
                                        .font(.caption)
                                        .padding(6)
                                        .background(Color.black.opacity(0.7))
                                        .foregroundColor(.white)
                                        .cornerRadius(4)

                                    Spacer()

                                    if let keypoints = mediaManager.getKeypointsCurrent() {
                                        Text("Keypoints: \(keypoints.count)")
                                            .font(.caption)
                                            .padding(6)
                                            .background(
                                                keypoints.count == 17
                                                    ? Color.green.opacity(0.7)
                                                    : Color.red.opacity(0.7)
                                            )
                                            .foregroundColor(.white)
                                            .cornerRadius(4)
                                    } else {
                                        Text("No Keypoints")
                                            .font(.caption)
                                            .padding(6)
                                            .foregroundColor(.white)
                                            .cornerRadius(4)
                                    }
                                }
                                .padding(.horizontal)
                                .padding(.top, 8)
                            }
                            .overlay(alignment: .topLeading) {
                                // Annotation tap layer — sits above frame, below calibration
                                if selectedRightView == .manualAnnotation {
                                    AnnotationTapOverlay(
                                        mediaManager: mediaManager,
                                        calibrationModel: calibrationModel,
                                        vm: annotationVM,
                                        nextLabel: $nextLabel,
                                        labelCounter: $labelCounter
                                    )
                                }
                                
                            }
                            .overlay{
                                
                                // 2-point overlay — only when bar calibration is active
                                if calibrationModel.isCalibrationMode {
                                    CalibrationOverlayView(
                                        calibrationModel: $calibrationModel,
                                        containerSize: frameViewSize,
                                        imageSize: currentImageSize
                                    )
                                    .allowsHitTesting(true)
                                }
                                
                                // Quad overlay — completely independent flag
                                if quadCalibrationModel.isQuadCalibrationMode {
                                    QuadCalibrationOverlayView(
                                        quadModel: quadCalibrationModel,
                                        containerSize: frameViewSize,
                                        imageSize: currentImageSize
                                    )
                                    .allowsHitTesting(true)
                                }
                            }
                                

                        } else {
                            // Empty state
                            VStack(spacing: 20) {
                                Text("No File Selected")
                                    .font(.title2)
                                    .multilineTextAlignment(.center)
                                    .foregroundColor(.secondary)

                                Image(systemName: "folder.fill")
                                    .font(.system(size: 50))
                                    .foregroundColor(.secondary)

                                Text("Open a file or video to analyze")
                                    .font(.body)
                                    .foregroundColor(.secondary)
                                    .padding(.top, 10)

                                Button(action: { appState.isFilePickerPresented = true }) {
                                    Text("Select File")
                                        .font(.headline)
                                        .padding()
                                        .background(Color.blue)
                                        .foregroundColor(.white)
                                        .cornerRadius(8)
                                }
                                .padding(.top, 20)
                            }
                            .frame(height: geometry.size.height)
                            .frame(maxWidth: .infinity)
                            .background(Color(.systemGray6))
                        }
                    }
                    .cornerRadius(16)
                    .padding(.horizontal, 8)

                    if mediaManager.isMediaAvailable {
                        PlaybackControlLandscapeView(mediaManager: mediaManager)
                            .background(Color.clear.contentShape(Rectangle()))
                            .frame(height: geometry.size.height * 0.25 - 10)
                            .padding(.top, 10)
                    }
                }

               

            } // end outer ZStack
            .coordinateSpace(name: "leftViewSpace")
        }
    }

    // The actual pixel dimensions of the current frame image,
    // used by both overlay views to compute fittedImageRect correctly.
    private var currentImageSize: CGSize {
        guard let img = mediaManager.currentFrameImage else {
            return CGSize(width: 16, height: 9) // safe fallback aspect ratio
        }
        return CGSize(width: img.size.width, height: img.size.height)
    }

    
    
    
    private struct AnnotationTapOverlay: View {
        @State var mediaManager: MediaManagerVM
        @State var calibrationModel: CalibrationModel
        @State var vm: ManualAnnotationVM
        @Binding var nextLabel: String
        @Binding var labelCounter: Int

        var body: some View {
            GeometryReader { geo in
                ZStack {
                    // Transparent hit area
                    Color.clear.contentShape(Rectangle())

                    // Bar reference line
                    if calibrationModel.isCalibrated, let barTop = calibrationModel.barTopPoint {
                        let lineY = CGFloat(barTop.y) * geo.size.height
                        Path { p in
                            p.move(to: CGPoint(x: 0, y: lineY))
                            p.addLine(to: CGPoint(x: geo.size.width, y: lineY))
                        }
                        .stroke(Color.yellow.opacity(0.7),
                                style: StrokeStyle(lineWidth: 1.5, dash: [6, 3]))
                    }

                    // Placed dots for current frame
                    let pts = vm.annotationsByFrame[mediaManager.currentFrameIndex] ?? []
                    ForEach(pts) { pt in
                        let px = CGFloat(pt.normalizedX) * geo.size.width
                        let py = CGFloat(pt.normalizedY) * geo.size.height
                        ZStack {
                            Circle().fill(Color.red.opacity(0.85)).frame(width: 12, height: 12)
                            Circle().stroke(Color.white, lineWidth: 1.5).frame(width: 12, height: 12)
                        }
                        .position(x: px, y: py)
                        .overlay(
                            Text(pt.label)
                                .font(.system(size: 9, weight: .bold))
                                .foregroundColor(.white)
                                .padding(2)
                                .background(Color.red.opacity(0.75))
                                .cornerRadius(3)
                                .position(x: px + 12, y: py - 10),
                            alignment: .topLeading
                        )
                    }

                    // Annotation mode badge
                    VStack {
                        HStack {
                            Spacer()
                            Label("Tap to annotate", systemImage: "hand.tap.fill")
                                .font(.system(size: 9, weight: .semibold))
                                .padding(.horizontal, 7)
                                .padding(.vertical, 4)
                                .background(Color.red.opacity(0.75))
                                .foregroundColor(.white)
                                .cornerRadius(6)
                                .padding(6)
                        }
                        Spacer()
                    }
                }
                .onTapGesture { location in
                    let nx = Double(location.x / geo.size.width)
                    let ny = Double(location.y / geo.size.height)
                    let point = AnnotationPoint(
                        frameIndex: mediaManager.currentFrameIndex,
                        normalizedX: nx,
                        normalizedY: ny,
                        label: nextLabel
                    )
                    vm.addPoint(point)
                    labelCounter += 1
                    nextLabel = "P\(labelCounter)"
                    Task {
                        await vm.computeMeasurement(for: point, calibration: calibrationModel)
                    }
                }
            }
        }
    }

}
