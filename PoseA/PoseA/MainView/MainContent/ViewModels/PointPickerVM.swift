//
//  PointPickerVM.swift
//  PoseA
//
//  Created by Ardhika Maulidani on 9/5/25.
//

import SwiftUI

@Observable
class PointPickerViewModel {
    var isPointMode: Bool = false
    var isPickerMode: Bool = false
    var isPointAvailable: Bool = false
    var pointDisplay: CGPoint? = nil // Display space
    var pointImage: CGPoint? = nil // Image space

    
    func setPointMode(_ isPointMode: Bool) {
        self.isPointMode = isPointMode
        if pointDisplay != nil {
            setPickerMode(true)
        } else {
            setPickerMode(false)
        }
    }

    private func setPickerMode(_ isPickerMode: Bool) {
        self.isPickerMode = isPickerMode
    }

    func clearPoint() {
        pointDisplay = .zero
        pointImage = .zero
        isPointAvailable = false
        setPickerMode(true)
    }

    // MARK: - Coordinate Conversions

    func updateImageSpace(from containerSize: CGSize, imageSize: CGSize) {
        guard let pointDisplay = pointDisplay else {
            self.pointImage = nil
            return
        }
        
        let mapper = CoordinateMapper(containerSize: containerSize,
                                      imageSize: imageSize,
                                      scaleMode: .aspectFill)

        self.pointImage = mapper.mapPointInverse(pointDisplay)
        log("Point (Image) updated: \(self.pointImage!)", level: .debug)
    }

    func updateDisplaySpace(from containerSize: CGSize, imageSize: CGSize) {
        guard let pointImage = pointImage else {
            self.pointDisplay = nil
            return
        }
        
        let mapper = CoordinateMapper(containerSize: containerSize,
                                      imageSize: imageSize,
                                      scaleMode: .aspectFill)

        self.pointImage = mapper.mapPoint(pointImage)
        log("Point (Display) updated: \(self.pointDisplay!)", level: .debug)

    }
}
