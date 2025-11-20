//
//  RealtimePoseJointVM.swift
//  PoseA
//
//  Created by Ardhika Maulidani on 8/28/25.
//

import Spatial
import SwiftUI
import Combine
import simd

@Observable
class RealtimePoseJointViewModel {
    // MARK: - Core State
    var cameraManager: CameraManagerVM
    var appState: MainAppState
    
    private var cancellables: Set<AnyCancellable> = []

    // History (only last N frames kept)
    private let maxHistory = 90 // Keep 3 seconds data alive
    private var poseHistory: [PoseBox?] = []
    
    // Chart state
    var nearestPose: PoseBox?
    var barPoints: Point3D? = nil
    
    var chartData: [ChartData2D] = []
    var chartData3D: [ChartData3D] = []
    
    var isAthleteBar: Bool = false
    var distToBar: Double? = nil
    
    // Internal joint buffers
    private var jointBuffers: [String: [Point3D]] = [:]
    private var positionFilters: [String: KF3DWrapper] = [:]
    private var posInitialized: [String: Bool] = [:]
    
    private var wristHistory: [Bool] = []
    private let maxSpikeFrames = 5
    
    // Background queue for filtering
    private let processingQueue = DispatchQueue(label: "com.posea.processing", qos: .userInitiated)
    private let bufferQueue = DispatchQueue(label: "com.posea.jointBuffers", qos: .userInitiated)

    // Timer to throttle chart updates
    private var chartUpdateTimer: DispatchSourceTimer?
    
    var latched: Bool = false
    private var prevAthleteBar: Bool = false
    
    // DEBUG MODE
    var debugMode: Bool = true
    
    // MARK: - Init
    init(cameraManager: CameraManagerVM, appState: MainAppState) {
        self.cameraManager = cameraManager
        self.appState = appState
        availableJoints.forEach {
            positionFilters[$0] = KF3DWrapper(dt: 1.0 / 30) // 30fps assumption
            jointBuffers[$0] = []
            posInitialized[$0] = false
        }
        startChartUpdates()
        
        // Subscribe to pose updates automatically
        cameraManager.$poseKeypoints
            .receive(on: DispatchQueue.main)
            .sink { [weak self] _ in
                guard let self else { return }
                self.getNearPose()
            }
            .store(in: &cancellables)
    }
    
    deinit {
        chartUpdateTimer?.cancel()
    }
    
    // MARK: - Public Entry Point
    func updatePoint(point: CGPoint?) {
        guard let point = point else {
            self.barPoints = nil
            return
        }
        
        // Update to Class Variable
        var Z_BAR: Float = 8.30 // default z
        if !debugMode && (self.cameraManager.isLiDARSupported && self.cameraManager.isLiDAREnabled) {
            // Get Bar Depth
            Z_BAR = self.cameraManager.getPointDepth(x: point.x, y: point.y) ?? 8.30
            log("Depth at Bar Point: \(String(format: "%.2f", Z_BAR)) m", level: .debug)
        }
        self.barPoints = self.camToWorldTransform(x: point.x, y: point.y, z: Double(Z_BAR))
    }
    
    private func getNearPose() {
        guard let point = self.barPoints else {
            nearestPose = nil
            return
        }
        
        if self.cameraManager.poseKeypoints.isEmpty {
            nearestPose = nil
            appendPose(nil)
            return
        }

        // Pick nearest pose
        nearestPose = self.cameraManager.poseKeypoints.min(by: { lhs, rhs in
            let lhsCenter = CGPoint(x: lhs.bbox.midX, y: lhs.bbox.midY)
            let rhsCenter = CGPoint(x: rhs.bbox.midX, y: rhs.bbox.midY)
            let lhsDist = hypot(lhsCenter.x - CGFloat(point.x), lhsCenter.y - CGFloat(point.y))
            let rhsDist = hypot(rhsCenter.x - CGFloat(point.x), rhsCenter.y - CGFloat(point.y))
            return lhsDist < rhsDist
        })
        if let pose = nearestPose {
            appendPose(pose)
            
            // Process incrementally in background
            processingQueue.async { [weak self] in
                self?.processPose(pose)
            }
        }
    }
    
    // MARK: - Pose History Management
    private func appendPose(_ pose: PoseBox?) {
        poseHistory.append(pose)
        if poseHistory.count > maxHistory {
            poseHistory.removeFirst()
        }
    }
    
    private func camToWorldTransform(x: Double, y: Double, z: Double) -> Point3D {
        // Prepare Intrinsic
        let camIntrinsics = self.cameraManager.camIntrinsics
        let cu = Double(camIntrinsics[2, 0])
        let cv = Double(camIntrinsics[2, 1])
        let fu = Double(camIntrinsics[0, 0])
        let fv = Double(camIntrinsics[1, 1])
        
        // Assume Camera is Pinhole
        let _x = (x - cu) * z / fu
        let _y = (y - cv) * z / fv

        return Point3D(x: Double(_x), y: Double(_y), z: Double(z))
    }
    
    // MARK: - Pose Processing
    private func processPose(_ pose: PoseBox) {
//        let start = CFAbsoluteTimeGetCurrent()

        // Prepare temporary storage on background thread
        guard let barPoint = self.barPoints else { return }
        var newJointData: [String: Point3D] = [:]
        
        for joint in availableJoints {
            let index = jointIndex(for: joint)
            guard pose.keypoints.count == 17 else { continue }

            let kp = pose.keypoints[index]
            
            // Depth
            var Z_ATHLETE: Float = 9.60 // m
            if !debugMode || (self.cameraManager.isLiDARSupported && self.cameraManager.isLiDAREnabled) {
                Z_ATHLETE = kp.depth
            }
            let points = self.camToWorldTransform(x: Double(kp.x), y: Double(kp.y), z: Double(Z_ATHLETE))

            // Initialize filter once
            if !posInitialized[joint]!, kp.confidence > 0.3 {
                positionFilters[joint]?.reset(x: points.x, y: points.y, z: points.z)
                posInitialized[joint] = true
            }

            // Update filter
            if posInitialized[joint]! {
                positionFilters[joint]?.update(x: points.x, y: points.y, z: points.z)
                if let (fx, fy, fz) = positionFilters[joint]!.getFilteredPosition() {
                    newJointData[joint] = Point3D(x: fx, y: fy, z: fz)
                }
            }
        }
  
        // Compute Center Point if exist
        if let lHip = newJointData["L Hip"], let rHip = newJointData["R Hip"] {
            let cx = (lHip.x + rHip.x) / 2
            let cy = (lHip.y + rHip.y) / 2
            let cz = (lHip.z + rHip.z) / 2
            newJointData["Center Hip"] = Point3D(x: cx, y: cy, z: cz)
        }
        
        // Compute Hip Angle if barPoints exist
        if let centerHip = newJointData["Center Hip"] {
            let hipPoint = Point3D(x: centerHip.x, y: centerHip.y, z: centerHip.z)
            let angle = polarAngle(center: barPoint, outer: hipPoint)
            newJointData["Hip Angle"] = Point3D(x: angle, y: 0, z: 0)
        }
        
        // Compute Fly Dist
        if prevAthleteBar == true && isAthleteBar == false {
            latched = true   // trigger A
        }
        
        // Reset latch when back on
        if isAthleteBar == true {
            latched = false
        }
        
        prevAthleteBar = isAthleteBar
        
        if let cHip = newJointData["Center Hip"] {
            if latched {
                let dist = cHip.distance(to: barPoint)
                DispatchQueue.main.async { [weak self] in
                    self?.distToBar = dist
                }
            } else {
                DispatchQueue.main.async { [weak self] in
                    self?.distToBar = nil
                }
            }
        }

        // Update Atlhete Bar
        if let lWrist = newJointData["L Wrist"], let rWrist = newJointData["R Wrist"] {
            let near = isWristNearBar(leftWrist: lWrist, rightWrist: rWrist, bar: barPoint)
            DispatchQueue.main.async { [weak self] in
                self?.updateIsAthleteBar(current: near)
            }
        }

        // Now append all newJointData safely on main thread
        DispatchQueue.main.async { [weak self] in
            guard let self = self else { return }

            for (joint, data) in newJointData {
                if self.jointBuffers[joint] == nil {
                    self.jointBuffers[joint] = []
                }
                self.jointBuffers[joint]!.append(data)
                if self.jointBuffers[joint]!.count > self.maxHistory {
                    self.jointBuffers[joint]!.removeFirst()
                }
            }
        }
        
//        let diff = (CFAbsoluteTimeGetCurrent() - start) * 1000
//        print("⏱ process time: \(String(format: "%.2f", diff)) ms")
    }
    
    // MARK: - Chart Updates
    private func startChartUpdates() {
        chartUpdateTimer = DispatchSource.makeTimerSource(queue: .main)
        chartUpdateTimer?.schedule(deadline: .now(),
                                   repeating: 0.05) // 20 fps
        chartUpdateTimer?.setEventHandler { [weak self] in
            self?.publishChartData()
            if #available(iOS 26, *) { self?.publishChartData3D() }
        }
        chartUpdateTimer?.resume()
    }
    
    private func publishChartData() {
        bufferQueue.sync { [weak self] in
            guard let self = self else { return }
            let jointsToShow = ["Hip Angle"] // configurable
            
            self.chartData = jointsToShow.compactMap { joint in
                guard let buffer = self.jointBuffers[joint], !buffer.isEmpty else { return nil }
                let points = buffer.enumerated().map { idx, pt in
                    Point2D(x: Double(idx), y: Double(pt.x))
                }
                return ChartData2D(
                    joint: joint,
                    dataPoints: points,
                    dataMetrics: self.calculateDataMetrics(from: points)
                )
            }
        }
    }
    
    // MARK: - Publish 3D Chart Data
    private func publishChartData3D() {
        bufferQueue.sync { [weak self] in
            guard let self = self else { return }

            let jointsToShow = availableJoints // or subset ["L Wrist","R Wrist","L Hip","R Hip"]
            var newData3D: [ChartData3D] = []

            for joint in jointsToShow {
                guard let buffer = self.jointBuffers[joint], !buffer.isEmpty else { continue }

                // Map xyzChartData → PointData3D
                let points = ChartPoint3D(buffer.first!)
                newData3D.append(ChartData3D(joint: joint, dataPoints: points))
            }

            DispatchQueue.main.async { [weak self] in
                self?.chartData3D = newData3D
            }
        }
    }


    private func calculateDataMetrics(from dataPoints: [Point2D]) -> dataMetrics {
        let xs = dataPoints.map { $0.x }
        let ys = dataPoints.map { $0.y }
        return dataMetrics(
            minX: (xs.min() ?? 0),
            maxX: (xs.max() ?? 0),
            minY: (ys.min() ?? 0),
            maxY: (ys.max() ?? 0)
        )
    }
    
    // MARK: - Helpers
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
    
    private func polarAngle(center: Point3D, outer: Point3D) -> Double {
        let d = outer - center
        let angle = Angle2D.atan2(y: d.y, x: d.x)
        
        return appState.angleUnit == .rad ? angle.radians : angle.degrees
    }
    
    private func isWristNearBar(leftWrist: Point3D, rightWrist: Point3D, bar: Point3D, threshold: CGFloat = 0.3) -> Bool {
        let lDistance = leftWrist.distance(to: bar)
        let rDistance = rightWrist.distance(to: bar)
        
        return rDistance <= threshold || lDistance <= threshold
    }

    private func updateIsAthleteBar(current: Bool) {
        wristHistory.append(current)
        if wristHistory.count > maxSpikeFrames {
            wristHistory.removeFirst()
        }
        
        // Only update if majority agrees
        let trueCount = wristHistory.filter { $0 }.count
        let majority = (wristHistory.count + 1) / 2
        isAthleteBar = trueCount >= majority
    }
}

extension Float16 {
    func toFloat32() -> Float {
        return Float(self)
    }
}
