//
//  FileClass.swift
//  PoseA
//
//  Created by Shiela Cabahug on 2025/4/14.
//

import Foundation
import UIKit // For UIDeviceOrientation
// Add this struct if you don't have it, or ensure your existing one has these properties
//struct RecordingMetadata: Codable {
//    let personName: String
//    let action: String
//    let frameCount: Int
//    let useLiDAR: Bool
//    let duration: TimeInterval
//    let resolution: Resolution
//    let deviceOrientation: DeviceOrientation?
//    let timestamp: TimeInterval
//    let distance: String?
//    let cameraIntrinsics: [[Float]]
//    
//    struct Resolution: Codable {
//        let width: CGFloat
//        let height: CGFloat
//    }
//    
//    struct DeviceOrientation: Codable {
//        let rawValue: Int
//        let name: String
//        
//        // Add camera orientation to clarify how the image was actually captured
//        var cameraOrientation: String?
//        
//        // Add image dimensions to help resolve orientation issues
//        var capturedWidth: Int?
//        var capturedHeight: Int?
//        
//        // Convert to UIDeviceOrientation
//        var uiDeviceOrientation: UIDeviceOrientation {
//            return UIDeviceOrientation(rawValue: self.rawValue) ?? .portrait
//        }
//        
//        // Determine if device was held in portrait or landscape
//        var isPortraitOrientation: Bool {
//            return uiDeviceOrientation == .portrait || uiDeviceOrientation == .portraitUpsideDown
//        }
//    }
//        
//
//    
//    // Static method to create a default metadata with portrait orientation
//    static func defaultMetadata() -> RecordingMetadata {
//        return RecordingMetadata(
//            personName: "Unknown",
//            action: "Unknown",
//            frameCount: 0,
//            useLiDAR: false,
//            duration: 0.0,
//            resolution: Resolution(width: 1920, height: 1080),
//            deviceOrientation: DeviceOrientation(rawValue: UIDeviceOrientation.portrait.rawValue, name: "portrait"),
//            timestamp: Date().timeIntervalSince1970,
//            distance: nil,
//            cameraIntrinsics: [
//                [1.0, 0.0, 0.0],
//                [0.0, 1.0, 0.0],
//                [0.0, 0.0, 1.0]
//            ]
//        )
//    }
//}
//
