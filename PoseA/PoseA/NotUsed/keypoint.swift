//import Foundation
//import CoreML
//import UIKit
//import Metal
//import Combine
//
//// MARK: - KeypointData Model
//
//struct KeypointData: Codable, Identifiable, Equatable {
//    // Core properties
//    let id: UUID
//    let name: String
//    var x: CGFloat
//    var y: CGFloat
//    let confidence: Float
//    let depth: Float
//    let frameIndex: Int
//    
//    // Computed properties for convenient access
//    var position: CGPoint {
//        return CGPoint(x: x, y: y)
//    }
//    
//    // Optional metadata
//    var metadata: [String: String]?
//    
//    // Default initializer
//    init(
//        name: String,
//        x: CGFloat,
//        y: CGFloat,
//        confidence: Float,
//        depth: Float,
//        frameIndex: Int,
//        id: UUID = UUID(),
//        metadata: [String: String]? = nil
//    ) {
//        self.id = id
//        self.name = name
//        self.x = x
//        self.y = y
//        self.confidence = confidence
//        self.depth = depth
//        self.frameIndex = frameIndex
//        self.metadata = metadata
//    }
//    
//    // Helper method to create a copy with transformed coordinates
//    func withTransformedCoordinates(x: CGFloat, y: CGFloat) -> KeypointData {
//        return KeypointData(
//            name: self.name,
//            x: x,
//            y: y,
//            confidence: self.confidence,
//            depth: self.depth,
//            frameIndex: self.frameIndex,
//            id: self.id,
//            metadata: self.metadata
//        )
//    }
//    
//    // Get a rotated position based on the current rotation value
//    func getRotatedPosition(frameSize: CGSize, rotation: Int) -> CGPoint {
//        // First, normalize coordinates to [0,1] range
//        let normalizedX = x / frameSize.width
//        let normalizedY = y / frameSize.height
//        
//        // Apply rotation to normalized coordinates
//        var rotatedX: CGFloat
//        var rotatedY: CGFloat
//        
//        switch rotation % 4 {
//        case 0: // 0 degrees - no change
//            rotatedX = normalizedX
//            rotatedY = normalizedY
//        case 1: // 90 degrees clockwise
//            rotatedX = 1.0 - normalizedY
//            rotatedY = normalizedX
//        case 2: // 180 degrees
//            rotatedX = 1.0 - normalizedX
//            rotatedY = 1.0 - normalizedY
//        case 3: // 270 degrees clockwise (90 counterclockwise)
//            rotatedX = normalizedY
//            rotatedY = 1.0 - normalizedX
//        default:
//            rotatedX = normalizedX
//            rotatedY = normalizedY
//        }
//        
//        // Convert back to view coordinates
//        return CGPoint(
//            x: rotatedX * frameSize.width,
//            y: rotatedY * frameSize.height
//        )
//    }
//    
//    // Get the normalized keypoint position (0-1 range)
//    func getNormalizedPosition(frameSize: CGSize) -> CGPoint {
//        return CGPoint(
//            x: x / frameSize.width,
//            y: y / frameSize.height
//        )
//    }
//    
//    // Create a new keypoint at a rotated position
//    func rotated(frameSize: CGSize, rotation: Int) -> KeypointData {
//        let rotatedPoint = getRotatedPosition(frameSize: frameSize, rotation: rotation)
//        return withTransformedCoordinates(x: rotatedPoint.x, y: rotatedPoint.y)
//    }
//    
//    // Helper to check if this keypoint is valid (confidence above threshold)
//    func isValid(threshold: Float = 0.3) -> Bool {
//        return confidence > threshold
//    }
//    
//    // Return a transformed keypoint applying zoom and offset
//    func withZoomAndOffset(scale: CGFloat, offset: CGSize) -> KeypointData {
//        let newX = x * scale + offset.width
//        let newY = y * scale + offset.height
//        return withTransformedCoordinates(x: newX, y: newY)
//    }
//    
//    // Create transformed keypoint with zoom, offset, and rotation
//    func withFullTransform(frameSize: CGSize, rotation: Int, scale: CGFloat, offset: CGSize) -> KeypointData {
//        // First apply rotation
//        let rotated = getRotatedPosition(frameSize: frameSize, rotation: rotation)
//        
//        // Then apply zoom and offset
//        let finalX = rotated.x * scale + offset.width
//        let finalY = rotated.y * scale + offset.height
//        
//        return withTransformedCoordinates(x: finalX, y: finalY)
//    }
//    
//    // Equatable implementation
//    static func == (lhs: KeypointData, rhs: KeypointData) -> Bool {
//        return lhs.id == rhs.id
//    }
//}
//
//// MARK: - Frame Update Publisher
//
//class FrameUpdatePublisher {
//    static let shared = FrameUpdatePublisher()
//    
//    private init() {}
//    
//    // Use NotificationCenter for broadcasting frame changes
//    func notifyFrameChanged(frameIndex: Int) {
//        NotificationCenter.default.post(
//            name: NSNotification.Name("FrameChanged"),
//            object: nil,
//            userInfo: ["frameIndex": frameIndex]
//        )
//    }
//}
//
//// MARK: - CGImage Extensions
//
//extension CGImage {
//    func resize(to size: CGSize) -> CGImage? {
//        let width = Int(size.width)
//        let height = Int(size.height)
//        
//        let colorSpace = CGColorSpaceCreateDeviceRGB()
//        let bitmapInfo = CGBitmapInfo(rawValue: CGImageAlphaInfo.premultipliedLast.rawValue)
//        
//        guard let context = CGContext(
//            data: nil,
//            width: width,
//            height: height,
//            bitsPerComponent: 8,
//            bytesPerRow: width * 4,
//            space: colorSpace,
//            bitmapInfo: bitmapInfo.rawValue
//        ) else {
//            return nil
//        }
//        
//        // Draw the original image in the new size
//        context.draw(self, in: CGRect(x: 0, y: 0, width: width, height: height))
//        
//        return context.makeImage()
//    }
//    
//    func toRGBPixels() -> [UInt8]? {
//        let width = self.width
//        let height = self.height
//        
//        // Calculate bytes per row with 4 bytes per pixel (RGBA)
//        let bytesPerPixel = 4
//        let bytesPerRow = width * bytesPerPixel
//        
//        // Create buffer to hold pixel data
//        var buffer = [UInt8](repeating: 0, count: width * height * bytesPerPixel)
//        
//        let colorSpace = CGColorSpaceCreateDeviceRGB()
//        let bitmapInfo = CGBitmapInfo(rawValue: CGImageAlphaInfo.premultipliedLast.rawValue)
//        
//        // Create CGContext with buffer
//        guard let context = CGContext(
//            data: &buffer,
//            width: width,
//            height: height,
//            bitsPerComponent: 8,
//            bytesPerRow: bytesPerRow,
//            space: colorSpace,
//            bitmapInfo: bitmapInfo.rawValue
//        ) else {
//            return nil
//        }
//        
//        // Draw image into context
//        context.draw(self, in: CGRect(x: 0, y: 0, width: width, height: height))
//        
//        return buffer
//    }
//}
//
