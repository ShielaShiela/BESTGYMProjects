//import SwiftUI
//import MetalKit
//import Metal
//
//struct MetalTextureViewFused: UIViewRepresentable, MetalRepresentable {
//    var rotationAngle: Double
//    @Binding var minDepth: Float
//    @Binding var maxDepth: Float
//    var capturedData: CameraCapturedData
//    
//    func makeCoordinator() -> MTKFusedTextureCoordinator {
//        MTKFusedTextureCoordinator(parent: self)
//    }
//}
//
//final class MTKFusedTextureCoordinator: MTKCoordinator<MetalTextureViewFused> {
//    override func preparePipelineAndDepthState() {
//        guard let metalDevice = mtkView.device else { fatalError("Expected a Metal device.") }
//        do {
//            let library = MetalEnvironment.shared.metalLibrary
//            let pipelineDescriptor = MTLRenderPipelineDescriptor()
//            pipelineDescriptor.colorAttachments[0].pixelFormat = .bgra8Unorm
//            pipelineDescriptor.vertexFunction = library.makeFunction(name: "planeVertexShader")
//            pipelineDescriptor.fragmentFunction = library.makeFunction(name: "fusedDepthEdgeFragmentShader")
//            pipelineDescriptor.vertexDescriptor = createPlaneMetalVertexDescriptor()
//            pipelineDescriptor.depthAttachmentPixelFormat = .depth32Float
//            pipelineState = try metalDevice.makeRenderPipelineState(descriptor: pipelineDescriptor)
//            
//            let depthDescriptor = MTLDepthStencilDescriptor()
//            depthDescriptor.isDepthWriteEnabled = true
//            depthDescriptor.depthCompareFunction = .less
//            depthState = metalDevice.makeDepthStencilState(descriptor: depthDescriptor)
//        } catch {
//            print("Unexpected error: \(error).")
//        }
//    }
//    
//    override func draw(in view: MTKView) {
//        guard parent.capturedData.depth != nil else {
//            print("Depth data not available; skipping a draw.")
//            return
//        }
//        guard let commandBuffer = metalCommandQueue.makeCommandBuffer() else { return }
//        guard let passDescriptor = view.currentRenderPassDescriptor else { return }
//        guard let encoder = commandBuffer.makeRenderCommandEncoder(descriptor: passDescriptor) else { return }
//        
//        let vertexData: [Float] = [-1, -1, 1, 1,
//                                   1, -1, 1, 0,
//                                   -1,  1, 0, 1,
//                                   1,  1, 0, 0]
//        var texelSize = float2(1.0 / Float(parent.capturedData.depth!.width),
//                               1.0 / Float(parent.capturedData.depth!.height))
//        
//        encoder.setVertexBytes(vertexData, length: vertexData.count * MemoryLayout<Float>.stride, index: 0)
//        encoder.setFragmentBytes(&parent.minDepth, length: MemoryLayout<Float>.stride, index: 0)
//        encoder.setFragmentBytes(&parent.maxDepth, length: MemoryLayout<Float>.stride, index: 1)
//        encoder.setFragmentBytes(&texelSize, length: MemoryLayout<float2>.stride, index: 2)
//        
//        encoder.setFragmentTexture(parent.capturedData.depth!, index: 0)
//        encoder.setFragmentTexture(parent.capturedData.colorY, index: 1)
//        encoder.setDepthStencilState(depthState)
//        encoder.setRenderPipelineState(pipelineState)
//        encoder.drawPrimitives(type: .triangleStrip, vertexStart: 0, vertexCount: 4)
//        encoder.endEncoding()
//        
//        commandBuffer.present(view.currentDrawable!)
//        commandBuffer.commit()
//    }
//}
import SwiftUI
import MetalKit
import Metal

struct MetalTextureViewFused: UIViewRepresentable, MetalRepresentable {
    var rotationAngle: Double
    @Binding var maxDepth: Float
    @Binding var minDepth: Float
    var highThreshold: Float = 0.8 // Adjust these values as needed
    var lowThreshold: Float = 0.2

    var capturedData: CameraCapturedData
    
    func makeCoordinator() -> MTKCannyEdgeCoordinator {
        MTKCannyEdgeCoordinator(parent: self)
    }
}

final class MTKCannyEdgeCoordinator: MTKCoordinator<MetalTextureViewFused> {
    override func preparePipelineAndDepthState() {
        guard let metalDevice = mtkView.device else { fatalError("Expected a Metal device.") }
        do {
            let library = MetalEnvironment.shared.metalLibrary
            let pipelineDescriptor = MTLRenderPipelineDescriptor()
            pipelineDescriptor.colorAttachments[0].pixelFormat = .bgra8Unorm
            pipelineDescriptor.vertexFunction = library.makeFunction(name: "planeVertexShader")
            pipelineDescriptor.fragmentFunction = library.makeFunction(name: "planeFragmentShaderCannyEdgeDetection") // Use Canny edge detection
            pipelineDescriptor.vertexDescriptor = createPlaneMetalVertexDescriptor()
            pipelineDescriptor.depthAttachmentPixelFormat = .depth32Float
            pipelineState = try metalDevice.makeRenderPipelineState(descriptor: pipelineDescriptor)
            
            let depthDescriptor = MTLDepthStencilDescriptor()
            depthDescriptor.isDepthWriteEnabled = true
            depthDescriptor.depthCompareFunction = .less
            depthState = metalDevice.makeDepthStencilState(descriptor: depthDescriptor)
        } catch {
            print("Unexpected error: \(error).")
        }
    }
    
    override func draw(in view: MTKView) {
        guard parent.capturedData.depth != nil else {
            print("There's no content to display.")
            return
        }
        guard parent.capturedData.depth != nil else {
            print("Depth texture is missing.")
            return
        }
        guard let commandBuffer = metalCommandQueue.makeCommandBuffer() else { return }
        guard let passDescriptor = view.currentRenderPassDescriptor else { return }
        guard let encoder = commandBuffer.makeRenderCommandEncoder(descriptor: passDescriptor) else { return }

        let vertexData: [Float] = [  -1, -1, 1, 1,
                                     1, -1, 1, 0,
                                     -1, 1, 0, 1,
                                     1, 1, 0, 0]
        encoder.setVertexBytes(vertexData, length: vertexData.count * MemoryLayout<Float>.stride, index: 0)
        
        // Set minDepth and maxDepth
        encoder.setFragmentBytes(&parent.minDepth, length: MemoryLayout<Float>.stride, index: 0)
        encoder.setFragmentBytes(&parent.maxDepth, length: MemoryLayout<Float>.stride, index: 1)
        
        // Set Canny edge detection thresholds
        var highThreshold = parent.highThreshold
        var lowThreshold = parent.lowThreshold
        encoder.setFragmentBytes(&highThreshold, length: MemoryLayout<Float>.stride, index: 2)
        encoder.setFragmentBytes(&lowThreshold, length: MemoryLayout<Float>.stride, index: 3)

        guard let depthTexture = parent.capturedData.depth else {
            print("Depth texture is missing.")
            return
        }

        var texelSize = float2(1.0 / Float(depthTexture.width), 1.0 / Float(depthTexture.height))
        encoder.setFragmentBytes(&texelSize, length: MemoryLayout<float2>.stride, index: 2)
        encoder.setFragmentTexture(parent.capturedData.depth!, index: 0)
        encoder.setDepthStencilState(depthState)
        encoder.setRenderPipelineState(pipelineState)
        encoder.drawPrimitives(type: .triangleStrip, vertexStart: 0, vertexCount: 4)
        encoder.endEncoding()
        commandBuffer.present(view.currentDrawable!)
        commandBuffer.commit()
    }
}
