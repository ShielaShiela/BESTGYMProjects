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

// MARK: Image Function

extension UIImage {
    func rotated(to orientation: UIImage.Orientation) -> UIImage? {
        guard let cgImage = self.cgImage else { return nil }
        return UIImage(cgImage: cgImage, scale: 1.0, orientation: orientation)
    }
}
