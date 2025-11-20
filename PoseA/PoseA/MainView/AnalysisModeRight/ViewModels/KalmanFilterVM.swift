//
//  KalmanFilterVM.swift
//  PoseA
//
//  Created by Ardhika Maulidani on 7/1/25.
//

import Foundation

class KF1DWrapper {
    private var ptr: OpaquePointer?

    init(dt: Double) {
        self.ptr = kalman_create(dt)
    }

    func reset(angle: Double) {
        guard let ptr = ptr else { return }
        kalman_reset(ptr, angle)
    }

    func update(measurement: Double?) -> Double {
        guard let ptr = ptr else { return 0.0 }
        if var z = measurement {
            return kalman_update(ptr, &z)
        } else {
            return kalman_update(ptr, nil)
        }
    }

    deinit {
        if let ptr = ptr {
            kalman_free(ptr)
        }
    }
}

class KF3DWrapper {
    private var ptr: OpaquePointer?

    init(dt: Double) {
        ptr = kalman3d_create(dt)
    }

    func reset(x: Double, y: Double, z: Double) {
        guard let ptr = ptr else { return }
        kalman3d_reset(ptr, x, y, z)
    }

    func update(x: Double?, y: Double?, z: Double?) {
        guard let ptr = ptr else { return }

        var vx: Double = x ?? 0
        var vy: Double = y ?? 0
        var vz: Double = z ?? 0

        withUnsafeMutablePointer(to: &vx) { px in
            withUnsafeMutablePointer(to: &vy) { py in
                withUnsafeMutablePointer(to: &vz) { pz in
                    let xPtr = x != nil ? px : nil
                    let yPtr = y != nil ? py : nil
                    let zPtr = z != nil ? pz : nil

                    kalman3d_update(ptr, xPtr, yPtr, zPtr)
                }
            }
        }
    }

    func getFilteredPosition() -> (Double, Double, Double)? {
        guard let ptr = ptr else { return nil }
        var x: Double = 0, y: Double = 0, z: Double = 0
        kalman3d_get_state(ptr, &x, &y, &z)
        return (x, y, z)
    }

    deinit {
        if let ptr = ptr {
            kalman3d_free(ptr)
        }
    }
}
