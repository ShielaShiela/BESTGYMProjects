//
//  CustomVariables.swift
//  PoseA
//
//  Created by Ardhika Maulidani on 5/27/25.
//  Refactor from Shiela Cabahug's codebase

import SwiftUI

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


// MARK: Chart Data Structure
struct JointData: Identifiable {
    var id: String { joint }
    var joint: String
    var dataPoints: [xyChartData]
}

struct xyChartData: Identifiable {
    var id = UUID()
    var x: Double
    var y: Double
}

extension xyChartData {
    init(x: Int, y: Double) {
        self.x = Double(x)
        self.y = y
    }

    init(x: Double, y: Double) {
        self.x = x
        self.y = y
    }
}

// Joint colors for the graph
let jointColors: [String: Color] = [
    "L Shoulder": .blue,
    "R Shoulder": .red,
    "L Elbow": .orange,
    "R Elbow": .yellow,
    "L Hip": .purple,
    "R Hip": .pink,
    "L Knee": .black,
    "R Knee": .gray
]

// MARK: Error Variables
struct ErrorWrapper: Identifiable {
    let id = UUID()
    let error: String
}

// MARK: Video Variables
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

