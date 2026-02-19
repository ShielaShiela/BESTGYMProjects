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

    // Compute once and store — avoids compiler timeout
    @State private var cachedFlightData: [FlightHeightData] = []

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 12) {

                // Not calibrated warning
                if !calibrationModel.isCalibrated {
                    HStack(spacing: 8) {
                        Image(systemName: "exclamationmark.triangle.fill")
                            .foregroundColor(.orange)
                        Text("Calibrate the bar first using the ruler button in the toolbar")
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                    .padding()
                    .frame(maxWidth: .infinity)
                    .background(Color.orange.opacity(0.1))
                    .cornerRadius(8)
                    .padding(.horizontal)
                }

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
                        onSeek: handleSeek        // change this line
                    )
                    .padding(.horizontal)
                }
            }
            .padding(.vertical)
        }
        .onAppear { rebuildData() }
        .onChange(of: calibrationModel.isCalibrated) { _, _ in rebuildData() }
        .onChange(of: appState.isAnalysisAvailable) { _, _ in rebuildData() }
    }
    
    private func handleSeek(_ frameIndex: Int) {
           mediaManager.seekToFrame(frameIndex)
       }

    private func rebuildData() {
        guard calibrationModel.isCalibrated else {
            cachedFlightData = []
            return
        }
        cachedFlightData = FlightHeightCalculator.calculate(
            mediaManager: mediaManager,
            calibration: calibrationModel
        )
    }
}

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
                // Bar top reference line
                RuleMark(y: .value("Bar Top", 0.0))
                    .lineStyle(StrokeStyle(lineWidth: 1.5, dash: [4, 3]))
                    .foregroundStyle(Color.yellow.opacity(0.8))
                    .annotation(position: .trailing) {
                        Text("Bar")
                            .font(.system(size: 9))
                            .foregroundColor(.yellow)
                    }

                // Max height reference
                if let maxH = maxEntry?.cmAboveBar {
                    RuleMark(y: .value("Max", maxH))
                        .lineStyle(StrokeStyle(lineWidth: 1, dash: [3, 3]))
                        .foregroundStyle(Color.cyan.opacity(0.5))
                }

                // Current frame marker
                RuleMark(x: .value("Frame", currentFrameIndex))
                    .lineStyle(StrokeStyle(lineWidth: 1.5, dash: [4, 2]))
                    .foregroundStyle(Color.orange.opacity(0.7))

                // Height line
                ForEach(flightData, id: \.frameIndex) { entry in
                    LineMark(
                        x: .value("Frame", entry.frameIndex),
                        y: .value("Height (cm)", entry.cmAboveBar ?? 0)
                    )
                    .foregroundStyle(Color.cyan)
                    .lineStyle(StrokeStyle(lineWidth: 1.5))
                }

                // Above-bar shading
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
                           Text(String(format: "%.0fcm", d))   // change this
                               .font(.system(size: 9))
                       }                    }
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
                            Text(String(format: "+%.1f cm",h))
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
