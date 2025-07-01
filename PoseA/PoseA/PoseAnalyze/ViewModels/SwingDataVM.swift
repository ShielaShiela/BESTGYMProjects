//
//  SwingDataVM.swift
//  PoseA
//
//  Created by Ardhika Maulidani on 6/30/25.
//

import SwiftUI
import Combine

class SwingDataVM: ObservableObject {
    @Published var barPosition: [PointData] = []
    @Published var swingAngleData: [JointData] = []
    @Published var swingTurns: Float = 0
    
    private let poseJointViewModel: PoseJointVM
    private let processingQueue = DispatchQueue(label: "com.posea.swingdata", qos: .userInitiated)
    

    init(poseJointViewModel: PoseJointVM) {
        self.poseJointViewModel = poseJointViewModel
    }
    
    func estimateBar(completion: @escaping () -> Void) {
        processingQueue.async { [weak self] in
            guard let self = self else { return }
            
            let jointNames = ["L Wrist", "R Wrist"]
            var newData: [JointData] = Array(repeating: JointData(joint: "", dataPoints: [], dataMetrics: dataMetrics()), count: jointNames.count)
            let group = DispatchGroup()
            
            // Fetch wrist data
            for (index, joint) in jointNames.enumerated() {
                group.enter()
                DispatchQueue.main.async {
                    self.poseJointViewModel.fetchPositionData(for: joint, useDepth: false) { jointData in
                        newData[index] = jointData
                        group.leave()
                    }
                }
            }
            
            group.notify(queue: self.processingQueue) {
                guard newData.allSatisfy({ !$0.dataPoints.isEmpty }),
                      newData[0].dataPoints.count == newData[1].dataPoints.count else {
                    DispatchQueue.main.async {
                        self.barPosition = []
                        completion()
                    }
                    return
                }

                var barPositions: [CGPoint] = []
                
                for i in 0..<newData[0].dataPoints.count {
                    let left = newData[0].dataPoints[i]
                    let right = newData[1].dataPoints[i]
                    
                    guard !left.x.isNaN, !right.x.isNaN else { continue }
                    
                    let handDist = abs(left.x - right.x)
                    let verticalDist = abs(left.y - right.y)
                    
                    if (50..<400).contains(handDist), verticalDist < 80 {
                        let midPoint = CGPoint(
                            x: Double(left.x + right.x) / 2,
                            y: Double(left.y + right.y) / 2
                        )
                        barPositions.append(midPoint)
                    }
                }

                var estimatedPosition = CGPoint.zero
                
                if !barPositions.isEmpty {
                    if barPositions.count > 5 {
                        let medianX = self.median(of: barPositions.map { $0.x })
                        let medianY = self.median(of: barPositions.map { $0.y })
                        estimatedPosition = CGPoint(x: medianX, y: medianY)
                    } else {
                        let sumX = barPositions.map { $0.x }.reduce(0, +)
                        let sumY = barPositions.map { $0.y }.reduce(0, +)
                        estimatedPosition = CGPoint(
                            x: sumX / CGFloat(barPositions.count),
                            y: sumY / CGFloat(barPositions.count)
                        )
                    }
                }

                DispatchQueue.main.async {
                    self.barPosition.append(PointData(x: estimatedPosition.x, y: estimatedPosition.y))
                    print("Bar Pose: \(estimatedPosition)")
                    completion()
                }
            }
        }
    }

    func calculateAngleData(completion: @escaping () -> Void) {
        processingQueue.async { [weak self] in
            guard let self = self else { return }
            
            var results: [xyzChartData] = []
            var prevAngle: Float = 0
            var accumulatedAngle: Float = 0
            var turns: Float = 0
            
            // Get Hip Data
            let jointNames = ["L Hip", "R Hip"]
            var newData: [JointData] = Array(repeating: JointData(joint: "", dataPoints: [], dataMetrics: dataMetrics()), count: jointNames.count)
            let group = DispatchGroup()
            
            // Fetch wrist data
            for (index, joint) in jointNames.enumerated() {
                group.enter()
                DispatchQueue.main.async {
                    self.poseJointViewModel.fetchPositionData(for: joint, useDepth: false) { jointData in
                        newData[index] = jointData
                        group.leave()
                    }
                }
            }
            
            group.notify(queue: self.processingQueue) {
                guard newData.allSatisfy({ !$0.dataPoints.isEmpty }),
                      newData[0].dataPoints.count == newData[1].dataPoints.count else {
                    DispatchQueue.main.async {
                        completion()
                    }
                    return
                }
                
                for i in 1..<newData[0].dataPoints.count {
                    let prev = newData[0].dataPoints[i - 1]
                    let curr = newData[0].dataPoints[i]
                    
                    let dx = curr.x - Float(self.barPosition.first!.x)
                    let dy = curr.y - Float(self.barPosition.first!.y)
                    
                    // Angle from +Y axis (clockwise is positive)
                    let angle = atan2(dx, dy)
                    
                    // Unwrap angle to avoid jumps at ±π
                    let delta = angle - prevAngle
                    let unwrappedDelta = atan2(sin(delta), cos(delta))
                    accumulatedAngle += unwrappedDelta
                    prevAngle = angle
                    
                    turns = abs(accumulatedAngle / (.pi * 2))

                    results.append(xyzChartData(x: i, y: angle))
                }
                
                DispatchQueue.main.async {
                    self.swingTurns = turns
                    self.swingAngleData.append(JointData(joint: "Swing",
                                                         dataPoints: results,
                                                         dataMetrics: dataMetrics())
                    )
                    completion()
                }
            }
            
        }
    }
    
    private func median(of array: [CGFloat]) -> CGFloat {
        let sorted = array.sorted()
        let count = sorted.count
        if count % 2 == 0 {
            return (sorted[count / 2 - 1] + sorted[count / 2]) / 2
        } else {
            return sorted[count / 2]
        }
    }
}

