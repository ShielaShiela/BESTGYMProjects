//
//  DepthRenderer.swift
//  PoseA
//
//  Created by Ardhika Maulidani on 9/26/25.
//

import MetalKit

class DepthRenderer {
    let device: MTLDevice
    let commandQueue: MTLCommandQueue
    let pipelineState: MTLRenderPipelineState
    let sampler: MTLSamplerState
    
    init(view: MTKView) throws {
        guard let device = view.device else { throw NSError() }
        self.device = device
        self.commandQueue = device.makeCommandQueue()!

        let library = device.makeDefaultLibrary()!
        let pipelineDesc = MTLRenderPipelineDescriptor()
        pipelineDesc.vertexFunction = library.makeFunction(name: "vs_depth")
        pipelineDesc.fragmentFunction = library.makeFunction(name: "fs_depth")
        pipelineDesc.colorAttachments[0].pixelFormat = view.colorPixelFormat

        // Add vertex descriptor
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
        pipelineDesc.vertexDescriptor = vertexDescriptor

        self.pipelineState = try device.makeRenderPipelineState(descriptor: pipelineDesc)

        let samplerDesc = MTLSamplerDescriptor()
        samplerDesc.minFilter = .linear
        samplerDesc.magFilter = .linear
        samplerDesc.sAddressMode = .clampToEdge
        samplerDesc.tAddressMode = .clampToEdge
        self.sampler = device.makeSamplerState(descriptor: samplerDesc)!
    }

    
    func draw(texture: MTLTexture, in view: MTKView, maxDepth: Float = 15.0) {
        guard let cmdBuf = commandQueue.makeCommandBuffer(),
              let rpd = view.currentRenderPassDescriptor,
              let rce = cmdBuf.makeRenderCommandEncoder(descriptor: rpd) else { return }
        
        rce.setRenderPipelineState(pipelineState)
        rce.setFragmentTexture(texture, index: 0)
        rce.setFragmentSamplerState(sampler, index: 0)
        
        var maxD = maxDepth
        rce.setFragmentBytes(&maxD, length: MemoryLayout<Float>.size, index: 0)
        
        // Fullscreen quad
        let verts: [Float] = [
            -1,-1, 0,1,
             1,-1, 1,1,
            -1, 1, 0,0,
             1, 1, 1,0
        ]
        let vb = device.makeBuffer(bytes: verts, length: verts.count * MemoryLayout<Float>.size, options: [])
        rce.setVertexBuffer(vb, offset: 0, index: 0)
        
        rce.drawPrimitives(type: .triangleStrip, vertexStart: 0, vertexCount: 4)
        
        rce.endEncoding()
        if let drawable = view.currentDrawable {
            cmdBuf.present(drawable)
        }
        cmdBuf.commit()
    }
}
