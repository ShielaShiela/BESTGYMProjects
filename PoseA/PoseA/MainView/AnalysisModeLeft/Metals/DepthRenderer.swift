//
//  DepthRenderer.swift
//  PoseA
//
//  Created by Ardhika Maulidani on 8/8/25.
//

import Metal
import MetalKit
import UIKit

final class DepthRenderer: NSObject, MTKViewDelegate {
    let device: MTLDevice
    let queue: MTLCommandQueue
    var pipelineState: MTLRenderPipelineState!
    var sampler: MTLSamplerState!
    var vertexBuffer: MTLBuffer!
    var uniformBuffer: MTLBuffer!

    // Uniform struct must match the metal layout
    struct DepthUniforms {
        var nearPlane: Float
        var farPlane: Float
        var mode: UInt32
        var padding: UInt32 = 0 // align to 16 bytes
    }

    // Current depth texture to visualize
    var depthTexture: MTLTexture?
    var uniforms = DepthUniforms(nearPlane: 0.2, farPlane: 5.0, mode: 1)

    init(mtkView: MTKView) throws {
        guard let device = MTLCreateSystemDefaultDevice() else {
            throw NSError(domain: "DepthRenderer", code: -1, userInfo: [NSLocalizedDescriptionKey: "GPU not available"])
        }
        self.device = device
        self.queue = device.makeCommandQueue()!

        super.init()

        mtkView.device = device
        mtkView.delegate = self
        mtkView.framebufferOnly = false
        mtkView.colorPixelFormat = .bgra8Unorm

        try makePipeline(mtkView: mtkView)
        makeResources()
    }

    func makePipeline(mtkView: MTKView) throws {
        let library = device.makeDefaultLibrary()!
        let vs = library.makeFunction(name: "vs_main")!
        let fs = library.makeFunction(name: "fs_main")!

        let desc = MTLRenderPipelineDescriptor()
        desc.vertexFunction = vs
        desc.fragmentFunction = fs
        desc.colorAttachments[0].pixelFormat = mtkView.colorPixelFormat

        pipelineState = try device.makeRenderPipelineState(descriptor: desc)

        let samplerDesc = MTLSamplerDescriptor()
        samplerDesc.minFilter = .linear
        samplerDesc.magFilter = .linear
        samplerDesc.sAddressMode = .clampToEdge
        samplerDesc.tAddressMode = .clampToEdge
        sampler = device.makeSamplerState(descriptor: samplerDesc)
    }

    func makeResources() {
        // Fullscreen quad (two triangles) with positions and UVs
        // positions in NDC, uv in [0,1]
        let quad: [Float] = [
            -1, -1, 0, 1,   0, 1, // bottom-left
             1, -1, 0, 1,   1, 1, // bottom-right
            -1,  1, 0, 1,   0, 0, // top-left

             1, -1, 0, 1,   1, 1, // bottom-right
             1,  1, 0, 1,   1, 0, // top-right
            -1,  1, 0, 1,   0, 0  // top-left
        ]
        let size = quad.count * MemoryLayout<Float>.size
        vertexBuffer = device.makeBuffer(bytes: quad, length: size, options: [])

        uniformBuffer = device.makeBuffer(length: MemoryLayout<DepthUniforms>.size, options: [])
        updateUniforms()
    }

    func updateUniforms() {
        var u = uniforms
        memcpy(uniformBuffer.contents(), &u, MemoryLayout<DepthUniforms>.size)
    }

    // Call this when you have a depth texture (your loadDepthTexture result)
    func setDepthTexture(_ tex: MTLTexture, near: Float? = nil, far: Float? = nil, mode: UInt32 = 1) {
        self.depthTexture = tex
        if let n = near { uniforms.nearPlane = n }
        if let f = far { uniforms.farPlane = f }
        uniforms.mode = mode
        updateUniforms()
    }

    // MARK: - MTKViewDelegate
    func mtkView(_ view: MTKView, drawableSizeWillChange size: CGSize) {
        // nothing required
    }

    func draw(in view: MTKView) {
        guard let drawable = view.currentDrawable,
              let dtx = depthTexture,
              let cmdBuffer = queue.makeCommandBuffer(),
              let rpd = view.currentRenderPassDescriptor else {
            return
        }

        let encoder = cmdBuffer.makeRenderCommandEncoder(descriptor: rpd)!
        encoder.setRenderPipelineState(pipelineState)

        // Vertex buffer: each vertex has 6 floats: pos.xyzw (4 floats) and uv.xy (2 floats)
        encoder.setVertexBuffer(vertexBuffer, offset: 0, index: 0)

        // Fragment resources
        encoder.setFragmentTexture(dtx, index: 0)
        encoder.setFragmentSamplerState(sampler, index: 0)
        encoder.setFragmentBuffer(uniformBuffer, offset: 0, index: 0)

        // Draw 6 vertices
        encoder.drawPrimitives(type: .triangle, vertexStart: 0, vertexCount: 6)
        encoder.endEncoding()

        cmdBuffer.present(drawable)
        cmdBuffer.commit()
    }
}

extension DepthRenderer {
    func renderDepthToUIImage(width: Int, height: Int) -> UIImage? {
        guard let dtx = depthTexture else { return nil }

        // 1. Create an offscreen BGRA8Unorm texture
        let texDesc = MTLTextureDescriptor.texture2DDescriptor(pixelFormat: .bgra8Unorm,
                                                               width: width,
                                                               height: height,
                                                               mipmapped: false)
        texDesc.usage = [.renderTarget, .shaderRead]
        guard let outTexture = device.makeTexture(descriptor: texDesc) else { return nil }

        // 2. Create render pass descriptor
        let rpd = MTLRenderPassDescriptor()
        rpd.colorAttachments[0].texture = outTexture
        rpd.colorAttachments[0].loadAction = .clear
        rpd.colorAttachments[0].storeAction = .store
        rpd.colorAttachments[0].clearColor = MTLClearColorMake(0, 0, 0, 1)

        // 3. Encode render pass
        guard let cmdBuffer = queue.makeCommandBuffer(),
              let encoder = cmdBuffer.makeRenderCommandEncoder(descriptor: rpd) else {
            return nil
        }

        encoder.setRenderPipelineState(pipelineState)
        encoder.setVertexBuffer(vertexBuffer, offset: 0, index: 0)
        encoder.setFragmentTexture(dtx, index: 0)
        encoder.setFragmentSamplerState(sampler, index: 0)
        encoder.setFragmentBuffer(uniformBuffer, offset: 0, index: 0)
        encoder.drawPrimitives(type: .triangle, vertexStart: 0, vertexCount: 6)
        encoder.endEncoding()

        cmdBuffer.commit()
        cmdBuffer.waitUntilCompleted()

        // 4. Read back pixels
        let bytesPerPixel = 4
        let bytesPerRow = bytesPerPixel * width
        let dataSize = bytesPerRow * height
        var rawData = [UInt8](repeating: 0, count: dataSize)

        let region = MTLRegionMake2D(0, 0, width, height)
        outTexture.getBytes(&rawData,
                            bytesPerRow: bytesPerRow,
                            from: region,
                            mipmapLevel: 0)

        // 5. Create CGImage
        guard let providerRef = CGDataProvider(data: Data(rawData) as CFData) else { return nil }
        guard let cgImage = CGImage(width: width,
                                    height: height,
                                    bitsPerComponent: 8,
                                    bitsPerPixel: 32,
                                    bytesPerRow: bytesPerRow,
                                    space: CGColorSpaceCreateDeviceRGB(),
                                    bitmapInfo: CGBitmapInfo(rawValue: CGImageAlphaInfo.premultipliedLast.rawValue),
                                    provider: providerRef,
                                    decode: nil,
                                    shouldInterpolate: false,
                                    intent: .defaultIntent) else { return nil }

        return UIImage(cgImage: cgImage)
    }
}
