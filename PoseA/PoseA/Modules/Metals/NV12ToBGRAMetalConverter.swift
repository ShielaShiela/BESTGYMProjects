//
//  NV12ToBGRAMetalConverter.swift
//  PoseA
//
//  Created by Ardhika Maulidani on 8/21/25.
//

import Metal
import MetalKit
import CoreVideo
import UIKit

class NV12ToBGRAMetalConverter {
    let device: MTLDevice
    let commandQueue: MTLCommandQueue
    let library: MTLLibrary
    let pipelineState: MTLRenderPipelineState
    let samplerState: MTLSamplerState
    var textureCache: CVMetalTextureCache!

    // Rotation enum for convenience
    enum Rotation: UInt {
        case rotation0 = 0
        case rotation90 = 90
        case rotation180 = 180
        case rotation270 = 270
    }

    init(device: MTLDevice) throws {
        self.device = device
        self.commandQueue = device.makeCommandQueue()!
        self.library = device.makeDefaultLibrary()!

        // Sampler
        let samplerDesc = MTLSamplerDescriptor()
        samplerDesc.minFilter = .linear
        samplerDesc.magFilter = .linear
        samplerDesc.sAddressMode = .clampToEdge
        samplerDesc.tAddressMode = .clampToEdge
        self.samplerState = device.makeSamplerState(descriptor: samplerDesc)!

        // Vertex & Fragment
        let pipelineDescriptor = MTLRenderPipelineDescriptor()
        pipelineDescriptor.vertexFunction = library.makeFunction(name: "vs_nv12_to_bgra")
        pipelineDescriptor.fragmentFunction = library.makeFunction(name: "fs_nv12_to_bgra")
        pipelineDescriptor.colorAttachments[0].pixelFormat = .bgra8Unorm

        // Vertex descriptor
        let vertexDescriptor = MTLVertexDescriptor()
        vertexDescriptor.attributes[0].format = .float2
        vertexDescriptor.attributes[0].offset = 0
        vertexDescriptor.attributes[0].bufferIndex = 0

        vertexDescriptor.attributes[1].format = .float2
        vertexDescriptor.attributes[1].offset = MemoryLayout<Float>.size * 2
        vertexDescriptor.attributes[1].bufferIndex = 0

        vertexDescriptor.layouts[0].stride = MemoryLayout<Float>.size * 4
        vertexDescriptor.layouts[0].stepRate = 1
        vertexDescriptor.layouts[0].stepFunction = .perVertex

        pipelineDescriptor.vertexDescriptor = vertexDescriptor

        self.pipelineState = try device.makeRenderPipelineState(descriptor: pipelineDescriptor)

        CVMetalTextureCacheCreate(nil, nil, device, nil, &textureCache)
    }

    func nv12ToBGRAPixelBuffer(nv12PixelBuffer: CVPixelBuffer,
                               rotation: UInt = 0) -> CVPixelBuffer? {
        let width = CVPixelBufferGetWidth(nv12PixelBuffer)
        let height = CVPixelBufferGetHeight(nv12PixelBuffer)
        
        // If 90° or 270°, swap output buffer dimensions
        let outWidth = (rotation == 90 || rotation == 270) ? height : width
        let outHeight = (rotation == 90 || rotation == 270) ? width : height
        
        guard let bgraBuffer = makeBGRAPixelBuffer(width: outWidth, height: outHeight) else {
            return nil
        }
        
        // --- Y & UV textures setup same as before ---
        var yTexRef: CVMetalTexture?
        var uvTexRef: CVMetalTexture?
        CVMetalTextureCacheCreateTextureFromImage(kCFAllocatorDefault, textureCache,
                                                  nv12PixelBuffer, nil,
                                                  .r8Unorm, width, height, 0, &yTexRef)
        CVMetalTextureCacheCreateTextureFromImage(kCFAllocatorDefault, textureCache,
                                                  nv12PixelBuffer, nil,
                                                  .rg8Unorm, width/2, height/2, 1, &uvTexRef)
        
        guard let yTex = CVMetalTextureGetTexture(yTexRef!),
              let uvTex = CVMetalTextureGetTexture(uvTexRef!) else { return nil }
        
        // Output BGRA texture backed by PixelBuffer
        var bgraTexRef: CVMetalTexture?
        CVMetalTextureCacheCreateTextureFromImage(kCFAllocatorDefault, textureCache,
                                                  bgraBuffer, nil,
                                                  .bgra8Unorm, outWidth, outHeight, 0, &bgraTexRef)
        guard let outTex = CVMetalTextureGetTexture(bgraTexRef!) else { return nil }
        
        // Render pass
        let desc = MTLRenderPassDescriptor()
        desc.colorAttachments[0].texture = outTex
        desc.colorAttachments[0].loadAction = .dontCare
        desc.colorAttachments[0].storeAction = .store
        
        guard let cmdBuffer = commandQueue.makeCommandBuffer(),
              let encoder = cmdBuffer.makeRenderCommandEncoder(descriptor: desc) else { return nil }
        
        encoder.setRenderPipelineState(pipelineState)
        encoder.setFragmentTexture(yTex, index: 0)
        encoder.setFragmentTexture(uvTex, index: 1)
        encoder.setFragmentSamplerState(samplerState, index: 0)
        
        // Adjust quad vertices depending on rotation
        var quad = quadVertices(for: rotation)
        
        encoder.setVertexBytes(&quad,
                               length: MemoryLayout<Float>.size * quad.count,
                               index: 0)
        
        encoder.drawPrimitives(type: .triangleStrip, vertexStart: 0, vertexCount: 4)

        encoder.endEncoding()
        cmdBuffer.commit()
        cmdBuffer.waitUntilCompleted()
        
        return bgraBuffer
    }

    private func quadVertices(for rotation: UInt) -> [Float] {
        switch rotation {
        case 90:
            // Rotated clockwise: (0,0) → (1,0), (1,0) → (1,1), etc.
            return [
                -1, -1, 1, 1,   // bottom-left  -> top-right
                 1, -1, 1, 0,   // bottom-right -> bottom-right
                -1,  1, 0, 1,   // top-left     -> top-left
                 1,  1, 0, 0    // top-right    -> bottom-left
            ]
        case 180:
            // Flipped: (0,0) → (1,1), (1,0) → (0,1), etc.
            return [
                -1, -1, 1, 0,
                 1, -1, 0, 0,
                -1,  1, 1, 1,
                 1,  1, 0, 1
            ]
        case 270:
            // Rotated counter-clockwise: (0,0) → (0,1), (1,0) → (0,0), etc.
            return [
                -1, -1, 0, 0,
                 1, -1, 0, 1,
                -1,  1, 1, 0,
                 1,  1, 1, 1
            ]
        default: // 0
            return [
                -1, -1, 0, 1,
                 1, -1, 1, 1,
                -1,  1, 0, 0,
                 1,  1, 1, 0
            ]
        }
    }

    private func makeBGRAPixelBuffer(width: Int, height: Int) -> CVPixelBuffer? {
        var pixelBuffer: CVPixelBuffer?
        let attrs: [CFString: Any] = [
            kCVPixelBufferPixelFormatTypeKey: kCVPixelFormatType_32BGRA,
            kCVPixelBufferWidthKey: width,
            kCVPixelBufferHeightKey: height,
            kCVPixelBufferMetalCompatibilityKey: true,
            kCVPixelBufferIOSurfacePropertiesKey: [:]
        ]
        CVPixelBufferCreate(nil, width, height, kCVPixelFormatType_32BGRA, attrs as CFDictionary, &pixelBuffer)
        return pixelBuffer
    }
}
