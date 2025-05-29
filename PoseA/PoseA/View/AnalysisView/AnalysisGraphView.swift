//
//  AnalysisGraphView.swift
//  PoseA
//
//  Created by Ardhika Maulidani on 5/27/25.
//  Refactor from Shiela Cabahug's codebase

import SwiftUI

struct AnalysisGraphView: View {
    // Define Variable
    let analysisType: PoseAnalysisView.AnalysisType
    let selectedJoints: [String]
    let timeRange: ClosedRange<Double>
    let poseProcessor: VitPoseProcessor
    let currentFrameIndex: Int
    
    // Body View
    var body: some View {
        VStack {
            if selectedJoints.isEmpty {
                Text("Select Joints to Analyze")
                    .foregroundColor(.secondary)
                    .frame(maxWidth: .infinity, maxHeight: 300)
            } else {
                // Different visualizations based on analysis type
                switch analysisType {
                case .jointAngles:
                    JointAngleGraphView(
                        selectedJoints: selectedJoints,
                        timeRange: timeRange,
                        poseProcessor: poseProcessor,
                        currentFrameIndex: currentFrameIndex
                    )
                    
                case .trajectories:
                    TrajectoryGraphView(
                        selectedJoints: selectedJoints,
                        timeRange: timeRange,
                        poseProcessor: poseProcessor
                    )
                    
                case .velocities:
                    VelocityGraphView(
                        selectedJoints: selectedJoints,
                        timeRange: timeRange,
                        poseProcessor: poseProcessor
                    )
                    
                case .accelerations:
                    AccelerationGraphView(
                        selectedJoints: selectedJoints,
                        timeRange: timeRange,
                        poseProcessor: poseProcessor
                    )
                    
                case .comparison:
                    ComparisonGraphView(
                        selectedJoints: selectedJoints,
                        timeRange: timeRange,
                        poseProcessor: poseProcessor
                    )
                }
            }
        }
        .frame(height: 300)
    }
}

