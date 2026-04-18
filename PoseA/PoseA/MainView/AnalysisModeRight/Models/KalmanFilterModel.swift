//
//  KalmanFilterSIMD.swift
//

import Foundation
import simd
import CoreGraphics

class KalmanFilter2D {

    // MARK: - Properties
    private var dt: Double
    private var isInitialized = false

    // State vector: [x, y, vx, vy]
    private var x = simd_double4(0, 0, 0, 0)

    // State transition matrix (4×4)
    private var F: simd_double4x4

    // Measurement matrix H (2×4) represented as row vectors
    private let h1 = simd_double4(1, 0, 0, 0)
    private let h2 = simd_double4(0, 1, 0, 0)

    // Covariance matrices
    private var P: simd_double4x4
    private var Q: simd_double4x4
    private var R: simd_double2x2

    private let I = matrix_identity_double4x4

    // MARK: - Initialization
    init(dt: Double = 1.0) {
        self.dt = dt

        // State transition matrix F (column-major initialization)
        self.F = simd_double4x4(
            simd_double4(1, 0, 0, 0),   // column 0
            simd_double4(0, 1, 0, 0),   // column 1
            simd_double4(dt, 0, 1, 0),  // column 2
            simd_double4(0, dt, 0, 1)   // column 3
        )

        // Initial covariance P
        self.P = simd_double4x4(diagonal: simd_double4(repeating: 100))

        // Process noise covariance Q
        self.Q = simd_double4x4(
            simd_double4(5, 0, 0, 0),
            simd_double4(0, 5, 0, 0),
            simd_double4(0, 0, 50, 0),
            simd_double4(0, 0, 0, 50)
        )

        // Measurement noise covariance R
        self.R = simd_double2x2(
            simd_double2(2.5, 0),
            simd_double2(0, 2.5)
        )
    }

    // MARK: - Public API

    /// Initialize the state with the first measurement
    func initializeState(x u: Double, y v: Double) {
        self.x = simd_double4(u, v, 0, 0)
        self.isInitialized = true
    }

    /// Prediction step: x = F·x,  P = F·P·Fᵀ + Q
    func predict() -> CGPoint? {
        guard isInitialized else { return nil }

        x = F * x
        P = F * P * F.transpose + Q

        return CGPoint(x: x.x, y: x.y)
    }

    /// Update step with measurement (u, v)
    func update(x measX: Double, y measY: Double) -> CGPoint {
        if !isInitialized {
            initializeState(x: measX, y: measY)
            return CGPoint(x: measX, y: measY)
        }

        let z = simd_double2(measX, measY)

        // Innovation: y = z − Hx
        let Hx = simd_double2(dot(h1, x), dot(h2, x))
        let y = z - Hx

        // S = HPHᵀ + R (2×2)
        let PHt0 = P * h1   // First column of P·Hᵀ
        let PHt1 = P * h2   // Second column

        let S = simd_double2x2(
            simd_double2(dot(h1, PHt0), dot(h1, PHt1)),
            simd_double2(dot(h2, PHt0), dot(h2, PHt1))
        ) + R

        guard let Sinv = invert2x2(S) else {
            return CGPoint(x: x.x, y: x.y)
        }

        // K = P·Hᵀ·S⁻¹  (4×2)
        let K0 = PHt0 * Sinv[0,0] + PHt1 * Sinv[1,0]
        let K1 = PHt0 * Sinv[0,1] + PHt1 * Sinv[1,1]

        // State update: x = x + K·y
        x += K0 * y.x + K1 * y.y

        // Joseph form covariance update
        let KH = outerProduct(K0, h1) + outerProduct(K1, h2)
        let I_KH = I - KH
        let KRKt = SinvKRKt(K0: K0, K1: K1)

        P = I_KH * P * I_KH.transpose + KRKt

        return CGPoint(x: x.x, y: x.y)
    }

    var initialized: Bool { isInitialized }

    // MARK: - Helper Functions

    // Invert a 2×2 matrix
    private func invert2x2(_ m: simd_double2x2) -> simd_double2x2? {
        let a = m[0,0], b = m[0,1]
        let c = m[1,0], d = m[1,1]
        let det = a * d - b * c
        guard abs(det) > 1e-10 else { return nil }
        let invDet = 1.0 / det
        return simd_double2x2(
            simd_double2( d * invDet, -c * invDet),
            simd_double2(-b * invDet,  a * invDet)
        )
    }

    // Outer product of two 4D vectors producing a 4×4 matrix
    private func outerProduct(_ a: simd_double4, _ b: simd_double4) -> simd_double4x4 {
        return simd_double4x4(
            a * b.x,
            a * b.y,
            a * b.z,
            a * b.w
        )
    }

    // Compute K·R·Kᵀ for Joseph form
    private func SinvKRKt(K0: simd_double4, K1: simd_double4) -> simd_double4x4 {
        let r00 = R[0,0], r01 = R[0,1]
        let r10 = R[1,0], r11 = R[1,1]

        let KR0 = K0 * r00 + K1 * r10
        let KR1 = K0 * r01 + K1 * r11

        return outerProduct(KR0, K0) + outerProduct(KR1, K1)
    }
}
