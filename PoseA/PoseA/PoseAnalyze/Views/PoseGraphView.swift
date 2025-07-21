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
    @ObservedObject var chartBuilderViewModel: ChartBuilderVM
    @ObservedObject var swingAnalysisViewModel: SwingDataVM
    
    // Body View
    var body: some View {
        VStack {
            if selectedJoints.isEmpty && analysisType != .swingMotion {
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
                        Charts2DView(
                            chartData: chartBuilderViewModel.angleData,
                            yAxisUnit: "°"
                        )
                        
                        Spacer()
                        
                        // Chart Legend View
                        ChartsLegendView(chartData: chartBuilderViewModel.angleData)
                        
                        Spacer()
                    }
                    
                case .trajectories2D:
                    // Chart View
                    Charts2DView(
                        chartData: chartBuilderViewModel.positionData,
                        yAxisUnit: "cm"
                    )
                    
                    Spacer()
                    
                    // Chart Legend View
                    ChartsLegendView(chartData: chartBuilderViewModel.positionData)
                    
                    Spacer()

                case .swingMotion:
                    Text("Swing Trajectory")
                        .font(.body)
                    // Chart View
                    ChartsPoseView(
                        chartData: chartBuilderViewModel.positionData,
                        BarPoint: swingAnalysisViewModel.barPosition
                    )
                    
                    Text("Rotation Angle")
                        .font(.body)
                    // Chart View
                    Charts2DView(
                        chartData: swingAnalysisViewModel.swingAngleData,
                        yAxisUnit: "rad"
                    )
                    
                    Text("Angular Velocity")
                        .font(.body)
                    // Chart View
                    Charts2DView(
                        chartData: swingAnalysisViewModel.swingOmegaData,
                        yAxisUnit: "rad/s"
                    )
                    
                case .velocities:
                    // Double Chart View
                    Charts2DView(
                        chartData: chartBuilderViewModel.velocityData.x,
                        yAxisUnit: "m/s"
                    )
                    Charts2DView(
                        chartData: chartBuilderViewModel.velocityData.y,
                        yAxisUnit: "m/s"
                    )
                    
                    Spacer()
                    
                    // Chart Legend View
                    ChartsLegendView(chartData: chartBuilderViewModel.velocityData.x)
                    
                    Spacer()
                    
                case .accelerations:
                    // Double Chart View
                    Charts2DView(
                        chartData: chartBuilderViewModel.accelerationData.x,
                        yAxisUnit: "m/s2"
                    )
                    Charts2DView(
                        chartData: chartBuilderViewModel.accelerationData.y,
                        yAxisUnit: "m/s2"
                    )
                    
                    Spacer()
                    
                    // Chart Legend View
                    ChartsLegendView(chartData: chartBuilderViewModel.accelerationData.x)
                    
                    Spacer()
                }
            }
        }
        .frame(height: 400)
    }
}

