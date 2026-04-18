//
//  CoMLevaModel.swift
//  PoseA
//
//  Created by Ardhika Maulidani on 4/14/26.
//

import Foundation

// MARK: - Center of Mass Calculator (De Leva anthropometric data)
struct CoMLevaModel {
    private static let segmentDensities: [String: Double] = [
        "head": 1.11, "torso": 0.92, "upper_arm": 1.07, "forearm": 1.13,
        "hand": 1.16, "thigh": 1.05, "shank": 1.09, "foot": 1.10
    ]
    private static let segmentK: [String: Double] = [
        "head": 0.4024, "torso": 0.4486, "upper_arm": 0.5772, "forearm": 0.4574,
        "hand": 0.79,   "thigh": 0.4095, "shank":    0.4459,  "foot":   0.5
    ]
    private static let deLevaSH: [String: Double] = [
        "head": 0.1308, "torso": 0.3000, "upper_arm": 0.1720, "forearm": 0.1570,
        "hand": 0.1088, "thigh": 0.2323, "shank":    0.2472,  "foot":   0.1523
    ]
    private static let headToTorso   = deLevaSH["head"]! / deLevaSH["torso"]!
    private static let handToForearm = deLevaSH["hand"]! / deLevaSH["forearm"]!
    private static let footToShank   = deLevaSH["foot"]! / deLevaSH["shank"]!

    static func computePlanarCoM(keypoints: [KeypointData], side: String = "left") -> CGPoint {

        // ── Step 1: resolve joints ─────────────────────────────────────────────
        func getKeypoint(name: String) -> (x: Double, y: Double)? {
            guard let kp = keypoints.first(where: { $0.name == name }) else {
                return nil
            }
            let pos = kp.position
            return (Double(pos.x), Double(pos.y))
        }

        let s = (side == "left") ? 0 : 1
        guard
            let nose     = getKeypoint(name: "nose"),
            let shoulder = getKeypoint(name: s == 0 ? "left_shoulder"  : "right_shoulder"),
            let elbow    = getKeypoint(name: s == 0 ? "left_elbow"     : "right_elbow"),
            let wrist    = getKeypoint(name: s == 0 ? "left_wrist"     : "right_wrist"),
            let hip      = getKeypoint(name: s == 0 ? "left_hip"       : "right_hip"),
            let knee     = getKeypoint(name: s == 0 ? "left_knee"      : "right_knee"),
            let ankle    = getKeypoint(name: s == 0 ? "left_ankle"     : "right_ankle")
        else {
            return .zero
        }

        // ── Step 2: derived endpoints ──────────────────────────────────────────
        let torsoVecX = shoulder.x - hip.x
        let torsoVecY = shoulder.y - hip.y
        let torsoLen  = (torsoVecX * torsoVecX + torsoVecY * torsoVecY).squareRoot()

        let headTopX: Double, headTopY: Double
        if torsoLen > 1e-6 {
            let headLen = torsoLen * headToTorso
            headTopX = nose.x + (torsoVecX / torsoLen) * headLen
            headTopY = nose.y + (torsoVecY / torsoLen) * headLen
        } else { headTopX = nose.x; headTopY = nose.y - 50.0 }

        let forearmVecX = wrist.x - elbow.x
        let forearmVecY = wrist.y - elbow.y
        let forearmLen  = (forearmVecX * forearmVecX + forearmVecY * forearmVecY).squareRoot()
        let fingertipX: Double, fingertipY: Double
        if forearmLen > 1e-6 {
            fingertipX = wrist.x + (forearmVecX / forearmLen) * forearmLen * handToForearm
            fingertipY = wrist.y + (forearmVecY / forearmLen) * forearmLen * handToForearm
        } else { fingertipX = wrist.x + 20.0; fingertipY = wrist.y }

        let shankVecX = ankle.x - knee.x
        let shankVecY = ankle.y - knee.y
        let shankLen  = (shankVecX * shankVecX + shankVecY * shankVecY).squareRoot()
        let toeX: Double, toeY: Double
        if shankLen > 1e-6 {
            toeX = ankle.x + (shankVecX / shankLen) * shankLen * footToShank
            toeY = ankle.y + (shankVecY / shankLen) * shankLen * footToShank
        } else { toeX = ankle.x + 20.0; toeY = ankle.y }

        // ── Step 3: mass-weighted sum (pure Double) ────────────────────────────
        let segments: [(String, Double, Double, Double, Double)] = [
            ("head",      nose.x,     nose.y,     headTopX,   headTopY),
            ("torso",     shoulder.x, shoulder.y, hip.x,      hip.y),
            ("upper_arm", shoulder.x, shoulder.y, elbow.x,    elbow.y),
            ("forearm",   elbow.x,    elbow.y,    wrist.x,    wrist.y),
            ("hand",      wrist.x,    wrist.y,    fingertipX, fingertipY),
            ("thigh",     hip.x,      hip.y,      knee.x,     knee.y),
            ("shank",     knee.x,     knee.y,     ankle.x,    ankle.y),
            ("foot",      ankle.x,    ankle.y,    toeX,       toeY)
        ]

        var comSumX: Double = 0.0
        var comSumY: Double = 0.0
        var massSum: Double = 0.0

        for (name, p1x, p1y, p2x, p2y) in segments {
            let k       = segmentK[name]!
            let segComX = p1x + k * (p2x - p1x)
            let segComY = p1y + k * (p2y - p1y)
            let dx      = p2x - p1x
            let dy      = p2y - p1y
            let length  = (dx * dx + dy * dy).squareRoot() + 1e-6
            var mass    = segmentDensities[name]! * length
            if name != "torso" && name != "head" { mass *= 2.0 }

            comSumX += segComX * mass
            comSumY += segComY * mass
            massSum += mass

        }

        let result = CGPoint(x: comSumX / massSum, y: comSumY / massSum)
        return result
    }
}
