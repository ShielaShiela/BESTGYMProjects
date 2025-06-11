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
    let cameraManager: CameraLiDARManager
    let currentFrameIndex: Int
    
    // Body View
    var body: some View {
        // Data Provider
        let jointDataProvider = JointDataProvider(poseProcessor: poseProcessor)

        VStack {
            if selectedJoints.isEmpty {
                Text("Select Joints to Analyze")
                    .foregroundColor(.secondary)
                    .frame(maxWidth: .infinity, maxHeight: 500)
            } else {
                // Different visualizations based on analysis type
                switch analysisType {
                case .jointAngles:
                    let chartData = selectedJoints
                        .filter { joint in
                            return !(joint == "L Ankle" || joint == "R Ankle" || joint == "L Wrist" || joint == "R Wrist")
                        }
                        .map { joint in
                            JointData(joint: joint, dataPoints: jointDataProvider.getAngleData(for: joint))
                        }
                    
                    ChartsView(
                        chartData: chartData,
                        timeRange: timeRange,
                        currentFrameIndex: currentFrameIndex,
                        yAxisUnit: "°"
                    )
                    Spacer()
                    ChartsLegendView(chartData: chartData)
                    Spacer()
                    
                case .trajectories:
                    let chartData = selectedJoints.map { joint in
                        JointData(joint: joint, dataPoints: jointDataProvider.getPositionData(for: joint))
                    }
                    ChartsView(
                        chartData: chartData,
                        timeRange: timeRange,
                        currentFrameIndex: currentFrameIndex,
                        yAxisUnit: "px"
                    )
                    Spacer()
                    ChartsLegendView(chartData: chartData)
                    Spacer()
                    
                case .velocities:
                    let chartDataX = selectedJoints.map { joint -> JointData in
                        let (xData, _) = jointDataProvider.getVelocitiesData(for: joint)
                        return JointData(joint: joint, dataPoints: xData)
                    }

                    let chartDataY = selectedJoints.map { joint -> JointData in
                        let (_, yData) = jointDataProvider.getVelocitiesData(for: joint)
                        return JointData(joint: joint, dataPoints: yData)
                    }
                    
                    ChartsView(
                        chartData: chartDataX,
                        timeRange: timeRange,
                        currentFrameIndex: currentFrameIndex,
                        yAxisUnit: "px/s"
                    )
                    ChartsView(
                        chartData: chartDataY,
                        timeRange: timeRange,
                        currentFrameIndex: currentFrameIndex,
                        yAxisUnit: "px/s"
                    )
                    Spacer()
                    ChartsLegendView(chartData: chartDataX)
                    Spacer()
                    
                case .accelerations:
                    let chartDataX = selectedJoints.map { joint -> JointData in
                        let (xData, _) = jointDataProvider.getAccelerationData(for: joint)
                        return JointData(joint: joint, dataPoints: xData)
                    }

                    let chartDataY = selectedJoints.map { joint -> JointData in
                        let (_, yData) = jointDataProvider.getAccelerationData(for: joint)
                        return JointData(joint: joint, dataPoints: yData)
                    }
                    
                    ChartsView(
                        chartData: chartDataX,
                        timeRange: timeRange,
                        currentFrameIndex: currentFrameIndex,
                        yAxisUnit: "px/s²"
                    )
                    ChartsView(
                        chartData: chartDataY,
                        timeRange: timeRange,
                        currentFrameIndex: currentFrameIndex,
                        yAxisUnit: "px/s²"
                    )
                    Spacer()
                    ChartsLegendView(chartData: chartDataX)
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

