//
//  JointDataProvider.swift
//  PoseA
//
//  Created by Ardhika Maulidani on 6/1/25.
//

import Spatial
import SwiftUI
import Charts

// MARK: ------------------------------- Chart Data Structure BEGIN -------------------------------

struct ChartData2D: Identifiable, Equatable {
    var id: String { joint }
    var joint: String
    var dataPoints: [Point2D]
    var dataMetrics: dataMetrics
    var color: Color = .gray
}

struct JointData3D: Identifiable, Equatable {
    var id: String { joint }
    var joint: String
    var dataPoints: [Point3D]
    var dataMetrics: dataMetrics
}

struct Point2D: Identifiable, Equatable {
    var id = UUID()
    var x: Double
    var y: Double
        
    init(_ point: CGPoint) {
        self.x = Double(point.x)
        self.y = Double(point.y)
    }
    
    init(x: Double, y: Double) {
        self.x = x
        self.y = y
    }
}


struct dataMetrics: Equatable {
    var minX: Double = 0.0
    var maxX: Double = 0.0
    var minY: Double = 0.0
    var maxY: Double = 0.0
    var minZ: Double = 0.0
    var maxZ: Double = 0.0
}
// MARK: -------------------------------- Chart Data Structure END --------------------------------

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

// Joint colors for the graph
let jointColors: [String: Color] = [
    "Shoulder": Color(red: 1.0, green: 0.0, blue: 1.0),
    "Hip": Color(red: 0.294, green: 0.0, blue: 0.510),
    "Knee": Color(red: 243/255, green: 122/255, blue: 72/255),

    "vArm": .yellow,
    "vTorso": .blue,
    "vThigh": .purple,
    "vLowerLeg": .teal,
    "CoM": .gray,
    
    "Head-Bar": .blue,
    "Wrist-Bar": .red,
    
    "Flight Phase": .gray,
    "Release Phase": .gray,
]
