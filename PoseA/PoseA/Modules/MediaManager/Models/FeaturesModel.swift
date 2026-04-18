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
    var armAngle:      Double
    var torsoAngle:    Double
    var thighAngle:    Double
    var lowerLegAngle: Double

    // Joint angles (degrees, signed CCW positive)
    var shoulderAngle: Double
    var hipAngle:      Double
    var kneeAngle:     Double

    // CoM angle
    var comAngle:    Double

    // Head height relative to bar top
    var headHeightM: Double

    // Angular velocities (deg/s)
    var armAngleVel:      Double?
    var torsoAngleVel:    Double?
    var thighAngleVel:    Double?
    var lowerLegAngleVel: Double?
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
        case armAngle
        case torsoAngle
        case thighAngle
        case lowerLegAngle
        case shoulderAngle
        case hipAngle
        case kneeAngle
        case comAngle
        case headHeightM
        case armAngleVel
        case torsoAngleVel
        case thighAngleVel
        case lowerLegAngleVel
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
        try container.encode(armAngle,             forKey: .armAngle)
        try container.encode(torsoAngle,           forKey: .torsoAngle)
        try container.encode(thighAngle,           forKey: .thighAngle)
        try container.encode(lowerLegAngle,        forKey: .lowerLegAngle)
        try container.encode(shoulderAngle,        forKey: .shoulderAngle)
        try container.encode(hipAngle,             forKey: .hipAngle)
        try container.encode(kneeAngle,            forKey: .kneeAngle)
        try container.encode(comAngle,             forKey: .comAngle)
        try container.encode(headHeightM,          forKey: .headHeightM)
        try container.encodeIfPresent(armAngleVel,      forKey: .armAngleVel)
        try container.encodeIfPresent(torsoAngleVel,    forKey: .torsoAngleVel)
        try container.encodeIfPresent(thighAngleVel,    forKey: .thighAngleVel)
        try container.encodeIfPresent(lowerLegAngleVel, forKey: .lowerLegAngleVel)
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
        armAngle             = try container.decode(Double.self, forKey: .armAngle)
        torsoAngle           = try container.decode(Double.self, forKey: .torsoAngle)
        thighAngle           = try container.decode(Double.self, forKey: .thighAngle)
        lowerLegAngle        = try container.decode(Double.self, forKey: .lowerLegAngle)
        shoulderAngle        = try container.decode(Double.self, forKey: .shoulderAngle)
        hipAngle             = try container.decode(Double.self, forKey: .hipAngle)
        kneeAngle            = try container.decode(Double.self, forKey: .kneeAngle)
        comAngle             = try container.decode(Double.self, forKey: .comAngle)
        headHeightM          = try container.decode(Double.self, forKey: .headHeightM)
        armAngleVel          = try container.decodeIfPresent(Double.self, forKey: .armAngleVel)
        torsoAngleVel        = try container.decodeIfPresent(Double.self, forKey: .torsoAngleVel)
        thighAngleVel        = try container.decodeIfPresent(Double.self, forKey: .thighAngleVel)
        lowerLegAngleVel     = try container.decodeIfPresent(Double.self, forKey: .lowerLegAngleVel)
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
        armAngle:             Double,
        torsoAngle:           Double,
        thighAngle:           Double,
        lowerLegAngle:        Double,
        shoulderAngle:        Double,
        hipAngle:             Double,
        kneeAngle:            Double,
        comAngle:             Double,
        headHeightM:          Double,
        armAngleVel:          Double? = nil,
        torsoAngleVel:        Double? = nil,
        thighAngleVel:          Double? = nil,
        lowerLegAngleVel:        Double? = nil,
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
        self.armAngle             = armAngle
        self.torsoAngle           = torsoAngle
        self.thighAngle           = thighAngle
        self.lowerLegAngle        = lowerLegAngle
        self.shoulderAngle        = shoulderAngle
        self.hipAngle             = hipAngle
        self.kneeAngle            = kneeAngle
        self.comAngle             = comAngle
        self.headHeightM          = headHeightM
        self.armAngleVel          = armAngleVel
        self.torsoAngleVel        = torsoAngleVel
        self.thighAngleVel        = thighAngleVel
        self.lowerLegAngleVel     = lowerLegAngleVel
        self.shoulderAngleVel     = shoulderAngleVel
        self.hipAngleVel          = hipAngleVel
        self.kneeAngleVel         = kneeAngleVel
    }
}
