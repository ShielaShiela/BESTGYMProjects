//
//  PointPickerView.swift
//  PoseA
//
//  Created by Ardhika Maulidani on 8/28/25.
//

import SwiftUI

struct PointPickerView: View {
    @State private var selectedPoint: CGPoint = .zero
    @State private var dragStartPoint: CGPoint = .zero
    @State private var isDragging = false

    var body: some View {
        GeometryReader { geo in
            ZStack {
                // Background content
                Color.black.opacity(0.2)
                    .ignoresSafeArea()

                // Crosshair overlay
                CrosshairView(point: selectedPoint, size: geo.size)
                    .stroke(style: StrokeStyle(lineWidth: 2, dash: [5]))
                    .foregroundColor(.white.opacity(0.7))
                    .animation(.easeInOut(duration: 0.1), value: selectedPoint)

                // Circle Dot
                Circle()
                    .foregroundColor(.white.opacity(0.7))
                    .frame(width: 8, height: 8)
                    .position(selectedPoint)
            }
            .onAppear {
                // Initialize at center only once
                if selectedPoint == .zero {
                    selectedPoint = CGPoint(x: geo.size.width / 2,
                                            y: geo.size.height / 2)
                }
            }
            .contentShape(Rectangle()) // Drag anywhere
            .gesture(
                DragGesture(minimumDistance: 0)
                    .onChanged { value in
                        // First event of this drag: capture base point
                        if !isDragging {
                            isDragging = true
                            dragStartPoint = selectedPoint
                        }

                        // Move relative to starting crosshair position
                        let proposed = CGPoint(
                            x: dragStartPoint.x + value.translation.width * 0.4,
                            y: dragStartPoint.y + value.translation.height * 0.4
                        )

                        // Keep inside bounds
                        selectedPoint = proposed.clamped(to: geo.size)
                    }
                    .onEnded { _ in
                        isDragging = false
                    }
            )
        }
    }
}

/// A shape that draws crosshair lines at the chosen point
struct CrosshairView: Shape {
    let point: CGPoint
    let size: CGSize

    func path(in rect: CGRect) -> Path {
        var path = Path()

        // Horizontal line
        path.move(to: CGPoint(x: 0, y: point.y))
        path.addLine(to: CGPoint(x: size.width, y: point.y))

        // Vertical line
        path.move(to: CGPoint(x: point.x, y: 0))
        path.addLine(to: CGPoint(x: point.x, y: size.height))

        return path
    }
}

// MARK: - Utilities
private extension CGPoint {
    func clamped(to size: CGSize, inset: CGFloat = 0) -> CGPoint {
        CGPoint(
            x: max(inset, min(size.width - inset, x)),
            y: max(inset, min(size.height - inset, y))
        )
    }
}

