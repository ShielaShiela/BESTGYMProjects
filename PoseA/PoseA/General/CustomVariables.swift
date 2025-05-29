//
//  CustomVariables.swift
//  PoseA
//
//  Created by Ardhika Maulidani on 5/27/25.
//  Refactor from Shiela Cabahug's codebase

import SwiftUI

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

struct ErrorWrapper: Identifiable {
    let id = UUID()
    let error: String
}

struct VideoFormat {
    let width: Int
    let height: Int
    let fps: Int
}

struct VideoSettings {
    var selectedFormat: VideoFormat
    
    static let defaultSettings = VideoSettings(
        selectedFormat: VideoFormat(width: 1920, height: 1080, fps: 30)
    )
}
