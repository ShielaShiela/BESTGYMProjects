//
//  MetalPointCloud.swift
//  DataCaptureTest
//
//  Created by Shiela Cabahug on 2024/7/31.
//


import Foundation
import SwiftUI
import MetalKit
import Metal

//struct MetalPointCloudView: UIViewRepresentable, MetalRepresentable {
//    var rotationAngle: Double
////    var cameraController: Camera3DController
//
//    @Binding var maxDepth: Float
//    @Binding var minDepth: Float
//    @Binding var scaleMovement: Float
////    @State private var panOffset: CGSize = .zero
//
//  
//    var capturedData: CameraCapturedData
//    
//    func makeCoordinator() -> MTKPointCloudCoordinator {
//        MTKPointCloudCoordinator(parent: self)
//    }
//    
//    func makeUIView(context: Context) -> MTKView {
//            let mtkView = MTKView()
//            mtkView.delegate = context.coordinator
//            mtkView.backgroundColor = context.environment.colorScheme == .dark ? .black : .white
//            context.coordinator.setupView(mtkView: mtkView)
//            
//            // Add pan gesture recognizer
//            let panGesture = UIPanGestureRecognizer(target: context.coordinator, action: #selector(MTKPointCloudCoordinator.handlePanGesture(_:)))
//            mtkView.addGestureRecognizer(panGesture)
//        
//        // Add pinch gesture recognizer
//            let pinchGesture = UIPinchGestureRecognizer(target: context.coordinator, action: #selector(MTKPointCloudCoordinator.handlePinchGesture(_:)))
//            mtkView.addGestureRecognizer(pinchGesture)
//        
//            mtkView.isUserInteractionEnabled = true
//            
//            return mtkView
//        }
//
//        
//}

//final class MTKPointCloudCoordinator: MTKCoordinator<MetalPointCloudView> {
//    var staticAngle: Float = 0.0
//    var staticInc: Float = 0.02
//    var panOffset: SIMD2<Float> = SIMD2<Float>(0, 0)
//    var zoomFactor: Float = 1.0
//    
//    var cameraController: Camera3DController
//        
//    override init(parent: MetalPointCloudView) {
//        self.cameraController = Camera3DController()
//        super.init(parent: parent)
//        // ... other initialization ...
//    }
//    
//    enum CameraModes {
//        case quarterArc
//        case sidewaysMovement
//    }
//    var currentCameraMode: CameraModes = .sidewaysMovement
//    
//    override func preparePipelineAndDepthState() {
//        guard let metalDevice = mtkView.device else { fatalError("Expected a Metal device.") }
//        do {
//            let library = MetalEnvironment.shared.metalLibrary
//            let pipelineDescriptor = MTLRenderPipelineDescriptor()
//            pipelineDescriptor.colorAttachments[0].pixelFormat = .bgra8Unorm
//            pipelineDescriptor.vertexFunction = library.makeFunction(name: "pointCloudVertexShader")
//            pipelineDescriptor.fragmentFunction = library.makeFunction(name: "pointCloudFragmentShader")
//            pipelineDescriptor.vertexDescriptor = createMetalVertexDescriptor()
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
//    func createMetalVertexDescriptor() -> MTLVertexDescriptor {
//        let mtlVertexDescriptor: MTLVertexDescriptor = MTLVertexDescriptor()
//        // Store position in `attribute[[0]]`.
//        mtlVertexDescriptor.attributes[0].format = .float2
//        mtlVertexDescriptor.attributes[0].offset = 0
//        mtlVertexDescriptor.attributes[0].bufferIndex = 0
//        
//        // Set stride to twice the `float2` bytes per vertex.
//        mtlVertexDescriptor.layouts[0].stride = 2 * MemoryLayout<SIMD2<Float>>.stride
//        mtlVertexDescriptor.layouts[0].stepRate = 1
//        mtlVertexDescriptor.layouts[0].stepFunction = .perVertex
//        
//        return mtlVertexDescriptor
//    }
////    
//    func calcCurrentPMVMatrix(viewSize: CGSize) -> matrix_float4x4 {
//        let projection: matrix_float4x4 = makePerspectiveMatrixProjection(fovyRadians: Float.pi / 3.0,
//                                                                          aspect: Float(viewSize.width) / Float(viewSize.height),
//                                                                          nearZ: 10.0, farZ: 8000.0)
//        
//        var orientationOrig: simd_float4x4 = simd_float4x4()
//        orientationOrig.columns.0 = [0, -1, 0, 0]
//        orientationOrig.columns.1 = [-1, 0, 0, 0]
//        orientationOrig.columns.2 = [0, 0, 1, 0]
//        orientationOrig.columns.3 = [0, 0, 0, 1]
//        
//        let cameraIntrinsics = parent.capturedData.cameraIntrinsics
//        let refDimensions = parent.capturedData.cameraReferenceDimensions
//        
//        // Calculate camera position based on intrinsics
//        let focalLengthX = cameraIntrinsics[0][0]
//        let focalLengthY = cameraIntrinsics[1][1]
//        let principalPointX = cameraIntrinsics[2][0]
//        let principalPointY = cameraIntrinsics[2][1]
//        
//        let averageFocalLength = (focalLengthX + focalLengthY) / 2
//        let cameraZ = -averageFocalLength * parent.scaleMovement / zoomFactor // Apply zoom factor here
//        
//        let cameraX = (Float(refDimensions.width) / 2 - principalPointX) / averageFocalLength * cameraZ
//        let cameraY = (Float(refDimensions.height) / 2 - principalPointY) / averageFocalLength * cameraZ
//            
//        var translationCamera: simd_float4x4 = simd_float4x4()
//        translationCamera.columns.0 = [1, 0, 0, 0]
//        translationCamera.columns.1 = [0, 1, 0, 0]
//        translationCamera.columns.2 = [0, 0, 1, 0]
//        translationCamera.columns.3 = [cameraX + panOffset.x, cameraY + panOffset.y, cameraZ, 1]
//
//        // Calculate rotation based on principal point offset
//        let rotationX = atan2(principalPointY - Float(refDimensions.height) / 2, averageFocalLength)
//        let rotationY = -atan2(principalPointX - Float(refDimensions.width) / 2, averageFocalLength)
//            
//        let rotationMatrix = simd_float4x4(simd_quatf(angle: rotationX, axis: SIMD3(x: 1, y: 0, z: 0)) *
//                                           simd_quatf(angle: rotationY, axis: SIMD3(x: 0, y: 1, z: 0)))
//        
//        let pmv = projection * rotationMatrix * translationCamera * orientationOrig
//        return pmv
//    }
//    
////    func calcCurrentPMVMatrix(viewSize: CGSize) -> matrix_float4x4 {
////        let projection: matrix_float4x4 = makePerspectiveMatrixProjection(fovyRadians: Float.pi / 3.0,
////                                                                          aspect: Float(viewSize.width) / Float(viewSize.height),
////                                                                          nearZ: 10.0, farZ: 8000.0)
////        
////        var orientationOrig: simd_float4x4 = simd_float4x4()
////        // Since the camera stream is rotated clockwise, rotate it back.
////        orientationOrig.columns.0 = [0, -1, 0, 0]
////        orientationOrig.columns.1 = [-1, 0, 0, 0]
////        orientationOrig.columns.2 = [0, 0, 1, 0]
////        orientationOrig.columns.3 = [0, 0, 0, 1]
////        
////        var translationOrig: simd_float4x4 = simd_float4x4()
////        // Move the object forward to enhance visibility.
////        translationOrig.columns.0 = [1, 0, 0, 0]
////        translationOrig.columns.1 = [0, 1, 0, 0]
////        translationOrig.columns.2 = [0, 0, 1, 0]
////        translationOrig.columns.3 = [0, 0, +0, 1]
////        staticAngle += staticInc
////
////        if currentCameraMode == .quarterArc {
////            // Limit camera rotation to a quarter arc, to and fro, while aimed
////            // at the center.
////            if staticAngle <= 0 {
////                 staticInc = -staticInc
////             }
////             if staticAngle > 1.2 {
////                 staticInc = -staticInc
////             }
////        }
////        
////        let sinf = sin(staticAngle)
////        let cosf = cos(staticAngle)
////        let sinsqr = sinf * sinf
////        let cossqr = cosf * cosf
////        
////        var translationCamera: simd_float4x4 = simd_float4x4()
////        translationCamera.columns.0 = [1, 0, 0, 0]
////        translationCamera.columns.1 = [0, 1, 0, 0]
////        translationCamera.columns.2 = [0, 0, 1, 0]
////        translationCamera.columns.3 = [0, 0, 0, 1]
////
////        var cameraRotation: simd_quatf
////        switch currentCameraMode {
////        case .quarterArc:
////            // Rotate the point cloud 1/4 arc.
////            translationCamera.columns.3 = [-1500 * sinf, 0, -1500 * parent.scaleMovement * sinf, 1]
////            cameraRotation = simd_quatf(angle: staticAngle, axis: SIMD3(x: 0, y: 1, z: 0))
////        case .sidewaysMovement:
////            // Randomize the camera scale.
////            translationCamera.columns.3 = [150 * sinf, -150 * cossqr, -150 * parent.scaleMovement * sinsqr, 1]
////            // Randomize the camera movement.
////            cameraRotation = simd_quatf(angle: staticAngle, axis: SIMD3(x: -sinsqr / 3, y: -cossqr / 3, z: 0))
////        }
////        let rotationMatrix: matrix_float4x4 = matrix_float4x4(cameraRotation)
////        let pmv = projection * rotationMatrix * translationCamera * translationOrig * orientationOrig
////        return pmv
////    }
//    
//    override func draw(in view: MTKView) {
//        guard parent.capturedData.depth != nil else {
//            print("Depth data not available; skipping a draw.")
//            return
//        }
//        guard let commandBuffer = metalCommandQueue.makeCommandBuffer() else { return }
//        guard let passDescriptor = view.currentRenderPassDescriptor else { return }
//        guard let encoder = commandBuffer.makeRenderCommandEncoder(descriptor: passDescriptor) else { return }
//        encoder.setDepthStencilState(depthState)
//        encoder.setVertexTexture(parent.capturedData.depth, index: 0)
//        encoder.setVertexTexture(parent.capturedData.colorY, index: 1)
//        encoder.setVertexTexture(parent.capturedData.colorCbCr, index: 2)
//        // Camera-intrinsics units are in full camera-resolution pixels.
//
//        let depthResolution = simd_float2(x: Float(parent.capturedData.depth!.width), y: Float(parent.capturedData.depth!.height))
//        let scaleRes = simd_float2(x: Float( parent.capturedData.cameraReferenceDimensions.width) / depthResolution.x,
//                                   y: Float(parent.capturedData.cameraReferenceDimensions.height) / depthResolution.y )
//        var cameraIntrinsics = parent.capturedData.cameraIntrinsics
//        cameraIntrinsics[0][0] /= scaleRes.x
//        cameraIntrinsics[1][1] /= scaleRes.y
//
//        cameraIntrinsics[2][0] /= scaleRes.x
//        cameraIntrinsics[2][1] /= scaleRes.y
//        var pmv = calcCurrentPMVMatrix(viewSize: CGSize(width: view.frame.size.width, height: view.frame.size.height))
//        encoder.setVertexBytes(&pmv, length: MemoryLayout<matrix_float4x4>.stride, index: 0)
//        encoder.setVertexBytes(&cameraIntrinsics, length: MemoryLayout<matrix_float3x3>.stride, index: 1)
//        encoder.setRenderPipelineState(pipelineState)
//        encoder.drawPrimitives(type: .point, vertexStart: 0, vertexCount: Int(depthResolution.x * depthResolution.y))
//        encoder.endEncoding()
//        commandBuffer.present(view.currentDrawable!)
//        commandBuffer.commit()
//    }
//
////    @objc func handlePanGesture(_ gesture: UIPanGestureRecognizer) {
////        let translation = gesture.translation(in: gesture.view)
////        cameraController.pan(dx: Float(translation.x), dy: Float(translation.y))
////        gesture.setTranslation(.zero, in: gesture.view)
////        mtkView.setNeedsDisplay()
////    }
////
////    @objc func handlePinchGesture(_ gesture: UIPinchGestureRecognizer) {
////        let delta = Float(gesture.scale - 1.0)
////        cameraController.zoom(delta: delta)
////        gesture.scale = 1.0
////        mtkView.setNeedsDisplay()
////    }
////
////    @objc func handleRotationGesture(_ gesture: UIRotationGestureRecognizer) {
////        cameraController.rotate(dx: Float(gesture.rotation), dy: 0)
////        gesture.rotation = 0
////        mtkView.setNeedsDisplay()
////    }
//    
////    var panOffset: SIMD2<Float> = SIMD2<Float>(0, 0)
//
//       @objc func handlePanGesture(_ gesture: UIPanGestureRecognizer) {
//           let translation = gesture.translation(in: gesture.view)
//           let sensitivity: Float = 0.5  // Adjust this value to change pan sensitivity
//           
//           panOffset.x += Float(translation.x) * sensitivity
//           panOffset.y -= Float(translation.y) * sensitivity
//           
//           gesture.setTranslation(.zero, in: gesture.view)
//           
//           // Force a redraw of the view
//           mtkView.setNeedsDisplay()
//       }
//    
//    @objc func handlePinchGesture(_ gesture: UIPinchGestureRecognizer) {
//            switch gesture.state {
//            case .changed:
//                let delta = Float(gesture.scale)
//                zoomFactor *= delta
//                zoomFactor = max(0.1, min(zoomFactor, 5.0)) // Limit zoom range
//                gesture.scale = 1.0 // Reset scale for next callback
//                mtkView.setNeedsDisplay()
//            default:
//                break
//            }
//        }
//
//}
//
///// A helper function that calculates the projection matrix given fovY in radians, aspect ration and nearZ and farZ planes.
//func makePerspectiveMatrixProjection(fovyRadians: Float, aspect: Float, nearZ: Float, farZ: Float) -> simd_float4x4 {
//    let yProj: Float = 1.0 / tanf(fovyRadians * 0.5)
//    let xProj: Float = yProj / aspect
//    let zProj: Float = farZ / (farZ - nearZ)
//    let proj: simd_float4x4 = simd_float4x4(SIMD4<Float>(xProj, 0, 0, 0),
//                                           SIMD4<Float>(0, yProj, 0, 0),
//                                           SIMD4<Float>(0, 0, zProj, 1.0),
//                                           SIMD4<Float>(0, 0, -zProj * nearZ, 0))
//    return proj
//}

