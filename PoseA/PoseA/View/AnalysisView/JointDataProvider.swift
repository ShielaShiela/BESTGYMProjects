//
//  JointDataProvider.swift
//  PoseA
//
//  Created by Ardhika Maulidani on 6/1/25.
//

import Foundation

protocol JointDataProvider {
    var poseProcessor: VitPoseProcessor { get }
    func getDataCount() -> Int
    func getAngleData(for joint: String) -> [xyChartData]
    func getVelocitiesData(for joint: String) -> ([xyChartData], [xyChartData]) 
}

struct DefaultJointDataProvider: JointDataProvider {
    let poseProcessor: VitPoseProcessor
    
    func getDataCount() -> Int {
        return poseProcessor.getTotalFrames()
    }
    
    func getPositionData(for joint: String) -> [xyChartData] {
        var dataPoints: [xyChartData] = []
        let totalFrame = self.getDataCount()
        
        for i in 0..<totalFrame {
            var _x: Double = 0
            var _y: Double = 0
            
            guard let keypoints = poseProcessor.getKeypoints(for: i) else {
                print("Error: No keypoints found at frame \(i)")
                continue
            }
            
            if keypoints.count != 17 { continue }
            
            // Angle Calculation
            switch joint {
            case "L Shoulder":
                _x = keypoints[5].x
                _y = keypoints[5].y
            case "R Shoulder":
                _x = keypoints[6].x
                _y = keypoints[6].y
            case "L Elbow":
                _x = keypoints[7].x
                _y = keypoints[7].y
            case "R Elbow":
                _x = keypoints[8].x
                _y = keypoints[8].y
            case "L Hip":
                _x = keypoints[11].x
                _y = keypoints[11].y
            case "R Hip":
                _x = keypoints[12].x
                _y = keypoints[12].y
            case "L Knee":
                _x = keypoints[13].x
                _y = keypoints[13].y
            case "R Knee":
                _x = keypoints[14].x
                _y = keypoints[14].y
            default:
                _x = 0
                _y = 0
            }
            dataPoints.append(xyChartData(x: _x, y: _y))
        }
        return dataPoints
    }

    func getAngleData(for joint: String) -> [xyChartData] {
        var dataAngles: [xyChartData] = []
        let totalFrame = self.getDataCount()
        
        for i in 0..<totalFrame {
            var angle: Double = 0
            
            guard let keypoints = poseProcessor.getKeypoints(for: i) else {
                print("Error: No keypoints found at frame \(i)")
                continue
            }
            
            if keypoints.count != 17 { continue }
            
            // Angle Calculation
            switch joint {
            case "L Shoulder":
                angle = angleBetween(keypoints[11], keypoints[5], keypoints[7])
            case "R Shoulder":
                angle = angleBetween(keypoints[12], keypoints[6], keypoints[8])
            case "L Elbow":
                angle = angleBetween(keypoints[5], keypoints[7], keypoints[9])
            case "R Elbow":
                angle = angleBetween(keypoints[6], keypoints[8], keypoints[10])
            case "L Hip":
                angle = angleBetween(keypoints[5], keypoints[11], keypoints[13])
            case "R Hip":
                angle = angleBetween(keypoints[6], keypoints[12], keypoints[14])
            case "L Knee":
                angle = angleBetween(keypoints[11], keypoints[13], keypoints[15])
            case "R Knee":
                angle = angleBetween(keypoints[12], keypoints[14], keypoints[16])
            default:
                angle = 0
            }
            dataAngles.append(xyChartData(x: i, y: angle))
        }
        return dataAngles
    }
    
    func getVelocitiesData(for joint: String) -> ([xyChartData], [xyChartData]) {
        var dataXDot: [xyChartData] = []
        var dataYDot: [xyChartData] = []
        let totalFrame = self.getDataCount()
        let fps: Double = 30
        
        // First Data, Assume that V0 = 0.0 px/s
        dataXDot.append(xyChartData(x: 0, y: 0.0))
        dataYDot.append(xyChartData(x: 0, y: 0.0))
        
        for i in 1..<totalFrame {
            var _xDot: Double = 0.0
            var _yDot: Double = 0.0
            
            guard let keypoints_0 = poseProcessor.getKeypoints(for: i-1), let keypoints_1 = poseProcessor.getKeypoints(for: i) else {
                print("Error: No keypoints pair found at frame \(i-1) and frame \(i)")
                continue
            }
            
            if (keypoints_0.count != 17 || keypoints_1.count != 17) {
                print("Error: Invalid keypoint count at frame \(i-1) and frame \(i)")
                continue
            }
            
            // Angle Calculation
            switch joint {
            case "L Shoulder":
                _xDot = Double(keypoints_1[5].x - keypoints_0[5].x)/(1/fps)
                _yDot = Double(keypoints_1[5].y - keypoints_0[5].y)/(1/fps)
            case "R Shoulder":
                _xDot = Double(keypoints_1[6].x - keypoints_0[6].x)/(1/fps)
                _yDot = Double(keypoints_1[6].y - keypoints_0[6].y)/(1/fps)
            case "L Elbow":
                _xDot = Double(keypoints_1[7].x - keypoints_0[7].x)/(1/fps)
                _yDot = Double(keypoints_1[7].y - keypoints_0[7].y)/(1/fps)
            case "R Elbow":
                _xDot = Double(keypoints_1[8].x - keypoints_0[8].x)/(1/fps)
                _yDot = Double(keypoints_1[8].y - keypoints_0[8].y)/(1/fps)
            case "L Hip":
                _xDot = Double(keypoints_1[11].x - keypoints_0[11].x)/(1/fps)
                _yDot = Double(keypoints_1[11].y - keypoints_0[11].y)/(1/fps)
            case "R Hip":
                _xDot = Double(keypoints_1[12].x - keypoints_0[12].x)/(1/fps)
                _yDot = Double(keypoints_1[12].y - keypoints_0[12].y)/(1/fps)
            case "L Knee":
                _xDot = Double(keypoints_1[13].x - keypoints_0[13].x)/(1/fps)
                _yDot = Double(keypoints_1[13].y - keypoints_0[13].y)/(1/fps)
            case "R Knee":
                _xDot = Double(keypoints_1[14].x - keypoints_0[14].x)/(1/fps)
                _yDot = Double(keypoints_1[14].y - keypoints_0[14].y)/(1/fps)
            default:
                _xDot = 0
                _yDot = 0
            }
            
            dataXDot.append(xyChartData(x: i, y: _xDot))
            dataYDot.append(xyChartData(x: i, y: _yDot))
        }
        return (dataXDot, dataYDot)
    }

    func getAccelerationData(for joint: String, interpolateMissing: Bool = false) -> ([xyChartData], [xyChartData]) {
        var dataXDDot: [xyChartData] = []
        var dataYDDot: [xyChartData] = []
        let totalFrame = self.getDataCount()
        let fps: Double = 30
        
        // First Data, Assume that V0 = 0.0 px/s
        dataXDDot.append(xyChartData(x: 0, y: 0.0))
        dataYDDot.append(xyChartData(x: 0, y: 0.0))
        
        let (dataXDot, dataYDot) = self.getVelocitiesData(for: joint)
        
        // Create a dictionary for quick lookup of velocity data
        var velocityDict: [Int: (x: Double, y: Double)] = [:]
        for i in 0..<dataXDot.count {
            let frameIndex = Int(dataXDot[i].x)
            velocityDict[frameIndex] = (dataXDot[i].y, dataYDot[i].y)
        }
        
        for i in 1..<totalFrame {
            var _xDDot: Double = 0.0
            var _yDDot: Double = 0.0
            
            if let currentVel = velocityDict[i], let prevVel = velocityDict[i-1] {
                // Both frames exist, calculate acceleration normally
                _xDDot = (currentVel.x - prevVel.x) / (1/fps)
                _yDDot = (currentVel.y - prevVel.y) / (1/fps)
            } else if interpolateMissing {
                // Find the nearest available frames for interpolation
                let prevFrame = findNearestFrame(before: i, in: velocityDict)
                let nextFrame = findNearestFrame(after: i, in: velocityDict)
                
                if let prevFrame = prevFrame, let nextFrame = nextFrame {
                    // Interpolate velocity values
                    let prevVel = velocityDict[prevFrame]!
                    let nextVel = velocityDict[nextFrame]!
                    
                    let t = Double(i - prevFrame) / Double(nextFrame - prevFrame)
                    let interpolatedVelX = prevVel.x + t * (nextVel.x - prevVel.x)
                    let interpolatedVelY = prevVel.y + t * (nextVel.y - prevVel.y)
                    
                    // Calculate acceleration using interpolated values
                    if let prevVel = velocityDict[i-1] {
                        _xDDot = (interpolatedVelX - prevVel.x) / (1/fps)
                        _yDDot = (interpolatedVelY - prevVel.y) / (1/fps)
                    }
                }
            } else {
                // Skip this frame if interpolation is not enabled
                continue
            }
            
            dataXDDot.append(xyChartData(x: i, y: _xDDot))
            dataYDDot.append(xyChartData(x: i, y: _yDDot))
        }
        return (dataXDDot, dataYDDot)
    }
    
    // Helper function to find the nearest available frame before the given index
    private func findNearestFrame(before index: Int, in dict: [Int: (x: Double, y: Double)]) -> Int? {
        var current = index - 1
        while current >= 0 {
            if dict[current] != nil {
                return current
            }
            current -= 1
        }
        return nil
    }
    
    // Helper function to find the nearest available frame after the given index
    private func findNearestFrame(after index: Int, in dict: [Int: (x: Double, y: Double)]) -> Int? {
        var current = index + 1
        while current < dict.keys.max() ?? Int.max {
            if dict[current] != nil {
                return current
            }
            current += 1
        }
        return nil
    }
}
