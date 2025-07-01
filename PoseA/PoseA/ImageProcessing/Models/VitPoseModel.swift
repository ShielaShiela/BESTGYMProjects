//
//  ImageProcessing.swift
//  PoseA
//
//  Created by Ardhika Maulidani on 6/27/25.
//

import Foundation

// Updated KeypointData struct with Equatable conformance
struct KeypointData: Identifiable, Codable, Equatable {
    let id: UUID
    let name: String
    var x: CGFloat
    var y: CGFloat
    let confidence: Float
    var depth: Float
    let frameIndex: Int
    
    // Store original position for reset functionality
    private let originalX: CGFloat
    private let originalY: CGFloat
    
    init(name: String, x: CGFloat, y: CGFloat, confidence: Float, depth: Float, frameIndex: Int) {
        self.id = UUID()
        self.name = name
        self.x = x
        self.y = y
        self.confidence = confidence
        self.depth = depth
        self.frameIndex = frameIndex
        self.originalX = x
        self.originalY = y
    }
    
    var position: CGPoint {
        return CGPoint(x: x, y: y)
    }
    
    // Implement Equatable
    static func == (lhs: KeypointData, rhs: KeypointData) -> Bool {
        return lhs.id == rhs.id &&
               lhs.name == rhs.name &&
               lhs.x == rhs.x &&
               lhs.y == rhs.y &&
               lhs.confidence == rhs.confidence &&
               lhs.depth == rhs.depth &&
               lhs.frameIndex == rhs.frameIndex
    }
}
var keypointNames = [
    "nose", "left_eye", "right_eye", "left_ear", "right_ear",
    "left_shoulder", "right_shoulder", "left_elbow", "right_elbow",
    "left_wrist", "right_wrist", "left_hip", "right_hip",
    "left_knee", "right_knee", "left_ankle", "right_ankle"
]

var availableJoints: [String] {
    return [
        "L Shoulder",
        "R Shoulder",
        "L Elbow",
        "R Elbow",
        "L Wrist",
        "R Wrist",
        "L Hip",
        "R Hip",
        "L Knee",
        "R Knee",
        "L Ankle",
        "R Ankle"
    ]
}

var jointConnections: [(String, String)] = [
    // Torso
    ("left_shoulder", "right_shoulder"),
    ("left_shoulder", "left_hip"),
    ("right_shoulder", "right_hip"),
    ("left_hip", "right_hip"),
    
    // Arms
    ("left_shoulder", "left_elbow"),
    ("left_elbow", "left_wrist"),
    ("right_shoulder", "right_elbow"),
    ("right_elbow", "right_wrist"),
    
    // Legs
    ("left_hip", "left_knee"),
    ("left_knee", "left_ankle"),
    ("right_hip", "right_knee"),
    ("right_knee", "right_ankle"),
    
    // Face
    ("nose", "left_eye"),
    ("nose", "right_eye")
]
