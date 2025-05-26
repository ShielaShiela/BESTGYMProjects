//
//  CVPixelBufferExtension.swift
//  DataCaptureTest
//
//  Created by Shiela Cabahug on 2024/7/4.
//

/*
See LICENSE folder for this sample’s licensing information.

Abstract:
An extension to wrap a pixel buffer in an MTLTexture object.
*/

import Foundation
import AVFoundation

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
