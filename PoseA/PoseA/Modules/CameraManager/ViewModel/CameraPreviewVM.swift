//
//  CameraPreviewViewModel.swift
//  PoseA
//
//  Created by Ardhika Maulidani on 5/27/25.
//  Refactor from Shiela's codebase

import SwiftUI
import AVFoundation

class CameraPreviewVM: UIView {
    // MARK: - COCO Keypoint Connections
    private let cocoConnections: [(Int, Int)] = [
        (0, 1), (0, 2),
        (1, 3), (2, 4),
        (0, 5), (0, 6),
        (5, 7), (7, 9),
        (6, 8), (8, 10),
        (5, 11), (6, 12),
        (11, 12),
        (11, 13), (13, 15),
        (12, 14), (14, 16)
    ]
    
    // MARK: - Camera Preview Layer
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
    
    // MARK: - Overlay
    private let overlayLayer = CAShapeLayer()
    
    // MARK: - Pose Data
    var poseKeypoints: [PoseBox] = [] {
        didSet { drawPoses() }
    }
    
    // MARK: - Camera Resolution
    private var cameraResolution: CGSize = .zero
    
    // MARK: - Init
    override init(frame: CGRect) {
        super.init(frame: frame)
        setupOverlay()
    }
    
    required init?(coder: NSCoder) {
        super.init(coder: coder)
        setupOverlay()
    }
    
    private func setupOverlay() {
        overlayLayer.frame = bounds
        overlayLayer.strokeColor = UIColor.clear.cgColor
        overlayLayer.fillColor = UIColor.clear.cgColor
        layer.addSublayer(overlayLayer)
    }
    
    // MARK: - Layout & Rotation
    override func layoutSubviews() {
        super.layoutSubviews()
        videoPreviewLayer.frame = bounds
        updateRotation()
    }
    
    private func updateRotation() {
        guard let connection = videoPreviewLayer.connection else { return }
        let orientation = currentInterfaceOrientation()
        
        if #available(iOS 17.0, *) {
            connection.videoRotationAngle = {
                switch orientation {
                case .portrait: return 90
                case .landscapeRight: return 0
                case .landscapeLeft: return 180
                case .portraitUpsideDown: return 270
                default: return 0
                }
            }()
        } else if connection.isVideoOrientationSupported {
            connection.videoOrientation = {
                switch orientation {
                case .portrait: return .portrait
                case .landscapeRight: return .landscapeLeft
                case .landscapeLeft: return .landscapeRight
                case .portraitUpsideDown: return .portraitUpsideDown
                default: return .portrait
                }
            }()
        }
    }
    
    private func currentInterfaceOrientation() -> UIInterfaceOrientation {
        UIApplication.shared.connectedScenes
            .compactMap { $0 as? UIWindowScene }
            .first?.interfaceOrientation ?? .portrait
    }
    
    private func updateCameraResolution() {
        guard let deviceInput = session?.inputs
            .compactMap({ $0 as? AVCaptureDeviceInput }).first else { return }
        let desc = deviceInput.device.activeFormat.formatDescription
        let dimensions = CMVideoFormatDescriptionGetDimensions(desc)
        cameraResolution = CGSize(width: CGFloat(dimensions.width),
                                  height: CGFloat(dimensions.height))
    }
    
    
    // MARK: - Drawing Poses
    private func drawPoses() {
        let path = UIBezierPath()
        
        for poseBox in poseKeypoints {
            // Convert bbox
            let viewRect = convertCameraRectToView(poseBox.bbox)
            path.append(UIBezierPath(rect: viewRect))

            // Convert keypoints
            let viewPoints = poseBox.keypoints.map { convertCameraPointToView($0) }
            
            // Draw keypoints
            for p in viewPoints {
                let circle = UIBezierPath(ovalIn: CGRect(x: p.x - 4, y: p.y - 4, width: 8, height: 8))
                path.append(circle)
            }
            
            // Draw skeleton
            for (start, end) in cocoConnections {
                guard start < viewPoints.count, end < viewPoints.count else { continue }
                path.move(to: viewPoints[start])
                path.addLine(to: viewPoints[end])
            }
        }
        
        overlayLayer.strokeColor = UIColor.orange.cgColor
        overlayLayer.fillColor = UIColor.clear.cgColor
        overlayLayer.lineWidth = 2
        overlayLayer.path = path.cgPath
    }
    
    // MARK: - Coordinate Conversion
    private func convertCameraRectToView(_ rect: CGRect) -> CGRect {
        guard cameraResolution != .zero else { return .zero }
        
        let topLeft = CGPoint(x: rect.minX / cameraResolution.width,
                              y: rect.minY / cameraResolution.height)
        let bottomRight = CGPoint(x: rect.maxX / cameraResolution.width,
                                  y: rect.maxY / cameraResolution.height)
        
        let viewTopLeft = videoPreviewLayer.layerPointConverted(fromCaptureDevicePoint: topLeft)
        let viewBottomRight = videoPreviewLayer.layerPointConverted(fromCaptureDevicePoint: bottomRight)
        
        return CGRect(
            x: viewTopLeft.x,
            y: viewTopLeft.y,
            width: viewBottomRight.x - viewTopLeft.x,
            height: viewBottomRight.y - viewTopLeft.y
        )
    }
    
    private func convertCameraPointToView(_ point: CGPoint) -> CGPoint {
        guard cameraResolution != .zero else { return .zero }
        let normalized = CGPoint(x: point.x / cameraResolution.width,
                                 y: point.y / cameraResolution.height)
        return videoPreviewLayer.layerPointConverted(fromCaptureDevicePoint: normalized)
    }
    
}
