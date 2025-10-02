//
//  rotateDepthMetal.swift
//  PoseA
//
//  Created by Ardhika Maulidani on 9/26/25.
//

import MetalKit

class PixelBufferRotation {
    let device: MTLDevice
    let commandQueue: MTLCommandQueue
    let pipelineState: MTLRenderPipelineState
    let samplerState: MTLSamplerState
    var textureCache: CVMetalTextureCache!
    
    init(device: MTLDevice) throws {
        self.device = device
        self.commandQueue = device.makeCommandQueue()!
        
        let library = device.makeDefaultLibrary()!
        
        let samplerDesc = MTLSamplerDescriptor()
        samplerDesc.minFilter = .nearest
        samplerDesc.magFilter = .nearest
        samplerDesc.sAddressMode = .clampToEdge
        samplerDesc.tAddressMode = .clampToEdge
        self.samplerState = device.makeSamplerState(descriptor: samplerDesc)!
        
        let pipelineDescriptor = MTLRenderPipelineDescriptor()
        pipelineDescriptor.vertexFunction = library.makeFunction(name: "vs_fullscreen")
        pipelineDescriptor.fragmentFunction = library.makeFunction(name: "fs_rotate_depth")
        pipelineDescriptor.colorAttachments[0].pixelFormat = .r16Float
        
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
    
    /// Rotate a depth pixel buffer (DepthFloat16) on GPU, return a new rotated CVPixelBuffer
    func rotate(pixelBuffer: CVPixelBuffer, rotation: UInt) -> CVPixelBuffer? {
        let width = CVPixelBufferGetWidth(pixelBuffer)
        let height = CVPixelBufferGetHeight(pixelBuffer)
        let outWidth = (rotation == 90 || rotation == 270) ? height : width
        let outHeight = (rotation == 90 || rotation == 270) ? width : height

        // Source texture
        var cvSrcTex: CVMetalTexture?
        CVMetalTextureCacheCreateTextureFromImage(nil, textureCache, pixelBuffer,
                                                  nil, .r16Float, width, height, 0, &cvSrcTex)
        guard let srcTex = CVMetalTextureGetTexture(cvSrcTex!) else { return nil }

        // Destination pixel buffer (Metal-compatible)
        var dstPixelBuffer: CVPixelBuffer?
        let attrs: [String: Any] = [
            kCVPixelBufferMetalCompatibilityKey as String: true,
            kCVPixelBufferIOSurfacePropertiesKey as String: [:]
        ]
        let status = CVPixelBufferCreate(nil, outWidth, outHeight,
                                         kCVPixelFormatType_DepthFloat16,
                                         attrs as CFDictionary, &dstPixelBuffer)
        guard status == kCVReturnSuccess, let dstBuffer = dstPixelBuffer else { return nil }

        // Destination texture
        var cvDstTex: CVMetalTexture?
        CVMetalTextureCacheCreateTextureFromImage(nil, textureCache, dstBuffer,
                                                  nil, .r16Float, outWidth, outHeight, 0, &cvDstTex)
        guard let dstTex = CVMetalTextureGetTexture(cvDstTex!) else { return nil }

        // Render pass
        guard let cmdBuf = commandQueue.makeCommandBuffer() else { return nil }
        let rpd = MTLRenderPassDescriptor()
        rpd.colorAttachments[0].texture = dstTex
        rpd.colorAttachments[0].loadAction = .dontCare
        rpd.colorAttachments[0].storeAction = .store

        guard let rEncoder = cmdBuf.makeRenderCommandEncoder(descriptor: rpd) else { return nil }
        rEncoder.setRenderPipelineState(pipelineState)
        rEncoder.setFragmentTexture(srcTex, index: 0)
        rEncoder.setFragmentSamplerState(samplerState, index: 0)

        // Use quad vertices for rotation (same approach as NV12 converter)
        var quad = quadVertices(for: rotation)
        rEncoder.setVertexBytes(&quad, length: MemoryLayout<Float>.size * quad.count, index: 0)

        rEncoder.drawPrimitives(type: .triangleStrip, vertexStart: 0, vertexCount: 4)
        rEncoder.endEncoding()

        cmdBuf.commit()
        cmdBuf.waitUntilCompleted()

        return dstBuffer
    }

    private func quadVertices(for rotation: UInt) -> [Float] {
        switch rotation {
        case 90:
            return [
                -1, -1, 1, 1,
                 1, -1, 1, 0,
                -1,  1, 0, 1,
                 1,  1, 0, 0
            ]
        case 180:
            return [
                -1, -1, 1, 0,
                 1, -1, 0, 0,
                -1,  1, 1, 1,
                 1,  1, 0, 1
            ]
        case 270:
            return [
                -1, -1, 0, 0,
                 1, -1, 0, 1,
                -1,  1, 1, 0,
                 1,  1, 1, 1
            ]
        default:
            return [
                -1, -1, 0, 1,
                 1, -1, 1, 1,
                -1,  1, 0, 0,
                 1,  1, 1, 0
            ]
        }
    }
}
