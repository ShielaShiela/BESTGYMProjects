//
//  JointAngleGraphView.swift
//  PoseA
//
//  Created by Ardhika Maulidani on 5/27/25.
//

import SwiftUI
import Charts

// TODO: SIMPLIFIED THE STRUCTURE WITHOUT KNTL

// Joint Angle Graph
struct ChartsView: View {
    // Define Variable
    let chartData: [JointData]
    let yAxisUnit: String
    
    @State private var baseXScale: ClosedRange<Double> = 0...0
    @State private var baseYScale: ClosedRange<Double> = 0...190
    
    init(chartData: [JointData], yAxisUnit: String = "") {
        self.chartData = chartData
        self.yAxisUnit = yAxisUnit
    }
    
    var body: some View {
        VStack(spacing: 0) {
            Chart {
                ForEach(chartData, id: \.joint) { jointData in
                    ForEach(jointData.dataPoints) { point in
                        LineMark(
                            x: .value("X", point.x),
                            y: .value("Y", point.y),
                            series: .value("Joint", jointData.joint)
                        )
                        .foregroundStyle(jointColors[jointData.joint] ?? .gray)
                        .interpolationMethod(.catmullRom)
                    }
                }
            }
            .chartPlotStyle { plotArea in
                plotArea
                    .background(Color.black.opacity(0.1))
            }
            // Make Sure it is clipped
            .clipped()
            
            // Add X Axes
            .chartXAxis {
                AxisMarks(preset: .inset, position: .bottom) { value in
                    AxisGridLine()
                        .foregroundStyle(.gray.opacity(0.2))
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
                AxisMarks(preset: .inset, position: .leading) { value in
                    AxisGridLine()
                        .foregroundStyle(.gray.opacity(0.2))
                    AxisTick()
                        .foregroundStyle(.gray)
                    AxisValueLabel {
                        if let doubleValue = value.as(Double.self) {
                            Text(String(format: "%.1f%@", doubleValue, yAxisUnit))
                                .foregroundStyle(.gray)
                        }
                    }
                }
            }
            
            // Define Axes Scale -> Use Default Scale For Now
            .chartXScale(domain: baseXScale)
            .chartYScale(domain: baseYScale)
            
            // Add Gesture Registration for X Axes
            .gesture(DomainXGesture(domain: $baseXScale))
            
            // Change Axes Scale to Data
            .onAppear {
                calculateScales()
            }
            .onChange(of: chartData.count) { oldCount, newCount in
                if newCount != oldCount {
                    calculateYScale()
                }
            }
            
            .frame(maxWidth: .infinity, maxHeight: 400)
        }
    }

    private func calculateYScale() {
        // Calculate XY scale based on maximum and minimum XY values
        let allYValues = chartData.flatMap { $0.dataPoints }.map { $0.y }
        
        let maxY = allYValues.max() ?? 0
        let minY = allYValues.min() ?? 0
        
        // Add some padding to the Y scale (20% on each side)
        let yPadding = (maxY - minY) * 0.2
        baseYScale = Double((minY - yPadding))...Double((maxY + yPadding))
    }
    
    private func calculateScales() {
        // Calculate XY scale based on maximum and minimum XY values
        let allXValues = chartData.flatMap { $0.dataPoints }.map { $0.x }
        let allYValues = chartData.flatMap { $0.dataPoints }.map { $0.y }
        
        let maxX = allXValues.max() ?? 0
        let minX = allXValues.min() ?? 0
        let maxY = allYValues.max() ?? 0
        let minY = allYValues.min() ?? 0
        
        // Add some padding to the Y scale (10% on each side)
        let yPadding = (maxY - minY) * 0.2
        let xPadding = (maxX - minX) * 0.2
        baseXScale = Double((minX - xPadding))...Double((maxX + xPadding))
        baseYScale = Double((minY - yPadding))...Double((maxY + yPadding))
    }
}
