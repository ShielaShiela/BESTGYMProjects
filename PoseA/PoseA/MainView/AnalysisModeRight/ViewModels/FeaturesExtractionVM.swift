//
//  FeaturesVM.swift
//  PoseA
//
//  Created by Ardhika Maulidani on 4/16/26.
//

import Foundation
import CoreGraphics

private enum FeaturesConstants {
    // MARK: - Physical / Depth constants
    static let barRealLengthM:   Double = 2.80  // real-world bar length (m)
    static let depthBarsM:       Double = 8.30  // camera -> bar plane (m)
    static let depthKeypointsM:  Double = 9.50  // camera -> athlete plane (m)
}


// MARK: - Private intermediate type (pixel-space, one body side)
private struct SideRaw {
    var armActualPx:           Double
    var armRestPx:             Double
    var upperArmPx:            Double
    var forearmPx:             Double
    var armSpringDeflectionPx: Double
    var torsoLenPx:            Double
    var thighLenPx:            Double
    var lowerLegLenPx:         Double
    var vArmAngle:             Double
    var vTorsoAngle:           Double
    var vThighAngle:           Double
    var vLowerLegAngle:        Double
    var shoulderAngle:         Double
    var hipAngle:              Double
    var kneeAngle:             Double
    var wriPx:                 CGPoint
}

@Observable
class FeaturesExtractionVM {
    // MARK: - Properties
    private var mediaManager: MediaManagerVM
    
    // MARK: - Output Variable
    private var processedFeatures: [Int: FeaturesModel] = [:]
    private var processedScale: Double = 0.0
    
    private var dt: Double {
        return 1.0 / self.mediaManager.fps
    }
    init(mediaManager: MediaManagerVM) {
        self.mediaManager = mediaManager
    }
    
    func buildFeatures() async throws {
        let frameCount = mediaManager.importFileVM.FrameImageURLs.count
        guard frameCount > 0 else {
            throw PipelineError.insufficientData(reason: "No frames found in import file")
        }

        guard
            let barTop    = mediaManager.BarReferenceData[0],
            let barBottom = mediaManager.BarReferenceData[1]
        else {
            throw PipelineError.insufficientData(reason: "Bar reference points are missing")
        }

        let scale = scalePxMeter(barTopPx: barTop, barBottomPx: barBottom)
        self.processedScale = scale

        var features: [FeaturesModel] = []

        for i in 0..<frameCount {
            guard
                let kp_detection  = mediaManager.getKeypointsByIndex(i),
                let com_detection = mediaManager.getCoMByIndex(i)
            else { continue }

            let kp = kp_detection.keypoints
            let headPx = self.computeHeadAvg(kp: kp)
            let left   = self.computeSide(kp: kp, isLeft: true)
            let right  = self.computeSide(kp: kp, isLeft: false)

            let frame = self.computeSegment(
                left: left,
                right: right,
                comPx: com_detection,
                headPx: headPx,
                scale: scale,
                barTopPx: barTop,
                barBottomPx: barBottom,
                frameIndex: i
            )
            features.append(frame)
        }

        self.computeOmega(frames: &features)

        for feature in features {
            processedFeatures[feature.frameIdx] = feature
        }

        await MainActor.run {
            mediaManager.updateFeaturesData(processedFeatures, source: .processing)
        }
    }

    // MARK: - Pixel-to-metre scale
    private func scalePxMeter(barTopPx: CGPoint, barBottomPx: CGPoint) -> Double {
        let pxLength    = barTopPx.distance(to: barBottomPx)
        let scaleAtBars = pxLength / FeaturesConstants.barRealLengthM
        let scaleAtKp   = scaleAtBars * (FeaturesConstants.depthBarsM / FeaturesConstants.depthKeypointsM)
        return scaleAtKp
    }

    // MARK: - Head position
    private func computeHeadAvg(kp: [KeypointData]) -> CGPoint {
        // Use the average of all detected head keypoints (nose, left_eye, right_eye, left_ear, right_ear).
        let headIndices = [0, 1, 2, 3, 4]

        var pts: [(Double, Double)] = []
        for idx in headIndices {
            pts.append((kp[idx].x, kp[idx].y))
        }
        
        guard !pts.isEmpty else { return .zero }

        let sumX = pts.map(\.0).reduce(0, +)
        let sumY = pts.map(\.1).reduce(0, +)
        return CGPoint(x: sumX / Double(pts.count), y: sumY / Double(pts.count))
    }

    // MARK: - Per-side raw computation (pixel space)
    private func computeSide(kp: [KeypointData], isLeft: Bool) -> SideRaw {
        func v(_ idx: Int) -> CGPoint {
            return CGPoint(x: kp[idx].x, y: kp[idx].y)
        }

        let wri = v(isLeft ? 9  : 10)
        let elb = v(isLeft ? 7  : 8)
        let sho = v(isLeft ? 5  : 6)
        let hip = v(isLeft ? 11 : 12)
        let kne = v(isLeft ? 13 : 14)
        let ank = v(isLeft ? 15 : 16)

        // 4 segment vectors
        let vArm      = wri.sub(sho)  // shoulder → wrist  (effective arm bar)
        let vTorso    = hip.sub(sho)  // shoulder → hip
        let vThigh    = kne.sub(hip)  // hip      → knee
        let vLowerLeg = ank.sub(kne)  // knee     → ankle

        // Rigid segment lengths (pixels)
        let upperArmPx  = (elb.sub(sho)).magnitude()
        let forearmPx   = (wri.sub(elb)).magnitude()
        let armActualPx = vArm.magnitude()
        let armRestPx   = upperArmPx + forearmPx

        // Arm spring: positive when elbow is flexed/compressed
        let armSpringPx = armRestPx - armActualPx

        // Absolute segment orientations (degrees from +X axis)
        let vArmAng      = vArm.angle()
        let vTorsoAng    = vTorso.angle()
        let vThighAng    = vThigh.angle()
        let vLowerLegAng = vLowerLeg.angle()

        // shoulder: angle between arm bar and torso bar, measured at shoulder
        let shoulderAng = jointAngleDeg(v1: vArm, v2: vTorso)
        // hip: angle between torso bar and thigh bar, measured at hip
        let hipAng      = jointAngleDeg(v1: vTorso.scale(-1), v2: vThigh)
        // knee: angle between thigh bar and lower-leg bar, measured at knee
        let kneeAng     = jointAngleDeg(v1: vThigh.scale(-1), v2: vLowerLeg)

        return SideRaw(
            armActualPx:           armActualPx,
            armRestPx:             armRestPx,
            upperArmPx:            upperArmPx,
            forearmPx:             forearmPx,
            armSpringDeflectionPx: armSpringPx,
            torsoLenPx:            vTorso.magnitude(),
            thighLenPx:            vThigh.magnitude(),
            lowerLegLenPx:         vLowerLeg.magnitude(),
            vArmAngle:              vArmAng,
            vTorsoAngle:            vTorsoAng,
            vThighAngle:            vThighAng,
            vLowerLegAngle:         vLowerLegAng,
            shoulderAngle:         shoulderAng,
            hipAngle:              hipAng,
            kneeAngle:             kneeAng,
            wriPx:                 CGPoint(x: wri.x, y: wri.y)
        )
    }

    // MARK: - Merge both sides and convert to metres
    private func computeSegment(left: SideRaw,
                                right: SideRaw,
                                comPx: CGPoint,
                                headPx: CGPoint,
                                scale: Double,
                                barTopPx: CGPoint,
                                barBottomPx: CGPoint,
                                frameIndex: Int) -> FeaturesModel {
        
        // Helper: average a pixel length from both sides and convert to metres
        func asc(_ lPx: Double, _ rPx: Double) -> Double {
            ((lPx + rPx) / 2.0) / scale
        }

        // Bar-bending spring: avg wrist pixel → bar top pixel, converted to metres
        let avgWriX = (Double(left.wriPx.x) + Double(right.wriPx.x)) / 2.0
        let avgWriY = (Double(left.wriPx.y) + Double(right.wriPx.y)) / 2.0
        let dwx = avgWriX - Double(barTopPx.x)
        let dwy = avgWriY - Double(barTopPx.y)
        let barSpringLenM = sqrt(dwx * dwx + dwy * dwy) / scale

        // CoM angle relative to bar top
        // 0° = directly above bar, 90° = right, 180° = below, 270° = left
        let barToComX = (Double(comPx.x) - Double(barTopPx.x)) / scale
        let barToComY = (Double(comPx.y) - Double(barTopPx.y)) / scale
        let comAngle = mod360(atan2(barToComX, -barToComY) * 180.0 / .pi)
        let comAngleWrapped = comAngle < 0 ? comAngle + 360.0 : comAngle

        // Head height relative to bar top (positive = head above bar)
        // image Y grows downward: (head_y - bar_top_y) / scale * -1
        let headHeightM = (Double(headPx.y) - Double(barTopPx.y)) / scale * -1.0

        let frame = FeaturesModel(frameIdx: frameIndex,
                                  topBarPx: barTopPx,
                                  bottomBarPx: barBottomPx,
                                  // Lengths
                                  armActualLenM: asc(left.armActualPx, right.armActualPx),
                                  armRestLenM: asc(left.armRestPx, right.armRestPx),
                                  upperArmLenM: asc(left.upperArmPx, right.upperArmPx),
                                  forearmLenM: asc(left.forearmPx, right.forearmPx),
                                  torsoLenM: asc(left.torsoLenPx, right.torsoLenPx),
                                  thighLenM: asc(left.thighLenPx, right.thighLenPx),
                                  lowerLegLenM: asc(left.lowerLegLenPx, right.lowerLegLenPx),
                                  armSpringDeflectionM: asc(left.armSpringDeflectionPx, right.armSpringDeflectionPx),
                                  barSpringLenM: barSpringLenM,
                                  // Angles
                                  vArmAngle: avgAngle(left.vArmAngle, right.vArmAngle),
                                  vTorsoAngle: avgAngle(left.vTorsoAngle, right.vTorsoAngle),
                                  vThighAngle: avgAngle(left.vThighAngle, right.vThighAngle),
                                  vLowerLegAngle: avgAngle(left.vLowerLegAngle, right.vLowerLegAngle),
                                  shoulderAngle: avgAngle(left.shoulderAngle, right.shoulderAngle),
                                  hipAngle: avgAngle(left.hipAngle, right.hipAngle),
                                  kneeAngle: avgAngle(left.kneeAngle, right.kneeAngle),
                                  comAngle: comAngleWrapped,
                                  headHeightM: headHeightM)

        return frame
    }

    // MARK: - Angular velocities (central finite differences)
    // Uses the same wrap-aware delta: d = (next - prev + 180) % 360 - 180
    // then vel = d / (2 * dt)

    private func computeOmega(frames: inout [FeaturesModel]) {
        let n  = frames.count

        typealias AngleGetter = (FeaturesModel) -> Double
        typealias VelSetter   = (inout FeaturesModel, Double?) -> Void

        let pairs: [(AngleGetter, VelSetter)] = [
            ({ $0.vArmAngle },      { $0.vArmAngleVel      = $1 }),
            ({ $0.vTorsoAngle },    { $0.vTorsoAngleVel    = $1 }),
            ({ $0.vThighAngle },    { $0.vThighAngleVel    = $1 }),
            ({ $0.vLowerLegAngle }, { $0.vLowerLegAngleVel = $1 }),
            ({ $0.shoulderAngle }, { $0.shoulderAngleVel = $1 }),
            ({ $0.hipAngle },      { $0.hipAngleVel      = $1 }),
            ({ $0.kneeAngle },     { $0.kneeAngleVel     = $1 }),
        ]

        for i in 0..<n {
            for (get, set) in pairs {
                // Boundaries always get nil
                if i == 0 || i == n - 1 {
                    set(&frames[i], nil)
                    continue
                }
                let prev = frames[i - 1]
                let next = frames[i + 1]

                // Wrap-aware delta: (next - prev + 180) % 360 - 180
                let d = mod360((get(next) - get(prev)) + 180.0) - 180.0
                set(&frames[i], d / (2.0 * self.dt))
            }
        }
    }

    // MARK: - Calculation helper
    private func median(of array: [Double]) -> Double {
        let sorted = array.sorted()
        let count = sorted.count
        if count % 2 == 0 {
            return (sorted[count / 2 - 1] + sorted[count / 2]) / 2
        } else {
            return sorted[count / 2]
        }
    }
    
    // Signed angle FROM v1 TO v2 (CCW positive)
    private func jointAngleDeg(v1: CGPoint, v2: CGPoint) -> Double {
        let cross = v1.cross(v2)
        let dot   = v1.dot(v2)
        return atan2(cross, dot) * 180.0 / .pi
    }
    
    // Non-negative modulo, matching Python's % behaviour for positive divisor
    private func mod360(_ x: Double) -> Double {
        let r = x.truncatingRemainder(dividingBy: 360.0)
        return r < 0 ? r + 360.0 : r
    }
    
    // Average two angles accounting for wrap-around
    private func avgAngle(_ a: Double, _ b: Double) -> Double {
        let diff = mod360(b - a + 180.0) - 180.0
        return mod360(a + diff / 2.0)
    }
}

// MARK: - Features Export Extension
extension FeaturesExtractionVM {
    func exportFeatures(to fileURL: URL) throws {
        let featuresData = mediaManager.FeaturesData
        guard !featuresData.isEmpty else {
            throw ExportImportError.invalidFormat
        }
        
        try ExportImportManager.exportFeatures(
            featuresData: featuresData,
            scalePxPerM: processedScale,
            to: fileURL
        )
    }
}
