//
//  BoxVM.swift
//  PoseA
//
//  Created by Ardhika Maulidani on 7/10/25.
//

import SwiftUI

@Observable
class BoxViewModel {
    var isBoxMode: Bool = false
    var isBoxSelectMode: Bool = false
    var isBoxAvailable: Bool = false
    var pointsDisplay: [CGPoint] = [] // Display space
    var pointsImage: [CGPoint] = [] // Image space

    
    func setBoxMode(_ isBoxMode: Bool) {
        self.isBoxMode = isBoxMode
        if pointsDisplay.isEmpty {
            setBoxSelectMode(true)
        } else {
            setBoxSelectMode(false)
        }
    }

    private func setBoxSelectMode(_ isBoxSelectMode: Bool) {
        self.isBoxSelectMode = isBoxSelectMode
    }

    func addPoint(_ point: CGPoint) {
        guard pointsDisplay.count < 4 else { return }
        pointsDisplay.append(point)
        if pointsDisplay.count == 4 {
            isBoxAvailable = true
            setBoxSelectMode(false)
        }
    }

    func movePoint(index: Int, to location: CGPoint) {
        guard index >= 0 && index < pointsDisplay.count else { return }
        var updatedPoints = pointsDisplay // <- Copy array (not reference)
        updatedPoints[index] = location   // <- Mutate the copy
        pointsDisplay = updatedPoints     // <- Re-assign to trigger @Published
    }

    func clearBox() {
        pointsDisplay = []
        pointsImage = []
        isBoxAvailable = false
        setBoxSelectMode(true)
    }

    // MARK: - Coordinate Conversions

    func updateImageSpace(from containerSize: CGSize, imageSize: CGSize) {
        guard !pointsDisplay.isEmpty else {
            self.pointsImage = []
            return
        }

        let mapper = CoordinateMapper(containerSize: containerSize,
                                      imageSize: imageSize,
                                      scaleMode: .aspectFit)

        self.pointsImage =  pointsDisplay.map { displayPoint in
            mapper.mapPointInverse(displayPoint)
        }
        
        log("Box Image updated: \(self.pointsImage)", level: .debug)
    }

    func updateDisplaySpace(from containerSize: CGSize, imageSize: CGSize) {
        guard !pointsDisplay.isEmpty else {
            self.pointsDisplay = []
            return
        }
        
        let mapper = CoordinateMapper(containerSize: containerSize,
                                      imageSize: imageSize,
                                      scaleMode: .aspectFit)

        self.pointsDisplay =  pointsImage.map { imagePoint in
            mapper.mapPoint(imagePoint)
        }
        log("Box Display updated: \(self.pointsDisplay)", level: .debug)
    }
}
