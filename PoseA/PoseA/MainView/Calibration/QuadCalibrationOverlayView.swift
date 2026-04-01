import SwiftUI

// MARK: - QuadCalibrationOverlayView
/// Renders when quad calibration mode is active.
/// Shows a draggable 4-corner quad over the video frame.
/// Placement phase: tap to place corners one by one.
/// Edit phase: drag any corner handle to fine-tune.

struct QuadCalibrationOverlayView: View {
    @Bindable var quadModel: QuadCalibrationModel
    let containerSize: CGSize
    let imageSize: CGSize

    @State private var dragOffsets: [CGSize] = Array(repeating: .zero, count: 4)
    @State private var draggingIndex: Int? = nil
    @State private var showDimensionInput: Bool = false

    // Corner labels for UX clarity
    private let cornerLabels = ["TL", "TR", "BR", "BL"]
    private let cornerColors: [Color] = [.yellow, .yellow, .orange, .orange]

    var body: some View {
        ZStack {
            // ── Placement tap area ─────────────────────────────────────
            if quadModel.step == .placing && quadModel.corners.count < 4 {
                placementInstructionBanner

                Color.clear
                    .contentShape(Rectangle())
                    .onTapGesture { location in
                        let normalized = displayToNormalized(location)
                        quadModel.addCorner(normalized)
                        // Auto-open dimension input when 4th corner placed
                        if quadModel.corners.count == 4 {
                            DispatchQueue.main.asyncAfter(deadline: .now() + 0.2) {
                                showDimensionInput = true
                            }
                        }
                    }
            }

            // ── Quad polygon ───────────────────────────────────────────
            if quadModel.corners.count >= 2 {
                let displayPts = quadModel.corners.map { normalizedToDisplay($0) }

                // Filled semi-transparent tint
                if quadModel.corners.count == 4 {
                    Path { path in
                        path.addLines(displayPts + [adjustedPoint(index: 0)])
                        path.closeSubpath()
                    }
                    .fill(Color.cyan.opacity(0.10))

                    // Outline
                    Path { path in
                        path.move(to: adjustedDisplayPoint(index: 0))
                        for i in 1..<4 { path.addLine(to: adjustedDisplayPoint(index: i)) }
                        path.closeSubpath()
                    }
                    .stroke(Color.cyan.opacity(0.85), lineWidth: 1.5)

                    // Dimension labels on edges
                    widthLabel(displayPts: displayPts)
                    heightLabel(displayPts: displayPts)
                } else {
                    // Partial outline while still placing
                    Path { path in
                        path.move(to: normalizedToDisplay(quadModel.corners[0]))
                        for i in 1..<quadModel.corners.count {
                            path.addLine(to: normalizedToDisplay(quadModel.corners[i]))
                        }
                    }
                    .stroke(Color.cyan.opacity(0.7), style: StrokeStyle(lineWidth: 1.5, dash: [5, 3]))
                }
            }

            // ── Placed corner dots (while placing) ─────────────────────
            ForEach(Array(quadModel.corners.enumerated()), id: \.offset) { i, pt in
                let dp = normalizedToDisplay(pt)
                ZStack {
                    Circle().fill(cornerColors[i < cornerColors.count ? i : 0].opacity(0.9))
                        .frame(width: 14, height: 14)
                    Circle().stroke(Color.white, lineWidth: 1.5)
                        .frame(width: 14, height: 14)
                    Text(cornerLabels[i < cornerLabels.count ? i : 0])
                        .font(.system(size: 8, weight: .bold))
                        .foregroundColor(.black)
                }
                .position(x: dp.x, y: dp.y)
            }

            // ── Draggable handles (complete quad) ──────────────────────
            if quadModel.corners.count == 4 {
                ForEach(0..<4, id: \.self) { i in
                    let dp = adjustedDisplayPoint(index: i)

                    ZStack {
                        // Large invisible hit area
                        Color.clear
                            .frame(width: 44, height: 44)
                            .contentShape(Circle())

                        // Visual handle
                        ZStack {
                            Circle()
                                .fill(draggingIndex == i ? Color.white : Color.black.opacity(0.6))
                                .frame(width: 22, height: 22)
                            Circle()
                                .stroke(cornerColors[i], lineWidth: draggingIndex == i ? 2.5 : 1.5)
                                .frame(width: 22, height: 22)
                            Text(cornerLabels[i])
                                .font(.system(size: 8, weight: .bold))
                                .foregroundColor(cornerColors[i])
                        }
                        .scaleEffect(draggingIndex == i ? 1.25 : 1.0)
                        .animation(.spring(response: 0.2), value: draggingIndex)
                    }
                    .position(x: dp.x, y: dp.y)
                    .gesture(
                        DragGesture(minimumDistance: 0)
                            .onChanged { value in
                                draggingIndex = i
                                dragOffsets[i] = value.translation
                            }
                            .onEnded { value in
                                let rawPt = CGPoint(
                                    x: normalizedToDisplay(quadModel.corners[i]).x + value.translation.width,
                                    y: normalizedToDisplay(quadModel.corners[i]).y + value.translation.height
                                )
                                let clamped = clampToImageBounds(rawPt)
                                quadModel.moveCorner(index: i, to: displayToNormalized(clamped))
                                dragOffsets[i] = .zero
                                draggingIndex = nil
                            }
                    )
                }

                // ── Edit buttons ──────────────────────────────────────
                editButtons
            }
        }
        .frame(width: containerSize.width, height: containerSize.height)
        .sheet(isPresented: $showDimensionInput) {
            QuadDimensionInputView(quadModel: quadModel)
        }
    }

    // MARK: - Sub-views

    private var placementInstructionBanner: some View {
        VStack {
            HStack {
                Spacer()
                VStack(spacing: 2) {
                    Text("Quad Calibration")
                        .font(.caption.bold())
                        .foregroundColor(.cyan)
                    Text("Tap corner \(quadModel.corners.count + 1)/4: \(cornerLabels[quadModel.corners.count])")
                        .font(.system(size: 11))
                        .foregroundColor(.white)
                    Text("Place in clockwise order starting top-left")
                        .font(.system(size: 10))
                        .foregroundColor(.white.opacity(0.7))
                }
                .padding(.horizontal, 10)
                .padding(.vertical, 6)
                .background(Color.black.opacity(0.75))
                .cornerRadius(8)
                Spacer()
            }
            .padding(.top, 8)
            Spacer()
        }
        .allowsHitTesting(false)
    }

    private var editButtons: some View {
        VStack {
            Spacer()
            HStack {
                Spacer()
                Button {
                    showDimensionInput = true
                } label: {
                    HStack(spacing: 4) {
                        Image(systemName: "ruler")
                            .font(.system(size: 11))
                        Text(String(format: "%.0f × %.0f cm", quadModel.realWidthCm, quadModel.realHeightCm))
                            .font(.caption.monospacedDigit())
                    }
                    .foregroundColor(.white)
                    .padding(.horizontal, 9)
                    .padding(.vertical, 5)
                    .background(Color.cyan.opacity(0.8))
                    .cornerRadius(7)
                }
                .padding(.bottom, 8)
                .padding(.trailing, 8)
            }
        }
        .allowsHitTesting(true)
    }

    @ViewBuilder
    private func widthLabel(displayPts: [CGPoint]) -> some View {
        let topMid = CGPoint(
            x: (displayPts[0].x + displayPts[1].x) / 2,
            y: (displayPts[0].y + displayPts[1].y) / 2 - 14
        )
        Text(String(format: "%.0f cm", quadModel.realWidthCm))
            .font(.system(size: 9, weight: .semibold))
            .foregroundColor(.cyan)
            .padding(.horizontal, 4)
            .padding(.vertical, 2)
            .background(Color.black.opacity(0.6))
            .cornerRadius(3)
            .position(topMid)
            .allowsHitTesting(false)
    }

    @ViewBuilder
    private func heightLabel(displayPts: [CGPoint]) -> some View {
        let rightMid = CGPoint(
            x: (displayPts[1].x + displayPts[2].x) / 2 + 22,
            y: (displayPts[1].y + displayPts[2].y) / 2
        )
        Text(String(format: "%.0f cm", quadModel.realHeightCm))
            .font(.system(size: 9, weight: .semibold))
            .foregroundColor(.orange)
            .padding(.horizontal, 4)
            .padding(.vertical, 2)
            .background(Color.black.opacity(0.6))
            .cornerRadius(3)
            .position(rightMid)
            .allowsHitTesting(false)
    }

    // MARK: - Coordinate helpers

    private func fittedImageRect() -> CGRect {
        let imageAspect     = imageSize.width / imageSize.height
        let containerAspect = containerSize.width / containerSize.height
        if imageAspect > containerAspect {
            let w = containerSize.width
            let h = w / imageAspect
            return CGRect(x: 0, y: (containerSize.height - h) / 2, width: w, height: h)
        } else {
            let h = containerSize.height
            let w = h * imageAspect
            return CGRect(x: (containerSize.width - w) / 2, y: 0, width: w, height: h)
        }
    }

    private func normalizedToDisplay(_ pt: CGPoint) -> CGPoint {
        let r = fittedImageRect()
        return CGPoint(x: r.origin.x + pt.x * r.width, y: r.origin.y + pt.y * r.height)
    }

    private func displayToNormalized(_ pt: CGPoint) -> CGPoint {
        let r = fittedImageRect()
        return CGPoint(x: (pt.x - r.origin.x) / r.width, y: (pt.y - r.origin.y) / r.height)
    }

    private func clampToImageBounds(_ pt: CGPoint) -> CGPoint {
        let r = fittedImageRect()
        return CGPoint(
            x: Swift.min(Swift.max(pt.x, r.minX), r.maxX),
            y: Swift.min(Swift.max(pt.y, r.minY), r.maxY)
        )
    }

    private func adjustedPoint(index: Int) -> CGPoint {
        normalizedToDisplay(quadModel.corners[index])
    }

    private func adjustedDisplayPoint(index: Int) -> CGPoint {
        let base = normalizedToDisplay(quadModel.corners[index])
        return CGPoint(
            x: base.x + dragOffsets[index].width,
            y: base.y + dragOffsets[index].height
        )
    }
}

// MARK: - QuadDimensionInputView

struct QuadDimensionInputView: View {
    @Bindable var quadModel: QuadCalibrationModel
    @Environment(\.dismiss) private var dismiss

    @State private var widthText:  String = ""
    @State private var heightText: String = ""

    var body: some View {
        NavigationView {
            Form {
                Section {
                    VStack(alignment: .leading, spacing: 6) {
                        Text("Enter the real-world size of the reference rectangle you placed.")
                            .font(.subheadline)
                            .foregroundColor(.secondary)
                        Text("Example: a 100×60 cm mat, a door frame, court markings…")
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                    .padding(.vertical, 4)
                } header: {
                    Text("Reference Dimensions")
                }

                Section("Width (horizontal, cm)") {
                    TextField("e.g. 100", text: $widthText)
                        .keyboardType(.decimalPad)
                }

                Section("Height (vertical, cm)") {
                    TextField("e.g. 60", text: $heightText)
                        .keyboardType(.decimalPad)
                }

                if let w = Double(widthText), let h = Double(heightText), w > 0, h > 0 {
                    Section("Scale Preview") {
                        if let scaleY = previewScaleY(height: h) {
                            Text(String(format: "Vertical: %.1f cm per normalised unit", scaleY))
                                .font(.caption.monospacedDigit())
                                .foregroundColor(.secondary)
                        }
                        if let scaleX = previewScaleX(width: w) {
                            Text(String(format: "Horizontal: %.1f cm per normalised unit", scaleX))
                                .font(.caption.monospacedDigit())
                                .foregroundColor(.secondary)
                        }
                    }
                }
            }
            .navigationTitle("Quad Reference Size")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Confirm") {
                        if let w = Double(widthText), let h = Double(heightText), w > 0, h > 0 {
                            quadModel.realWidthCm  = w
                            quadModel.realHeightCm = h
                            quadModel.confirmDimensions()
                        }
                        dismiss()
                    }
                    .disabled(!inputIsValid)
                }
            }
            .onAppear {
                widthText  = String(format: "%.0f", quadModel.realWidthCm)
                heightText = String(format: "%.0f", quadModel.realHeightCm)
            }
        }
        .presentationDetents([.medium])
    }

    private var inputIsValid: Bool {
        guard let w = Double(widthText), let h = Double(heightText) else { return false }
        return w > 0 && h > 0
    }

    private func previewScaleY(height: Double) -> Double? {
        guard let span = quadModel.normalizedHeightSpan else { return nil }
        return height / span
    }

    private func previewScaleX(width: Double) -> Double? {
        guard let span = quadModel.normalizedWidthSpan else { return nil }
        return width / span
    }
}

struct QuadCalibrationModeControlView: View {
    @Bindable var quadCalibrationModel: QuadCalibrationModel
    let exitAction: () -> Void

    var body: some View {
        HStack(spacing: 8) {
            quadControls

            Divider().frame(height: 16)

            Button(action: exitAction) {
                Text("Done")
                    .font(.caption.bold())
                    .foregroundColor(.white)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 3)
                    .background(Color.blue.opacity(0.8))
                    .cornerRadius(5)
            }
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 5)
        .background(Color(.systemGray5).opacity(0.9))
        .cornerRadius(10)
    }

    private var quadControls: some View {
        HStack(spacing: 8) {
            Text(quadStatusLabel)
                .font(.caption)
                .foregroundColor(quadStatusColor)

            Divider().frame(height: 16)

            if quadCalibrationModel.step != .placing {
                Button(action: { quadCalibrationModel.startPlacing() }) {
                    HStack(spacing: 4) {
                        Image(systemName: "square.dashed")
                            .font(.system(size: 11))
                        Text(quadCalibrationModel.isCalibrated ? "Re-place" : "Place Quad")
                            .font(.caption.bold())
                    }
                    .foregroundColor(.white)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 3)
                    .background(Color.cyan.opacity(0.85))
                    .cornerRadius(5)
                }
            } else {
                Text("Tap 4 corners →")
                    .font(.caption)
                    .foregroundColor(.cyan)
            }

            if quadCalibrationModel.corners.count > 0 {
                Button(action: { quadCalibrationModel.reset() }) {
                    Image(systemName: "xmark.circle")
                        .font(.system(size: 12))
                        .foregroundColor(.secondary)
                }
            }
        }
    }

    private var quadStatusLabel: String {
        switch quadCalibrationModel.step {
        case .idle:                return "Not placed"
        case .placing:             return "Placing (\(quadCalibrationModel.corners.count)/4)"
        case .inputtingDimensions: return "Enter size…"
        case .complete:
            return String(format: "✓ %.0f×%.0f cm",
                          quadCalibrationModel.realWidthCm,
                          quadCalibrationModel.realHeightCm)
        }
    }

    private var quadStatusColor: Color {
        switch quadCalibrationModel.step {
        case .idle:                return .secondary
        case .placing:             return .cyan
        case .inputtingDimensions: return .orange
        case .complete:            return .green
        }
    }
}
