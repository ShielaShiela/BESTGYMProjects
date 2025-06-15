//
//  JointDataProvider.swift
//  PoseA
//
//  Created by Ardhika Maulidani on 6/1/25.
//

import Foundation

// MARK: ------------------------------- Chart Data Structure BEGIN -------------------------------

struct JointData: Identifiable {
    var id: String { joint }
    var joint: String
    var dataPoints: [xyzChartData]
    var dataMetrics: dataMetrics
}

struct xyzChartData: Identifiable {
    var id = UUID()
    var x: Float // For X Axis Data
    var y: Float // For Y Axis Data
    var z: Float // For Z Axis (Depth) or Indices Data
}

extension xyzChartData {
    init(x: Int, y: Float, z: Float = 0.0) {
        self.x = Float(x)
        self.y = Float(y)
        self.z = Float(z)
    }
}

struct dataMetrics {
    var minX: Float = 0.0
    var maxX: Float = 0.0
    var minY: Float = 0.0
    var maxY: Float = 0.0
    var minZ: Float = 0.0
    var maxZ: Float = 0.0
}
// MARK: -------------------------------- Chart Data Structure END --------------------------------


var availableJoints: [String] {
    return [
        "L Shoulder", "R Shoulder",
        "L Elbow", "R Elbow",
        "L Wrist", "R Wrist",
        "L Hip", "R Hip",
        "L Knee", "R Knee",
        "L Ankle", "R Ankle"
    ]
}
