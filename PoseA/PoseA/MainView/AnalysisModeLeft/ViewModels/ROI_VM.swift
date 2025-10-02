//
//  ROIModel.swift
//  PoseA
//
//  Created by Ardhika Maulidani on 6/23/25.
//

import SwiftUI

@Observable
class ROIViewModel {
    var isROIMode: Bool = false
    var isROISelectMode: Bool = false
    var isROIAvailable: Bool = false
    var roiDisplaySpace: CGRect? = nil // ROI in display coordinates
    var roiImageSpace: CGRect? = nil // ROI in actual image coordinates
    
    // App State Selection
    func setROIMode(_ isROIMode: Bool) {
        self.isROIMode = isROIMode
        if roiDisplaySpace == nil && roiImageSpace == nil{
            setROISelectMode(true)
        } else {
            setROISelectMode(false)
        }
    }
    
    private func setROISelectMode(_ isROISelectMode: Bool) {
        self.isROISelectMode = isROISelectMode
    }
    
    // Update ROI Value to Database
    func updateROI(displaySpace: CGRect, containerSize: CGSize, imageSize: CGSize) {
        self.roiDisplaySpace = displaySpace
        self.roiImageSpace = self.toImageSpace(containerSize: containerSize, imageSize: imageSize)
        log("Successfully set ROI.", level: .debug)
        
        // Set Availability
        self.isROIAvailable = true
        setROISelectMode(false)
    }
    
    func updateROI(imageSpace: CGRect, containerSize: CGSize, imageSize: CGSize) {
        self.roiImageSpace = imageSpace
        self.roiDisplaySpace = self.toDisplaySpace(containerSize: containerSize, imageSize: imageSize)
        log("ROI updated to: \(self.roiImageSpace!)", level: .debug)

        // Set Availability
        self.isROIAvailable = true
        setROISelectMode(false)
    }
    
    // Clear ROI Value
    func clearROI() {
        self.roiDisplaySpace = nil
        self.roiImageSpace = nil
        
        // Set Availability
        self.isROIAvailable = false
        self.setROISelectMode(true)
    }
    
    // Convert display rectangle to image coordinates
    private func toImageSpace(containerSize: CGSize, imageSize: CGSize) -> CGRect {
        // Check if ROI is Available
        guard let roiDisplaySpace = self.roiDisplaySpace else {
            log("No ROI Rect Available.", level: .warn)
            return .zero
        }
            
        let mapper = CoordinateMapper(containerSize: containerSize,
                                      imageSize: imageSize,
                                      scaleMode: .aspectFit)
        
        let p1 = mapper.mapPointInverse(CGPoint(x: roiDisplaySpace.minX, y: roiDisplaySpace.minY), normalized: true)
        let p2 = mapper.mapPointInverse(CGPoint(x: roiDisplaySpace.maxX, y: roiDisplaySpace.maxY), normalized: true)
        
        return CGRect(x: p1.x, y: p1.y, width: p2.x - p1.x, height: p2.y - p1.y)
    }
    
    // Convert image space to display coordinates
    private func toDisplaySpace(containerSize: CGSize, imageSize: CGSize) -> CGRect {
        // Check if ROI is Available
        guard let roiImageSpace = self.roiImageSpace else {
            log("No ROI Rect Available.", level: .warn)
            return .zero
        }
        
        let mapper = CoordinateMapper(containerSize: containerSize,
                                      imageSize: imageSize,
                                      scaleMode: .aspectFit)
        
        let p1 = mapper.mapPoint(CGPoint(x: roiImageSpace.minX, y: roiImageSpace.minY), normalized: true)
        let p2 = mapper.mapPoint(CGPoint(x: roiImageSpace.maxX, y: roiImageSpace.maxY), normalized: true)

        return CGRect(x: p1.x, y: p1.y, width: p2.x - p1.x, height: p2.y - p1.y)
    }
}
