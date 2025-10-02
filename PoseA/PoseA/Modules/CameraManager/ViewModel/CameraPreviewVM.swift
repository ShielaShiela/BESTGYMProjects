//
//  CameraPreviewViewModel.swift
//  PoseA
//
//  Created by Ardhika Maulidani on 5/27/25.
//  Refactor from Shiela's codebase

import MetalKit
import AVFoundation

class CameraPreviewVM: UIView {
    override class var layerClass: AnyClass { AVCaptureVideoPreviewLayer.self }
    var videoPreviewLayer: AVCaptureVideoPreviewLayer { layer as! AVCaptureVideoPreviewLayer }

    var session: AVCaptureSession? {
        get { videoPreviewLayer.session }
        set {
            videoPreviewLayer.session = newValue
            videoPreviewLayer.videoGravity = .resizeAspectFill
            updateRotation()
            updateCameraResolution()
        }
    }

    private var depthMTKView: MTKView?
    private var depthRenderer: DepthRenderer?

    override init(frame: CGRect) {
        super.init(frame: frame)
        setupDepthView()
    }

    required init?(coder: NSCoder) {
        super.init(coder: coder)
        setupDepthView()
    }

    private func setupDepthView() {
        guard let device = MTLCreateSystemDefaultDevice() else {
            print("❌ Metal device not available")
            return
        }

        let mtkView = MTKView(frame: .zero, device: device) // assign device here!
        mtkView.backgroundColor = .clear
        mtkView.isPaused = false
        mtkView.enableSetNeedsDisplay = false
        mtkView.preferredFramesPerSecond = 30 // or 60
        mtkView.framebufferOnly = false
        addSubview(mtkView)
        self.depthMTKView = mtkView
    }

    override func layoutSubviews() {
        super.layoutSubviews()
        videoPreviewLayer.frame = bounds
        depthMTKView?.frame = bounds

        // Initialize DepthRenderer only once, after MTKView has valid frame
        if depthRenderer == nil, let mtkView = depthMTKView, mtkView.bounds.width > 0 {
            do {
                depthRenderer = try DepthRenderer(view: mtkView)
            } catch {
                print("Failed to initialize DepthRenderer:", error)
            }
        }

        updateRotation()
    }

    func renderDepth(texture: MTLTexture, maxDepth: Float = 8.0) {
        guard let mtkView = depthMTKView else { return }

        // Lazy init DepthRenderer only once
        if depthRenderer == nil {
            guard let device = MTLCreateSystemDefaultDevice() else {
                return
            }
            mtkView.device = device
            depthRenderer = try? DepthRenderer(view: mtkView)
        }

        guard let renderer = depthRenderer else {
            return
        }

        renderer.draw(texture: texture, in: mtkView, maxDepth: maxDepth)
    }
    
    func toggleDepthView(status: Bool) {
        guard let mtkView = depthMTKView else { return }
        mtkView.isHidden = status
        mtkView.isPaused = status
    }

    private func updateRotation() {
        guard let connection = videoPreviewLayer.connection else { return }
        connection.videoRotationAngle = {
            switch OrientationCache.shared.orientation {
            case .portrait: return 90
            case .landscapeRight: return 0
            case .landscapeLeft: return 180
            case .portraitUpsideDown: return 270
            }
        }()
    }

    private func updateCameraResolution() {
        guard let deviceInput = session?.inputs
            .compactMap({ $0 as? AVCaptureDeviceInput }).first else { return }
        let desc = deviceInput.device.activeFormat.formatDescription
        let dimensions = CMVideoFormatDescriptionGetDimensions(desc)
        // store camera resolution
        _ = CGSize(width: CGFloat(dimensions.width),
                   height: CGFloat(dimensions.height))
    }
}
