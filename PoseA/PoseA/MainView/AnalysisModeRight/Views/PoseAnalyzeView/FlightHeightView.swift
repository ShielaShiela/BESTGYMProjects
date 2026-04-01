//
//  FlightHeightView.swift
//  PoseA
//
//  Created by Shiela Cabahug on 2026/2/19.
//
// FlightHeightView.swift
import SwiftUI
import Charts

struct FlightHeightView: View {
    @ObservedObject var appState: MainAppState
    @State var poseJointVM: PoseJointLandscapeVM
    @State var mediaManager: MediaManagerVM
    @State var calibrationModel: CalibrationModel
    @State var quadCalibrationModel: QuadCalibrationModel

    @State private var cachedFlightData: [FlightHeightData] = []
    // ── NEW: persisted keypoint selection ──
    @State private var selectedKeypointMode: FlightKeypointMode = .nose

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 12) {
                
                CalibrationSourceBadge(
                    calibrationModel: calibrationModel,
                    quadCalibrationModel: quadCalibrationModel
                )
                .padding(.horizontal)
                
                

                // Replace the single warning HStack with these two:

                // Warning 1: Bar top reference missing
                if calibrationModel.barTopPoint == nil {
                    WarningBanner(
                        icon: "scope",
                        message: "Tap the ruler button → mark the bar top position (required as height zero reference)",
                        color: .red
                    )
                    .padding(.horizontal)
                }

                // Warning 2: Scale calibration missing
                if !isScaleCalibrated {
                    WarningBanner(
                        icon: "exclamationmark.triangle.fill",
                        message: scaleWarningMessage,
                        color: .orange
                    )
                    .padding(.horizontal)
                }

                // ── NEW: Keypoint picker ──
                KeypointSelectorRow(selectedMode: $selectedKeypointMode)
                    .padding(.horizontal)

                // Stat cards
                FlightHeightStatsRow(
                    flightData: cachedFlightData,
                    currentFrameIndex: mediaManager.currentFrameIndex,
                    calibrationModel: calibrationModel,
                    imagePixelHeight: Double(mediaManager.currentFrameImage?.size.height ?? 0)
                )
                .padding(.horizontal)

                // Chart
                if !cachedFlightData.isEmpty {
                    FlightHeightChartView(
                        flightData: cachedFlightData,
                        currentFrameIndex: mediaManager.currentFrameIndex
                    )

                    FlightPeaksTableView(
                        flightData: cachedFlightData,
                        onSeek: handleSeek
                    )
                    .padding(.horizontal)
                }
            }
            .padding(.vertical)
        }
        .onAppear { rebuildData() }
        .onChange(of: calibrationModel.isCalibrated) { _, _ in rebuildData() }
        .onChange(of: quadCalibrationModel.step) { _, _ in rebuildData() }
        .onChange(of: appState.isAnalysisAvailable)  { _, _ in rebuildData() }
        // ── NEW: rebuild when keypoint changes ──
        .onChange(of: selectedKeypointMode)          { _, _ in rebuildData() }
    }

    private var isScaleCalibrated: Bool {
        quadCalibrationModel.isCalibrated || calibrationModel.isCalibrated
    }

    private var scaleWarningMessage: String {
        if quadCalibrationModel.isCalibrated {
            return "Quad calibration active"
        } else if calibrationModel.isCalibrated {
            return "Complete 2-point calibration — mark both bar top and bar bottom"
        } else {
            return "Complete bar or quad calibration to get cm measurements"
        }
    }

    private var isEffectivelyCalibrated: Bool {
        calibrationModel.barTopPoint != nil && isScaleCalibrated
    }

    private func handleSeek(_ frameIndex: Int) {
        mediaManager.seekToFrame(frameIndex)
    }

    
    private func rebuildData() {
        guard calibrationModel.barTopPoint != nil, isScaleCalibrated else {
            cachedFlightData = []
            return
        }
        cachedFlightData = FlightHeightCalculator.calculate(
            mediaManager: mediaManager,
            calibration: calibrationModel,
            quadCalibration: quadCalibrationModel,
            keypointMode: selectedKeypointMode
        )
    }
}

// MARK: - Keypoint Selector Row
struct KeypointSelectorRow: View {
    @Binding var selectedMode: FlightKeypointMode

    // Group the full list into sections for the picker
    private let singleKeypoints: [FlightKeypointMode] = [
        .nose,
        .leftEye, .rightEye,
        .leftEar, .rightEar,
        .leftShoulder, .rightShoulder,
        .leftElbow, .rightElbow,
        .leftWrist, .rightWrist,
        .leftHip, .rightHip,
        .leftKnee, .rightKnee,
        .leftAnkle, .rightAnkle
    ]

    private let midpointKeypoints: [FlightKeypointMode] = [
        .midEyes, .midEars,
        .midShoulders, .midElbows, .midWrists,
        .midHips, .midKnees, .midAnkles
    ]

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(spacing: 6) {
                Image(systemName: "figure.walk")
                    .font(.system(size: 11))
                    .foregroundColor(.secondary)
                Text("Tracking Keypoint")
                    .font(.caption.bold())
                    .foregroundColor(.secondary)
            }

            Menu {
                // Single keypoints
                Section("Body Keypoints") {
                    ForEach(singleKeypoints) { mode in
                        Button {
                            selectedMode = mode
                        } label: {
                            HStack {
                                Text(mode.rawValue)
                                if selectedMode == mode {
                                    Spacer()
                                    Image(systemName: "checkmark")
                                }
                            }
                        }
                    }
                }

                // Midpoint options
                Section("Midpoints (L+R average)") {
                    ForEach(midpointKeypoints) { mode in
                        Button {
                            selectedMode = mode
                        } label: {
                            HStack {
                                Text(mode.rawValue)
                                if selectedMode == mode {
                                    Spacer()
                                    Image(systemName: "checkmark")
                                }
                            }
                        }
                    }
                }
            } label: {
                HStack(spacing: 6) {
                    // Color dot matching the keypoint (reuse jointColors if available)
                    Circle()
                        .fill(keypointColor(for: selectedMode))
                        .frame(width: 8, height: 8)
                    Text(selectedMode.rawValue)
                        .font(.caption)
                        .foregroundColor(.primary)
                    Spacer()
                    Image(systemName: "chevron.up.chevron.down")
                        .font(.system(size: 10))
                        .foregroundColor(.secondary)
                }
                .padding(.horizontal, 10)
                .padding(.vertical, 6)
                .background(
                    RoundedRectangle(cornerRadius: 8)
                        .fill(Color(.systemGray6))
                        .overlay(
                            RoundedRectangle(cornerRadius: 8)
                                .stroke(Color.gray.opacity(0.3), lineWidth: 1)
                        )
                )
            }
        }
    }

    /// Maps each mode to a representative color (falls back to cyan)
    private func keypointColor(for mode: FlightKeypointMode) -> Color {
        switch mode {
        case .nose, .leftEye, .rightEye, .leftEar, .rightEar,
             .midEyes, .midEars:
            return .yellow
        case .leftShoulder, .rightShoulder, .midShoulders:
            return .orange
        case .leftElbow, .rightElbow, .midElbows:
            return .red
        case .leftWrist, .rightWrist, .midWrists:
            return .pink
        case .leftHip, .rightHip, .midHips:
            return .green
        case .leftKnee, .rightKnee, .midKnees:
            return .mint
        case .leftAnkle, .rightAnkle, .midAnkles:
            return .cyan
        }
    }
}

// ── The rest of FlightHeightView.swift is unchanged ──

// MARK: - Stats Row
struct FlightHeightStatsRow: View {
    let flightData: [FlightHeightData]
    let currentFrameIndex: Int
    let calibrationModel: CalibrationModel
    let imagePixelHeight: Double

    private var maxEntry: FlightHeightData? {
        FlightHeightCalculator.maxFlightHeight(flightData)
    }

    private var currentEntry: FlightHeightData? {
        flightData.first(where: { $0.frameIndex == currentFrameIndex })
    }

    var body: some View {
        HStack(spacing: 12) {
            FlightStatCard(
                label: "Max Height",
                value: maxEntry?.cmAboveBar,
                unit: "cm",
                color: .cyan,
                icon: "arrow.up.to.line"
            )
            FlightStatCard(
                label: "Current",
                value: currentEntry?.cmAboveBar,
                unit: "cm",
                color: (currentEntry?.cmAboveBar ?? 0) > 0 ? .green : .orange,
                icon: "figure.gymnastics"
            )
            FlightStatCard(
                label: "px / cm",
                value: calibrationModel.pixelsPerCm(imagePixelHeight: imagePixelHeight),
                unit: "px",
                color: .yellow,
                icon: "ruler"
            )
        }
    }
}

// MARK: - Chart
struct FlightHeightChartView: View {
    let flightData: [FlightHeightData]
    let currentFrameIndex: Int

    private var maxEntry: FlightHeightData? {
        FlightHeightCalculator.maxFlightHeight(flightData)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("Flight Height Over Time")
                .font(.caption.bold())
                .foregroundColor(.secondary)
                .padding(.horizontal)

            Chart {
                RuleMark(y: .value("Bar Top", 0.0))
                    .lineStyle(StrokeStyle(lineWidth: 1.5, dash: [4, 3]))
                    .foregroundStyle(Color.yellow.opacity(0.8))
                    .annotation(position: .trailing) {
                        Text("Bar")
                            .font(.system(size: 9))
                            .foregroundColor(.yellow)
                    }

                if let maxH = maxEntry?.cmAboveBar {
                    RuleMark(y: .value("Max", maxH))
                        .lineStyle(StrokeStyle(lineWidth: 1, dash: [3, 3]))
                        .foregroundStyle(Color.cyan.opacity(0.5))
                }

                RuleMark(x: .value("Frame", currentFrameIndex))
                    .lineStyle(StrokeStyle(lineWidth: 1.5, dash: [4, 2]))
                    .foregroundStyle(Color.orange.opacity(0.7))

                ForEach(flightData, id: \.frameIndex) { entry in
                    LineMark(
                        x: .value("Frame", entry.frameIndex),
                        y: .value("Height (cm)", entry.cmAboveBar ?? 0)
                    )
                    .foregroundStyle(Color.cyan)
                    .lineStyle(StrokeStyle(lineWidth: 1.5))
                }

                ForEach(flightData.filter { ($0.cmAboveBar ?? 0) > 0 },
                        id: \.frameIndex) { entry in
                    AreaMark(
                        x: .value("Frame", entry.frameIndex),
                        yStart: .value("Zero", 0.0),
                        yEnd: .value("Height", entry.cmAboveBar ?? 0)
                    )
                    .foregroundStyle(Color.green.opacity(0.15))
                }
            }
            .frame(height: 200)
            .padding(.horizontal, 8)
            .chartYAxis {
                AxisMarks(position: .leading) { value in
                    AxisGridLine()
                    AxisValueLabel {
                        if let d = value.as(Double.self) {
                            Text(String(format: "%.0fcm", d))
                                .font(.system(size: 9))
                        }
                    }
                }
            }
            .chartXAxis {
                AxisMarks(values: .stride(by: 100)) { value in
                    AxisGridLine()
                    AxisValueLabel {
                        if let i = value.as(Int.self) {
                            Text("\(i)")
                                .font(.system(size: 9))
                        }
                    }
                }
            }
        }
    }
}

// MARK: - Peaks Table
struct FlightPeaksTableView: View {
    let flightData: [FlightHeightData]
    let onSeek: (Int) -> Void

    private var peaks: [FlightHeightData] {
        findPeaks(in: flightData, minHeight: 5.0)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("Peak Moments")
                .font(.caption.bold())
                .foregroundColor(.secondary)

            if peaks.isEmpty {
                Text("No significant peaks detected above bar level")
                    .font(.caption)
                    .foregroundColor(.secondary)
            } else {
                ForEach(Array(peaks.prefix(5).enumerated()), id: \.offset) { idx, peak in
                    HStack {
                        Text("Peak \(idx + 1)")
                            .font(.caption)
                            .foregroundColor(.secondary)
                            .frame(width: 50, alignment: .leading)

                        Text("Frame \(peak.frameIndex)")
                            .font(.caption.monospaced())

                        Spacer()

                        if let h = peak.cmAboveBar {
                            Text(String(format: "+%.1f cm", h))
                                .font(.caption.bold())
                                .foregroundColor(.cyan)
                        }

                        Button(action: { onSeek(peak.frameIndex) }) {
                            Image(systemName: "arrow.right.circle")
                                .font(.system(size: 14))
                                .foregroundColor(.blue)
                        }
                    }
                    .padding(.vertical, 3)

                    if idx < min(peaks.count, 5) - 1 {
                        Divider()
                    }
                }
            }
        }
        .padding(8)
        .background(Color(.systemGray6))
        .cornerRadius(10)
    }

    private func findPeaks(in data: [FlightHeightData], minHeight: Double) -> [FlightHeightData] {
        guard data.count > 4 else { return [] }
        let window = 15
        var peaks: [FlightHeightData] = []

        for i in window..<(data.count - window) {
            guard let h = data[i].cmAboveBar, h > minHeight else { continue }
            let slice = data[(i - window)...(i + window)]
            let localMax = slice.compactMap { $0.cmAboveBar }.max() ?? 0
            guard abs(h - localMax) < 0.001 else { continue }
            if let lastPeak = peaks.last,
               abs(lastPeak.frameIndex - data[i].frameIndex) < window * 2 { continue }
            peaks.append(data[i])
        }

        return peaks.sorted { ($0.cmAboveBar ?? 0) > ($1.cmAboveBar ?? 0) }
    }
}

// MARK: - Stat Card
struct FlightStatCard: View {
    let label: String
    let value: Double?
    let unit: String
    let color: Color
    let icon: String

    var body: some View {
        VStack(spacing: 4) {
            HStack(spacing: 4) {
                Image(systemName: icon)
                    .font(.system(size: 10))
                    .foregroundColor(color)
                Text(label)
                    .font(.system(size: 10))
                    .foregroundColor(.secondary)
            }
            if let v = value {
                Text(String(format: "%.2f", v))
                    .font(.system(size: 16, weight: .bold).monospacedDigit())
                    .foregroundColor(color)
                Text(unit)
                    .font(.system(size: 9))
                    .foregroundColor(.secondary)
            } else {
                Text("--")
                    .font(.system(size: 16, weight: .bold))
                    .foregroundColor(.secondary)
            }
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 8)
        .background(Color(.systemGray6))
        .cornerRadius(8)
    }
}

struct CalibrationSourceBadge: View {
    let calibrationModel: CalibrationModel
    let quadCalibrationModel: QuadCalibrationModel

    private var barTopStatus: String {
        calibrationModel.barTopPoint != nil ? "✓" : "✗"
    }

    var body: some View {
        HStack(spacing: 8) {
            // Scale source pill — quad takes priority if calibrated
            if quadCalibrationModel.isCalibrated {
                label(
                    String(format: "Quad  %.0f×%.0f cm",
                           quadCalibrationModel.realWidthCm,
                           quadCalibrationModel.realHeightCm),
                    icon: "square.grid.2x2",
                    color: .purple
                )
            } else if calibrationModel.isCalibrated {
                label(
                    String(format: "2-pt  %.0f cm", calibrationModel.realBarHeightCm),
                    icon: "ruler",
                    color: .orange
                )
            } else {
                label("No Scale", icon: "exclamationmark.circle", color: .red)
            }

            Spacer()

            // Bar top reference pill
            HStack(spacing: 4) {
                Image(systemName: calibrationModel.barTopPoint != nil
                      ? "checkmark.circle.fill" : "xmark.circle.fill")
                    .foregroundColor(calibrationModel.barTopPoint != nil ? .green : .red)
                    .font(.system(size: 11))
                Text("Bar top ref \(calibrationModel.barTopPoint != nil ? "✓" : "✗")")
                    .font(.caption2)
                    .foregroundColor(.secondary)
            }
            .padding(.horizontal, 8)
            .padding(.vertical, 4)
            .background(Color(.systemGray5))
            .cornerRadius(6)
        }
    }

    @ViewBuilder
    private func label(_ text: String, icon: String, color: Color) -> some View {
        HStack(spacing: 5) {
            Image(systemName: icon)
                .font(.system(size: 11))
                .foregroundColor(color)
            Text(text)
                .font(.caption2.bold())
                .foregroundColor(color)
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 4)
        .background(color.opacity(0.12))
        .cornerRadius(6)
    }
}

struct WarningBanner: View {
    let icon: String
    let message: String
    let color: Color

    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: icon)
                .foregroundColor(color)
            Text(message)
                .font(.caption)
                .foregroundColor(.secondary)
        }
        .padding()
        .frame(maxWidth: .infinity)
        .background(color.opacity(0.1))
        .cornerRadius(8)
    }
}
