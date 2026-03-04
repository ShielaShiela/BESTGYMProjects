//
//  CalibrationOverlayView.swift
//  PoseA
//
//  Created by Shiela Cabahug on 2026/2/19.
//

import SwiftUI

// MARK: - Main Calibration Overlay

struct CalibrationOverlayView: View {
    @Binding var calibrationModel: CalibrationModel
    let containerSize: CGSize
    let imageSize: CGSize

    @State private var topGuideX: CGFloat = -1
    @State private var topGuideY: CGFloat = -1
    @State private var bottomGuideX: CGFloat = -1
    @State private var bottomGuideY: CGFloat = -1
    

    
    var body: some View {
        ZStack {
            if calibrationModel.isCalibrationMode {
                

                // ── Bar Top guides (yellow) ──────────────────────────────
                if calibrationModel.calibrationStep == .selectingBarTop
                    || calibrationModel.calibrationStep == .complete {
                    CrosshairGuideView(
                        guideX: $topGuideX,
                        guideY: $topGuideY,
                        color: .yellow,
                        label: "Bar Top",
                        containerSize: containerSize,
                        imageBounds: fittedImageRect(),
                        coordinateSpaceName: "overlay_top",
                        onDragEnded: { commitAll()}
                    )
                }

                // ── Bar Bottom guides (green) ────────────────────────────
                if calibrationModel.calibrationStep == .selectingBarBottom
                    || calibrationModel.calibrationStep == .complete {
                    CrosshairGuideView(
                        guideX: $bottomGuideX,
                        guideY: $bottomGuideY,
                        color: .green,
                        label: "Ground Ref",
                        containerSize: containerSize,
                        imageBounds: fittedImageRect(),
                        coordinateSpaceName: "overlay_bottom",
                        onDragEnded: { commitAll()}
                    )
                }

                // ── Dashed connector ─────────────────────────────────────
                if calibrationModel.calibrationStep == .complete {
                    Path { path in
                        path.move(to: CGPoint(x: topGuideX, y: topGuideY))
                        path.addLine(to: CGPoint(x: bottomGuideX, y: bottomGuideY))
                    }
                    .stroke(Color.orange,
                            style: StrokeStyle(lineWidth: 1.5, dash: [6, 4]))
                    .allowsHitTesting(false)
                }

                // ── Instruction banner ───────────────────────────────────
                VStack {
                    HStack {
                        Spacer()
                        Text(instructionText)
                            .font(.caption)
                            .padding(8)
                            .background(Color.black.opacity(0.75))
                            .foregroundColor(.yellow)
                            .cornerRadius(8)
                        Spacer()
                    }
                    .padding(.top, 8)
                    Spacer()
                }
                .allowsHitTesting(false)   // ← banner never blocks touches
            }
        }
        // ── Give the ZStack a real frame so .position() works correctly ──
        .frame(width: containerSize.width, height: containerSize.height)
        .onAppear { initializeGuides() }
        .onChange(of: calibrationModel.calibrationStep) { _, _ in initializeGuides() }
        .onChange(of: containerSize) { _, _ in initializeGuides() }
        .onChange(of: calibrationModel.isCalibrationMode) { _, isOn in
            if !isOn && calibrationModel.calibrationStep != .idle {
                commitAll()
                calibrationModel.calibrationStep = .complete
            }
        }
    }

    // MARK: - Guide Initialisation

//    private func initializeGuides() {
//        let rect = fittedImageRect()
//        guard rect.width > 0, rect.height > 0 else { return }
//
//        if let top = calibrationModel.barTopPoint {
//            let dp = normalizedToDisplay(top)
//            topGuideX = dp.x; topGuideY = dp.y
//        } else {
//            topGuideX = rect.midX
//            topGuideY = rect.origin.y + rect.height * 0.25
//        }
//
//        if let bottom = calibrationModel.barBottomPoint {
//            let dp = normalizedToDisplay(bottom)
//            bottomGuideX = dp.x; bottomGuideY = dp.y
//        } else {
//            bottomGuideX = rect.midX
//            bottomGuideY = rect.origin.y + rect.height * 0.80
//        }
//    }
    
    private func initializeGuides() {
        let rect = fittedImageRect()
        guard rect.width > 0, rect.height > 0 else { return }

        if let top = calibrationModel.barTopPoint {
            let dp = normalizedToDisplay(top)
            topGuideX = dp.x; topGuideY = dp.y
        } else {
            let defaultTop = CGPoint(x: 0.5155440414507773, y: 0.507915947035118)
            let dp = normalizedToDisplay(defaultTop)
            topGuideX = dp.x; topGuideY = dp.y
        }

        if let bottom = calibrationModel.barBottomPoint {
            let dp = normalizedToDisplay(bottom)
            bottomGuideX = dp.x; bottomGuideY = dp.y
        } else {
            let defaultBottom = CGPoint(x: 0.5164075993091537, y: 0.9842256764536558)
            let dp = normalizedToDisplay(defaultBottom)
            bottomGuideX = dp.x; bottomGuideY = dp.y
        }
    }

    private func commitAll() {
        let rect = fittedImageRect()
        
        // Clamp display coords to fitted image rect before normalizing
        let clampedTopX    = topGuideX.clamped(to: rect.minX...rect.maxX)
        let clampedTopY    = topGuideY.clamped(to: rect.minY...rect.maxY)
        let clampedBottomX = bottomGuideX.clamped(to: rect.minX...rect.maxX)
        let clampedBottomY = bottomGuideY.clamped(to: rect.minY...rect.maxY)
        
        // Also update the guide positions to snap back visually
        topGuideX    = clampedTopX
        topGuideY    = clampedTopY
        bottomGuideX = clampedBottomX
        bottomGuideY = clampedBottomY
        
        calibrationModel.barTopPoint    = displayToNormalized(CGPoint(x: clampedTopX,    y: clampedTopY))
        calibrationModel.barBottomPoint = displayToNormalized(CGPoint(x: clampedBottomX, y: clampedBottomY))
        
        print("📍 barTop normalized: \(calibrationModel.barTopPoint!)")
        print("📍 barBottom normalized: \(calibrationModel.barBottomPoint!)")
        print("📐 fittedRect: \(rect)")
    }

    private var instructionText: String {
        switch calibrationModel.calibrationStep {
        case .selectingBarTop:    return "Drag the YELLOW lines to the top of the bar, then tap Next"
        case .selectingBarBottom: return "Drag the GREEN lines to ground level, then tap Confirm"
        case .complete:           return "Calibrated ✓  — re-open Calibrate to adjust"
        default:                  return ""
        }
    }

    // MARK: - Coordinate helpers

    private func fittedImageRect() -> CGRect {
        let imageAspect     = imageSize.width / imageSize.height
        let containerAspect = containerSize.width / containerSize.height
        
        print("📐 imageSize: \(imageSize), containerSize: \(containerSize)")

        if imageAspect > containerAspect {
            let width   = containerSize.width
            let height  = width / imageAspect
            let yOffset = (containerSize.height - height) / 2
            return CGRect(x: 0, y: yOffset, width: width, height: height)
        } else {
            let height  = containerSize.height
            let width   = height * imageAspect
            let xOffset = (containerSize.width - width) / 2
            return CGRect(x: xOffset, y: 0, width: width, height: height)
        }
        
    }

    private func normalizedToDisplay(_ point: CGPoint) -> CGPoint {
        let rect = fittedImageRect()
        return CGPoint(x: rect.origin.x + point.x * rect.width,
                       y: rect.origin.y + point.y * rect.height)
    }

    private func displayToNormalized(_ point: CGPoint) -> CGPoint {
        let rect = fittedImageRect()
        return CGPoint(x: (point.x - rect.origin.x) / rect.width,
                       y: (point.y - rect.origin.y) / rect.height)
    }
}

// MARK: - CrosshairGuideView

struct CrosshairGuideView: View {
    @Binding var guideX: CGFloat
    @Binding var guideY: CGFloat
    let color: Color
    let label: String
    let containerSize: CGSize
    let imageBounds: CGRect
    let coordinateSpaceName: String  // ADD THIS
    let onDragEnded: () -> Void

    @State private var draggingH = false
    @State private var draggingV = false
    @State private var dragStartGuideX: CGFloat = 0
    @State private var dragStartGuideY: CGFloat = 0

    private let handleSize: CGFloat = 44   // larger = easier to hit
    private let lineWidth:  CGFloat = 1.5
    
    

    var body: some View {
        // Use a Canvas-backed ZStack with an explicit frame.
        // Every interactive element sits directly in this fixed-size space
        // so .position(x:y:) values are unambiguous.
        ZStack(alignment: .topLeading) {

            // ── Guide lines (non-interactive) ────────────────────────────
            Canvas { ctx, _ in
                var hPath = Path()
                hPath.move(to:    CGPoint(x: 0,                  y: guideY))
                hPath.addLine(to: CGPoint(x: containerSize.width, y: guideY))
                ctx.stroke(hPath,
                           with: .color(color.opacity(0.85)),
                           style: StrokeStyle(lineWidth: lineWidth, dash: [6, 3]))

                var vPath = Path()
                vPath.move(to:    CGPoint(x: guideX, y: 0))
                vPath.addLine(to: CGPoint(x: guideX, y: containerSize.height))
                ctx.stroke(vPath,
                           with: .color(color.opacity(0.85)),
                           style: StrokeStyle(lineWidth: lineWidth, dash: [6, 3]))
            }
            .allowsHitTesting(false)
            .frame(width: containerSize.width, height: containerSize.height)

            // ── Crosshair marker ─────────────────────────────────────────
            CrosshairMarker(color: color, label: label)
                .position(x: guideX, y: guideY)
                .allowsHitTesting(false)

            // ── Horizontal handle (drags the H line up/down) ─────────────
            // Horizontal handle
            ZStack {
                Color.clear.frame(width: handleSize + 32, height: handleSize + 32) // hit area
                DragHandle(icon: "arrow.up.and.down", color: color, size: handleSize, isActive: draggingH)
            }
            .position(x: containerSize.width/4 - handleSize / 2 - 8, y: guideY)
            .gesture(
                DragGesture(minimumDistance: 0, coordinateSpace: .named(coordinateSpaceName))
                    .onChanged { value in
                        if !draggingH { draggingH = true; dragStartGuideY = guideY }
                        let newY = (dragStartGuideY + value.translation.height)
                            .clamped(to: imageBounds.minY...imageBounds.maxY)
                        print("🔴 dragStart: \(dragStartGuideY), translation: \(value.translation.height), newY: \(newY), bounds: \(imageBounds.minY)...\(imageBounds.maxY)")
                        guideY = newY
                    }
                    .onEnded { _ in
                        draggingH = false
                        onDragEnded()   // ← add this
                    }
            )

            // ── Vertical handle (drags the V line left/right) ────────────
            DragHandle(icon: "arrow.left.and.right",
                       color: color,
                       size: handleSize,
                       isActive: draggingV)
                .frame(width: handleSize, height: handleSize)
                .contentShape(Rectangle().size(width: handleSize + 32, height: handleSize + 32)
                    .offset(x: -(handleSize + 32) / 2, y: -(handleSize + 32) / 2))
                .position(x: guideX, y: containerSize.height - handleSize / 2 - 50)
                .gesture(
                    DragGesture(minimumDistance: 0, coordinateSpace: .named(coordinateSpaceName))
                        .onChanged { value in
                            if !draggingV {
                                draggingV = true
                                dragStartGuideX = guideX
                            }
                            guideX = (dragStartGuideX + value.translation.width)
                            .clamped(to: imageBounds.minX...imageBounds.maxX)
                        }
                        .onEnded { _ in
                            draggingV = false
                            onDragEnded()   // ← add this
                            
                        }
                )
        }
        .frame(width: containerSize.width, height: containerSize.height)
        // Named coordinate space so DragGesture and .position share the same origin
        .coordinateSpace(name: coordinateSpaceName)
        .transaction { $0.animation = nil }
    }
}

// MARK: - Supporting views (unchanged)

private struct CrosshairMarker: View {
    let color: Color
    let label: String

    var body: some View {
        ZStack {
            Circle().stroke(color, lineWidth: 1.5).frame(width: 20, height: 20)
            Circle().fill(color).frame(width: 5, height: 5)
            Group {
                Rectangle().frame(width: 10, height: 1.5).offset(x: -12)
                Rectangle().frame(width: 10, height: 1.5).offset(x:  12)
                Rectangle().frame(width: 1.5, height: 10).offset(y: -12)
                Rectangle().frame(width: 1.5, height: 10).offset(y:  12)
            }
            .foregroundColor(color)
            Text(label)
                .font(.system(size: 10, weight: .bold))
                .foregroundColor(color)
                .padding(3)
                .background(Color.black.opacity(0.7))
                .cornerRadius(4)
                .offset(x: 36, y: -14)
        }
    }
}

private struct DragHandle: View {
    let icon: String
    let color: Color
    let size: CGFloat
    let isActive: Bool

    var body: some View {
        ZStack {
            Circle().fill(Color.black.opacity(isActive ? 0.85 : 0.65))
                .frame(width: size, height: size)
            Circle().stroke(color, lineWidth: isActive ? 2 : 1)
                .frame(width: size, height: size)
            Image(systemName: icon)
                .font(.system(size: size * 0.38, weight: .semibold))
                .foregroundColor(color)
        }
        .scaleEffect(isActive ? 1.15 : 1.0)
        .animation(.spring(response: 0.2), value: isActive)
    }
}

private extension CGFloat {
    func clamped(to range: ClosedRange<CGFloat>) -> CGFloat {
        Swift.min(Swift.max(self, range.lowerBound), range.upperBound)
    }
}
