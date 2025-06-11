
//
//  Extensions.swift
//  DataCaptureTest
//
//  Created by Shiela Cabahug on 2024/7/4.
//

import SwiftUI
import Foundation
import AVFoundation

// MARK: An extension to wrap a pixel buffer in an MTLTexture object.
extension CVPixelBuffer {
    func texture(withFormat pixelFormat: MTLPixelFormat, planeIndex: Int, addToCache cache: CVMetalTextureCache) -> MTLTexture? {
        let width = CVPixelBufferGetWidthOfPlane(self, planeIndex)
        let height = CVPixelBufferGetHeightOfPlane(self, planeIndex)
        
        var cvtexture: CVMetalTexture?
        CVMetalTextureCacheCreateTextureFromImage(nil, cache, self, nil, pixelFormat, width, height, planeIndex, &cvtexture)
        guard let texture = cvtexture else { return nil }
        return CVMetalTextureGetTexture(texture)
    }
    
}

extension MTLPixelFormat {
    var bytesPerPixel: Int {
        switch self {
        case .r8Unorm: return 1
        case .rg8Unorm: return 2
        case .rgba8Unorm, .bgra8Unorm: return 4
        case .r16Float: return 2
        // Add more cases as needed
        default: return 0
        }
    }
    
    var cvPixelFormatType: OSType {
        switch self {
        case .r8Unorm: return kCVPixelFormatType_OneComponent8
        case .rg8Unorm: return kCVPixelFormatType_TwoComponent8
        case .rgba8Unorm: return kCVPixelFormatType_32RGBA
        case .bgra8Unorm: return kCVPixelFormatType_32BGRA
        // Add more cases as needed
        default: return 0
        }
    }
}

extension CGImage {
    func toPixelBuffer(width: Int, height: Int) -> CVPixelBuffer? {
        var pixelBuffer: CVPixelBuffer?
        let attributes = [kCVPixelBufferCGImageCompatibilityKey: kCFBooleanTrue,
                          kCVPixelBufferCGBitmapContextCompatibilityKey: kCFBooleanTrue] as CFDictionary
        CVPixelBufferCreate(kCFAllocatorDefault, width, height, kCVPixelFormatType_32ARGB, attributes, &pixelBuffer)

        if let pixelBuffer = pixelBuffer {
            CVPixelBufferLockBaseAddress(pixelBuffer, CVPixelBufferLockFlags(rawValue: 0))
            let colorSpace = CGColorSpaceCreateDeviceRGB()
            let context = CGContext(data: CVPixelBufferGetBaseAddress(pixelBuffer),
                                    width: width,
                                    height: height,
                                    bitsPerComponent: 8,
                                    bytesPerRow: CVPixelBufferGetBytesPerRow(pixelBuffer),
                                    space: colorSpace,
                                    bitmapInfo: CGImageAlphaInfo.noneSkipFirst.rawValue)
            context?.draw(self, in: CGRect(x: 0, y: 0, width: width, height: height))
            CVPixelBufferUnlockBaseAddress(pixelBuffer, CVPixelBufferLockFlags(rawValue: 0))
            return pixelBuffer
        }
        return nil
    }
}

extension MTLTexture {
    func toPixelBuffer() -> CVPixelBuffer? {
        var pixelBuffer: CVPixelBuffer?
        let attributes = [kCVPixelBufferCGImageCompatibilityKey: kCFBooleanTrue,
                          kCVPixelBufferCGBitmapContextCompatibilityKey: kCFBooleanTrue] as CFDictionary
        CVPixelBufferCreate(kCFAllocatorDefault, width, height, kCVPixelFormatType_32BGRA, attributes, &pixelBuffer)

        if let pixelBuffer = pixelBuffer {
            CVPixelBufferLockBaseAddress(pixelBuffer, CVPixelBufferLockFlags(rawValue: 0))
            let pixelData = CVPixelBufferGetBaseAddress(pixelBuffer)

            let region = MTLRegionMake2D(0, 0, width, height)
            self.getBytes(pixelData!, bytesPerRow: CVPixelBufferGetBytesPerRow(pixelBuffer), from: region, mipmapLevel: 0)

            CVPixelBufferUnlockBaseAddress(pixelBuffer, CVPixelBufferLockFlags(rawValue: 0))
            return pixelBuffer
        }
        return nil
    }
    
    func getPixelValues<T>() -> [T] {
        let width = self.width
        let height = self.height
        let bytesPerRow = width * MemoryLayout<T>.stride
        let size = height * bytesPerRow
        var bytes = [UInt8](repeating: 0, count: size)
        
        getBytes(&bytes, bytesPerRow: bytesPerRow, from: MTLRegionMake2D(0, 0, width, height), mipmapLevel: 0)
        
        return bytes.withUnsafeBytes { buffer in
            Array(buffer.bindMemory(to: T.self))
        }
    }
    
    func toData() -> Data? {
        let width = self.width
        let height = self.height
        let bytesPerRow = width * 4
        var data = [UInt8](repeating: 0, count: height * bytesPerRow)
        self.getBytes(&data, bytesPerRow: bytesPerRow, from: MTLRegionMake2D(0, 0, width, height), mipmapLevel: 0)
        return Data(data)
    }
}

extension matrix_float3x3 {
    func toArray() -> [[Float]] {
        return [
            [columns.0.x, columns.0.y, columns.0.z],
            [columns.1.x, columns.1.y, columns.1.z],
            [columns.2.x, columns.2.y, columns.2.z]
        ]
    }
}

// MARK: Image Processing Extension
extension CGRect {
    var center: CGPoint {
        CGPoint(x: self.midX, y: self.midY)
    }
}

extension UIImage {
    func rotated(to orientation: UIImage.Orientation) -> UIImage? {
        guard let cgImage = self.cgImage else { return nil }
        return UIImage(cgImage: cgImage, scale: 1.0, orientation: orientation)
    }
}

extension UIImage.Orientation {
    var debugDescription: String {
        switch self {
        case .up: return "up (0)"
        case .down: return "down (2)"
        case .left: return "left (4)"
        case .right: return "right (3)"
        case .upMirrored: return "upMirrored (1)"
        case .downMirrored: return "downMirrored (5)"
        case .leftMirrored: return "leftMirrored (7)"
        case .rightMirrored: return "rightMirrored (6)"
        @unknown default: return "unknown (\(self.rawValue))"
        }
    }
}
extension UIDeviceOrientation {
    var name: String {
        switch self {
        case .portrait: return "portrait"
        case .portraitUpsideDown: return "portraitUpsideDown"
        case .landscapeLeft: return "landscapeLeft"
        case .landscapeRight: return "landscapeRight"
        case .faceUp: return "faceUp"
        case .faceDown: return "faceDown"
        case .unknown: return "unknown"
        @unknown default: return "unknown"
        }
    }
    
    // Convert UIDeviceOrientation to AVCaptureVideoOrientation
    var videoOrientation: AVCaptureVideoOrientation {
        switch self {
        case .portrait: return .portrait
        case .portraitUpsideDown: return .portraitUpsideDown
        case .landscapeLeft: return .landscapeRight  // They're opposite
        case .landscapeRight: return .landscapeLeft  // They're opposite
        default: return .portrait
        }
    }
}

extension View{
    func calcAspect(orientation: UIImage.Orientation, texture: MTLTexture?) -> CGFloat {
        guard let texture = texture else { return 1 }
        switch orientation {
        case .up:
            return CGFloat(texture.width) / CGFloat(texture.height)
        case .down:
            return CGFloat(texture.width) / CGFloat(texture.height)
        case .left:
            return  CGFloat(texture.height) / CGFloat(texture.width)
        case .right:
            return  CGFloat(texture.height) / CGFloat(texture.width)
        default:
            return CGFloat(texture.width) / CGFloat(texture.height)
        }
    }
    
    var rotationAngle: Double {
        var angle = 0.0
        switch viewOrientation {
        
        case .up:
            angle = -Double.pi / 2
        case .down:
            angle = Double.pi / 2
        case .left:
            angle = Double.pi
        case .right:
            angle = 0
        default:
            angle = 0
        }
        return angle
    }

    var viewOrientation: UIImage.Orientation {
        var result = UIImage.Orientation.up
       
        guard let currentWindowScene = UIApplication.shared.connectedScenes.first(
            where: { $0.activationState == .foregroundActive }) as? UIWindowScene
        else { return result }
        
        let interfaceOrientation = currentWindowScene.interfaceOrientation
        switch interfaceOrientation {
        case .portrait:
            result = .right
        case .portraitUpsideDown:
            result = .left
        case .landscapeLeft:
            result = .down
        case .landscapeRight:
            result = .up
        default:
            result = .up
        }
            
        return result
    }
}

