//
//  DepthRenderer.swift
//  PoseA
//
//  Created by Ardhika Maulidani on 9/26/25.
//

import MetalKit

final class DepthRenderer: NSObject, MTKViewDelegate {
    private let device: MTLDevice
    private let commandQueue: MTLCommandQueue
    private let pipelineState: MTLRenderPipelineState
    private let sampler: MTLSamplerState

    private var inputTexture: MTLTexture?
    private var maxDepth: Float = 8.0

    init(view: MTKView) throws {
        guard let device = view.device else { throw NSError(domain: "DepthRenderer", code: -1) }
        self.device = device
        self.commandQueue = device.makeCommandQueue()!

        let library = device.makeDefaultLibrary()!
        let pipelineDesc = MTLRenderPipelineDescriptor()
        pipelineDesc.vertexFunction = library.makeFunction(name: "vs_depth")
        pipelineDesc.fragmentFunction = library.makeFunction(name: "fs_depth")
        pipelineDesc.colorAttachments[0].pixelFormat = view.colorPixelFormat

        // Vertex layout (fullscreen quad)
        let vertexDescriptor = MTLVertexDescriptor()
        vertexDescriptor.attributes[0].format = .float2
        vertexDescriptor.attributes[0].offset = 0
        vertexDescriptor.attributes[0].bufferIndex = 0
        vertexDescriptor.attributes[1].format = .float2
        vertexDescriptor.attributes[1].offset = MemoryLayout<Float>.size * 2
        vertexDescriptor.attributes[1].bufferIndex = 0
        vertexDescriptor.layouts[0].stride = MemoryLayout<Float>.size * 4
        pipelineDesc.vertexDescriptor = vertexDescriptor

        self.pipelineState = try device.makeRenderPipelineState(descriptor: pipelineDesc)

        let samplerDesc = MTLSamplerDescriptor()
        samplerDesc.minFilter = .linear
        samplerDesc.magFilter = .linear
        samplerDesc.sAddressMode = .clampToEdge
        samplerDesc.tAddressMode = .clampToEdge
        self.sampler = device.makeSamplerState(descriptor: samplerDesc)!

        super.init()
        view.delegate = self
    }

    // Called externally to push new texture
    func updateInputTexture(_ texture: MTLTexture, maxDepth: Float) {
        self.inputTexture = texture
        self.maxDepth = maxDepth
    }

    // MARK: - MTKViewDelegate
    func draw(in view: MTKView) {
        guard let inputTex = inputTexture,
              let drawable = view.currentDrawable,
              let rpd = view.currentRenderPassDescriptor else { return }

        guard let cmdBuf = commandQueue.makeCommandBuffer(),
              let rce = cmdBuf.makeRenderCommandEncoder(descriptor: rpd) else { return }

        rce.setRenderPipelineState(pipelineState)
        rce.setFragmentTexture(inputTex, index: 0)
        rce.setFragmentSamplerState(sampler, index: 0)
        var maxD = maxDepth
        rce.setFragmentBytes(&maxD, length: MemoryLayout<Float>.size, index: 0)

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

        cmdBuf.present(drawable)
        cmdBuf.commit()
    }

    func mtkView(_ view: MTKView, drawableSizeWillChange size: CGSize) {
        // not needed for fullscreen quad
    }
}
