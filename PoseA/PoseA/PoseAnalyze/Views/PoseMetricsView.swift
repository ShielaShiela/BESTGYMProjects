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
    @ObservedObject var chartBuilderViewModel: ChartBuilderViewModel
    
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            if !(analysisType == .jointAngles && chartBuilderViewModel.angleData.isEmpty) {
                Text("Metrics")
                    .font(.headline)
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
                        
                        case .trajectories:
                            VStack {
                                Text("X -> Min: \(String(format: "%.1f", dataMetrics.minX))px Max: \(String(format: "%.1f", dataMetrics.maxX))px")
                                    .font(.system(.body, design: .monospaced))
                                    .lineLimit(1)
                                    .minimumScaleFactor(0.5)
                                
                                Text("Y -> Min: \(String(format: "%.1f", dataMetrics.minY))px Max: \(String(format: "%.1f", dataMetrics.maxY))px")
                                    .font(.system(.body, design: .monospaced))
                                    .lineLimit(1)
                                    .minimumScaleFactor(0.5)
                            }
                            
                        case .velocities:
                            VStack {
                                Text("X -> Min: \(String(format: "%.1f", dataMetrics.minX))px/s Max: \(String(format: "%.1f", dataMetrics.maxX))px/s")
                                    .font(.system(.body, design: .monospaced))
                                    .lineLimit(1)
                                    .minimumScaleFactor(0.5)
                                
                                Text("Y -> Min: \(String(format: "%.1f", dataMetrics.minY))px/s Max: \(String(format: "%.1f", dataMetrics.maxY))px/s")
                                    .font(.system(.body, design: .monospaced))
                                    .lineLimit(1)
                                    .minimumScaleFactor(0.5)
                            }
                        case .accelerations:
                            VStack {
                                Text("X -> Min: \(String(format: "%.1f", dataMetrics.minX))px/s^2 Max: \(String(format: "%.1f", dataMetrics.maxX))px/s^2")
                                    .font(.system(.body, design: .monospaced))
                                    .lineLimit(1)
                                    .minimumScaleFactor(0.3)
                                
                                Text("Y -> Min: \(String(format: "%.1f", dataMetrics.minY))px/s^2 Max: \(String(format: "%.1f", dataMetrics.maxY))px/s^2")
                                    .font(.system(.body, design: .monospaced))
                                    .lineLimit(1)
                                    .minimumScaleFactor(0.3)
                            }
                        case .comparison:
                            Text("Diff: \(String(format: "%.1f", Double.random(in: 0...15)))%")
                                .font(.system(.body, design: .monospaced))
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
        case .trajectories:
            return chartBuilderViewModel.fetchJointMetrics(joint: joint, using: chartBuilderViewModel.positionData)
        case .velocities:
            return chartBuilderViewModel.fetchJointMetrics(joint: joint, using: chartBuilderViewModel.velocityData.x)
        case .accelerations:
            return chartBuilderViewModel.fetchJointMetrics(joint: joint, using: chartBuilderViewModel.accelerationData.x)
        case .comparison:
            return dataMetrics()
        }
    }
}
