//
//  PoseJointLandscapeVM.swift
//  PoseA
//
//  Created by Ardhika Maulidani on 7/15/25.
//

import Foundation

// MARK: ----------------------------- Pose Joint Dataase Class BEGIN -----------------------------
@Observable
class PoseJointLandscapeVM {
    var angleCompleteData: [JointData] = []
    var positionCompleteData: [JointData] = []
    var velocityCompleteData: [JointData] = []
    var accelerationCompleteData: [JointData] = []
    
    private var BoxModel: BoxViewModel
    private var mediaManager: MediaManagerVM
    private let fps: Float = 30.0
    private let processingQueue = DispatchQueue(label: "com.posea.processing", qos: .userInitiated)
    

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
    
    init(BoxModel: BoxViewModel, mediaManager: MediaManagerVM) {
        self.BoxModel = BoxModel
        self.mediaManager = mediaManager
    }
    
    func buildCompleteData(useDepth: Bool = false, completion: @escaping (Bool) -> Void) {
        // Build Base Position First
        self.fetchPositionData(useDepth: useDepth) { success in
            if !success {
                log("Failed to fetch position data.", level: .error)
            }
            // Compute Derivative
            self.buildVelocityAndAcceleration()
            
            // Compute Joint Angles
            self.buildAngles()
            
            completion(success)
        }
    }
    
    private func fetchPositionData(useDepth: Bool, completion: @escaping (Bool) -> Void) {
        // Init Variable
        var positionFilters: [String: KF3DWrapper] = [:]
        var posData: [String: [xyzChartData]] = [:]
        var posInitialized: [String: Bool] = [:]
        
        // Result Variable
        var completePosData: [JointData] = []

        processingQueue.sync { [weak self] in
            guard let self = self else { return }
            
            // Define Variable per Joint
            availableJoints.forEach {
                positionFilters[$0] = KF3DWrapper(dt: 1.0 / self.fps)
                posData[$0] = []
                posInitialized[$0] = false
            }
            
            // Iterate per Keypoint Frame
            for i in 0..<self.mediaManager.fileLoaderViewModel.FrameImageURLs.count {
                let keypoints = self.mediaManager.getKeypointsByIndex(i)
                
                // Iterate per Joints
                for joint in availableJoints {
                    let index = self.jointIndex(for: joint)

                    var x: Float? = nil
                    var y: Float? = nil
                    var z: Float? = nil

                    if let keypoints = keypoints, keypoints.count == 17 {
                        if useDepth {
                            // To be implemented later
                            continue
                        } else {
                            let kp = keypoints[index]
                            x = Float(kp.x)
                            y = Float(kp.y)
                            z = Float(kp.depth)
                        }
                    }
                    
                    // Initialize Kalman filter if this is the first valid frame
                    if !posInitialized[joint]!, let x = x, let y = y, let z = z {
                        positionFilters[joint]!.reset(x: x, y: y, z: z)
                        posInitialized[joint] = true
                    }

                    // Only update filter if initialized
                    if posInitialized[joint]! {
                        positionFilters[joint]!.update(x: x, y: y, z: z)
                        if let (fx, fy, fz) = positionFilters[joint]!.getFilteredPosition() {
                            posData[joint]!.append(xyzChartData(x: fx, y: fy, z: fz))
                        }
                    }
                }
            }

            // Compute Metrics Value
            for joint in availableJoints {
                let pdata = posData[joint] ?? []

                let metrics = dataMetrics(
                    minX: pdata.map { $0.x }.min() ?? 0.0,
                    maxX: pdata.map { $0.x }.max() ?? 0.0,
                    minY: pdata.map { $0.y }.min() ?? 0.0,
                    maxY: pdata.map { $0.y }.max() ?? 0.0,
                    minZ: pdata.map { $0.z }.min() ?? 0.0,
                    maxZ: pdata.map { $0.z }.max() ?? 0.0
                )
                // Create Joint Data Structure
                completePosData.append(JointData(joint: joint,
                                                 dataPoints: pdata,
                                                 dataMetrics: metrics))
            }
        }
        
        DispatchQueue.main.async {
            self.positionCompleteData = completePosData
            completion(self.positionCompleteData.count > 0)
        }
    }
    
    private func buildVelocityAndAcceleration() {
        // Result Variable
        let dt = 1.0 / fps

        var completeVelData: [JointData] = []
        var completeAccData: [JointData] = []

        for jointData in positionCompleteData {
            let joint = jointData.joint
            let pos = jointData.dataPoints

            var velList: [xyzChartData] = [xyzChartData(x: 0.0, y: 0.0, z: 0.0)]
            var accList: [xyzChartData] = [xyzChartData(x: 0.0, y: 0.0, z: 0.0)]

            for i in 1..<pos.count {
                let vx = (pos[i].x - pos[i-1].x) / dt
                let vy = (pos[i].y - pos[i-1].y) / dt
                velList.append(xyzChartData(x: vx, y: vy, z: 0.0))
            }

            for i in 1..<velList.count {
                let ax = (velList[i].x - velList[i-1].x) / dt
                let ay = (velList[i].y - velList[i-1].x) / dt
                accList.append(xyzChartData(x: ax, y: ay, z: 0.0))
            }
            
            // Compute Metrics Value
            let metricsVel = dataMetrics(
                minX: velList.map { $0.x }.min() ?? 0.0,
                maxX: velList.map { $0.x }.max() ?? 0.0,
                minY: velList.map { $0.y }.min() ?? 0.0,
                maxY: velList.map { $0.y }.max() ?? 0.0
            )
            
            // Compute Metrics Value
            let metricsAcc = dataMetrics(
                minX: accList.map { $0.x }.min() ?? 0.0,
                maxX: accList.map { $0.x }.max() ?? 0.0,
                minY: accList.map { $0.y }.min() ?? 0.0,
                maxY: accList.map { $0.y }.max() ?? 0.0
            )
            
            completeVelData.append(JointData(joint: joint, dataPoints: velList, dataMetrics: metricsVel))
            completeAccData.append(JointData(joint: joint, dataPoints: accList, dataMetrics: metricsAcc))
        }
        
        // Publish
        self.velocityCompleteData = completeVelData
        self.accelerationCompleteData = completeAccData
    }

    private func buildAngles() {
        var angleData: [String: [Float]] = [:]
        var resultData: [JointData] = []

        // Prepare angle data buffer
        for joint in jointAngleLimits.keys {
            angleData[joint] = []
        }

        let frameCount = positionCompleteData.first?.dataPoints.count ?? 0

        // Get Keypoints Dictionary
        for frameIndex in 0..<frameCount {
            var keypointDict: [Int: xyzChartData] = [:]

            for jointData in positionCompleteData {
                let jointName = jointData.joint
                let jointIndex = jointIndex(for: jointName)
                if frameIndex < jointData.dataPoints.count {
                    keypointDict[jointIndex] = jointData.dataPoints[frameIndex]
                }
            }

            // If all required joints are present in this frame, compute angles
            for joint in jointAngleLimits.keys {
                // Calculate Angle
                let rawAngle = calculateAngleFromFrame(for: joint, frame: keypointDict)
                angleData[joint]?.append(rawAngle)
            }
        }

        for (joint, angles) in angleData {
            let metrics = dataMetrics(
                minX: angles.min() ?? 0,
                maxX: angles.max() ?? 0,
                minY: 0,
                maxY: 0
            )

            let chartData = angles.map { xyzChartData(x: $0, y: 0, z: 0) }
            resultData.append(JointData(joint: joint, dataPoints: chartData, dataMetrics: metrics))
        }

        self.angleCompleteData = resultData
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

    private func calculateAngle2D(for joint: String, keypoints: [KeypointData]) -> Float {
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
}

private func calculateAngleFromFrame(for joint: String, frame: [Int: xyzChartData]) -> Float {
    func get(_ i: Int) -> xyzChartData? {
        return frame[i]
    }
    
    switch joint {
    case "L Shoulder":
        guard let a = get(11), let b = get(5), let c = get(7) else { return 0 }
        return angleBetween(a, b, c)
    case "R Shoulder":
        guard let a = get(12), let b = get(6), let c = get(8) else { return 0 }
        return angleBetween(a, b, c)
    case "L Elbow":
        guard let a = get(5), let b = get(7), let c = get(9) else { return 0 }
        return angleBetween(a, b, c)
    case "R Elbow":
        guard let a = get(6), let b = get(8), let c = get(10) else { return 0 }
        return angleBetween(a, b, c)
    case "L Hip":
        guard let a = get(5), let b = get(11), let c = get(13) else { return 0 }
        return angleBetween(a, b, c)
    case "R Hip":
        guard let a = get(6), let b = get(12), let c = get(14) else { return 0 }
        return angleBetween(a, b, c)
    case "L Knee":
        guard let a = get(11), let b = get(13), let c = get(15) else { return 0 }
        return angleBetween(a, b, c)
    case "R Knee":
        guard let a = get(12), let b = get(14), let c = get(16) else { return 0 }
        return angleBetween(a, b, c)
    default:
        return 0
    }
}

private func angleBetween(_ a: xyzChartData, _ b: xyzChartData, _ c: xyzChartData) -> Float {
    let ab = CGVector(dx: Double(a.x - b.x), dy: Double(a.y - b.y))
    let cb = CGVector(dx: Double(c.x - b.x), dy: Double(c.y - b.y))

    let dot = ab.dx * cb.dx + ab.dy * cb.dy
    let cross = ab.dx * cb.dy - ab.dy * cb.dx

    var angle = atan2(cross, dot) * 180 / .pi // [-180, 180]

    if angle < 0 {
        angle += 360 // Wrap to [0, 360]
    }

    return Float(angle)
}
// MARK: ------------------------------ Pose Joint Dataase Class END ------------------------------
