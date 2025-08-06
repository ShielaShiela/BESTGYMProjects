//
//  KeypointModel.swift
//  PoseA
//
//  Created by Ardhika Maulidani on 6/24/25.
//

import Foundation

// MARK: Keypoint Data Structure
struct Keypoint {
    let position: CGPoint
    let confidence: Float
    let name: String
}

enum BodySide {
    case left
    case right
    case center
}

struct KeypointConnection {
    let from: Int?
    let to: Int?
    let side: BodySide
}
