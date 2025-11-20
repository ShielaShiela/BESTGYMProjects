//
//  CameraPreviewViewModel.swift
//  PoseA
//
//  Created by Ardhika Maulidani on 5/27/25.
//  Refactor from Shiela's codebase

import MetalKit
import AVFoundation

class CameraPreviewVM: UIView {
    // MARK: - Video Layer
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

    // MARK: - Depth Rendering
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

    // MARK: - Setup Depth MTKView
    private func setupDepthView() {
        guard let device = MTLCreateSystemDefaultDevice() else {
            log("Metal device not available", level: .error)
            return
        }

        let mtkView = MTKView(frame: .zero, device: device)
        mtkView.backgroundColor = .clear
        mtkView.framebufferOnly = false
        mtkView.isPaused = false                      // continuous rendering mode
        mtkView.enableSetNeedsDisplay = false
        mtkView.preferredFramesPerSecond = 30
        addSubview(mtkView)
        self.depthMTKView = mtkView
    }

    override func layoutSubviews() {
        super.layoutSubviews()
        videoPreviewLayer.frame = bounds
        depthMTKView?.frame = bounds

        // Initialize DepthRenderer only once
        if depthRenderer == nil, let mtkView = depthMTKView, mtkView.bounds.width > 0 {
            do {
                depthRenderer = try DepthRenderer(view: mtkView)
            } catch {
                log("Failed to initialize DepthRenderer: \(error)", level: .error)
            }
        }

        updateRotation()
    }

    // MARK: - Update depth frame from camera
    func renderDepth(texture: MTLTexture, maxDepth: Float = 8.0) {
        guard let renderer = depthRenderer else { return }
        renderer.updateInputTexture(texture, maxDepth: maxDepth)
        depthMTKView?.draw() // manually trigger draw to update
    }

    // MARK: - Depth view visibility
    func toggleDepthView(status: Bool) {
        guard let mtkView = depthMTKView else { return }
        mtkView.isHidden = status
        mtkView.isPaused = status
    }

    // MARK: - Helpers
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
        _ = CGSize(width: CGFloat(dimensions.width),
                   height: CGFloat(dimensions.height))
    }
}
