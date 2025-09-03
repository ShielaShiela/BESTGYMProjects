//
//  YOLOModel.swift
//  PoseA
//
//  Created by Ardhika Maulidani on 8/11/25.
//

import Foundation

struct PoseBox {
    let bbox: CGRect
    let confidence: Float
    let keypoints: [KeypointData]
}

