//
//  ChartBuilderViewModel.swift
//  PoseA
//
//  Created by Ardhika Maulidani on 6/12/25.
//

import Foundation
import SwiftUI

class ChartBuilderViewModel: ObservableObject {
    @Published private(set) var angleData: [JointData] = []
    @Published private(set) var positionData: [JointData] = []
    @Published private(set) var velocityData: (x: [JointData], y: [JointData]) = ([], [])
    @Published private(set) var accelerationData: (x: [JointData], y: [JointData]) = ([], [])
    
    private let poseJointViewModel: PoseJointViewModel
    private let processingQueue = DispatchQueue(label: "com.posea.chartbuilder", qos: .userInitiated)
    
    init(poseJointViewModel: PoseJointViewModel) {
        self.poseJointViewModel = poseJointViewModel
    }
    
    // MARK: - Data Clearing Methods
    func clearAllData() {
        DispatchQueue.main.async {
            self.angleData = []
            self.positionData = []
            self.velocityData = ([], [])
            self.accelerationData = ([], [])
        }
    }
    
    func clearData(for analysisType: PoseAnalysisView.AnalysisType) {
        DispatchQueue.main.async {
            switch analysisType {
            case .jointAngles:
                self.angleData = []
            case .trajectories:
                self.positionData = []
            case .velocities:
                self.velocityData = ([], [])
            case .accelerations:
                self.accelerationData = ([], [])
            case .comparison:
                break
            }
        }
    }
    
    // MARK: - Data Building Methods
    func buildAngleData(joints: [String]) {
        processingQueue.async { [weak self] in
            guard let self = self else { return }
            var result: [JointData] = []
            
            for joint in joints {
                if ["L Ankle", "R Ankle", "L Wrist", "R Wrist"].contains(joint) { continue }
                
                // Fetch fresh data for each joint
                self.poseJointViewModel.fetchAngleData(for: joint)
                
                // Wait for data to be processed
                DispatchQueue.main.async {
                    let data = self.poseJointViewModel.angleData
                    if !data.dataPoints.isEmpty {
                        result.append(JointData(joint: joint, dataPoints: data.dataPoints, dataMetrics: data.dataMetrics))
                    }
                }
            }
            
            // Update UI on main thread
            DispatchQueue.main.async {
                self.angleData = result
            }
        }
    }

    func buildPositionData(joints: [String]) {
        processingQueue.async { [weak self] in
            guard let self = self else { return }
            var result: [JointData] = []
            
            for joint in joints {
                // Fetch fresh data for each joint
                self.poseJointViewModel.fetchPositionData(for: joint)
                
                // Wait for data to be processed
                DispatchQueue.main.async {
                    let data = self.poseJointViewModel.positionData
                    if !data.dataPoints.isEmpty {
                        result.append(JointData(joint: joint, dataPoints: data.dataPoints, dataMetrics: data.dataMetrics))
                    }
                }
            }
            
            // Update UI on main thread
            DispatchQueue.main.async {
                self.positionData = result
            }
        }
    }

    func buildVelocityData(joints: [String]) {
        processingQueue.async { [weak self] in
            guard let self = self else { return }
            var resultX: [JointData] = []
            var resultY: [JointData] = []
            
            for joint in joints {
                // Fetch fresh data for each joint
                self.poseJointViewModel.fetchVelocityData(for: joint)
                
                // Wait for data to be processed
                DispatchQueue.main.async {
                    let dataX = self.poseJointViewModel.velocityDataX
                    let dataY = self.poseJointViewModel.velocityDataY
                    
                    if !dataX.dataPoints.isEmpty {
                        resultX.append(JointData(joint: joint, dataPoints: dataX.dataPoints, dataMetrics: dataX.dataMetrics))
                    }
                    if !dataY.dataPoints.isEmpty {
                        resultY.append(JointData(joint: joint, dataPoints: dataY.dataPoints, dataMetrics: dataY.dataMetrics))
                    }
                }
            }
            
            // Update UI on main thread
            DispatchQueue.main.async {
                self.velocityData = (resultX, resultY)
            }
        }
    }
    
    func buildAccelerationData(joints: [String]) {
        processingQueue.async { [weak self] in
            guard let self = self else { return }
            var resultX: [JointData] = []
            var resultY: [JointData] = []
            
            for joint in joints {
                // Fetch fresh data for each joint
                self.poseJointViewModel.fetchAccelerationData(for: joint)
                
                // Wait for data to be processed
                DispatchQueue.main.async {
                    let dataX = self.poseJointViewModel.accelerationDataX
                    let dataY = self.poseJointViewModel.accelerationDataY
                    
                    if !dataX.dataPoints.isEmpty {
                        resultX.append(JointData(joint: joint, dataPoints: dataX.dataPoints, dataMetrics: dataX.dataMetrics))
                    }
                    if !dataY.dataPoints.isEmpty {
                        resultY.append(JointData(joint: joint, dataPoints: dataY.dataPoints, dataMetrics: dataY.dataMetrics))
                    }
                }
            }
            
            // Update UI on main thread
            DispatchQueue.main.async {
                self.accelerationData = (resultX, resultY)
            }
        }
    }
    
    func fetchJointMetrics(joint: String, using chartData: [JointData]) -> dataMetrics {
        if let bulkData = chartData.first(where: { $0.joint == joint }) {
            return bulkData.dataMetrics
        }
        return dataMetrics()
    }
}

