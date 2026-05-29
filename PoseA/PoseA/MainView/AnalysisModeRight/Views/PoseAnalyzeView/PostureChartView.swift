//
//  ChartView.swift
//  PoseA
//
//  Created by Ardhika Maulidani on 7/15/25.
//

import SwiftUI
import Charts

// MARK: - Clamping Helper
private extension Comparable {
    func clamped(to range: ClosedRange<Self>) -> Self {
        min(max(self, range.lowerBound), range.upperBound)
    }
}

// MARK: - ChartView

struct PostureChartView: View {
    // MARK: Constants
    private let offWhite         = Color(hex: 0xEBE8EB)
    private let minZoom: Double  = 0.5   // can see at most 2× full range
    private let maxZoom: Double  = 20.0  // can zoom in up to 20×
    private let axisStripHeight: CGFloat = 36

    // MARK: Inputs
    let chartData:   [ChartData2D]
    let currentX:    Double?
    let deviationData:  [DeviationModel]
    let xAxisUnit:   String
    let yAxisUnit:   String

    // MARK: Scale State
    @State private var baseXScale: ClosedRange<Double> = 0...1
    @State private var baseYScale: ClosedRange<Double> = 0...1

    // MARK: Zoom & Pan State
    @State private var xZoomScale: Double = 1.0
    @State private var zoomAtGestureStart: Double = 1.0
    @State private var xScrollPosition: Double = 0.0
    @State private var lastPanDragX: CGFloat = .zero
    @State private var lastAxisDragX: CGFloat = .zero

    // MARK: Derived

    private var xVisibleDomainLength: Double {
        let full = baseXScale.upperBound - baseXScale.lowerBound
        return max(full / xZoomScale, 1e-6)
    }

    private var visibleXScale: ClosedRange<Double> {
        let length   = xVisibleDomainLength
        let maxStart = baseXScale.upperBound - length
        let start    = xScrollPosition.clamped(
            to: baseXScale.lowerBound...max(baseXScale.lowerBound, maxStart)
        )
        return start...(start + length)
    }

    private var xAxisStride: Double {
        let length      = visibleXScale.upperBound - visibleXScale.lowerBound
        guard length > 0 else { return 1.0 }

        let rawStep     = length / 6.0                          // target ~6 ticks
        let magnitude   = pow(10, floor(log10(rawStep)))        // e.g. 0.1, 1, 10
        let normalized  = rawStep / magnitude                   // 1…10

        let niceStep: Double
        switch normalized {
        case ..<1.5:  niceStep = 1
        case ..<3.5:  niceStep = 2
        case ..<7.5:  niceStep = 5
        default:      niceStep = 10
        }
        return niceStep * magnitude
    }

    private func xAxisDecimalPlaces(for stride: Double) -> Int {
        guard stride > 0 else { return 2 }
        let places = Int(ceil(-log10(stride)))
        return max(0, places)
    }

    // MARK: - Init
    init(
        chartData:   [ChartData2D],
        currentX:    Double?,
        deviationData: [DeviationModel] = [],
        xAxisUnit:   String       = "",
        yAxisUnit:   String       = ""
    ) {
        self.chartData   = chartData
        self.currentX    = currentX
        self.deviationData = deviationData
        self.xAxisUnit   = xAxisUnit
        self.yAxisUnit   = yAxisUnit
    }

    // MARK: Body

    var body: some View {
        ZStack(alignment: .topTrailing) {
            chartContent

            GeometryReader { geo in
                gestureOverlay(size: geo.size)
            }

            yValuesOverlay
        }
        .onAppear    { calculateScales() }
        .onChange(of: chartData) { calculateScales() }
    }

    // MARK: – Chart

    private var chartContent: some View {
        Chart {
            eventMarks
            lineMarks
            currentXMark
            bandMarks
        }
        .chartXScale(domain: visibleXScale)
        .chartYScale(domain: baseYScale)
        .chartXAxis { xAxisMarks }
        .chartYAxis { yAxisMarks }
    }

    // MARK: – Gesture Overlay
    private func gestureOverlay(size: CGSize) -> some View {
        let panHeight  = max(0, size.height - axisStripHeight)
        let chartWidth = size.width

        return VStack(spacing: 0) {

            // Zone 1 — Pan (the main chart plot area)
            Color.clear
                .frame(height: panHeight)
                .contentShape(Rectangle())
                .gesture(panGesture(chartWidth: chartWidth))

            // Zone 2 — Axis zoom (the X-axis label strip at the bottom)
            Color.clear
                .frame(height: axisStripHeight)
                .contentShape(Rectangle())
                .gesture(axisZoomGesture)
                .onTapGesture(count: 2) {
                    withAnimation(.spring(duration: 0.35)) {
                        resetZoom()
                    }
                }
        }
    }

    // MARK: – Gestures
    // One-finger drag in the main plot area → pans the visible X window.
    private func panGesture(chartWidth: CGFloat) -> some Gesture {
        DragGesture(minimumDistance: 6)
            .onChanged { value in
                let pixelDelta  = value.translation.width - lastPanDragX
                lastPanDragX    = value.translation.width
                let dataDelta   = Double(pixelDelta) / Double(chartWidth) * xVisibleDomainLength
                xScrollPosition -= dataDelta
                clampScrollPosition()
            }
            .onEnded { _ in lastPanDragX = .zero }
    }

    // One-finger drag on the X-axis strip → zooms the X axis.
    private var axisZoomGesture: some Gesture {
        DragGesture(minimumDistance: 4)
            .onChanged { value in
                // 200 px of horizontal travel ≈ 1× zoom-scale change
                let delta      = Double(value.translation.width - lastAxisDragX) / 200.0
                lastAxisDragX  = value.translation.width

                xZoomScale     = (xZoomScale * (1.0 - delta)).clamped(to: minZoom...maxZoom)
                zoomAtGestureStart = xZoomScale
                clampScrollPosition()
            }
            .onEnded { _ in lastAxisDragX = .zero }
    }

    // Keeps xScrollPosition inside valid bounds after any zoom or pan change.
    private func clampScrollPosition() {
        let maxStart    = baseXScale.upperBound - xVisibleDomainLength
        xScrollPosition = xScrollPosition.clamped(
            to: baseXScale.lowerBound...max(baseXScale.lowerBound, maxStart)
        )
    }

    // MARK: – Event Marks

    @ChartContentBuilder
    private var eventMarks: some ChartContent {
        if !self.deviationData.isEmpty {
            ForEach(deviationData.indices, id: \.self) { index in
                let event = deviationData[index]
                deviationPhase(event)
            }
        }
    }

    @ChartContentBuilder
    private func deviationPhase(_ e: DeviationModel) -> some ChartContent {
        let start = e.tStart
        let end = e.tEnd
        
        RectangleMark(
            xStart: .value("Start", start), xEnd: .value("End",   end),
            yStart: .value("Y Min", baseYScale.lowerBound),
            yEnd:   .value("Y Max", baseYScale.upperBound)
        )
        .foregroundStyle(e.severity == .notable ? Color.orange.opacity(0.1) : Color.red.opacity(0.1))
        .zIndex(-1)
    }

    // MARK: – Data Marks
    @ChartContentBuilder
    private var lineMarks: some ChartContent {
        ForEach(chartData, id: \.joint) { joint in
            ForEach(joint.dataPoints) { point in
                LineMark(
                    x: .value("X", point.x),
                    y: .value("Y", point.y),
                    series: .value("Joint", joint.joint)
                )
                .lineStyle(StrokeStyle(lineWidth: 2, lineCap: .round, lineJoin: .round))
                .foregroundStyle(joint.color)
                .interpolationMethod(.cardinal(tension: 0.4))
            }
        }
    }

    @ChartContentBuilder
    private var currentXMark: some ChartContent {
        if let x = currentX {
            RuleMark(x: .value("Cursor", x))
                .lineStyle(StrokeStyle(lineWidth: 1, dash: [5]))
                .foregroundStyle(.orange)
        }
    }

    // MARK: – Axis Marks
    private var xAxisMarks: some AxisContent {
        let stride  = xAxisStride
        let decimals = xAxisDecimalPlaces(for: stride)

        return AxisMarks(
            preset: .extended,
            position: .bottom,
            values: .stride(by: stride)
        ) { value in
            AxisGridLine(centered: true, stroke: StrokeStyle(lineWidth: 1, dash: [5]))
                .foregroundStyle(offWhite.opacity(0.2))
            AxisTick()
                .foregroundStyle(.gray)
            AxisValueLabel {
                if let v = value.as(Double.self) {
                    let formatted = String(format: "%.\(decimals)f", v)
                    Text("\(formatted) \(xAxisUnit)")
                        .foregroundStyle(.gray)
                }
            }
        }
    }

    private var yAxisMarks: some AxisContent {
        AxisMarks(preset: .extended, position: .leading) { value in
            AxisGridLine()
                .foregroundStyle(.gray.opacity(0.2))
            AxisTick()
                .foregroundStyle(.gray)
            AxisValueLabel {
                if let v = value.as(Double.self) {
                    Text("\(v, specifier: "%.1f") \(yAxisUnit)")
                        .foregroundStyle(.gray)
                }
            }
        }
    }

    // MARK: – Y Values Overlay
    private var yValuesOverlay: some View {
        VStack(alignment: .trailing, spacing: 4) {
            ForEach(yValuesAtCurrentFrame, id: \.joint) { item in
                Text(String(format: "%@ = %.2f", item.joint, item.yValue))
                    .font(.caption)
                    .foregroundStyle(.gray.opacity(0.75))
            }
        }
        .padding([.top, .trailing], 8)
    }

    // Resets zoom and scroll to the initial full-data view.
    private func resetZoom() {
        xZoomScale         = 1.0
        zoomAtGestureStart = 1.0
        xScrollPosition    = baseXScale.lowerBound
    }

    // MARK: – Helpers

    private var yValuesAtCurrentFrame: [(joint: String, yValue: Double, color: Color)] {
        guard let currentX else { return [] }
        return chartData.compactMap { joint in
            joint.dataPoints
                .min(by: { abs($0.x - currentX) < abs($1.x - currentX) })
                .map { (joint: joint.joint, yValue: $0.y, color: joint.color) }
        }
    }

    private func calculateScales() {
        let validSeries = chartData.filter { series in
            guard series.dataPoints.count >= 2 else { return false }
            let xs = series.dataPoints.map(\.x)
            return (xs.max() ?? 0) > (xs.min() ?? 0)   // reject flat/zero-width series
        }
        guard !validSeries.isEmpty else { return }
        let metrics = validSeries.map(\.dataMetrics)
        let minX    = metrics.map(\.minX).min()!
        let maxX    = metrics.map(\.maxX).max()!
        let minY    = metrics.map(\.minY).min()!
        let maxY    = metrics.map(\.maxY).max()!

        let xPad = (maxX - minX) * 0.05
        let yPad = (maxY - minY) * 0.05

        baseXScale = (minX - xPad)...(maxX + xPad)
        baseYScale = (minY - yPad)...(maxY + yPad)

        // Reset to full view on data change
        xZoomScale         = 1.0
        zoomAtGestureStart = 1.0
        xScrollPosition    = minX - xPad
    }
    
    // MARK: – Band Marks (±1σ reference fill)
    // Fills the region between refLower and refUpper for every joint.
    @ChartContentBuilder
    private var bandMarks: some ChartContent {
        jointBand("Shoulder")
        jointBand("Hip")
        jointBand("Knee")
    }
 
    @ChartContentBuilder
    private func jointBand(_ joint: String) -> some ChartContent {
        if let lower = chartData.first(where: { $0.joint == "\(joint)_refLower" }),
           let upper = chartData.first(where: { $0.joint == "\(joint)_refUpper" }) {
            let count = min(lower.dataPoints.count, upper.dataPoints.count)
            ForEach(0..<count, id: \.self) { i in
                AreaMark(
                    x:      .value("X",     lower.dataPoints[i].x),
                    yStart: .value("Lower", lower.dataPoints[i].y),
                    yEnd:   .value("Upper", upper.dataPoints[i].y)
                )
                .foregroundStyle(Color(red: 118/255, green: 205/255, blue: 38/255).opacity(0.45))
                .interpolationMethod(.cardinal(tension: 0.4))   // matches lineMarks
            }
        }
    }
}
