//
//  Math.swift
//  PoseA
//
//  Created by Ardhika Maulidani on 5/29/25.
//  General Math Functions

import Foundation
import SwiftUI


// MARK: Angle Function

func angleBetween(_ a: KeypointData, _ b: KeypointData, _ c: KeypointData) -> Double {
    let ab = CGVector(dx: a.x - b.x, dy: a.y - b.y)
    let cb = CGVector(dx: c.x - b.x, dy: c.y - b.y)

    let dotProduct = ab.dx * cb.dx + ab.dy * cb.dy
    let magnitudeAB = sqrt(ab.dx * ab.dx + ab.dy * ab.dy)
    let magnitudeCB = sqrt(cb.dx * cb.dx + cb.dy * cb.dy)

    let cosineAngle = dotProduct / (magnitudeAB * magnitudeCB)
    let angleInRadians = acos(max(min(cosineAngle, 1.0), -1.0))
    return angleInRadians * 180 / .pi  // Convert to degrees
}

func wrapAngle(_ angle: Double) -> Double {
    var result = angle
    while result >= 180 {
        result -= 360
    }
    while result < -180 {
        result += 360
    }
    return result
}

func transformPoint(x: CGFloat, y: CGFloat, containerSize: CGSize, imageSize: CGSize, rotation: Int) -> CGPoint {
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
    var displayX = (x / imageSize.width) * displaySize.width + offsetX
    var displayY = (y / imageSize.height) * displaySize.height + offsetY
    
    // Apply rotation if needed
    if rotation != 0 {
        let centerX = containerSize.width / 2
        let centerY = containerSize.height / 2
        
        // Translate to origin
        displayX -= centerX
        displayY -= centerY
        
        // Apply rotation using CGAffineTransform (cleaner approach)
        let transform = CGAffineTransform(rotationAngle: CGFloat(rotation) * CGFloat.pi / 2)
        let rotatedPoint = CGPoint(x: displayX, y: displayY).applying(transform)
        
        // Translate back
        displayX = rotatedPoint.x + centerX
        displayY = rotatedPoint.y + centerY
    }
    
    return CGPoint(x: displayX, y: displayY)
}

// MARK: Image Function
