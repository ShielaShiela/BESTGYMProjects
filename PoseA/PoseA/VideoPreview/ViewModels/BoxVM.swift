//
//  BoxVM.swift
//  PoseA
//
//  Created by Ardhika Maulidani on 7/10/25.
//

import SwiftUI

class BoxViewModel: ObservableObject {
    @Published var isBoxMode: Bool = false
    @Published var isBoxSelectMode: Bool = false
    @Published var isBoxAvailable: Bool = false
    @Published var pointsDisplay: [CGPoint] = [] // Display space
    @Published var pointsImage: [CGPoint] = [] // Image space

    
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
        pointsDisplay[index] = location
    }

    func clearBox() {
        pointsDisplay = []
        pointsImage = []
        isBoxAvailable = false
        setBoxSelectMode(true)
    }

    // MARK: - Coordinate Conversions

    func updateImageSpace(from containerSize: CGSize, imageSize: CGSize) {
        self.pointsImage = toImageSpace(containerSize: containerSize, imageSize: imageSize)
    }

    func updateDisplaySpace(from containerSize: CGSize, imageSize: CGSize) {
        self.pointsDisplay = toDisplaySpace(containerSize: containerSize, imageSize: imageSize)
    }

    private func toImageSpace(containerSize: CGSize, imageSize: CGSize) -> [CGPoint] {
        guard !pointsDisplay.isEmpty else { return [] }

        let imageAspectRatio = imageSize.width / imageSize.height
        let containerAspectRatio = containerSize.width / containerSize.height

        var displaySize: CGSize
        var offsetX: CGFloat = 0
        var offsetY: CGFloat = 0

        if imageAspectRatio > containerAspectRatio {
            // Fit to width
            displaySize = CGSize(width: containerSize.width, height: containerSize.width / imageAspectRatio)
            offsetY = (containerSize.height - displaySize.height) / 2
        } else {
            // Fit to height
            displaySize = CGSize(width: containerSize.height * imageAspectRatio, height: containerSize.height)
            offsetX = (containerSize.width - displaySize.width) / 2
        }

        let scaleX = imageSize.width / displaySize.width
        let scaleY = imageSize.height / displaySize.height

        return pointsDisplay.map { displayPoint in
            CGPoint(
                x: (displayPoint.x - offsetX) * scaleX,
                y: (displayPoint.y - offsetY) * scaleY
            )
        }
    }

    private func toDisplaySpace(containerSize: CGSize, imageSize: CGSize) -> [CGPoint] {
        guard !pointsImage.isEmpty else { return [] }

        let imageAspectRatio = imageSize.width / imageSize.height
        let containerAspectRatio = containerSize.width / containerSize.height

        var displaySize: CGSize
        var offsetX: CGFloat = 0
        var offsetY: CGFloat = 0

        if imageAspectRatio > containerAspectRatio {
            displaySize = CGSize(width: containerSize.width, height: containerSize.width / imageAspectRatio)
            offsetY = (containerSize.height - displaySize.height) / 2
        } else {
            displaySize = CGSize(width: containerSize.height * imageAspectRatio, height: containerSize.height)
            offsetX = (containerSize.width - displaySize.width) / 2
        }

        let scaleX = displaySize.width / imageSize.width
        let scaleY = displaySize.height / imageSize.height

        return pointsImage.map { imagePoint in
            CGPoint(
                x: imagePoint.x * scaleX + offsetX,
                y: imagePoint.y * scaleY + offsetY
            )
        }
    }
}
