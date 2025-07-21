//
//  CameraDataModel.swift
//  PoseA
//
//  Created by Ardhika Maulidani on 6/15/25.
//

import SwiftUI
import Metal
import AVFoundation

struct MetadataInfo {
    let intrinsics: matrix_float3x3
    let referenceSize: CGSize
    let depthCenter: Float16
}

struct TextureInfo {
    let yWidth: Int, yHeight: Int, yPixelFormat: MTLPixelFormat
    let cbcrWidth: Int, cbcrHeight: Int, cbcrPixelFormat: MTLPixelFormat
    let depthWidth: Int, depthHeight: Int
}

class FrameDataModel: NSObject{
    // Define Variable
    var depth: MTLTexture?
    var colorY: MTLTexture?
    var colorCbCr: MTLTexture?
    var cameraIntrinsics: matrix_float3x3
    var cameraReferenceDimensions: CGSize
    var depthCenter: Float16
    var originalDepth: AVDepthData?
    var colorImage: UIImage?
    var processedImage: UIImage?
    
    init(depth: MTLTexture? = nil,
         colorY: MTLTexture? = nil,
         colorCbCr: MTLTexture? = nil,
         cameraIntrinsics: matrix_float3x3 = matrix_identity_float3x3,
         cameraReferenceDimensions: CGSize = .zero,
         depthCenter: Float16 = 0,
         originalDepth: AVDepthData? = nil,
         colorImage: UIImage? = nil,
         processedImage: UIImage? = nil){
        
        self.depth = depth
        self.colorY = colorY
        self.colorCbCr = colorCbCr
        self.cameraIntrinsics = cameraIntrinsics
        self.cameraReferenceDimensions = cameraReferenceDimensions
        self.depthCenter = depthCenter
        self.originalDepth = originalDepth
        self.colorImage = colorImage
        self.processedImage = processedImage
    }
}
