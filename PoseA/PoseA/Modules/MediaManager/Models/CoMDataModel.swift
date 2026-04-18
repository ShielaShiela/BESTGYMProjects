//
//  CoMDataModel.swift
//  PoseA
//
//  Created by Ardhika Maulidani on 4/15/26.
//

import Foundation

// MARK: - Data Models
struct CoMExportModel: Codable {
    let frames: [CoMDataModel]
    let frameCount: Int
    let exportTime: TimeInterval
    
    enum CodingKeys: String, CodingKey {
        case frames
        case frameCount = "frameCount"
        case exportTime = "exportTime"
    }
}

struct CoMDataModel: Codable {
    let frameNumber: Int
    let com: CGPoint
    let poseMissing: Bool

    enum CodingKeys: String, CodingKey {
        case frameNumber = "frame_number"
        case com = "CoM"
        case poseMissing = "pose_missing"
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(frameNumber, forKey: .frameNumber)
        try container.encode(["x": com.x, "y": com.y], forKey: .com)
        try container.encode(poseMissing, forKey: .poseMissing)
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        frameNumber = try container.decode(Int.self, forKey: .frameNumber)
        poseMissing = try container.decode(Bool.self, forKey: .poseMissing)
        let dict = try container.decode([String: Double].self, forKey: .com)
        com = CGPoint(x: dict["x"] ?? 0, y: dict["y"] ?? 0)
    }

    init(frameNumber: Int, com: CGPoint, poseMissing: Bool) {
        self.frameNumber = frameNumber
        self.com = com
        self.poseMissing = poseMissing
    }
}
