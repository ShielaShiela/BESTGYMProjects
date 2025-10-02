//
//  Math.swift
//  PoseA
//
//  Created by Ardhika Maulidani on 5/29/25.
//  General Math Functions

import SwiftUI
import AVFoundation

// MARK: Number Function
func arrayToMatrix(_ array: [[Double]]) -> matrix_float3x3? {
    guard array.count == 3, array.allSatisfy({ $0.count == 3 }) else { return nil }
    
    return matrix_float3x3(columns: (
        SIMD3<Float>(array[0].map(Float.init)),
        SIMD3<Float>(array[1].map(Float.init)),
        SIMD3<Float>(array[2].map(Float.init))
    ))
}

func arrayToMatrix(_ array: [Float]) -> matrix_float3x3? {
    guard array.count == 9 else { return nil }
    
    return matrix_float3x3(columns: (
        SIMD3(array[0], array[1], array[2]),
        SIMD3(array[3], array[4], array[5]),
        SIMD3(array[6], array[7], array[8])
    ))
}
