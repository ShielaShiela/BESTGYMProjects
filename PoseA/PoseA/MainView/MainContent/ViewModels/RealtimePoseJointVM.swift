//
//  RealtimePoseJointVM.swift
//  PoseA
//
//  Created by Ardhika Maulidani on 8/28/25.
//

import SwiftUI
import Combine
import simd

@Observable
class RealtimePoseJointViewModel {
    // MARK: - Core State
    var cameraManager: CameraManagerVM
    private var cancellables: Set<AnyCancellable> = []

    // History (only last N frames kept)
    private let maxHistory = 90 // Keep 3 seconds data alive
    private var poseHistory: [PoseBox?] = []
    
    // Chart state
    var nearestPose: PoseBox?
    var barPoints: CGPoint? = nil
    
    var chartData: [ChartData] = []
    var isAthleteBar: Bool = false
    var distToBar: CGFloat? = nil
    
    // Internal joint buffers
    private var jointBuffers: [String: [xyzChartData]] = [:]
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
    
    // MARK: - Init
    init(cameraManager: CameraManagerVM) {
        self.cameraManager = cameraManager
        
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
        self.barPoints = point
        
        // Get Depth if Available
        if self.cameraManager.isLiDARSupported && self.cameraManager.isLiDAREnabled {
            self.getPointDepth()
        }
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
            let lhsDist = hypot(lhsCenter.x - point.x, lhsCenter.y - point.y)
            let rhsDist = hypot(rhsCenter.x - point.x, rhsCenter.y - point.y)
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
    
    // MARK: - Pose Processing
    private func processPose(_ pose: PoseBox) {
//        let start = CFAbsoluteTimeGetCurrent()

        // Prepare temporary storage on background thread
        var newJointData: [String: xyzChartData] = [:]

        // Prepare Intrinsic
        let camIntrinsics = self.cameraManager.camIntrinsics
        let cu = camIntrinsics[2, 0]
        let cv = camIntrinsics[2, 1]
        let fu = camIntrinsics[0, 0]
        let fv = camIntrinsics[1, 1]
        
        // Dummy Depth
        let Z_BAR: Float = 8.30 // m
        let Z_ATHLETE: Float = Z_BAR + 1.3 // m
         
        // Assume Camera is Pinhole
        let _x = (Float(self.barPoints!.x) - cu) * Z_BAR / fu
        let _y = (Float(self.barPoints!.y) - cv) * Z_BAR / fv
        let barPoint = CGPoint(x: CGFloat(_x), y: CGFloat(_y))
        
        for joint in availableJoints {
            let index = jointIndex(for: joint)
            guard pose.keypoints.count == 17 else { continue }
            let kp = pose.keypoints[index]

            
            // Assume Camera is Pinhole
            let x = (Float(kp.x) - cu) * Z_ATHLETE / fu
            let y = (Float(kp.y) - cv) * Z_ATHLETE / fv
            let z = Float(kp.depth)

            // Initialize filter once
            if !posInitialized[joint]!, kp.confidence > 0.3 {
                positionFilters[joint]?.reset(x: x, y: y, z: z)
                posInitialized[joint] = true
            }

            // Update filter
            if posInitialized[joint]! {
                positionFilters[joint]?.update(x: x, y: y, z: z)
                if let (fx, fy, fz) = positionFilters[joint]!.getFilteredPosition() {
                    newJointData[joint] = xyzChartData(x: fx, y: fy, z: fz)
                }
            }
        }
  
        // Compute Center Point if exist
        if let lHip = newJointData["L Hip"], let rHip = newJointData["R Hip"] {
            let cx = (lHip.x + rHip.x) / 2
            let cy = (lHip.y + rHip.y) / 2
            let cz = (lHip.z + rHip.z) / 2
            newJointData["Center Hip"] = xyzChartData(x: cx, y: cy, z: cz)
        }
        
        // Compute Hip Angle if barPoints exist
        if let centerHip = newJointData["Center Hip"] {
            let hipPoint = CGPoint(x: CGFloat(centerHip.x), y: CGFloat(centerHip.y))
            let angle = polarAngle(center: barPoint, outer: hipPoint)
            newJointData["Hip Angle"] = xyzChartData(x: Float(angle), y: 0, z: 0)
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
                let dist = getAthletetoBar(refPoint: cHip, bar: barPoint)
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
                    PointData(x: Double(idx), y: Double(pt.x))
                }
                return ChartData(
                    joint: joint,
                    dataPoints: points,
                    dataMetrics: self.calculateDataMetrics(from: points)
                )
            }
        }
    }
    
    private func calculateDataMetrics(from dataPoints: [PointData]) -> dataMetrics {
        let xs = dataPoints.map { $0.x }
        let ys = dataPoints.map { $0.y }
        return dataMetrics(
            minX: Float(xs.min() ?? 0),
            maxX: Float(xs.max() ?? 0),
            minY: Float(ys.min() ?? 0),
            maxY: Float(ys.max() ?? 0)
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
    
    private func polarAngle(center: CGPoint, outer: CGPoint) -> CGFloat {
        let dx = outer.x - center.x
        let dy = outer.y - center.y
        
        var angle = atan2(dy, dx)
        let sinAngle = sin(angle)
        
        if angle < 0 {
            angle += 2 * .pi // normalize to 0–2pi
        }
//        return angle  * 180 / .pi
        return sinAngle
    }
    
    private func isWristNearBar(leftWrist: xyzChartData, rightWrist: xyzChartData, bar: CGPoint, threshold: CGFloat = 0.3) -> Bool {
        let lWristPoint = CGPoint(x: CGFloat(leftWrist.x), y: CGFloat(leftWrist.y))
        let rWristPoint = CGPoint(x: CGFloat(rightWrist.x), y: CGFloat(rightWrist.y))
        
        let lDistance = hypot(lWristPoint.x - bar.x, lWristPoint.y - bar.y)
        let rDistance = hypot(rWristPoint.x - bar.x, rWristPoint.y - bar.y)
        
        return rDistance <= threshold || lDistance <= threshold
    }
    
    private func getAthletetoBar(refPoint: xyzChartData, bar: CGPoint) -> CGFloat {
        let refPoint = CGPoint(x: CGFloat(refPoint.x), y: CGFloat(refPoint.y))
        let dist = hypot(refPoint.x - bar.x, refPoint.y - bar.y)
        return dist
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
    
    private func getPointDepth() {
        guard let point = self.barPoints else {
            return
        }
        
        // Access Depth Map
        guard let depthBuffer = self.cameraManager.depthMap else { return }
        let depthWidth = CVPixelBufferGetWidth(depthBuffer)
        let depthHeight = CVPixelBufferGetHeight(depthBuffer)
        
        // Convert Point Image to Point Depth
        let depthX = Int(point.x / CGFloat(self.cameraManager.cameraConfiguration.resolution.width) * CGFloat(depthWidth))
        let depthY = Int(point.y / CGFloat(self.cameraManager.cameraConfiguration.resolution.width) * CGFloat(depthHeight))

        
        // Access Depth value
        CVPixelBufferLockBaseAddress(depthBuffer, .readOnly)

        if let baseAddress = CVPixelBufferGetBaseAddress(depthBuffer) {
            let rowBytes = CVPixelBufferGetBytesPerRow(depthBuffer)
            let float16Buffer = baseAddress.assumingMemoryBound(to: UInt16.self)

            // Depth is in Float16 (r16Float), so cast manually
            let index = depthY * (rowBytes / MemoryLayout<UInt16>.size) + depthX
            
            let depthValueInMeters = Float16(bitPattern: float16Buffer[index])
                .toFloat32() // helper needed
            print("Depth at (\(depthX),\(depthY)) ≈ \(depthValueInMeters) m")
        }

        CVPixelBufferUnlockBaseAddress(depthBuffer, .readOnly)

    }
}

extension Float16 {
    func toFloat32() -> Float {
        return Float(self)
    }
}
