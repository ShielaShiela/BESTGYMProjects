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
    let hasDepthData: Bool  // Flag to indicate if depth was available
    let averageDepth: Float?  // Optional: average depth of all keypoints for later
    
    enum CodingKeys: String, CodingKey {
        case bbox, confidence, keypoints, hasDepthData, averageDepth
    }
    
    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(confidence, forKey: .confidence)
        try container.encode(keypoints, forKey: .keypoints)
        try container.encode(hasDepthData, forKey: .hasDepthData)
        try container.encodeIfPresent(averageDepth, forKey: .averageDepth)
        
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
        hasDepthData = try container.decodeIfPresent(Bool.self, forKey: .hasDepthData) ?? false
        averageDepth = try container.decodeIfPresent(Float.self, forKey: .averageDepth)
        
        let bboxDict = try container.decode([String: CGFloat].self, forKey: .bbox)
        bbox = CGRect(
            x: bboxDict["x"] ?? 0,
            y: bboxDict["y"] ?? 0,
            width: bboxDict["width"] ?? 0,
            height: bboxDict["height"] ?? 0
        )
    }
    
    // Initializer with depth support
    init(bbox: CGRect, confidence: Float, keypoints: [KeypointData], hasDepthData: Bool = false) {
        self.bbox = bbox
        self.confidence = confidence
        self.keypoints = keypoints
        self.hasDepthData = hasDepthData
        
        // Calculate average depth if available
        if hasDepthData {
            let validDepths = keypoints.compactMap { $0.depth }
            self.averageDepth = validDepths.isEmpty ? nil : validDepths.reduce(0, +) / Float(validDepths.count)
        } else {
            self.averageDepth = nil
        }
    }
}


// MARK: - Pose Frame Data for JSON Export
struct PoseFrameData: Codable {
    let frameIndex: Int
    let timestamp: Double
    let poses: [PoseBox]
    let hasDepthData: Bool
    let cameraIntrinsics: CameraIntrinsicsData?  // Store camera calibration
    
    // Optional: if you want to include PTS info
    let ptsValue: Int64
    let ptsTimescale: Int32
    
    init(frameIndex: Int, timestamp: Double, poses: [PoseBox], pts: CMTime, hasDepthData: Bool = false, cameraIntrinsics: matrix_float3x3? = nil) {
        self.frameIndex = frameIndex
        self.timestamp = timestamp
        self.poses = poses
        self.ptsValue = pts.value
        self.ptsTimescale = pts.timescale
        self.hasDepthData = hasDepthData
        
        if let intrinsics = cameraIntrinsics {
            self.cameraIntrinsics = CameraIntrinsicsData(matrix: intrinsics)
        } else {
            self.cameraIntrinsics = nil
        }
    }
}

// Helper struct to make camera intrinsics codable
struct CameraIntrinsicsData: Codable {
    let fx: Float
    let fy: Float
    let cx: Float
    let cy: Float
    
    init(matrix: matrix_float3x3) {
        self.fx = matrix.columns.0.x
        self.fy = matrix.columns.1.y
        self.cx = matrix.columns.2.x
        self.cy = matrix.columns.2.y
    }
}
