//
//  ChartBuilderLandscapeVM.swift
//  PoseA
//
//  Created by Ardhika Maulidani on 7/15/25.
//

import SwiftUI

struct ChartData: Identifiable, Equatable {
    var id: String { joint }
    var joint: String
    var dataPoints: [PointData]
    var dataMetrics: dataMetrics
}

@Observable
class ChartBuilderLandscapeVM {
    // MARK: - Properties
    
    // Observable Variable
    var chartDataFirst: [ChartData] = []
    var chartDataSecond: [ChartData] = []
    
    // Define ViewModel
    private let poseJointViewModel: PoseJointLandscapeVM
    
    // MARK: - Init
    
    init(poseJointViewModel: PoseJointLandscapeVM) {
        self.poseJointViewModel = poseJointViewModel
    }
    
    // MARK: - Data Fetching
    func BuildChartData(selectedView: RightViewModel, selectedOptions: Set<String>) {
        switch(selectedView) {
        case .angle:
            self.fetchJointAngleData(joints: Array(selectedOptions))
            break
        case .trajectoryAxes:
            self.fetchJointPoseData(joints: Array(selectedOptions))
            break
        case .velocity:
            self.fetchJointVelData(joints: Array(selectedOptions))
            break
        case .acceleration:
            self.fetchJointAccData(joints: Array(selectedOptions))
            break
        default:
            break
        }
    }
    
    func fetchJointAngleData(joints: [String]) {
        // Filter Angle based On Selected Joints
        let filteredData = poseJointViewModel.angleCompleteData.filter { joints.contains($0.joint) }
        
        self.chartDataFirst = filteredData.map { jointData in
            let xPoints = jointData.dataPoints.enumerated().map { index, point in
                PointData(x: Double(index) + 1, y: Double(point.x))
            }
            return ChartData(
                joint: jointData.joint,
                dataPoints: xPoints,
                dataMetrics: calculateDataMetrics(from: xPoints)
            )
        }
    }
    
    func fetchJointPoseData(joints: [String]) {
        // Filter Position based On Selected Joints
        let filteredData = poseJointViewModel.positionCompleteData.filter { joints.contains($0.joint) }
        
        // Prepare X vs Index
        self.chartDataFirst = filteredData.map { jointData in
            let xPoints = jointData.dataPoints.enumerated().map { index, point in
                PointData(x: Double(index) + 1, y: Double(point.x))
            }
            return ChartData(
                joint: jointData.joint,
                dataPoints: xPoints,
                dataMetrics: calculateDataMetrics(from: xPoints)
            )
        }

        // Prepare Y vs Index
        self.chartDataSecond = filteredData.map { jointData in
            let yPoints = jointData.dataPoints.enumerated().map { index, point in
                PointData(x: Double(index + 1), y: Double(point.y))
            }
            return ChartData(
                joint: jointData.joint,
                dataPoints: yPoints,
                dataMetrics: calculateDataMetrics(from: yPoints)
            )
        }
    }
    
    func fetchJointVelData(joints: [String]) {
        // Filter Velocity based On Selected Joints
        let filteredData = poseJointViewModel.velocityCompleteData.filter { joints.contains($0.joint) }
        
        // Prepare X vs Index
        self.chartDataFirst = filteredData.map { jointData in
            let xPoints = jointData.dataPoints.enumerated().map { index, point in
                PointData(x: Double(index) + 1, y: Double(point.x))
            }
            return ChartData(
                joint: jointData.joint,
                dataPoints: xPoints,
                dataMetrics: calculateDataMetrics(from: xPoints)
            )
        }

        // Prepare Y vs Index
        self.chartDataSecond = filteredData.map { jointData in
            let yPoints = jointData.dataPoints.enumerated().map { index, point in
                PointData(x: Double(index + 1), y: Double(point.y))
            }
            return ChartData(
                joint: jointData.joint,
                dataPoints: yPoints,
                dataMetrics: calculateDataMetrics(from: yPoints)
            )
        }
    }
    
    func fetchJointAccData(joints: [String]) {
        // Filter Acceleration based On Selected Joints
        let filteredData = poseJointViewModel.accelerationCompleteData.filter { joints.contains($0.joint) }
        
        // Prepare X vs Index
        self.chartDataFirst = filteredData.map { jointData in
            let xPoints = jointData.dataPoints.enumerated().map { index, point in
                PointData(x: Double(index) + 1, y: Double(point.x))
            }
            return ChartData(
                joint: jointData.joint,
                dataPoints: xPoints,
                dataMetrics: calculateDataMetrics(from: xPoints)
            )
        }

        // Prepare Y vs Index
        self.chartDataSecond = filteredData.map { jointData in
            let yPoints = jointData.dataPoints.enumerated().map { index, point in
                PointData(x: Double(index + 1), y: Double(point.y))
            }
            return ChartData(
                joint: jointData.joint,
                dataPoints: yPoints,
                dataMetrics: calculateDataMetrics(from: yPoints)
            )
        }
    }
    
    // MARK: - Data Clearing Methods
    func clearAllData() {
        self.chartDataFirst = []
        self.chartDataSecond = []
    }
    
    private func calculateDataMetrics(from dataPoints: [PointData]) -> dataMetrics {
        let xValues = dataPoints.map { $0.x }
        let yValues = dataPoints.map { $0.y }

        return dataMetrics(
            minX: Float(xValues.min() ?? 0),
            maxX: Float(xValues.max() ?? 0),
            minY: Float(yValues.min() ?? 0),
            maxY: Float(yValues.max() ?? 0)
        )
    }
}

