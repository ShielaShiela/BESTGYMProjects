// ManualAnnotationView.swift
// Manual point annotation with 2D, 2D+depth-assumption, and 3D LiDAR height measurements.
// Layout mirrors FlightHeightView: stat cards → (optional depth panel) → points table.

import SwiftUI
import Charts

// MARK: - Main View

struct ManualAnnotationView: View {
    @ObservedObject var appState: MainAppState
    @State var mediaManager: MediaManagerVM
    @State var calibrationModel: CalibrationModel
    let isLiDAR: Bool
    
    // ── Accept the shared VM instead of creating its own ──
  @State var vm: ManualAnnotationVM           // ← was @State private var vm = ManualAnnotationVM()
  @State private var showDepthPanel: Bool = true


    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 12) {

                // ── Calibration warning ──────────────────────────────────────
                if !calibrationModel.isCalibrated {
                    HStack(spacing: 8) {
                        Image(systemName: "exclamationmark.triangle.fill")
                            .foregroundColor(.orange)
                        Text("Calibrate the bar first using the ruler button in the toolbar.")
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                    .padding()
                    .frame(maxWidth: .infinity)
                    .background(Color.orange.opacity(0.1))
                    .cornerRadius(8)
                    .padding(.horizontal)
                }
                // ── Hint label replacing the removed image panel ──
                HStack(spacing: 6) {
                    Image(systemName: "hand.tap.fill").foregroundColor(.red).font(.caption)
                    Text("Tap on the left video panel to place annotation points.")
                        .font(.caption).foregroundColor(.secondary)
                }
                .padding(.horizontal)

                // ── LiDAR depth colourmap panel ──────────────────────────────
                if isLiDAR && vm.isLiDARAvailable {
                    DepthColormapPanel(vm: vm, showDepthPanel: $showDepthPanel)
                        .padding(.horizontal)
                }

                // ── Stat cards (summary of all placed points) ────────────────
                let currentPoints = vm.annotationsByFrame[mediaManager.currentFrameIndex] ?? []
                if !currentPoints.isEmpty {
                    ManualAnnotationStatsRow(
                        points: currentPoints,
                        measurements: vm.measurements
                    )
                    .padding(.horizontal)
                }

                // ── Points table ─────────────────────────────────────────────
                // Points table — NOW with depth column
                ManualAnnotationTableView(
                    vm: vm,
                    onSeek: { idx in mediaManager.seekToFrame(idx) },
                    onDelete: { id, frame in vm.removePoint(id: id, frameIndex: frame) }
                )
                .padding(.horizontal)            }
            .padding(.vertical)
        }
        .onAppear {
            setupDepthLoader()
        }
        .onChange(of: mediaManager.currentFrameIndex) { _, newIndex in
            Task { await vm.loadDepthColormap(frameIndex: newIndex) }
            Task { await vm.prefetchDepthColormap(frameIndex: newIndex + 1) }
        }
    }

    // MARK: - Helpers

    private func setupDepthLoader() {
        guard isLiDAR else {
            print("⚠️ ManualAnnotationView: isLiDAR=false, depth loader skipped")
            return
        }
        guard let sourceURL = appState.sourceURL else {
            print("⚠️ ManualAnnotationView: sourceURL is nil")
            return
        }

        // sourceURL can be:
        //  • the recording folder itself              → depth_frames/ is directly inside
        //  • the color_video.mp4 file inside folder   → depth_frames/ is next to it
        // configure() now handles both via recursive search, just pass sourceURL directly.
        print("📡 ManualAnnotationView: setupDepthLoader with sourceURL=\(sourceURL.path)")
        vm.configure(recordingFolderURL: sourceURL)
        Task { await vm.loadDepthColormap(frameIndex: mediaManager.currentFrameIndex) }
    }

}

// MARK: - Tap-to-Annotate Image Panel

private struct AnnotationImagePanel: View {
    @State var mediaManager: MediaManagerVM
    @State var calibrationModel: CalibrationModel
    @State var vm: ManualAnnotationVM
    var nextLabel: String
    @Binding var labelCounter: Int
    @Binding var nextLabelBinding: String
    var onPointAdded: (AnnotationPoint) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Text("Tap image to annotate · Frame \(mediaManager.currentFrameIndex)")
                    .font(.caption.bold())
                    .foregroundColor(.secondary)
                Spacer()
                Button {
                    vm.clearFrame(mediaManager.currentFrameIndex)
                } label: {
                    Label("Clear", systemImage: "trash")
                        .font(.caption)
                        .foregroundColor(.red)
                }
            }

            GeometryReader { geo in
                ZStack {
                    // Base image
                    if let img = mediaManager.currentFrameImage {
                        Image(uiImage: img)
                            .resizable()
                            .scaledToFit()
                            .frame(width: geo.size.width, height: geo.size.height)
                    } else {
                        Color.black.opacity(0.3)
                    }

                    // Bar top reference line
                    if calibrationModel.isCalibrated,
                       let barTop = calibrationModel.barTopPoint {
                        let lineY = CGFloat(barTop.y) * geo.size.height
                        Path { path in
                            path.move(to: CGPoint(x: 0, y: lineY))
                            path.addLine(to: CGPoint(x: geo.size.width, y: lineY))
                        }
                        .stroke(Color.yellow.opacity(0.8),
                                style: StrokeStyle(lineWidth: 1.5, dash: [6, 3]))
                    }

                    // Placed annotation dots
                    let currentPoints = vm.annotationsByFrame[mediaManager.currentFrameIndex] ?? []
                    ForEach(currentPoints) { pt in
                        let px = CGFloat(pt.normalizedX) * geo.size.width
                        let py = CGFloat(pt.normalizedY) * geo.size.height
                        ZStack {
                            Circle()
                                .fill(Color.red.opacity(0.8))
                                .frame(width: 12, height: 12)
                            Circle()
                                .stroke(Color.white, lineWidth: 1.5)
                                .frame(width: 12, height: 12)
                            // Draw line to bar
                            if calibrationModel.isCalibrated,
                               let barTop = calibrationModel.barTopPoint {
                                let barY = CGFloat(barTop.y) * geo.size.height
                                Path { path in
                                    path.move(to: CGPoint(x: px, y: py))
                                    path.addLine(to: CGPoint(x: px, y: barY))
                                }
                                .stroke(Color.red.opacity(0.6),
                                        style: StrokeStyle(lineWidth: 1, dash: [3, 2]))
                                .offset(x: -px, y: -py)   // path is absolute, ZStack needs offset correction
                            }
                        }
                        .position(x: px, y: py)
                        .overlay(
                            Text(pt.label)
                                .font(.system(size: 9, weight: .bold))
                                .foregroundColor(.white)
                                .padding(2)
                                .background(Color.red.opacity(0.7))
                                .cornerRadius(3)
                                .offset(x: 10, y: -10),
                            alignment: .topLeading
                        )
                    }
                }
                .contentShape(Rectangle())
                .onTapGesture { location in
                    let nx = Double(location.x / geo.size.width)
                    let ny = Double(location.y / geo.size.height)
                    let point = AnnotationPoint(
                        frameIndex: mediaManager.currentFrameIndex,
                        normalizedX: nx,
                        normalizedY: ny,
                        label: nextLabelBinding
                    )
                    onPointAdded(point)
                }
            }
            .frame(height: 200)
            .clipShape(RoundedRectangle(cornerRadius: 10))
            .overlay(
                RoundedRectangle(cornerRadius: 10)
                    .stroke(Color(.systemGray4), lineWidth: 1)
            )
        }
    }
}

// MARK: - Depth Colourmap Panel

// 2. DepthColormapPanel — spinner moves to header, image never blanks
private struct DepthColormapPanel: View {
    @State var vm: ManualAnnotationVM
    @Binding var showDepthPanel: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Image(systemName: "sensor.tag.radiowaves.forward.fill")
                    .foregroundColor(.cyan).font(.caption)
                Text("LiDAR Depth Visualisation")
                    .font(.caption.bold()).foregroundColor(.secondary)
                Spacer()
                // ✅ Subtle spinner in header — image stays visible underneath
                if vm.isLoadingDepth {
                    ProgressView().scaleEffect(0.6)
                }
                Button { withAnimation { showDepthPanel.toggle() } } label: {
                    Image(systemName: showDepthPanel ? "chevron.up" : "chevron.down")
                        .font(.caption).foregroundColor(.secondary)
                }
            }

            if showDepthPanel {
                if let img = vm.depthColormapImage {
                    // ✅ .id(img) tells SwiftUI the image changed → triggers animation
                    Image(uiImage: img)
                        .resizable().scaledToFit()
                        .frame(maxWidth: .infinity)
                        .clipShape(RoundedRectangle(cornerRadius: 8))
                        .transition(.opacity)
                        .animation(.easeInOut(duration: 0.12), value: ObjectIdentifier(img))
                        .overlay(DepthColorBarLegend().padding(4),
                                 alignment: .bottomTrailing)
                } else if !vm.isLoadingDepth {
                    Text("Depth frame not available for this frame.")
                        .font(.caption).foregroundColor(.secondary)
                        .frame(maxWidth: .infinity, minHeight: 60)
                        .multilineTextAlignment(.center)
                } else {
                    HStack {
                        ProgressView()
                        Text("Loading depth frame…")
                            .font(.caption).foregroundColor(.secondary)
                    }
                    .frame(maxWidth: .infinity, minHeight: 100)
                }
            }
        }
        .padding(10)
        .background(Color(.systemGray6))
        .cornerRadius(10)
    }
}

// MARK: - Depth colour bar legend (horizontal gradient)

private struct DepthColorBarLegend: View {
    var body: some View {
        HStack(spacing: 4) {
            Text("near")
                .font(.system(size: 8))
                .foregroundColor(.white)
            LinearGradient(
                colors: [
                    Color(red: 0, green: 0, blue: 0.5),
                    Color(red: 0, green: 1, blue: 1),
                    Color(red: 1, green: 1, blue: 0),
                    Color(red: 1, green: 0, blue: 0)
                ],
                startPoint: .leading,
                endPoint: .trailing
            )
            .frame(width: 60, height: 8)
            .cornerRadius(4)
            Text("far")
                .font(.system(size: 8))
                .foregroundColor(.white)
        }
        .padding(4)
        .background(Color.black.opacity(0.5))
        .cornerRadius(6)
    }
}

// MARK: - Stat Cards Row

private struct ManualAnnotationStatsRow: View {
    let points: [AnnotationPoint]
    let measurements: [UUID: ManualMeasurementResult]

    private var bestMeasurement: ManualMeasurementResult? {
        points
            .compactMap { measurements[$0.id] }
            .max(by: { ($0.cm2D ?? -999) < ($1.cm2D ?? -999) })
    }

    private var currentMeasurement: ManualMeasurementResult? {
        measurements[points.last?.id ?? UUID()]
    }

    var body: some View {
        HStack(spacing: 10) {
            ManualStatCard(
                label: "2D",
                value: (currentMeasurement ?? bestMeasurement)?.cm2D,
                unit: "cm",
                color: .green,
                icon: "ruler",
                subtitle: "pixel ratio"
            )
            ManualStatCard(
                label: "2D + depth",
                value: (currentMeasurement ?? bestMeasurement)?.cm2DWithDepthAssumption,
                unit: "cm",
                color: .yellow,
                icon: "perspective",
                subtitle: "8.3m+1.6m"
            )
            ManualStatCard(
                label: "3D LiDAR",
                value: (currentMeasurement ?? bestMeasurement)?.cm3D,
                unit: "cm",
                color: .cyan,
                icon: "sensor.tag.radiowaves.forward.fill",
                subtitle: "depth corrected"
            )
        }
    }
}

// MARK: - Single stat card

private struct ManualStatCard: View {
    let label: String
    let value: Double?
    let unit: String
    let color: Color
    let icon: String
    let subtitle: String

    var body: some View {
        VStack(spacing: 3) {
            HStack(spacing: 3) {
                Image(systemName: icon)
                    .font(.system(size: 9))
                    .foregroundColor(color)
                Text(label)
                    .font(.system(size: 10))
                    .foregroundColor(.secondary)
            }
            if let v = value {
                Text(String(format: "%.1f", v))
                    .font(.system(size: 15, weight: .bold).monospacedDigit())
                    .foregroundColor(color)
                Text(unit)
                    .font(.system(size: 9))
                    .foregroundColor(.secondary)
            } else {
                Text("--")
                    .font(.system(size: 15, weight: .bold))
                    .foregroundColor(.secondary)
            }
            Text(subtitle)
                .font(.system(size: 8))
                .foregroundColor(.secondary.opacity(0.7))
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 8)
        .background(Color(.systemGray6))
        .cornerRadius(8)
    }
}

// MARK: - Points Table
private struct ManualAnnotationTableView: View {
    @State var vm: ManualAnnotationVM
    let onSeek: (Int) -> Void
    let onDelete: (UUID, Int) -> Void

    private var allPoints: [AnnotationPoint] { vm.allPoints() }

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("Annotated Points")
                .font(.caption.bold())
                .foregroundColor(.secondary)

            if allPoints.isEmpty {
                Text("Tap on the video panel to place measurement points.")
                    .font(.caption)
                    .foregroundColor(.secondary)
                    .frame(maxWidth: .infinity, minHeight: 40)
                    .multilineTextAlignment(.center)
            } else {
                // ── Column headers ──────────────────────────────────────
                HStack {
                    Text("Label").frame(width: 40, alignment: .leading)
                    Text("Frame").frame(width: 46, alignment: .leading)
                    Spacer()
                    Text("2D").frame(width: 48, alignment: .trailing)
                    Text("+Depth").frame(width: 52, alignment: .trailing)
                    Text("3D").frame(width: 48, alignment: .trailing)
                    Text("Raw D").frame(width: 48, alignment: .trailing)   // ← NEW column
                    Spacer(minLength: 28)
                }
                .font(.system(size: 9, weight: .semibold))
                .foregroundColor(.secondary)
                .padding(.horizontal, 4)

                Divider()

                ForEach(allPoints) { pt in
                    let m = vm.measurements[pt.id]
                    HStack {
                        Text(pt.label)
                            .font(.caption.bold())
                            .foregroundColor(.primary)
                            .frame(width: 40, alignment: .leading)

                        Text("\(pt.frameIndex)")
                            .font(.caption.monospaced())
                            .frame(width: 46, alignment: .leading)

                        Spacer()

                        measureCell(m?.cm2D, color: .green)
                            .frame(width: 48, alignment: .trailing)

                        measureCell(m?.cm2DWithDepthAssumption, color: .yellow)
                            .frame(width: 52, alignment: .trailing)

                        measureCell(m?.cm3D, color: .cyan)
                            .frame(width: 48, alignment: .trailing)

                        // ── NEW: raw LiDAR depth at point ──────────────
                        depthCell(m?.rawDepthAtPoint)
                            .frame(width: 48, alignment: .trailing)

                        HStack(spacing: 6) {
                            Button { onSeek(pt.frameIndex) } label: {
                                Image(systemName: "arrow.right.circle")
                                    .font(.system(size: 13))
                                    .foregroundColor(.blue)
                            }
                            Button { onDelete(pt.id, pt.frameIndex) } label: {
                                Image(systemName: "xmark.circle")
                                    .font(.system(size: 13))
                                    .foregroundColor(.red)
                            }
                        }
                        .frame(width: 36)
                    }
                    .padding(.vertical, 3)
                    .padding(.horizontal, 4)

                    Divider()
                }

                // Footer note — unchanged
                if vm.isLiDARAvailable {
                    HStack(spacing: 4) {
                        Image(systemName: "info.circle").font(.system(size: 9)).foregroundColor(.cyan)
                        Text("Raw D = LiDAR depth (m) at tapped pixel · 3D uses actual depth · bar depth from sensor or assumed \(String(format: "%.1f", DepthConstants.barDepthMetres))m")
                            .font(.system(size: 9)).foregroundColor(.secondary)
                    }
                    .padding(.top, 4)
                } else {
                    HStack(spacing: 4) {
                        Image(systemName: "info.circle").font(.system(size: 9)).foregroundColor(.yellow)
                        Text("+Depth assumes bar \(String(format: "%.1f", DepthConstants.barDepthMetres))m, subject \(String(format: "%.1f", DepthConstants.subjectDepthMetres))m · No LiDAR")
                            .font(.system(size: 9)).foregroundColor(.secondary)
                    }
                    .padding(.top, 4)
                }
            }
        }
        .padding(10)
        .background(Color(.systemGray6))
        .cornerRadius(10)
    }

    @ViewBuilder
    private func measureCell(_ value: Double?, color: Color) -> some View {
        if let v = value {
            Text(String(format: "%.1f", v))
                .font(.system(size: 10, weight: .semibold).monospacedDigit())
                .foregroundColor(color)
        } else {
            Text("--").font(.system(size: 10)).foregroundColor(.secondary)
        }
    }

    // ── NEW helper for the raw depth cell ──
    @ViewBuilder
    private func depthCell(_ value: Float?) -> some View {
        if let v = value {
            Text(String(format: "%.2fm", v))
                .font(.system(size: 10, weight: .semibold).monospacedDigit())
                .foregroundColor(.purple)
        } else {
            Text("--").font(.system(size: 10)).foregroundColor(.secondary)
        }
    }
}
