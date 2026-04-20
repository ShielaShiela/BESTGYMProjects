//
//  FeaturesModel.swift
//  PoseA
//
//  Created by Ardhika Maulidani on 4/17/26.
//

import Foundation

struct FeaturesExportModel: Codable {
    var features:            [FeaturesModel]
    var scalePxPerM:         Double

    enum CodingKeys: String, CodingKey {
        case features
        case scalePxPerM = "scalePxPerM"
    }
}

struct FeaturesModel: Codable {
    // Frame Index
    var frameIdx: Int
    
    // Bar Points
    var topBarPx:            CGPoint
    var bottomBarPx:         CGPoint
    
    // Segment lengths (metres)
    var armActualLenM:        Double
    var armRestLenM:          Double
    var upperArmLenM:         Double
    var forearmLenM:          Double
    var torsoLenM:            Double
    var thighLenM:            Double
    var lowerLegLenM:         Double
    var armSpringDeflectionM: Double
    var barSpringLenM:        Double

    // Absolute segment orientations (degrees, from +X axis CCW)
    var vArmAngle:      Double
    var vTorsoAngle:    Double
    var vThighAngle:    Double
    var vLowerLegAngle: Double

    // Joint angles (degrees, signed CCW positive)
    var shoulderAngle: Double
    var hipAngle:      Double
    var kneeAngle:     Double

    // CoM angle
    var comAngle:    Double

    // Head height relative to bar top
    var headHeightM: Double

    // Angular velocities (deg/s)
    var vArmAngleVel:      Double?
    var vTorsoAngleVel:    Double?
    var vThighAngleVel:    Double?
    var vLowerLegAngleVel: Double?
    var shoulderAngleVel: Double?
    var hipAngleVel:      Double?
    var kneeAngleVel:     Double?

    enum CodingKeys: String, CodingKey {
        case frameIdx
        case topBarPx
        case bottomBarPx
        case armActualLenM
        case armRestLenM
        case upperArmLenM
        case forearmLenM
        case torsoLenM
        case thighLenM
        case lowerLegLenM
        case armSpringDeflectionM
        case barSpringLenM
        case vArmAngle
        case vTorsoAngle
        case vThighAngle
        case vLowerLegAngle
        case shoulderAngle
        case hipAngle
        case kneeAngle
        case comAngle
        case headHeightM
        case vArmAngleVel
        case vTorsoAngleVel
        case vThighAngleVel
        case vLowerLegAngleVel
        case shoulderAngleVel
        case hipAngleVel
        case kneeAngleVel
    }
    
    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(frameIdx,             forKey: .frameIdx)
        try container.encode(["x": topBarPx.x, "y": topBarPx.y], forKey: .topBarPx)
        try container.encode(["x": bottomBarPx.x, "y": bottomBarPx.y], forKey: .bottomBarPx)
        try container.encode(armActualLenM,        forKey: .armActualLenM)
        try container.encode(armRestLenM,          forKey: .armRestLenM)
        try container.encode(upperArmLenM,         forKey: .upperArmLenM)
        try container.encode(forearmLenM,          forKey: .forearmLenM)
        try container.encode(torsoLenM,            forKey: .torsoLenM)
        try container.encode(thighLenM,            forKey: .thighLenM)
        try container.encode(lowerLegLenM,         forKey: .lowerLegLenM)
        try container.encode(armSpringDeflectionM, forKey: .armSpringDeflectionM)
        try container.encode(barSpringLenM,        forKey: .barSpringLenM)
        try container.encode(vArmAngle,             forKey: .vArmAngle)
        try container.encode(vTorsoAngle,           forKey: .vTorsoAngle)
        try container.encode(vThighAngle,           forKey: .vThighAngle)
        try container.encode(vLowerLegAngle,        forKey: .vLowerLegAngle)
        try container.encode(shoulderAngle,        forKey: .shoulderAngle)
        try container.encode(hipAngle,             forKey: .hipAngle)
        try container.encode(kneeAngle,            forKey: .kneeAngle)
        try container.encode(comAngle,             forKey: .comAngle)
        try container.encode(headHeightM,          forKey: .headHeightM)
        try container.encodeIfPresent(vArmAngleVel,      forKey: .vArmAngleVel)
        try container.encodeIfPresent(vTorsoAngleVel,    forKey: .vTorsoAngleVel)
        try container.encodeIfPresent(vThighAngleVel,    forKey: .vThighAngleVel)
        try container.encodeIfPresent(vLowerLegAngleVel, forKey: .vLowerLegAngleVel)
        try container.encodeIfPresent(shoulderAngleVel, forKey: .shoulderAngleVel)
        try container.encodeIfPresent(hipAngleVel,      forKey: .hipAngleVel)
        try container.encodeIfPresent(kneeAngleVel,     forKey: .kneeAngleVel)
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        frameIdx             = try container.decode(Int.self,    forKey: .frameIdx)
        let dictTop = try container.decode([String: Double].self, forKey: .topBarPx)
        topBarPx = CGPoint(x: dictTop["x"] ?? 0, y: dictTop["y"] ?? 0)
        let dictBottom = try container.decode([String: Double].self, forKey: .bottomBarPx)
        bottomBarPx = CGPoint(x: dictBottom["x"] ?? 0, y: dictBottom["y"] ?? 0)

        armActualLenM        = try container.decode(Double.self, forKey: .armActualLenM)
        armRestLenM          = try container.decode(Double.self, forKey: .armRestLenM)
        upperArmLenM         = try container.decode(Double.self, forKey: .upperArmLenM)
        forearmLenM          = try container.decode(Double.self, forKey: .forearmLenM)
        torsoLenM            = try container.decode(Double.self, forKey: .torsoLenM)
        thighLenM            = try container.decode(Double.self, forKey: .thighLenM)
        lowerLegLenM         = try container.decode(Double.self, forKey: .lowerLegLenM)
        armSpringDeflectionM = try container.decode(Double.self, forKey: .armSpringDeflectionM)
        barSpringLenM        = try container.decode(Double.self, forKey: .barSpringLenM)
        vArmAngle             = try container.decode(Double.self, forKey: .vArmAngle)
        vTorsoAngle           = try container.decode(Double.self, forKey: .vTorsoAngle)
        vThighAngle           = try container.decode(Double.self, forKey: .vThighAngle)
        vLowerLegAngle        = try container.decode(Double.self, forKey: .vLowerLegAngle)
        shoulderAngle        = try container.decode(Double.self, forKey: .shoulderAngle)
        hipAngle             = try container.decode(Double.self, forKey: .hipAngle)
        kneeAngle            = try container.decode(Double.self, forKey: .kneeAngle)
        comAngle             = try container.decode(Double.self, forKey: .comAngle)
        headHeightM          = try container.decode(Double.self, forKey: .headHeightM)
        vArmAngleVel          = try container.decodeIfPresent(Double.self, forKey: .vArmAngleVel)
        vTorsoAngleVel        = try container.decodeIfPresent(Double.self, forKey: .vTorsoAngleVel)
        vThighAngleVel        = try container.decodeIfPresent(Double.self, forKey: .vThighAngleVel)
        vLowerLegAngleVel     = try container.decodeIfPresent(Double.self, forKey: .vLowerLegAngleVel)
        shoulderAngleVel     = try container.decodeIfPresent(Double.self, forKey: .shoulderAngleVel)
        hipAngleVel          = try container.decodeIfPresent(Double.self, forKey: .hipAngleVel)
        kneeAngleVel         = try container.decodeIfPresent(Double.self, forKey: .kneeAngleVel)
    }

    init(
        frameIdx:             Int,
        topBarPx:             CGPoint,
        bottomBarPx:          CGPoint,
        armActualLenM:        Double,
        armRestLenM:          Double,
        upperArmLenM:         Double,
        forearmLenM:          Double,
        torsoLenM:            Double,
        thighLenM:            Double,
        lowerLegLenM:         Double,
        armSpringDeflectionM: Double,
        barSpringLenM:        Double,
        vArmAngle:             Double,
        vTorsoAngle:           Double,
        vThighAngle:           Double,
        vLowerLegAngle:        Double,
        shoulderAngle:        Double,
        hipAngle:             Double,
        kneeAngle:            Double,
        comAngle:             Double,
        headHeightM:          Double,
        vArmAngleVel:          Double? = nil,
        vTorsoAngleVel:        Double? = nil,
        vThighAngleVel:          Double? = nil,
        vLowerLegAngleVel:        Double? = nil,
        shoulderAngleVel:        Double? = nil,
        hipAngleVel:           Double? = nil,
        kneeAngleVel:          Double? = nil
    ) {
        self.frameIdx             = frameIdx
        self.topBarPx             = topBarPx
        self.bottomBarPx          = bottomBarPx
        self.armActualLenM        = armActualLenM
        self.armRestLenM          = armRestLenM
        self.upperArmLenM         = upperArmLenM
        self.forearmLenM          = forearmLenM
        self.torsoLenM            = torsoLenM
        self.thighLenM            = thighLenM
        self.lowerLegLenM         = lowerLegLenM
        self.armSpringDeflectionM = armSpringDeflectionM
        self.barSpringLenM        = barSpringLenM
        self.vArmAngle             = vArmAngle
        self.vTorsoAngle           = vTorsoAngle
        self.vThighAngle           = vThighAngle
        self.vLowerLegAngle        = vLowerLegAngle
        self.shoulderAngle        = shoulderAngle
        self.hipAngle             = hipAngle
        self.kneeAngle            = kneeAngle
        self.comAngle             = comAngle
        self.headHeightM          = headHeightM
        self.vArmAngleVel          = vArmAngleVel
        self.vTorsoAngleVel        = vTorsoAngleVel
        self.vThighAngleVel        = vThighAngleVel
        self.vLowerLegAngleVel     = vLowerLegAngleVel
        self.shoulderAngleVel     = shoulderAngleVel
        self.hipAngleVel          = hipAngleVel
        self.kneeAngleVel         = kneeAngleVel
    }
}
