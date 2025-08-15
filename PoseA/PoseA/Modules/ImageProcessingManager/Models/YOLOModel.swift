//
//  YOLOModel.swift
//  PoseA
//
//  Created by Ardhika Maulidani on 8/11/25.
//

import Foundation

struct PoseBox {
    let bbox: CGRect    // x,y,w,h normalized or pixel coords
    let confidence: Float
    let keypoints: [CGPoint] // px, py scaled to image size
    let visibility: [Float]
}

