//
//  PoseJointLandscapeVM.swift
//  PoseA
//
//  Created by Ardhika Maulidani on 7/15/25.
//

import Spatial
import Foundation

// MARK: ----------------------------- Pose Joint Dataase Class BEGIN -----------------------------
@Observable
class PoseJointLandscapeVM {
    // MARK: - Properties
    
    var angleCompleteData: [JointData3D] = []
    var positionCompleteData: [JointData3D] = []
    var velocityCompleteData: [JointData3D] = []
    var accelerationCompleteData: [JointData3D] = []
    
    var barPosition: [Point2D] = []
    var swingData: [JointData3D] = []
    
    private var BoxModel: BoxViewModel
    private var mediaManager: MediaManagerVM
    private var appState: MainAppState

    private let fps: Double = 30.0
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
    
    // MARK: - Init
    
    init(appState: MainAppState, BoxModel: BoxViewModel, mediaManager: MediaManagerVM) {
        self.appState = appState
        self.BoxModel = BoxModel
        self.mediaManager = mediaManager
    }
    
    // MARK: - Public Function Calls
    
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
            // Compute Swing Data
            self.estimateBar {
                self.calculateSwingAngle()
            }
            completion(success)
        }
    }
    
    func estimateBar(completion: @escaping () -> Void) {
        // Declare Variable
        var usedData: [JointData3D] = []
        
        // Fetch wrist data
        for jointData in positionCompleteData {
            let joint = jointData.joint
            
            if joint == "L Wrist" || joint == "R Wrist" {
                usedData.append(jointData)
            }
        }
    
        // Check if Data is Empty
        guard usedData.allSatisfy({ !$0.dataPoints.isEmpty }), usedData[0].dataPoints.count == usedData[1].dataPoints.count else {
            return
        }

        var barPositions: [Point2D] = []
        
        for i in 0..<usedData[0].dataPoints.count {
            let left = usedData[0].dataPoints[i]
            let right = usedData[1].dataPoints[i]
            
            guard !left.x.isNaN, !right.x.isNaN else { continue }
            
            let handDist = abs(left.x - right.x)
            let verticalDist = abs(left.y - right.y)
            
            if (50..<400).contains(handDist), verticalDist < 80 {
                let midPoint = CGPoint(
                    x: (left.x + right.x) / 2,
                    y: (left.y + right.y) / 2
                )
                barPositions.append(Point2D(midPoint))
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

        self.barPosition.append(Point2D(x: estimatedPosition.x, y: estimatedPosition.y))
        completion()
    }
    
    func calculateSwingAngle() {
        var _dataMetricsAngle: dataMetrics = .init()
        var _dataMetricsVel: dataMetrics = .init()
        var _dataMetricsTurn: dataMetrics = .init()
        
        var resultsAngle: [Point3D] = []
        var resultsVelocity: [Point3D] = []
        
        var prevAngle: Angle2D = .zero
        var accumulatedAngle: Angle2D = .zero
        var turns: Double = 0
        
        // Declare Variable
        var usedData: [JointData3D] = []
        
        // Get Hip Data
        for jointData in positionCompleteData {
            let joint = jointData.joint
            
            if joint == "L Hip" || joint == "R Hip" {
                usedData.append(jointData)
            }
        }
        
        guard usedData.allSatisfy({ !$0.dataPoints.isEmpty }), usedData[0].dataPoints.count == usedData[1].dataPoints.count else {
            return
        }
            
        // Calculate Angle
        let dt: Double = 1 / fps
        let count = Int(usedData[0].dataPoints.count)
        
        for i in 0..<count {
            let currL = usedData[0].dataPoints[i]
            let currR = usedData[1].dataPoints[i]
            
            let dx = (currL.x + currR.x) / 2 - self.barPosition.first!.x
            let dy = (currL.y + currR.y) / 2 - self.barPosition.first!.y
            
            // Angle from +Y axis (clockwise is positive)
            let angle = Angle2D.atan2(y: dy, x: dx)  // Standard angle from +X
            let angleFromY = angle + Angle2D(radians: .pi / 2)  // Rotate CCW to make 0 = +Y

            // Unwrap angle to avoid jumps at ±π
            let delta = angle - prevAngle
            let unwrappedDelta = Angle2D.atan2(y: sin(delta), x: cos(delta))
            accumulatedAngle += unwrappedDelta
            prevAngle = angle
            
            let angularVelocity = i > 0 ? (appState.angleUnit == .rad ? unwrappedDelta.radians : unwrappedDelta.degrees) / dt : 0.0
            turns = abs(accumulatedAngle.radians / (.pi * 2))
            
            resultsAngle.append(Point3D(x: Double(i), y: appState.angleUnit == .rad ? angleFromY.radians : angleFromY.degrees, z: 0.0))
            resultsVelocity.append(Point3D(x: Double(i), y: angularVelocity, z: 0.0))
        }
            
        // Compute Metrics Value
        _dataMetricsAngle = dataMetrics(
            minX: resultsAngle.map { $0.y }.min() ?? 0.0,
            maxX: resultsAngle.map { $0.y }.max() ?? 0.0,
            minY: turns,
            maxY: turns
        )
        
        _dataMetricsVel = dataMetrics(
            minX: resultsVelocity.map { $0.y }.min() ?? 0.0,
            maxX: resultsVelocity.map { $0.y }.max() ?? 0.0,
            minY: turns,
            maxY: turns
        )
        
        _dataMetricsTurn = dataMetrics(
            minX: floor(turns),
            maxX: turns,
            minY: 0.0,
            maxY: 0.0
        )
        
        self.swingData.append(JointData3D(joint: "Swing Angle",
                                          dataPoints: resultsAngle,
                                          dataMetrics: _dataMetricsAngle)
        )
        self.swingData.append(JointData3D(joint: "Swing Angle Velocity",
                                          dataPoints: resultsVelocity,
                                          dataMetrics: _dataMetricsVel)
        )
        self.swingData.append(JointData3D(joint: "Turns",
                                          dataPoints: [],
                                          dataMetrics: _dataMetricsTurn)
        )
    }
    
    // MARK: - Private Function Calls
    private func median(of array: [Double]) -> Double {
        let sorted = array.sorted()
        let count = sorted.count
        if count % 2 == 0 {
            return (sorted[count / 2 - 1] + sorted[count / 2]) / 2
        } else {
            return sorted[count / 2]
        }
    }
    
    private func fetchPositionData(useDepth: Bool, completion: @escaping (Bool) -> Void) {
        // Init Variable
        var positionFilters: [String: KF3DWrapper] = [:]
        var posData: [String: [Point3D]] = [:]
        var posInitialized: [String: Bool] = [:]
        
        // Result Variable
        var completePosData: [JointData3D] = []

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

                    var x: Double? = nil
                    var y: Double? = nil
                    var z: Double? = nil

                    if let keypoints = keypoints?.keypoints, keypoints.count == 17 {
                        if useDepth {
                            // To be implemented later
                            continue
                        } else {
                            let kp = keypoints[index]
                            x = kp.x
                            y = kp.y
                            z = Double(kp.depth)
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
                            posData[joint]!.append(Point3D(x: fx, y: fy, z: fz))
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
                completePosData.append(JointData3D(joint: joint,
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

        var completeVelData: [JointData3D] = []
        var completeAccData: [JointData3D] = []

        for jointData in positionCompleteData {
            let joint = jointData.joint
            let pos = jointData.dataPoints

            var velList: [Point3D] = [Point3D(x: 0.0, y: 0.0, z: 0.0)]
            var accList: [Point3D] = [Point3D(x: 0.0, y: 0.0, z: 0.0)]

            for i in 1..<pos.count {
                let vx = (pos[i].x - pos[i-1].x) / dt
                let vy = (pos[i].y - pos[i-1].y) / dt
                velList.append(Point3D(x: vx, y: vy, z: 0.0))
            }

            for i in 1..<velList.count {
                let ax = (velList[i].x - velList[i-1].x) / dt
                let ay = (velList[i].y - velList[i-1].x) / dt
                accList.append(Point3D(x: ax, y: ay, z: 0.0))
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
            
            completeVelData.append(JointData3D(joint: joint, dataPoints: velList, dataMetrics: metricsVel))
            completeAccData.append(JointData3D(joint: joint, dataPoints: accList, dataMetrics: metricsAcc))
        }
        
        // Publish
        self.velocityCompleteData = completeVelData
        self.accelerationCompleteData = completeAccData
    }

    private func buildAngles() {
        var angleData: [String: [Double]] = [:]
        var resultData: [JointData3D] = []

        // Prepare angle data buffer
        for joint in jointAngleLimits.keys {
            angleData[joint] = []
        }

        let frameCount = positionCompleteData.first?.dataPoints.count ?? 0

        // Get Keypoints Dictionary
        for frameIndex in 0..<frameCount {
            var keypointDict: [Int: Point3D] = [:]

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

            let chartData = angles.map { Point3D(x: $0, y: 0, z: 0) }
            resultData.append(JointData3D(joint: joint, dataPoints: chartData, dataMetrics: metrics))
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
    
    private func calculateAngleFromFrame(for joint: String, frame: [Int: Point3D]) -> Double {
        func get(_ i: Int) -> Point3D? {
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

    private func angleBetween(_ a: Point3D, _ b: Point3D, _ c: Point3D) -> Double {
        let ab = CGVector(dx: Double(a.x - b.x), dy: Double(a.y - b.y))
        let cb = CGVector(dx: Double(c.x - b.x), dy: Double(c.y - b.y))

        let dot = ab.dx * cb.dx + ab.dy * cb.dy
        let cross = ab.dx * cb.dy - ab.dy * cb.dx
        
        let angle = Angle2D.atan2(y: cross, x: dot)
        
        return appState.angleUnit == .rad ? angle.normalized.radians : angle.normalized.degrees
    }
}


// MARK: ------------------------------ Pose Joint Database Class END ------------------------------
