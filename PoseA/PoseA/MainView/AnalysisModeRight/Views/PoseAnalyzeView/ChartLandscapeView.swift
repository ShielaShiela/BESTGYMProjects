//
//  ChartLandscapeView.swift
//  PoseA
//
//  Created by Ardhika Maulidani on 7/17/25.
//

import SwiftUI
import Charts

extension Color {
    init(hex: UInt, alpha: Double = 1.0) {
        let red = Double((hex >> 16) & 0xFF) / 255.0
        let green = Double((hex >> 8) & 0xFF) / 255.0
        let blue = Double(hex & 0xFF) / 255.0

        self.init(.sRGB, red: red, green: green, blue: blue, opacity: alpha)
    }
}

struct ChartLandscapeView: View {
    // Colors
    private let offWhite = Color(hex: 0xEBE8EB)

    // Initialize mock data for the chart
    let chartData: [ChartData2D]
    let pointData: [Point2D]
    let currentFrame: Int?
    
    let xAxisUnit: String
    let yAxisUnit: String
    
    // Chart Scale
    @State private var baseXScale: ClosedRange<Double> = 0...0
    @State private var baseYScale: ClosedRange<Double> = 0...190
    
    init(chartData: [ChartData2D], pointData: [Point2D] = [], currentFrame: Int?, xAxisUnit: String = "", yAxisUnit: String = "") {
        self.chartData = chartData
        self.pointData = pointData
        self.currentFrame = currentFrame
        self.xAxisUnit = xAxisUnit
        self.yAxisUnit = yAxisUnit
    }
    
    var body: some View {
        ZStack(alignment: .topTrailing) {
            // Chart View
            Chart {
                ForEach(pointData) { point in
                    PointMark(
                        x: .value("Bar_X", point.x),
                        y: .value("Bar_Y", point.y)
                    )
                    .foregroundStyle(.green)
                    .symbolSize(100)
                }
                
                ForEach(chartData, id: \.joint) { jointData in
                    ForEach(jointData.dataPoints) { point in
                        LineMark(
                            x: .value("X", point.x),
                            y: .value("Y", point.y),
                            series: .value("Joint", jointData.joint)
                        )
                        .lineStyle(StrokeStyle(lineWidth: 2, lineCap: .round, lineJoin: .round))
                        .foregroundStyle(jointColors[jointData.joint] ?? .gray)
                        .interpolationMethod(.cardinal(tension: 0.4))
                    }
                }

                if let currentFrame = self.currentFrame {
                    RuleMark(x: .value("X", currentFrame))
                        .lineStyle(StrokeStyle(lineWidth: 1, dash: [5]))
                        .foregroundStyle(.orange)
                }
            }
            .chartXScale(domain: baseXScale)
            .chartYScale(domain: baseYScale)
            
            // Add X Axes
            .chartXAxis {
                AxisMarks(preset: .extended, position: .bottom) { value in
                    // Customize X-axis grid line style (dashed line)
                    AxisGridLine(centered: true, stroke: StrokeStyle(lineWidth: 1, dash: [5]))
                        .foregroundStyle(offWhite.opacity(0.2)) // Set grid line color with transparency
                    AxisTick()
                        .foregroundStyle(.gray)
                    AxisValueLabel {
                        if let doubleValue = value.as(Double.self) {
                            Text(String(format: "%.1f", doubleValue) + " \(xAxisUnit)")
                                .foregroundStyle(.gray)
                        }
                    }
                }
            }
            
            // Add Y Axes
            .chartYAxis {
                AxisMarks(preset: .extended, position: .leading) { value in
                    AxisGridLine()
                        .foregroundStyle(.gray.opacity(0.2))
                    AxisTick()
                        .foregroundStyle(.gray)
                    AxisValueLabel {
                        if let doubleValue = value.as(Double.self) {
                            Text(String(format: "%.1f%", doubleValue) + " \(yAxisUnit)")
                                .foregroundStyle(.gray)
                        }
                    }
                }
            }
            
            .onAppear {
                calculateScales()
            }
            .onChange(of: chartData) {
                calculateScales()
            }
            
            // Y Value Display at Top Right
            VStack(alignment: .trailing, spacing: 5) {
                ForEach(getYValuesAtCurrentFrame(), id: \.joint) { item in
                    Text(String(format: "\(item.joint) = %.2f", item.yValue))
                        .font(.caption)
                        .foregroundColor(.gray)
                }
            }
            .padding([.top, .trailing], 8)
            
        }
    }

    private func getYValuesAtCurrentFrame() -> [(joint: String, yValue: Double)] {
        guard let currentFrame = currentFrame else { return [] }
        return chartData.compactMap { jointData in
            let index = currentFrame - 1
            if jointData.dataPoints.indices.contains(index) {
                return (joint: jointData.joint, yValue: jointData.dataPoints[index].y)
            } else {
                return nil
            }
        }
    }
    
    private func calculateScales() {
        // Calculate XY scale based on maximum and minimum XY values
        let maxX = chartData.map { $0.dataMetrics.maxX }.max() ?? 0
        let minX = chartData.map { $0.dataMetrics.minX }.min() ?? 0
        let maxY = chartData.map { $0.dataMetrics.maxY }.max() ?? 0
        let minY = chartData.map { $0.dataMetrics.minY }.min() ?? 0
        
        // Add some padding to X and Y (e.g., 20%)
        let xPadding = (maxX - minX) * 0.2
        let yPadding = (maxY - minY) * 0.2

        baseXScale = Double(minX - xPadding)...Double(maxX + xPadding)
        baseYScale = Double(minY - yPadding)...Double(maxY + yPadding)
    }
}
