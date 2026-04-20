//
//  BoxVM.swift
//  PoseA
//
//  Created by Ardhika Maulidani on 7/10/25.
//

import SwiftUI

@Observable
class BarPointVM {
    var isSelectMode: Bool = false
    var isFirstPointAvailable: Bool = false
    var isSecondPointAvailable: Bool = false
    var currentEditingPoint: Int = 0 // 0 for first point, 1 for second point
    var pointsDisplay: [Int : CGPoint] = [:] // Display space
    var pointsImage: [Int : CGPoint] = [:] // Image space
    
    func setSelectMode(_ isSelectMode: Bool) {
        self.isSelectMode = isSelectMode
    }
    
    func nextPoint() {
        self.currentEditingPoint = (currentEditingPoint == 0) ? 1 : 0
    }
    
    func addPoint(pos: Int, point: CGPoint) {
        guard pointsDisplay.count < 2 else { return }
        pointsDisplay[pos] = (point)
        
        if pos == 0 {
            isFirstPointAvailable = true
        } else {
            isSecondPointAvailable = true
        }
    }

    func movePoint(index: Int, to location: CGPoint) {
        guard index >= 0 && index < pointsDisplay.count else { return }
        var updatedPoints = pointsDisplay // <- Copy array (not reference)
        updatedPoints[index] = location   // <- Mutate the copy
        pointsDisplay = updatedPoints     // <- Re-assign to trigger @Published
    }

    func clear() {
        pointsDisplay = [:]
        pointsImage = [:]
        isFirstPointAvailable = false
        isSecondPointAvailable = false
        currentEditingPoint = 0
    }

    func syncBarPointsToMediaManager(mediaManagerVM: MediaManagerVM) {
        if pointsImage.count < 2 { return }
        mediaManagerVM.updateBarData(self.pointsImage, source: .processing)
    }
    
    // MARK: - Coordinate Conversions

    func updateImageSpace(from containerSize: CGSize, imageSize: CGSize) {
        guard !pointsDisplay.isEmpty else {
            self.pointsImage = [:]
            return
        }

        let mapper = CoordinateMapper(containerSize: containerSize,
                                      imageSize: imageSize,
                                      scaleMode: .aspectFit)
        
        for i in 0..<pointsDisplay.count {
            self.pointsImage[i] = mapper.mapPointInverse(self.pointsDisplay[i]!)
        }
        log("Box Image updated: \(self.pointsImage)", level: .debug)
    }

    func updateDisplaySpace(from containerSize: CGSize, imageSize: CGSize) {
        guard !pointsImage.isEmpty else {
            self.pointsDisplay = [:]
            return
        }
        
        let mapper = CoordinateMapper(containerSize: containerSize,
                                      imageSize: imageSize,
                                      scaleMode: .aspectFit)

        for i in 0..<pointsImage.count {
            self.pointsDisplay[i] = mapper.mapPoint(self.pointsImage[i]!)
        }
        
        log("Box Display updated: \(self.pointsDisplay)", level: .debug)
    }
}
