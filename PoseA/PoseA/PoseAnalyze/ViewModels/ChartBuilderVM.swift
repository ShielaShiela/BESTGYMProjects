//
//  ChartBuilderViewModel.swift
//  PoseA
//
//  Created by Ardhika Maulidani on 6/12/25.
//

import Foundation
import SwiftUI

class ChartBuilderVM: ObservableObject {
    @Published private(set) var angleData: [JointData] = []
    @Published private(set) var positionData: [JointData] = []
    @Published private(set) var velocityData: (x: [JointData], y: [JointData]) = ([], [])
    @Published private(set) var accelerationData: (x: [JointData], y: [JointData]) = ([], [])
    
    private let poseJointViewModel: PoseJointVM
    private let processingQueue = DispatchQueue(label: "com.posea.chartbuilder", qos: .userInitiated)
    
    init(poseJointViewModel: PoseJointVM) {
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
    
    func clearData(for type: PoseAnalysisView.AnalysisType, joints: [String]) {
        DispatchQueue.main.async {
            switch type {
            case .jointAngles:
                self.angleData.removeAll { joints.contains($0.joint) }
            case .trajectories:
                self.positionData.removeAll { joints.contains($0.joint) }
            case .velocities:
                self.velocityData.x.removeAll { joints.contains($0.joint) }
                self.velocityData.y.removeAll { joints.contains($0.joint) }
            case .accelerations:
                self.accelerationData.x.removeAll { joints.contains($0.joint) }
                self.accelerationData.y.removeAll { joints.contains($0.joint) }
            case .comparison:
                break
            }
        }
    }
    
    // MARK: - Data Building Methods
    func buildAngleData(joints: [String], completion: @escaping () -> Void) {
        processingQueue.async { [weak self] in
            guard let self = self else { return }
            var newData: [JointData] = []
            let group = DispatchGroup()
            
            for joint in joints {
                guard !["L Ankle", "R Ankle", "L Wrist", "R Wrist"].contains(joint) else { continue }
                
                group.enter()
                DispatchQueue.main.async {
                    self.poseJointViewModel.fetchAngleData(for: joint) { JointData in
                        if !JointData.dataPoints.isEmpty {
                            newData.append(JointData)
                        }
                    }
                    group.leave()
                }
            }
            
            group.notify(queue: .main) {
                self.angleData.append(contentsOf: newData)
                completion()
            }
        }
    }

    func buildPositionData(joints: [String], completion: @escaping () -> Void) {
        processingQueue.async { [weak self] in
            guard let self = self else { return }
            var newData: [JointData] = []
            let group = DispatchGroup()

            for joint in joints {
                group.enter()
                DispatchQueue.main.async {
                    self.poseJointViewModel.fetchPositionData(for: joint) { JointData in
                        if !JointData.dataPoints.isEmpty {
                            newData.append(JointData)
                        }
                    }
                    group.leave()
                }
            }

            group.notify(queue: .main) {
                self.positionData.append(contentsOf: newData)
                completion()
            }
        }
    }


    func buildVelocityData(joints: [String], completion: @escaping () -> Void) {
        processingQueue.async { [weak self] in
            guard let self = self else { return }
            var resultX: [JointData] = []
            var resultY: [JointData] = []
            let group = DispatchGroup()

            for joint in joints {
                group.enter()
                DispatchQueue.main.async {
                    self.poseJointViewModel.fetchVelocityData(for: joint) { (JointDataX, JointDataY) in
                        if !JointDataX.dataPoints.isEmpty {
                            resultX.append(JointData(joint: joint, dataPoints: JointDataX.dataPoints, dataMetrics: JointDataX.dataMetrics))
                        }
                        if !JointDataY.dataPoints.isEmpty {
                            resultY.append(JointData(joint: joint, dataPoints: JointDataY.dataPoints, dataMetrics: JointDataY.dataMetrics))
                        }
                    }
                    group.leave()
                }
            }

            group.notify(queue: .main) {
                self.velocityData.x.append(contentsOf: resultX)
                self.velocityData.y.append(contentsOf: resultY)
                completion()
            }
        }
    }

    
    func buildAccelerationData(joints: [String], completion: @escaping () -> Void) {
        processingQueue.async { [weak self] in
            guard let self = self else { return }
            var resultX: [JointData] = []
            var resultY: [JointData] = []
            let group = DispatchGroup()

            for joint in joints {
                group.enter()
                DispatchQueue.main.async {
                    self.poseJointViewModel.fetchAccelerationData(for: joint) { (JointDataX, JointDataY) in
                        if !JointDataX.dataPoints.isEmpty {
                            resultX.append(JointData(joint: joint, dataPoints: JointDataX.dataPoints, dataMetrics: JointDataX.dataMetrics))
                        }
                        if !JointDataY.dataPoints.isEmpty {
                            resultY.append(JointData(joint: joint, dataPoints: JointDataY.dataPoints, dataMetrics: JointDataY.dataMetrics))
                        }
                    }
                    group.leave()
                }
            }

            group.notify(queue: .main) {
                self.accelerationData.x.append(contentsOf: resultX)
                self.accelerationData.y.append(contentsOf: resultY)
                completion()
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

