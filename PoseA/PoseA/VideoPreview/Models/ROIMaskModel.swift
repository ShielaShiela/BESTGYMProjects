//
//  MaskModel.swift
//  PoseA
//
//  Created by Bestlab on 6/23/25.
//

import SwiftUI

struct InvertedMaskShape: Shape {
    let holeRect: CGRect

    func path(in rect: CGRect) -> Path {
        var path = Path()

        // Outer full rectangle
        path.addRect(rect)

        // Inner rectangle to cut out
        path.addRect(holeRect)

        // Just return the path normally; fill rule is applied during rendering
        return path
    }
}
