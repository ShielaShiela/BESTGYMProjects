//
//  YOLOModel.swift
//  PoseA
//
//  Created by Ardhika Maulidani on 8/11/25.
//

import Foundation
import AVFoundation
//struct PoseBox {
//    let bbox: CGRect
//    let confidence: Float
//    let keypoints: [KeypointData]
//}


//new PoseBox for saving keypoints
// MARK: - New PoseBox for Saving Keypoints

struct PoseBox: Codable {
    let bbox: CGRect
    let confidence: Float
    let keypoints: [KeypointData]
    
    // Add custom encoding/decoding for CGRect since it's not Codable by default
    enum CodingKeys: String, CodingKey {
        case bbox, confidence, keypoints
    }
    
    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(confidence, forKey: .confidence)
        try container.encode(keypoints, forKey: .keypoints)
        
        // Encode CGRect as a dictionary
        let bboxDict: [String: CGFloat] = [
            "x": bbox.origin.x,
            "y": bbox.origin.y,
            "width": bbox.size.width,
            "height": bbox.size.height
        ]
        try container.encode(bboxDict, forKey: .bbox)
    }
    
    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        confidence = try container.decode(Float.self, forKey: .confidence)
        keypoints = try container.decode([KeypointData].self, forKey: .keypoints)
        
        let bboxDict = try container.decode([String: CGFloat].self, forKey: .bbox)
        bbox = CGRect(
            x: bboxDict["x"] ?? 0,
            y: bboxDict["y"] ?? 0,
            width: bboxDict["width"] ?? 0,
            height: bboxDict["height"] ?? 0
        )
    }
    
    // Keep your existing initializer
    init(bbox: CGRect, confidence: Float, keypoints: [KeypointData]) {
        self.bbox = bbox
        self.confidence = confidence
        self.keypoints = keypoints
    }
}


// MARK: - Pose Frame Data for JSON Export
struct PoseFrameData: Codable {
    let frameIndex: Int
    let timestamp: Double
    let poses: [PoseBox]
    
    // Optional: if you want to include PTS info
    let ptsValue: Int64
    let ptsTimescale: Int32
    
    init(frameIndex: Int, timestamp: Double, poses: [PoseBox], pts: CMTime) {
        self.frameIndex = frameIndex
        self.timestamp = timestamp
        self.poses = poses
        self.ptsValue = pts.value
        self.ptsTimescale = pts.timescale
    }
}
