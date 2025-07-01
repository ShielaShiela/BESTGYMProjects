//
//  KalmanFilterVM.swift
//  PoseA
//
//  Created by Ardhika Maulidani on 7/1/25.
//

import SwiftUI
import simd

class Kalman1DAngleFilter {
    private var x = simd_float2(0, 0) // [angle, velocity]
    private var P = float2x2(diagonal: [1.0, 1.0])

    private let A: float2x2
    private let H = simd_float2(1, 0)
    private let Q = float2x2(diagonal: [0.01, 0.1]) // Process noise
    private let R: Float = 5.0 // Measurement noise

    init(dt: Float) {
        self.A = float2x2(rows: [
            simd_float2(1, dt),
            simd_float2(0, 1)
        ])
    }

    func reset(angle: Float) {
        x = simd_float2(angle, 0)
        P = float2x2(diagonal: [1.0, 1.0])
    }

    func update(measurement z: Float?) -> Float {
        // Predict
        x = A * x
        P = A * P * A.transpose + Q

        // Update (only if measurement is available)
        if let z = z {
            let y = z - simd_dot(H, x) // innovation
            let S = simd_dot(H, P * H) + R
            let K = (P * H) / S         // Kalman gain: 2x1 vector

            x = x + K * y
            let KH = float2x2(columns: (K * H.x, K * H.y)) // 2x2 matrix
            P = (matrix_identity_float2x2 - KH) * P
        }

        return x[0] // Return filtered angle
    }
}
