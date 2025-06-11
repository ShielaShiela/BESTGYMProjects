//
//  JointDataProvider.swift
//  PoseA
//
//  Created by Ardhika Maulidani on 6/1/25.
//

import Foundation

struct JointDataProvider {
    let poseProcessor: VitPoseProcessor
//    let cameraManager: CameraLiDARManager
    
    func getDataCount() -> Int {
        return poseProcessor.getTotalFrames()
    }
    
    func getPositionData(for joint: String) -> [xyzChartData] {
        var dataPoints: [xyzChartData] = []
        let totalFrame = self.getDataCount()
        
        for i in 0..<totalFrame {
            var _x: Double = 0
            var _y: Double = 0
            var _z: Float = 0
            
            guard let keypoints = poseProcessor.getKeypoints(for: i) else {
                log("No keypoint found at frame \(i)", level: .warn)
                continue
            }
            
            if keypoints.count != 17 { continue }
            
            // Angle Calculation
            switch joint {
            case "L Shoulder":
                _x = keypoints[5].x
                _y = keypoints[5].y
                _z = keypoints[5].depth
                
            case "R Shoulder":
                _x = keypoints[6].x
                _y = keypoints[6].y
                _z = keypoints[6].depth

            case "L Elbow":
                _x = keypoints[7].x
                _y = keypoints[7].y
                _z = keypoints[7].depth
                
            case "R Elbow":
                _x = keypoints[8].x
                _y = keypoints[8].y
                _z = keypoints[8].depth
                
            case "L Wrist":
                _x = keypoints[9].x
                _y = keypoints[9].y
                _z = keypoints[9].depth
                
            case "R Wrist":
                _x = keypoints[10].x
                _y = keypoints[10].y
                _z = keypoints[10].depth
                
            case "L Hip":
                _x = keypoints[11].x
                _y = keypoints[11].y
                _z = keypoints[11].depth
                
            case "R Hip":
                _x = keypoints[12].x
                _y = keypoints[12].y
                _z = keypoints[12].depth
                
            case "L Knee":
                _x = keypoints[13].x
                _y = keypoints[13].y
                _z = keypoints[13].depth
                
            case "R Knee":
                _x = keypoints[14].x
                _y = keypoints[14].y
                _z = keypoints[14].depth
                
            case "L Ankle":
                _x = keypoints[15].x
                _y = keypoints[15].y
                _z = keypoints[15].depth
                
            case "R Ankle":
                _x = keypoints[16].x
                _y = keypoints[16].y
                _z = keypoints[16].depth
                
            default:
                _x = 0
                _y = 0
                _z = 0
            }
            
            //Calculate 3D Points based on Camera Intrinsic
//            guard let _points = cameraManager.calculate3DPoint(from: CGPoint(x: _x, y: _y), depthValue: _z) else {
//                log("Error: Failed to calculate 3D point", level: .error)
//                continue
//            }
            dataPoints.append(xyzChartData(x: Double(_x), y: Double(_y), z: _z))
        }
        return dataPoints
    }

    func getAngleData(for joint: String) -> [xyzChartData] {
        var dataAngles: [xyzChartData] = []
        let totalFrame = self.getDataCount()
        
        for i in 0..<totalFrame {
            var angle: Double = 0
            
            guard let keypoints = poseProcessor.getKeypoints(for: i) else {
                log("No keypoint found at frame \(i)", level: .warn)
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
            dataAngles.append(xyzChartData(x: i, y: angle))
        }
        return dataAngles
    }
    
    func getVelocitiesData(for joint: String) -> ([xyzChartData], [xyzChartData]) {
        var dataXDot: [xyzChartData] = []
        var dataYDot: [xyzChartData] = []
        let totalFrame = self.getDataCount()
        let fps: Double = 30
        
        // First Data, Assume that V0 = 0.0 px/s
        dataXDot.append(xyzChartData(x: 0, y: 0.0))
        dataYDot.append(xyzChartData(x: 0, y: 0.0))
        
        for i in 1..<totalFrame {
            var _xDot: Double = 0.0
            var _yDot: Double = 0.0
            
            guard let keypoints_0 = poseProcessor.getKeypoints(for: i-1), let keypoints_1 = poseProcessor.getKeypoints(for: i) else {
                log("No keypoints pair found at frame \(i-1) and frame \(i)", level: .warn)
                continue
            }
            
            if (keypoints_0.count != 17 || keypoints_1.count != 17) {
                log("Invalid keypoints found at frame \(i-1) and frame \(i)", level: .warn)
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
            case "L Wrist":
                _xDot = Double(keypoints_1[9].x - keypoints_0[9].x)/(1/fps)
                _yDot = Double(keypoints_1[9].y - keypoints_0[9].y)/(1/fps)
            case "R Wrist":
                _xDot = Double(keypoints_1[10].x - keypoints_0[10].x)/(1/fps)
                _yDot = Double(keypoints_1[10].y - keypoints_0[10].y)/(1/fps)
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
            case "L Ankle":
                _xDot = Double(keypoints_1[15].x - keypoints_0[15].x)/(1/fps)
                _yDot = Double(keypoints_1[15].y - keypoints_0[15].y)/(1/fps)
            case "R Ankle":
                _xDot = Double(keypoints_1[16].x - keypoints_0[16].x)/(1/fps)
                _yDot = Double(keypoints_1[16].y - keypoints_0[16].y)/(1/fps)
            default:
                _xDot = 0
                _yDot = 0
            }
            
            dataXDot.append(xyzChartData(x: i, y: _xDot))
            dataYDot.append(xyzChartData(x: i, y: _yDot))
        }
        return (dataXDot, dataYDot)
    }

    func getAccelerationData(for joint: String, interpolateMissing: Bool = false) -> ([xyzChartData], [xyzChartData]) {
        var dataXDDot: [xyzChartData] = []
        var dataYDDot: [xyzChartData] = []
        let totalFrame = self.getDataCount()
        let fps: Double = 30
        
        // First Data, Assume that V0 = 0.0 px/s
        dataXDDot.append(xyzChartData(x: 0, y: 0.0))
        dataYDDot.append(xyzChartData(x: 0, y: 0.0))
        
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
            
            dataXDDot.append(xyzChartData(x: i, y: _xDDot))
            dataYDDot.append(xyzChartData(x: i, y: _yDDot))
        }
        return (dataXDDot, dataYDDot)
    }
    
    func getExtremeData(for joint: String, in analysis: PoseAnalysisView.AnalysisType) -> (Double, Double, Double, Double) {
        // Initiate Return Data Holder
        var minValueX: Double = 0
        var minValueY: Double = 0
        
        var maxValueX: Double = 0
        var maxValueY: Double = 0
        
        // Get Data Value
        switch analysis {
        case .jointAngles:
            // Get Data Value
            let _data = self.getAngleData(for: joint)
            
            // Find Max and Min Data
            let allYValues = _data.compactMap { $0.y }
            minValueY = allYValues.min() ?? 0
            maxValueY = allYValues.max() ?? 0
            break
        
        case .trajectories:
            // Get Data Value
            let _data = self.getPositionData(for: joint)
            
            // Find Max and Min Data
            let allXValues = _data.compactMap { $0.x }
            let allYValues = _data.compactMap { $0.y }
            minValueX = allXValues.min() ?? 0
            maxValueX = allXValues.max() ?? 0
            minValueY = allYValues.min() ?? 0
            maxValueY = allYValues.max() ?? 0
            break
            
        case .velocities:
            // Get Data Value
            let (_dataX, _dataY) = self.getVelocitiesData(for: joint)
            
            // Find Max and Min Data
            let allXValues = _dataX.compactMap { $0.y }
            let allYValues = _dataY.compactMap { $0.y }
            
            minValueX = allXValues.min() ?? 0
            maxValueX = allXValues.max() ?? 0
            minValueY = allYValues.min() ?? 0
            maxValueY = allYValues.max() ?? 0
            break
            
        case .accelerations:
            // Get Data Value
            let (_dataX, _dataY) = self.getAccelerationData(for: joint)
            
            // Find Max and Min Data
            let allXValues = _dataX.compactMap { $0.y }
            let allYValues = _dataY.compactMap { $0.y }
            minValueX = allXValues.min() ?? 0
            maxValueX = allXValues.max() ?? 0
            minValueY = allYValues.min() ?? 0
            maxValueY = allYValues.max() ?? 0
            break
            
        case .comparison:
            let _ = [0...100]
            break
        }
        
        return (minValueX, maxValueX, minValueY, maxValueY)
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
