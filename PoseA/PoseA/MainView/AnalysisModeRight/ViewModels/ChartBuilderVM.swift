//
//  ChartBuilderVM.swift
//  PoseA
//
//  Created by Ardhika Maulidani on 7/15/25.
//

import SwiftUI

@Observable
class ChartBuilderVM {
    // MARK: - Properties
    private let mediaManager: MediaManagerVM

    var featuresData: [Int: FeaturesModel] {
        return mediaManager.FeaturesData
    }

    // Observable Variable
    var chartDataFirst: [ChartData2D] = []
    var chartDataSecond: [ChartData2D] = []
    var pointData: [Point2D] = []
    
    // MARK: - Init
    init(mediaManager: MediaManagerVM) {
        self.mediaManager = mediaManager
    }
    
    // MARK: - Data Fetching
    func BuildChartData(selectedView: RightViewModel, selectedOptions: Set<String>) {
        switch(selectedView) {
        case .angle:
            self.buildAngleChartData(selectedOptions: selectedOptions)
            break
        case .position:
            self.buildPosChartData(selectedOptions: selectedOptions)
            break
        case .velocity:
            self.buildVelChartData(selectedOptions: selectedOptions)
            break
        default:
            break
        }
    }
    
    func BuildDataMetricsData(selectedView: String?) {
        switch(selectedView) {
        case "Position":
            break
        case "Velocity":
            break
        case "Angle":
            break
        default:
            break
        }
    }
    
    // MARK: - Data Clearing Methods
    
    func clearAllData() {
        self.chartDataFirst = []
        self.chartDataSecond = []
        self.pointData = []
    }
    
    // MARK: - Private Functions
    private func buildPosChartData(selectedOptions: Set<String>) {
        let sortedFrames = featuresData.keys.sorted()
        var chartDataByJoint: [String: [Point2D]] = [:]
        
        for frameIndex in sortedFrames {
            guard let feature = featuresData[frameIndex] else { continue }
            
            // Map joint angle data based on selected options
            let posData: [(String, Double)] = [
                ("Head-Bar", feature.headHeightM),
                ("Wrist-Bar", feature.barSpringLenM)
            ]
            
            for (jointName, value) in posData {
                if selectedOptions.contains(jointName) {
                    if chartDataByJoint[jointName] == nil {
                        chartDataByJoint[jointName] = []
                    }
                    chartDataByJoint[jointName]?.append(
                        Point2D(x: Double(frameIndex), y: value)
                    )
                }
            }
        }
        
        // Convert to ChartData2D array
        self.chartDataFirst = chartDataByJoint.map { (jointName, points) in
            ChartData2D(
                joint: jointName,
                dataPoints: points,
                dataMetrics: calculateDataMetrics(from: points)
            )
        }
    }
    private func buildAngleChartData(selectedOptions: Set<String>) {
        // Sort Features
        let sortedFrames = featuresData.keys.sorted()
        var chartDataByJoint: [String: [Point2D]] = [:]
        
        for frameIndex in sortedFrames {
            guard let feature = featuresData[frameIndex] else { continue }
            
            // Map joint angle data based on selected options
            let angleData: [(String, Double)] = [
                ("Shoulder", feature.shoulderAngle),
                ("Hip", feature.hipAngle),
                ("Knee", feature.kneeAngle),
                ("vArm", feature.vArmAngle),
                ("vTorso", feature.vTorsoAngle),
                ("vThigh", feature.vThighAngle),
                ("vLowerLeg", feature.vLowerLegAngle),
                ("CoM", feature.comAngle)
            ]
            
            for (jointName, angleValue) in angleData {
                if selectedOptions.contains(jointName) {
                    if chartDataByJoint[jointName] == nil {
                        chartDataByJoint[jointName] = []
                    }
                    chartDataByJoint[jointName]?.append(
                        Point2D(x: Double(frameIndex), y: angleValue)
                    )
                }
            }
        }
        
        // Convert to ChartData2D array
        self.chartDataFirst = chartDataByJoint.map { (jointName, points) in
            ChartData2D(
                joint: jointName,
                dataPoints: points,
                dataMetrics: calculateDataMetrics(from: points)
            )
        }
    }

    private func buildVelChartData(selectedOptions: Set<String>) {
        // Sort Features
        let sortedFrames = featuresData.keys.sorted()
        var chartDataByJoint: [String: [Point2D]] = [:]
        
        for frameIndex in sortedFrames {
            guard let feature = featuresData[frameIndex] else { continue }
            
            // Map joint velocity data based on selected options
            let velData: [(String, Double?)] = [
                ("Shoulder", feature.shoulderAngleVel),
                ("Hip", feature.hipAngleVel),
                ("Knee", feature.kneeAngleVel),
                ("vArm", feature.vArmAngleVel),
                ("vTorso", feature.vTorsoAngleVel),
                ("vThigh", feature.vThighAngleVel),
                ("vLowerLeg", feature.vLowerLegAngleVel)
            ]
            
            for (jointName, velocityValue) in velData {
                if selectedOptions.contains(jointName), let unwrappedVelocity = velocityValue {
                    if chartDataByJoint[jointName] == nil {
                        chartDataByJoint[jointName] = []
                    }
                    chartDataByJoint[jointName]?.append(
                        Point2D(x: Double(frameIndex), y: unwrappedVelocity)
                    )
                }
            }
        }
        
        // Convert to ChartData2D array
        self.chartDataFirst = chartDataByJoint.map { (jointName, points) in
            ChartData2D(
                joint: jointName,
                dataPoints: points,
                dataMetrics: calculateDataMetrics(from: points)
            )
        }
    }
    
    private func calculateDataMetrics(from dataPoints: [Point2D]) -> dataMetrics {
        guard !dataPoints.isEmpty else {
            return dataMetrics(minX: 0, maxX: 0, minY: 0, maxY: 0)
        }
        
        let xValues = dataPoints.map { $0.x }
        let yValues = dataPoints.map { $0.y }
        
        return dataMetrics(
            minX: xValues.min() ?? 0,
            maxX: xValues.max() ?? 0,
            minY: yValues.min() ?? 0,
            maxY: yValues.max() ?? 0
        )
    }
}
