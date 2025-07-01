//
//  AnalysisMetricsView.swift
//  PoseA
//
//  Created by Bestlab on 5/27/25.
//  Refactor from Shiela Cabahug's codebase

import SwiftUI

// MARK: - Analysis Metrics View
struct PoseMetricsView: View {
    let analysisType: PoseAnalysisView.AnalysisType
    let selectedJoints: [String]
    @ObservedObject var chartBuilderViewModel: ChartBuilderVM
    @ObservedObject var swingAnalysisViewModel: SwingDataVM
    
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            if !(analysisType == .jointAngles && chartBuilderViewModel.angleData.isEmpty) {
                Text("Metrics")
                    .font(.headline)
            }
            
            if analysisType == .swingMotion {
                VStack {
                    HStack {
                        Text("Turn Attempts: ")
                            .font(.system(.body, design: .monospaced))
                            .lineLimit(1)
                            .minimumScaleFactor(0.5)
                        
                        Spacer()
                        
                        Text("\(String(format: "%.1f", swingAnalysisViewModel.swingTurns))")
                            .font(.system(.body, design: .monospaced))
                            .lineLimit(1)
                            .minimumScaleFactor(0.5)
                    }
                    .padding(.vertical, 4)
                    .padding(.horizontal, 8)
                    .background(Color(.systemGray6))
                    .cornerRadius(8)
                    
                    HStack {
                        Text("Max Perfect Turns: ")
                            .font(.system(.body, design: .monospaced))
                            .lineLimit(1)
                            .minimumScaleFactor(0.5)
                        
                        Spacer()
                        
                        Text("\(Int(floor(swingAnalysisViewModel.swingTurns)))")
                            .font(.system(.body, design: .monospaced))
                            .lineLimit(1)
                            .minimumScaleFactor(0.5)
                    }
                    .padding(.vertical, 4)
                    .padding(.horizontal, 8)
                    .background(Color(.systemGray6))
                    .cornerRadius(8)
                }
            }
            
            ForEach(selectedJoints, id: \.self) { joint in
                if (analysisType == .jointAngles && (joint == "L Ankle" || joint == "R Ankle" || joint == "L Wrist" || joint == "R Wrist")) {
                    EmptyView()
                } else {
                    let dataMetrics = getMetricsForJoint(joint)
                    
                    HStack {
                        Text(joint)
                            .font(.subheadline)
                            .frame(width: 100, alignment: .leading)
                        
                        Spacer()
                        
                        switch analysisType {
                        case .jointAngles:
                            Text("Min: \(String(format: "%.1f", dataMetrics.minY))°  Max: \(String(format: "%.1f", dataMetrics.maxY))°")
                                .font(.system(.body, design: .monospaced))
                                .lineLimit(1)
                                .minimumScaleFactor(0.5)
                        
                        case .trajectories2D:
                            VStack {
                                Text("X -> Min: \(String(format: "%.1f", dataMetrics.minX))cm Max: \(String(format: "%.1f", dataMetrics.maxX))cm")
                                    .font(.system(.body, design: .monospaced))
                                    .lineLimit(1)
                                    .minimumScaleFactor(0.5)
                                
                                Text("Y -> Min: \(String(format: "%.1f", dataMetrics.minY))cm Max: \(String(format: "%.1f", dataMetrics.maxY))cm")
                                    .font(.system(.body, design: .monospaced))
                                    .lineLimit(1)
                                    .minimumScaleFactor(0.5)
                            }

                        case .swingMotion:
                            EmptyView()
                            
                        case .velocities:
                            VStack {
                                Text("X -> Min: \(String(format: "%.1f", dataMetrics.minX))m/s Max: \(String(format: "%.1f", dataMetrics.maxX))m/s")
                                    .font(.system(.body, design: .monospaced))
                                    .lineLimit(1)
                                    .minimumScaleFactor(0.5)
                                
                                Text("Y -> Min: \(String(format: "%.1f", dataMetrics.minY))m/s Max: \(String(format: "%.1f", dataMetrics.maxY))m/s")
                                    .font(.system(.body, design: .monospaced))
                                    .lineLimit(1)
                                    .minimumScaleFactor(0.5)
                            }
                        case .accelerations:
                            VStack {
                                Text("X -> Min: \(String(format: "%.1f", dataMetrics.minX))m/s^2 Max: \(String(format: "%.1f", dataMetrics.maxX))m/s^2")
                                    .font(.system(.body, design: .monospaced))
                                    .lineLimit(1)
                                    .minimumScaleFactor(0.3)
                                
                                Text("Y -> Min: \(String(format: "%.1f", dataMetrics.minY))m/s^2 Max: \(String(format: "%.1f", dataMetrics.maxY))m/s^2")
                                    .font(.system(.body, design: .monospaced))
                                    .lineLimit(1)
                                    .minimumScaleFactor(0.3)
                            }
                        }
                    }
                    .padding(.vertical, 4)
                    .padding(.horizontal, 8)
                    .background(Color(.systemGray6))
                    .cornerRadius(8)
                }
            }
        }
    }
    
    private func getMetricsForJoint(_ joint: String) -> dataMetrics {
        switch analysisType {
        case .jointAngles:
            return chartBuilderViewModel.fetchJointMetrics(joint: joint, using: chartBuilderViewModel.angleData)
        case .trajectories2D:
            return chartBuilderViewModel.fetchJointMetrics(joint: joint, using: chartBuilderViewModel.positionData)
        case .swingMotion:
            return chartBuilderViewModel.fetchJointMetrics(joint: joint, using: chartBuilderViewModel.positionData)
        case .velocities:
            return chartBuilderViewModel.fetchJointMetrics(joint: joint, using: chartBuilderViewModel.velocityData.x)
        case .accelerations:
            return chartBuilderViewModel.fetchJointMetrics(joint: joint, using: chartBuilderViewModel.accelerationData.x)
        }
    }
}
