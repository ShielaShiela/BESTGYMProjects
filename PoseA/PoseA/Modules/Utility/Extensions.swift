
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

extension MTLTexture {
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

extension CGImage {
    func resize(to size: CGSize) -> CGImage? {
        let width = Int(size.width)
        let height = Int(size.height)
        
        let colorSpace = CGColorSpaceCreateDeviceRGB()
        let bitmapInfo = CGBitmapInfo(rawValue: CGImageAlphaInfo.premultipliedLast.rawValue)
        
        guard let context = CGContext(
            data: nil,
            width: width,
            height: height,
            bitsPerComponent: 8,
            bytesPerRow: width * 4,
            space: colorSpace,
            bitmapInfo: bitmapInfo.rawValue
        ) else {
            return nil
        }
        
        // Draw the original image in the new size
        context.draw(self, in: CGRect(x: 0, y: 0, width: width, height: height))
        
        return context.makeImage()
    }
    
    func toRGBPixels() -> [UInt8]? {
        let width = self.width
        let height = self.height
        
        // Calculate bytes per row with 4 bytes per pixel (RGBA)
        let bytesPerPixel = 4
        let bytesPerRow = width * bytesPerPixel
        
        // Create buffer to hold pixel data
        var buffer = [UInt8](repeating: 0, count: width * height * bytesPerPixel)
        
        let colorSpace = CGColorSpaceCreateDeviceRGB()
        let bitmapInfo = CGBitmapInfo(rawValue: CGImageAlphaInfo.premultipliedLast.rawValue)
        
        // Create CGContext with buffer
        guard let context = CGContext(
            data: &buffer,
            width: width,
            height: height,
            bitsPerComponent: 8,
            bytesPerRow: bytesPerRow,
            space: colorSpace,
            bitmapInfo: bitmapInfo.rawValue
        ) else {
            return nil
        }
        
        // Draw image into context
        context.draw(self, in: CGRect(x: 0, y: 0, width: width, height: height))
        
        return buffer
    }
}

extension UIImage {
    func rotated(to orientation: UIImage.Orientation) -> UIImage? {
        guard let cgImage = self.cgImage else { return nil }
        return UIImage(cgImage: cgImage, scale: 1.0, orientation: orientation)
    }
}

// Shared Style Modifier
extension View {
    func toolbarCapsuleStyle() -> some View {
        self
            .font(.caption)
            .padding(.horizontal, 8)
            .padding(.vertical, 6) // consistent vertical
            .background(Color(.systemGray5))
            .clipShape(Capsule())
    }
}
