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
struct ChartData3D: Identifiable, Equatable {
    var id: String { joint }
    var joint: String
    var dataPoints: ChartPoint3D
}

struct ChartData2D: Identifiable, Equatable {
    var id: String { joint }
    var joint: String
    var dataPoints: [Point2D]
    var dataMetrics: dataMetrics
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

struct ChartPoint3D: Identifiable, Equatable {
    var id = UUID()
    var x: Double
    var y: Double
    var z: Double
        
    init(_ point: Point3D) {
        self.x = Double(point.x)
        self.y = Double(point.y)
        self.z = Double(point.z)
    }
    
    init(x: Double, y: Double, z: Double) {
        self.x = x
        self.y = y
        self.z = z
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
    "L Shoulder": .cyan,
    "R Shoulder": .blue,
    "L Elbow": .pink,
    "R Elbow": .red,
    "L Wrist": .brown,
    "R Wrist": .indigo,
    "L Hip": .orange,
    "R Hip": .yellow,
    "L Knee": .green,
    "R Knee": .purple,
    "L Ankle": .black,
    "R Ankle": .gray
]
