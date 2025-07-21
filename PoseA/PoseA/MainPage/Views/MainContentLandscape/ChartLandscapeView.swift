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
    private let darkBlue = Color(hex: 0x0A77AE)
    private let mediumBlue = Color(hex: 0x318FA8)
    private let offWhite = Color(hex: 0xEBE8EB)

    // Initialize mock data for the chart
    let chartData: [ChartData]
    let currentFrame: Int?
    
    // Chart Scale
    @State private var baseXScale: ClosedRange<Double> = 0...0
    @State private var baseYScale: ClosedRange<Double> = 0...190
    
    var body: some View {
        // Create a chart with the provided data
        Chart {
            ForEach(chartData, id: \.joint) { jointData in
                ForEach(jointData.dataPoints) { point in
                    // Define a LineMark for each data point in the chart
                    LineMark(
                        x: .value("X", point.x),
                        y: .value("Y", point.y),
                        series: .value("Joint", jointData.joint)
                    )
                    .lineStyle(StrokeStyle(lineWidth: 2, lineCap: .round, lineJoin: .round))  // Set line width
                    .foregroundStyle(jointColors[jointData.joint] ?? .gray)

                    .interpolationMethod(.cardinal(tension: 0.4)) // Smooth the line using cardinal interpolation
                }
            }
            
            // Add vertical dashed orange line
            if self.currentFrame != nil {
                RuleMark(x: .value("X", self.currentFrame!))
                    .lineStyle(StrokeStyle(lineWidth: 1, dash: [5]))
                    .foregroundStyle(.orange)
            }
        }
        
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
                        Text(String(format: "%.1f", doubleValue))
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
                        Text(String(format: "%.1f%", doubleValue))
                            .foregroundStyle(.gray)
                    }
                }
            }
        }
        
        // Define Axes Scale -> Use Default Scale For Now
        .chartXScale(domain: baseXScale)
        .chartYScale(domain: baseYScale)
    
        // Change Axes Scale to Data
        .onAppear {
            calculateScales()
        }
        .onChange(of: chartData) {
            calculateScales()
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
