//
//  PoseJointViewModel.swift
//  PoseA
//
//  Created by Ardhika Maulidani on 6/12/25.
//

import Foundation
import Metal

final class FrameDataCache {
    static let shared = FrameDataCache()
    
    private let cache = NSCache<NSNumber, FrameDataModel>()
    
    private init() {
        cache.countLimit = 150 // Tune based on device memory
    }
    
    func getFrame(at index: Int, from frameDir: URL, device: MTLDevice) throws -> FrameDataModel {
        if let cached = cache.object(forKey: NSNumber(value: index)) {
            return cached
        }
        
        // Load and cache
        let frameLoader = FrameDataVM()
        frameLoader.loadData(from: frameDir, device: device)
        
        let model = frameLoader.database
        
        cache.setObject(model, forKey: NSNumber(value: index))
        return model
    }
    
    func getMetadata(at index: Int, from frameDir: URL) throws -> FrameDataModel  {
        if let cached = cache.object(forKey: NSNumber(value: index)) {
            return cached
        }
        
        // Load and cache
        let frameLoader = FrameDataVM()
        frameLoader.loadMetadata(from: frameDir.appendingPathComponent("metadata.plist"))
        
        let model = frameLoader.database
        
        cache.setObject(model, forKey: NSNumber(value: index))
        return model
    }
}


// MARK: ----------------------------- Pose Joint Dataase Class BEGIN -----------------------------

class PoseJointVM: ObservableObject {
    private let poseProcessor: VitPoseProcessor
    private let cameraManager: CameraLiDARManager
    private let fps: Float = 30.0
    private let processingQueue = DispatchQueue(label: "com.posea.processing", qos: .userInitiated)
    
    var totalFrames: Int {
        poseProcessor.getTotalFrames()
    }
    
    let jointAngleLimits: [String: ClosedRange<Float>] = [
        "L Elbow": 30...180,
        "R Elbow": 30...180,
        "L Knee": 40...180,
        "R Knee": 40...180,
        "L Shoulder": 20...240,
        "R Shoulder": 20...240,
        "L Hip": 45...250,
        "R Hip": 45...250
    ]
    
    init(poseProcessor: VitPoseProcessor, cameraManager: CameraLiDARManager) {
        self.poseProcessor = poseProcessor
        self.cameraManager = cameraManager
    }
    
    func fetchFrameData(at frameIndex: Int) -> FrameDataModel? {
        let frameDir = cameraManager._lidarFrameURLs[frameIndex]
        
        do {
            let frameData = try FrameDataCache.shared.getMetadata(at: frameIndex, from: frameDir)
            return frameData
        } catch {
            log("Error fetching frame data at frame \(frameIndex): \(error)")
            return nil
        }
    }
    
    func getCameraSpacePose(at: [KeypointData], joints: Int, indices: Int) -> SIMD3<Float>?{
        // Get Current Frame Metadata
        guard let frameMetadata = self.fetchFrameData(at: indices) else {
            return nil
        }
        
        // Project 2D Image Space into 3D Camera Space
        let fx = frameMetadata.cameraIntrinsics[0][0]
        let fy = frameMetadata.cameraIntrinsics[1][1]
        let cx = frameMetadata.cameraIntrinsics[2][0]
        let cy = frameMetadata.cameraIntrinsics[2][1]
        
        let pointX = (Float(at[joints].x) - cx) * at[joints].depth / fx
        let pointY = -(Float(at[joints].y) - cy) * at[joints].depth / fy  // Flip Y-axis to match Metal rendering
        let pointZ = Float(-at[joints].depth)                             // Negate Z to match Metal rendering
        
        return SIMD3<Float>(pointX, pointY, pointZ)
    }
    
    func fetchPositionData(for joint: String, useDepth: Bool, completion: @escaping (JointData) -> Void) {
        var data: [xyzChartData] = []
        var _dataMetrics: dataMetrics = .init()
        
        processingQueue.sync { [weak self] in
            guard let self = self else { return }

            for i in 0..<self.totalFrames {
                guard let keypoints = self.poseProcessor.getKeypoints(for: i), keypoints.count == 17 else {
                    log("No keypoint found at frame \(i)", level: .warn)
                    continue
                }
                let index = self.jointIndex(for: joint)
                let kp = keypoints[index]
                
                if useDepth {
                    guard let _points = self.getCameraSpacePose(at: keypoints, joints: index, indices: i) else {
                        continue
                    }
                    // Convert to Centimeter
                    data.append(xyzChartData(x: _points.x * 100, y: _points.y * 100, z: _points.z * 100))
                } else {
                    data.append(xyzChartData(x: Float(kp.x), y: Float(kp.y), z: Float(kp.depth)))

                }
            }
            
            // Compute Metrics Value
            _dataMetrics = dataMetrics(
                minX: data.map { $0.x }.min() ?? 0.0,
                maxX: data.map { $0.x }.max() ?? 0.0,
                minY: data.map { $0.y }.min() ?? 0.0,
                maxY: data.map { $0.y }.max() ?? 0.0,
                minZ: data.map { $0.z }.min() ?? 0.0,
                maxZ: data.map { $0.z }.max() ?? 0.0
            )
        }
        
        DispatchQueue.main.async {
            completion(JointData(joint: joint, dataPoints: data, dataMetrics: _dataMetrics))
        }
    }

    func fetchAngleData(for joint: String, completion: @escaping (JointData) -> Void) {
        processingQueue.sync { [weak self] in
            guard let self = self else { return }
            let filter = Kalman1DAngleFilter(dt: 1.0 / fps)
            var data: [xyzChartData] = []

            var initialized = false

            for i in 0..<self.totalFrames {
                let keypoints = self.poseProcessor.getKeypoints(for: i)
                var angle: Float? = nil

                if let kp = keypoints, kp.count == 17 {
                    let rawAngle = self.calculateAngle(for: joint, keypoints: kp)
                    let range = jointAngleLimits[joint] ?? 0...360
                    if range.contains(rawAngle) {
                        angle = rawAngle
                    }
                }

                // Initialize filter with first valid measurement
                if !initialized, let angle = angle {
                    filter.reset(angle: angle)
                    initialized = true
                }

                // Feed into Kalman filter
                let filtered = filter.update(measurement: initialized ? angle : nil)
                if initialized {
                    data.append(xyzChartData(x: i, y: filtered, z: 0.0))
                }
            }

            // Compute Metrics Value
            let dataMetrics = dataMetrics(
                minY: data.map { $0.y }.min() ?? 0.0,
                maxY: data.map { $0.y }.max() ?? 0.0
            )

            DispatchQueue.main.async {
                completion(JointData(joint: joint, dataPoints: data, dataMetrics: dataMetrics))
            }
        }
    }


    func fetchVelocityData(for joint: String, completion: @escaping (JointData, JointData) -> Void) {
        processingQueue.sync { [weak self] in
            guard let self = self else { return }
            var dataX: [xyzChartData] = [xyzChartData(x: 0.0, y: 0.0, z: 0)]
            var dataY: [xyzChartData] = [xyzChartData(x: 0.0, y: 0.0, z: 0)]

            for i in 1..<self.totalFrames {
                guard let kp0 = self.poseProcessor.getKeypoints(for: i-1),
                      let kp1 = self.poseProcessor.getKeypoints(for: i),
                      kp0.count == 17, kp1.count == 17 else {
                    log("No keypoints pair found at frame \(i-1) and frame \(i)", level: .warn)
                    continue
                }
                
                let index = self.jointIndex(for: joint)
                
                guard let _points0 = self.getCameraSpacePose(at: kp0, joints: index, indices: i) else {
                    continue
                }
                
                guard let _points1 = self.getCameraSpacePose(at: kp1, joints: index,indices: i) else {
                    continue
                }
                
                let vx = Float(_points1.x - _points0.x) * self.fps
                let vy = Float(_points1.y - _points0.y) * self.fps
                dataX.append(xyzChartData(x: i, y: vx))
                dataY.append(xyzChartData(x: i, y: vy))
            }
            
            // Compute Metrics Value
            let dataMetrics = dataMetrics(
                minX: dataX.map { $0.y }.min() ?? 0.0,
                maxX: dataX.map { $0.y }.max() ?? 0.0,
                minY: dataY.map { $0.y }.min() ?? 0.0,
                maxY: dataY.map { $0.y }.max() ?? 0.0
            )
            
            DispatchQueue.main.async {
                completion(JointData(joint: joint, dataPoints: dataX, dataMetrics: dataMetrics),
                           JointData(joint: joint, dataPoints: dataY, dataMetrics: dataMetrics))
            }
        }
    }
    
    func fetchAccelerationData(for joint: String, interpolateMissing: Bool = false, completion: @escaping (JointData, JointData) -> Void) {
        processingQueue.sync { [weak self] in
            guard let self = self else { return }
            
            // Make sure to fetch velocities data first
            var dataVX: [xyzChartData] = [xyzChartData(x: 0.0, y: 0.0, z: 0)]
            var dataVY: [xyzChartData] = [xyzChartData(x: 0.0, y: 0.0, z: 0)]

            for i in 1..<self.totalFrames {
                guard let kp0 = self.poseProcessor.getKeypoints(for: i-1),
                      let kp1 = self.poseProcessor.getKeypoints(for: i),
                      kp0.count == 17, kp1.count == 17 else {
                    log("No keypoints pair found at frame \(i-1) and frame \(i)", level: .warn)
                    continue
                }
                
                let index = self.jointIndex(for: joint)
                guard let _points0 = self.getCameraSpacePose(at: kp0, joints: index, indices: i) else {
                    continue
                }
                
                guard let _points1 = self.getCameraSpacePose(at: kp1, joints: index,indices: i) else {
                    continue
                }
                
                let vx = Float(_points1.x - _points0.x) * self.fps
                let vy = Float(_points1.y - _points0.y) * self.fps
                dataVX.append(xyzChartData(x: i, y: vx))
                dataVY.append(xyzChartData(x: i, y: vy))
            }
            
            // Create a dictionary for quick lookup of velocity data
            var velocityDict: [Int: (x: Float, y: Float)] = [:]
            for i in 0..<dataVX.count {
                let frameIndex = Int(dataVX[i].x)
                velocityDict[frameIndex] = (dataVX[i].y, dataVY[i].y)
            }
            
            var dataX: [xyzChartData] = [xyzChartData(x: 0.0, y: 0.0, z: 0)]
            var dataY: [xyzChartData] = [xyzChartData(x: 0.0, y: 0.0, z: 0)]
            
            for i in 1..<self.totalFrames {
                var ax: Float = 0.0
                var ay: Float = 0.0
                
                if let currentVel = velocityDict[i], let prevVel = velocityDict[i-1] {
                    // Both frames exist, calculate acceleration normally
                    ax = (currentVel.x - prevVel.x) * self.fps
                    ay = (currentVel.y - prevVel.y) * self.fps
                } else if interpolateMissing {
                    // Find the nearest available frames for interpolation
                    let prevFrame = self.findNearestFrame(before: i, in: velocityDict)
                    let nextFrame = self.findNearestFrame(after: i, in: velocityDict)
                    
                    if let prevFrame = prevFrame, let nextFrame = nextFrame {
                        // Interpolate velocity values
                        let prevVel = velocityDict[prevFrame]!
                        let nextVel = velocityDict[nextFrame]!
                        
                        let t = Float(i - prevFrame) / Float(nextFrame - prevFrame)
                        let interpolatedVelX = prevVel.x + t * (nextVel.x - prevVel.x)
                        let interpolatedVelY = prevVel.y + t * (nextVel.y - prevVel.y)
                        
                        // Calculate acceleration using interpolated values
                        if let prevVel = velocityDict[i-1] {
                            ax = (interpolatedVelX - prevVel.x) / (1/self.fps)
                            ay = (interpolatedVelY - prevVel.y) / (1/self.fps)
                        }
                    }
                } else {
                    // Skip this frame if interpolation is not enabled
                    continue
                }
                dataX.append(xyzChartData(x: i, y: ax))
                dataY.append(xyzChartData(x: i, y: ay))
            }
            
            // Compute Metrics Value
            let dataMetrics = dataMetrics(
                minX: dataX.map { $0.y }.min() ?? 0.0,
                maxX: dataX.map { $0.y }.max() ?? 0.0,
                minY: dataY.map { $0.y }.min() ?? 0.0,
                maxY: dataY.map { $0.y }.max() ?? 0.0
            )
            
            DispatchQueue.main.async {
                completion(JointData(joint: joint, dataPoints: dataX, dataMetrics: dataMetrics),
                           JointData(joint: joint, dataPoints: dataY, dataMetrics: dataMetrics))
            }
        }
    }
    
    // Define Joint Index (COCO Skeleton Keypoints Definition)
    private func jointIndex(for joint: String) -> Int {
        switch joint {
        case "L Shoulder": return 5
        case "R Shoulder": return 6
        case "L Elbow": return 7
        case "R Elbow": return 8
        case "L Wrist": return 9
        case "R Wrist": return 10
        case "L Hip": return 11
        case "R Hip": return 12
        case "L Knee": return 13
        case "R Knee": return 14
        case "L Ankle": return 15
        case "R Ankle": return 16
        default: return 0
        }
    }

    private func calculateAngle(for joint: String, keypoints: [KeypointData]) -> Float {
        switch joint {
        case "L Shoulder": return angleBetween(keypoints[11], keypoints[5], keypoints[7])
        case "R Shoulder": return angleBetween(keypoints[12], keypoints[6], keypoints[8])
        case "L Elbow": return angleBetween(keypoints[5], keypoints[7], keypoints[9])
        case "R Elbow": return angleBetween(keypoints[6], keypoints[8], keypoints[10])
        case "L Hip": return angleBetween(keypoints[5], keypoints[11], keypoints[13])
        case "R Hip": return angleBetween(keypoints[6], keypoints[12], keypoints[14])
        case "L Knee": return angleBetween(keypoints[11], keypoints[13], keypoints[15])
        case "R Knee": return angleBetween(keypoints[12], keypoints[14], keypoints[16])
        default: return 0
        }
    }
    
    // Helper function to find the nearest available frame before the given index
    private func findNearestFrame(before index: Int, in dict: [Int: (x: Float, y: Float)]) -> Int? {
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
    private func findNearestFrame(after index: Int, in dict: [Int: (x: Float, y: Float)]) -> Int? {
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

// MARK: ------------------------------ Pose Joint Dataase Class END ------------------------------
