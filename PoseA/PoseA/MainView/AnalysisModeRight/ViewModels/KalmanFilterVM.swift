//
//  KalmanFilterVM.swift
//  PoseA
//
//  Created by Ardhika Maulidani on 7/1/25.
//

import Foundation

class KF1DWrapper {
    private var ptr: OpaquePointer?

    init(dt: Float) {
        self.ptr = kalman_create(dt)
    }

    func reset(angle: Float) {
        guard let ptr = ptr else { return }
        kalman_reset(ptr, angle)
    }

    func update(measurement: Float?) -> Float {
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

    init(dt: Float) {
        ptr = kalman3d_create(dt)
    }

    func reset(x: Float, y: Float, z: Float) {
        guard let ptr = ptr else { return }
        kalman3d_reset(ptr, x, y, z)
    }

    func update(x: Float?, y: Float?, z: Float?) {
        guard let ptr = ptr else { return }

        var vx: Float = x ?? 0
        var vy: Float = y ?? 0
        var vz: Float = z ?? 0

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

    func getFilteredPosition() -> (Float, Float, Float)? {
        guard let ptr = ptr else { return nil }
        var x: Float = 0, y: Float = 0, z: Float = 0
        kalman3d_get_state(ptr, &x, &y, &z)
        return (x, y, z)
    }

    deinit {
        if let ptr = ptr {
            kalman3d_free(ptr)
        }
    }
}
