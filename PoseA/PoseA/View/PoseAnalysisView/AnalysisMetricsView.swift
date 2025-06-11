//
//  AnalysisMetricsView.swift
//  PoseA
//
//  Created by Bestlab on 5/27/25.
//  Refactor from Shiela Cabahug's codebase

import SwiftUI

// MARK: - Analysis Metrics View
struct AnalysisMetricsView: View {
    let analysisType: PoseAnalysisView.AnalysisType
    let selectedJoints: [String]
    let poseProcessor: VitPoseProcessor
    let currentFrameIndex: Int
    
    var body: some View {
        // Data Provider
        let jointDataProvider = JointDataProvider(poseProcessor: poseProcessor)
        
        VStack(alignment: .leading, spacing: 12) {
            Text("Metrics")
                .font(.headline)
            
            ForEach(selectedJoints, id: \.self) { joint in
                // Get extreme data
                let (minX, maxX, minY, maxY) = jointDataProvider.getExtremeData(for: joint, in: analysisType)
                
                if (analysisType == .jointAngles && (joint == "L Ankle" || joint == "R Ankle" || joint == "L Wrist" || joint == "R Wrist")){
                    EmptyView()
                } else {
                    HStack {
                        Text(joint)
                            .font(.subheadline)
                            .frame(width: 100, alignment: .leading)
                        
                        Spacer()
                        
                        switch analysisType {
                        case .jointAngles:
                            Text("Min: \(String(format: "%.1f", minY))°  Max: \(String(format: "%.1f", maxY))°")
                                .font(.system(.body, design: .monospaced))
                                .lineLimit(1)
                                .minimumScaleFactor(0.5)
                        
                        case .trajectories:
                            VStack{
                                Text("X -> Min: \(String(format: "%.1f", minX))px Max: \(String(format: "%.1f", maxX))px")
                                    .font(.system(.body, design: .monospaced))
                                    .lineLimit(1)
                                    .minimumScaleFactor(0.5)
                                
                                Text("Y -> Min: \(String(format: "%.1f", minY))px Max: \(String(format: "%.1f", maxY))px")
                                    .font(.system(.body, design: .monospaced))
                                    .lineLimit(1)
                                    .minimumScaleFactor(0.5)
                            }
                            
                        case .velocities:
                            VStack{
                                Text("X -> Min: \(String(format: "%.1f", minX))px/s Max: \(String(format: "%.1f", maxX))px/s")
                                    .font(.system(.body, design: .monospaced))
                                    .lineLimit(1)
                                    .minimumScaleFactor(0.5)
                                
                                Text("Y -> Min: \(String(format: "%.1f", minY))px/s Max: \(String(format: "%.1f", maxY))px/s")
                                    .font(.system(.body, design: .monospaced))
                                    .lineLimit(1)
                                    .minimumScaleFactor(0.5)
                            }
                        case .accelerations:
                            VStack{
                                Text("X -> Min: \(String(format: "%.1f", minX))px/s^2 Max: \(String(format: "%.1f", maxX))px/s^2")
                                    .font(.system(.body, design: .monospaced))
                                    .lineLimit(1)
                                    .minimumScaleFactor(0.3)
                                
                                Text("Y -> Min: \(String(format: "%.1f", minY))px/s^2 Max: \(String(format: "%.1f", maxY))px/s^2")
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
}
