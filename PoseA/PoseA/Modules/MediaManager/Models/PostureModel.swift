//
//  PostureModel.swift
//  PoseA
//
//  Created by Ardhika Maulidani on 4/24/26.
//

import Foundation

// MARK: - Joint Posture Data
struct JointPostureData: Codable {
    var feature:  CompareList
    // Athlete Data
    var athlete:  [CGPoint]   // raw athlete series          x=t(s), y=angle(°)
    // Reference Data
    var refMean:  [CGPoint]   // reference mean              x=t(s), y=mean(°)
    var refUpper: [CGPoint]   // reference mean + 1 std      x=t(s), y=(°)
    var refLower: [CGPoint]   // reference mean − 1 std      x=t(s), y=(°)
    // Magnitude Comparison Data
    var zScore:   [CGPoint]   // deviation from reference    x=t(s), y=z-score
    var magDev: [DeviationModel]   // time interval for each deviation
    var rmsZScore: Double?    // RMS z-score over window (quality scalar)
    
    enum CodingKeys: String, CodingKey {
        case feature = "feature"
        case athlete = "athlete"
        case refMean = "refMean"
        case refUpper = "refUpper"
        case refLower = "refLower"
        case zScore = "zScore"
        case magDev = "magDev"
        case rmsZScore = "rmsZScore"
    }
}

// MARK: - Posture Data
struct PostureData: Codable {
    var skill:       String
    var phase:       ComparisonPhase
    var joints:      [CompareList: JointPostureData]

    subscript(joint: CompareList) -> JointPostureData? { joints[joint] }
    
    enum CodingKeys: String, CodingKey {
        case skill = "skill"
        case phase = "phase"
        case joints = "joints"
    }
    
    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(skill, forKey: .skill)
        try container.encode(phase, forKey: .phase)
        
        // Convert dictionary to array for JSON encoding
        let jointsArray = joints.map { (key, value) in
            JointPostureDataWrapper(joint: key, data: value)
        }
        try container.encode(jointsArray, forKey: .joints)
    }
    
    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        skill = try container.decode(String.self, forKey: .skill)
        phase = try container.decode(ComparisonPhase.self, forKey: .phase)
        
        // Convert array back to dictionary
        let jointsArray = try container.decode([JointPostureDataWrapper].self, forKey: .joints)
        joints = Dictionary(uniqueKeysWithValues: jointsArray.map { ($0.joint, $0.data) })
    }
    
    init(skill: String, phase: ComparisonPhase, joints: [CompareList: JointPostureData] = [:]) {
        self.skill = skill
        self.phase = phase
        self.joints = joints
    }
}

// MARK: - Deviation Model Data
enum DeviationDirection: String, Codable { case above, below }
enum DeviationSeverity: String, Codable  { case significant, notable }

struct DeviationModel: Codable {
    let tStart:    Double
    let tEnd:      Double
    let duration:  Double
    let meanVal:   Double
    let direction: DeviationDirection
    let severity:  DeviationSeverity
    let suggestion: String?
    
    enum CodingKeys: String, CodingKey {
        case tStart = "tStart"
        case tEnd = "tEnd"
        case duration = "duration"
        case meanVal = "meanVal"
        case direction = "direction"
        case severity = "severity"
        case suggestion = "suggestion"
    }
}

// MARK: - Joint Posture Data Wrapper
private struct JointPostureDataWrapper: Codable {
    let joint: CompareList
    let data: JointPostureData
    
    enum CodingKeys: String, CodingKey {
        case joint = "joint"
        case data = "data"
    }
}

// MARK: - Comparison Phase
enum ComparisonPhase: String, Codable {
    case release = "release"
    case flight = "flight"
    
    var label: String {
        switch self {
        case .release: return "Release Phase"
        case .flight: return "Flight Phase"
        }
    }
    
    enum CodingKeys: String, CodingKey {
        case release = "release"
        case flight = "flight"
    }
}

// MARK: - Posture Export Model
struct PostureExportModel: Codable {
    let postureData: [PostureData]
    let exportTime: TimeInterval
    let version: String
    
    enum CodingKeys: String, CodingKey {
        case postureData = "postureData"
        case exportTime = "exportTime"
        case version = "version"
    }
    
    init(postureData: [PostureData], version: String = "1.0") {
        self.postureData = postureData
        self.exportTime = Date().timeIntervalSince1970
        self.version = version
    }
}

