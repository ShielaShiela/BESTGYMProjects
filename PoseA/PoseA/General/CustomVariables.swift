//
//  CustomVariables.swift
//  PoseA
//
//  Created by Ardhika Maulidani on 5/27/25.
//  Refactor from Shiela Cabahug's codebase

import SwiftUI

// MARK: Keypoint Data Structure
struct Keypoint {
    let position: CGPoint
    let confidence: Float
    let name: String
}

enum BodySide {
    case left
    case right
    case center
}

struct KeypointConnection {
    let from: Int?
    let to: Int?
    let side: BodySide
}


// MARK: Chart Data Structure
struct JointData: Identifiable {
    var id: String { joint }
    var joint: String
    var dataPoints: [xyzChartData]
}

struct xyzChartData: Identifiable {
    var id = UUID()
    var x: Double
    var y: Double
    var z: Float
}

extension xyzChartData {
    init(x: Int, y: Double, z: Float = 0) {
        self.x = Double(x)
        self.y = y
        self.z = z
    }

    init(x: Double, y: Double, z: Float = 0) {
        self.x = x
        self.y = y
        self.z = z
    }
}

// Joint colors for the graph
let jointColors: [String: Color] = [
    "L Shoulder": .cyan,
    "R Shoulder": .blue,
    "L Elbow": .pink,
    "R Elbow": .red,
    "L Wrist": .brown,
    "R Wrist": .indigo,
    "L Hip": .orange,
    "R Hip": .yellow,
    "L Knee": .green,
    "R Knee": .purple,
    "L Ankle": .black,
    "R Ankle": .gray
]

// MARK: Error Variables
struct ErrorWrapper: Identifiable {
    let id = UUID()
    let error: String
}

// MARK: Video Variables
struct VideoFormat {
    let width: Int
    let height: Int
    let fps: Int
}

struct VideoSettings {
    var selectedFormat: VideoFormat
    
    static let defaultSettings = VideoSettings(
        selectedFormat: VideoFormat(width: 1920, height: 1080, fps: 30)
    )
}

// MARK: RecordingMetadata.json Structure
struct RecordingMetadata: Codable {
    let personName: String
    let action: String
    let frameCount: Int
    let useLiDAR: Bool
    let duration: TimeInterval
    let resolution: Resolution
    let deviceOrientation: DeviceOrientation?
    let timestamp: TimeInterval
    let distance: String?
    let cameraIntrinsics: [[Float]]
    
    struct Resolution: Codable {
        let width: CGFloat
        let height: CGFloat
    }
    
    struct DeviceOrientation: Codable {
        let rawValue: Int
        let name: String
        
        // Add camera orientation to clarify how the image was actually captured
        var cameraOrientation: String?
        
        // Add image dimensions to help resolve orientation issues
        var capturedWidth: Int?
        var capturedHeight: Int?
        
        // Convert to UIDeviceOrientation
        var uiDeviceOrientation: UIDeviceOrientation {
            return UIDeviceOrientation(rawValue: self.rawValue) ?? .portrait
        }
        
        // Determine if device was held in portrait or landscape
        var isPortraitOrientation: Bool {
            return uiDeviceOrientation == .portrait || uiDeviceOrientation == .portraitUpsideDown
        }
    }
        

    
    // Static method to create a default metadata with portrait orientation
    static func defaultMetadata() -> RecordingMetadata {
        return RecordingMetadata(
            personName: "Unknown",
            action: "Unknown",
            frameCount: 0,
            useLiDAR: false,
            duration: 0.0,
            resolution: Resolution(width: 1920, height: 1080),
            deviceOrientation: DeviceOrientation(rawValue: UIDeviceOrientation.portrait.rawValue, name: "portrait"),
            timestamp: Date().timeIntervalSince1970,
            distance: nil,
            cameraIntrinsics: [
                [1.0, 0.0, 0.0],
                [0.0, 1.0, 0.0],
                [0.0, 0.0, 1.0]
            ]
        )
    }
}

// MARK: Error Enumeration
enum FileAccessError: LocalizedError {
    case fileNotFound
    case accessDenied
    case unsupportedFormat(String)
    
    var errorDescription: String? {
        switch self {
        case .fileNotFound:
            return "The selected file or folder could not be found."
        case .accessDenied:
            return "Access to the selected file or folder was denied."
        case .unsupportedFormat(let format):
            return "Unsupported file format: \(format)"
        }
    }
}
