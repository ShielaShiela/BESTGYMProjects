//
//  DepthViewControllerUI.swift
//  PoseA
//
//  Created by Ardhika Maulidani on 8/8/25.
//

//import UIKit
//import MetalKit
//
//class DepthViewControllerUI: UIViewController {
//    var renderer: DepthRenderer!
//    var imageView: UIImageView!
//
//    override func viewDidLoad() {
//        super.viewDidLoad()
//        view.backgroundColor = .black
//
//        // 1. Create the Metal renderer (we don’t need MTKView here since we render offscreen)
//        guard let device = MTLCreateSystemDefaultDevice() else {
//            fatalError("Metal not supported")
//        }
//        renderer = try? DepthRenderer(mtkView: dummyMTKView(device: device)) // Using dummy for init
//
//        // 2. Create UIImageView to display the result
//        imageView = UIImageView(frame: view.bounds)
//        imageView.autoresizingMask = [.flexibleWidth, .flexibleHeight]
//        imageView.contentMode = .scaleAspectFit
//        view.addSubview(imageView)
//
//        // 3. Load depth file and render to UIImage
//        loadAndDisplayDepthImage()
//    }
//
//    private func loadAndDisplayDepthImage() {
//        let url = Bundle.main.url(forResource: "depth_example", withExtension: "bin")! // change to your file
//        let width = 256   // your depth image width
//        let height = 192  // your depth image height
//
//        do {
//            let depthTex = try loadDepthTexture(from: url,
//                                                width: width,
//                                                height: height,
//                                                device: renderer.device)
//
//            // Set texture and visualization settings
//            renderer.setDepthTexture(depthTex, near: 0.2, far: 5.0, mode: 1) // mode 0 = grayscale, 1 = heatmap
//
//            // Render to UIImage
//            if let img = renderer.renderDepthToUIImage(width: width, height: height) {
//                imageView.image = img
//            }
//
//        } catch {
//            print("Failed to load depth texture: \(error)")
//        }
//    }
//
//    /// Dummy MTKView for DepthRenderer init (we won’t actually display it)
//    private func dummyMTKView(device: MTLDevice) -> MTKView {
//        let mtkView = MTKView(frame: .zero, device: device)
//        mtkView.isHidden = true
//        return mtkView
//    }
//}
//
