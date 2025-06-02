//
//  TrajectoryGraphView.swift
//  PoseA
//
//  Created by Ardhika Maulidani on 5/27/25.
//  

import SwiftUI
import Charts

struct AccelerationGraphView: View {
    let selectedJoints: [String]
    let timeRange: ClosedRange<Double>
    let poseProcessor: VitPoseProcessor
    
    var body: some View {
        Text("Joint Acceleration Analysis")
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(Color(.systemGray6))
            .cornerRadius(8)
    }
}

struct ComparisonGraphView: View {
    let selectedJoints: [String]
    let timeRange: ClosedRange<Double>
    let poseProcessor: VitPoseProcessor
    
    var body: some View {
        Text("Comparison with Reference Motion")
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(Color(.systemGray6))
            .cornerRadius(8)
    }
}
