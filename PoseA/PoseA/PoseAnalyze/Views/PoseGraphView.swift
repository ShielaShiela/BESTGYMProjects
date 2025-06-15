//
//  AnalysisGraphView.swift
//  PoseA
//
//  Created by Ardhika Maulidani on 5/27/25.
//  Refactor from Shiela Cabahug's codebase

import SwiftUI

struct PoseGraphView: View {
    // Define Variable
    let analysisType: PoseAnalysisView.AnalysisType
    let selectedJoints: [String]
    @ObservedObject var chartBuilderViewModel: ChartBuilderViewModel
    
    // Body View
    var body: some View {
        VStack {
            if selectedJoints.isEmpty {
                Text("Select Joints to Analyze")
                    .foregroundColor(.secondary)
                    .frame(maxWidth: .infinity, maxHeight: 500)
            } else {
                // Different visualizations based on analysis type
                switch analysisType {
                case .jointAngles:
                    // Chart View
                    if chartBuilderViewModel.angleData.isEmpty {
                        Text("Select Joints to Analyze")
                            .foregroundColor(.secondary)
                            .frame(maxWidth: .infinity, maxHeight: 500)
                    } else {
                        ChartsView(
                            chartData: chartBuilderViewModel.angleData,
                            yAxisUnit: "°"
                        )
                        
                        Spacer()
                        
                        // Chart Legend View
                        ChartsLegendView(chartData: chartBuilderViewModel.angleData)
                        
                        Spacer()
                    }
                    
                case .trajectories:
                    // Chart View
                    ChartsView(
                        chartData: chartBuilderViewModel.positionData,
                        yAxisUnit: "px"
                    )
                    
                    Spacer()
                    
                    // Chart Legend View
                    ChartsLegendView(chartData: chartBuilderViewModel.positionData)
                    
                    Spacer()
                    
                case .velocities:
                    // Double Chart View
                    ChartsView(
                        chartData: chartBuilderViewModel.velocityData.x,
                        yAxisUnit: "px/s"
                    )
                    ChartsView(
                        chartData: chartBuilderViewModel.velocityData.y,
                        yAxisUnit: "px/s"
                    )
                    
                    Spacer()
                    
                    // Chart Legend View
                    ChartsLegendView(chartData: chartBuilderViewModel.velocityData.x)
                    
                    Spacer()
                    
                case .accelerations:
                    // Double Chart View
                    ChartsView(
                        chartData: chartBuilderViewModel.accelerationData.x,
                        yAxisUnit: "px/s2"
                    )
                    ChartsView(
                        chartData: chartBuilderViewModel.accelerationData.y,
                        yAxisUnit: "px/s2"
                    )
                    
                    Spacer()
                    
                    // Chart Legend View
                    ChartsLegendView(chartData: chartBuilderViewModel.accelerationData.x)
                    
                    Spacer()
                    
                case .comparison:
                    Text("Comparison with Reference Motion")
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                        .background(Color(.systemGray6))
                        .cornerRadius(8)
                }
            }
        }
        .frame(height: 400)
    }
}

