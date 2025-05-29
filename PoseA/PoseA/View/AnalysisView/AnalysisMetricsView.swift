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
        VStack(alignment: .leading, spacing: 12) {
            Text("Metrics")
                .font(.headline)
            
            ForEach(selectedJoints, id: \.self) { joint in
                HStack {
                    Text(joint)
                        .font(.subheadline)
                        .frame(width: 120, alignment: .leading)
                    
                    Spacer()
                    
                    switch analysisType {
                    case .jointAngles:
                        Text("\(Int.random(in: 30...150))°")
                            .font(.system(.body, design: .monospaced))
                    case .trajectories:
                        Text("X: \(String(format: "%.1f", Double.random(in: -10...10))), Y: \(String(format: "%.1f", Double.random(in: -10...10)))")
                            .font(.system(.body, design: .monospaced))
                    case .velocities:
                        Text("\(String(format: "%.2f", Double.random(in: -2...2))) m/s")
                            .font(.system(.body, design: .monospaced))
                    case .accelerations:
                        Text("\(String(format: "%.2f", Double.random(in: -5...5))) m/s²")
                            .font(.system(.body, design: .monospaced))
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
