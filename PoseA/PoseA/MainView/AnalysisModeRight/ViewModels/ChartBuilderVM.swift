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
        case .posture:
            self.buildPostureChartData(selectedOptions: selectedOptions)
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
                dataMetrics: calculateDataMetrics(from: points),
                color: ChartColors[jointName] ?? .gray
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
                dataMetrics: calculateDataMetrics(from: points),
                color: ChartColors[jointName] ?? .gray
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
                dataMetrics: calculateDataMetrics(from: points),
                color: ChartColors[jointName] ?? .gray
            )
        }
    }
    
    private func buildPostureChartData(selectedOptions: Set<String>) {
        let PostureData = mediaManager.PostureData
        var chartDataFirst: [String: [Point2D]] = [:]
        var chartDataSecond: [String: [Point2D]] = [:]

        for posture in PostureData {
            let phase = posture.phase
            
            if selectedOptions.first == phase.label {
                if chartDataFirst[phase.label] == nil {
                    chartDataFirst[phase.label] = []
                }
                if chartDataSecond[phase.label] == nil {
                    chartDataSecond[phase.label] = []
                }
                for joint in posture.joints {
                    if joint.key == .shoulder {
                        chartDataFirst[joint.key.label+"_pts"] = joint.value.athlete.map { Point2D(x: Double($0.x), y: Double($0.y)) }
                        chartDataFirst[joint.key.label+"_refMean"] = joint.value.refMean.map { Point2D(x: Double($0.x), y: Double($0.y)) }
                        chartDataFirst[joint.key.label+"_refLower"] = joint.value.refLower.map { Point2D(x: Double($0.x), y: Double($0.y)) }
                        chartDataFirst[joint.key.label+"_refUpper"] = joint.value.refUpper.map { Point2D(x: Double($0.x), y: Double($0.y)) }
                    } else if joint.key == .hip {
                        chartDataSecond[joint.key.label+"_pts"] = joint.value.athlete.map { Point2D(x: Double($0.x), y: Double($0.y)) }
                        chartDataSecond[joint.key.label+"_refMean"] = joint.value.refMean.map { Point2D(x: Double($0.x), y: Double($0.y)) }
                        chartDataSecond[joint.key.label+"_refLower"] = joint.value.refLower.map { Point2D(x: Double($0.x), y: Double($0.y)) }
                        chartDataSecond[joint.key.label+"_refUpper"] = joint.value.refUpper.map { Point2D(x: Double($0.x), y: Double($0.y)) }
                    }
                }
            }
        }
        
        // Convert to ChartData2D array
        self.chartDataFirst = chartDataFirst.map { (jointName, points) in
            ChartData2D(
                joint: jointName,
                dataPoints: points,
                dataMetrics: calculateDataMetrics(from: points),
                color: ChartColors[jointName] ?? .gray
            )
        }
        
        self.chartDataSecond = chartDataSecond.map { (jointName, points) in
            ChartData2D(
                joint: jointName,
                dataPoints: points,
                dataMetrics: calculateDataMetrics(from: points),
                color: ChartColors[jointName] ?? .gray
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
    
    // Joint colors for the graph
    let ChartColors: [String: Color] = [
        "Shoulder_pts": .gray,
        "Shoulder_refMean": Color(red: 0.0, green: 1.0, blue: 0.0),
        "Shoulder_refLower": Color(red: 118/255, green: 205/255, blue: 38/255),
        "Shoulder_refUpper": Color(red: 118/255, green: 205/255, blue: 38/255),
        
        "Hip_pts": .gray,
        "Hip_refMean": Color(red: 0.0, green: 1.0, blue: 0.0),
        "Hip_refLower": Color(red: 118/255, green: 205/255, blue: 38/255),
        "Hip_refUpper": Color(red: 118/255, green: 205/255, blue: 38/255),
        
        "Shoulder": Color(red: 1.0, green: 0.0, blue: 1.0),
        "Hip": Color(red: 0.294, green: 0.0, blue: 0.510),
        "Knee": Color(red: 243/255, green: 122/255, blue: 72/255),

        "vArm": .yellow,
        "vTorso": .blue,
        "vThigh": .purple,
        "vLowerLeg": .teal,
        "CoM": .gray,
        
        "Head-Bar": .blue,
        "Wrist-Bar": .red
    ]
}
