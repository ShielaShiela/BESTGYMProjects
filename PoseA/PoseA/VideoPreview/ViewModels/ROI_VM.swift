//
//  ROIModel.swift
//  PoseA
//
//  Created by Ardhika Maulidani on 6/23/25.
//

import SwiftUI

class ROIViewModel: ObservableObject {
    @Published var isROIMode: Bool = false
    @Published var isROISelectMode: Bool = false
    @Published var isROIAvailable: Bool = false
    @Published var roiDisplaySpace: CGRect? = nil // ROI in display coordinates
    @Published var roiImageSpace: CGRect? = nil // ROI in actual image coordinates
    
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
        log("Successfully set ROI.", level: .debug)
        
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
            
        // Calculate the actual display size of the image within the container
        let imageAspectRatio = imageSize.width / imageSize.height
        let containerAspectRatio = containerSize.width / containerSize.height
        
        var displaySize: CGSize
        var offsetX: CGFloat = 0
        var offsetY: CGFloat = 0
        
        if imageAspectRatio > containerAspectRatio {
            // Image is wider than container - fit to width
            displaySize = CGSize(
                width: containerSize.width,
                height: containerSize.width / imageAspectRatio
            )
            offsetY = (containerSize.height - displaySize.height) / 2
        } else {
            // Image is taller than container - fit to height
            displaySize = CGSize(
                width: containerSize.height * imageAspectRatio,
                height: containerSize.height
            )
            offsetX = (containerSize.width - displaySize.width) / 2
        }
        
        // Convert display coordinates to image coordinates
        let scaleX = imageSize.width / displaySize.width
        let scaleY = imageSize.height / displaySize.height
        
        return CGRect(
            x: (roiDisplaySpace.origin.x - offsetX) * scaleX,
            y: (roiDisplaySpace.origin.y - offsetY) * scaleY,
            width: roiDisplaySpace.width * scaleX,
            height: roiDisplaySpace.height * scaleY
        )
    }
    
    // Convert image space to display coordinates
    private func toDisplaySpace(containerSize: CGSize, imageSize: CGSize) -> CGRect {
        // Check if ROI is Available
        guard let roiImageSpace = self.roiImageSpace else {
            log("No ROI Rect Available.", level: .warn)
            return .zero
        }
        
        // Calculate the actual display size of the image within the container
        let imageAspectRatio = imageSize.width / imageSize.height
        let containerAspectRatio = containerSize.width / containerSize.height

        var displaySize: CGSize
        var offsetX: CGFloat = 0
        var offsetY: CGFloat = 0

        if imageAspectRatio > containerAspectRatio {
            // Image fits to width
            displaySize = CGSize(
                width: containerSize.width,
                height: containerSize.width / imageAspectRatio
            )
            offsetY = (containerSize.height - displaySize.height) / 2
        } else {
            // Image fits to height
            displaySize = CGSize(
                width: containerSize.height * imageAspectRatio,
                height: containerSize.height
            )
            offsetX = (containerSize.width - displaySize.width) / 2
        }

        // Calculate scaling factor from image to display space
        let scaleX = displaySize.width / imageSize.width
        let scaleY = displaySize.height / imageSize.height

        return CGRect(
            x: roiImageSpace.origin.x * scaleX + offsetX,
            y: roiImageSpace.origin.y * scaleY + offsetY,
            width: roiImageSpace.width * scaleX,
            height: roiImageSpace.height * scaleY
        )
    }
}
