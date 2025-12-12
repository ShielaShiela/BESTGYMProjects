//
//  Math.swift
//  PoseA
//
//  Created by Ardhika Maulidani on 5/29/25.
//  General Math Functions

import SwiftUI
import AVFoundation

func transformPoint(x: CGFloat, y: CGFloat, containerSize: CGSize, imageSize: CGSize) -> CGPoint {
    // Calculate the actual display size of the image within the container
    let imageAspectRatio = imageSize.width / imageSize.height
    let containerAspectRatio = containerSize.width / containerSize.height
    
    var displaySize: CGSize
    
    if imageAspectRatio > containerAspectRatio {
        // Image is wider than container - fit to width
        displaySize = CGSize(
            width: containerSize.width,
            height: containerSize.width / imageAspectRatio
        )
    } else {
        // Image is taller than container - fit to height
        displaySize = CGSize(
            width: containerSize.height * imageAspectRatio,
            height: containerSize.height
        )
    }
    
    // Calculate offset to center the image
    let offsetX = (containerSize.width - displaySize.width) / 2
    let offsetY = (containerSize.height - displaySize.height) / 2
    
    // Convert keypoint coordinates to display coordinates
    let displayX = (x / imageSize.width) * displaySize.width + offsetX
    let displayY = (y / imageSize.height) * displaySize.height + offsetY
    
    return CGPoint(x: displayX, y: displayY)
}

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

func matrixToArray(_ matrix: matrix_float3x3) -> [[Float]] {
    return (0..<3).map { i in
        [matrix.columns.0[i], matrix.columns.1[i], matrix.columns.2[i]]
    }
}
