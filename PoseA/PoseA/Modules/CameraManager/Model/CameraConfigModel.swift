//
//  CameraConfigModel.swift
//  PoseA
//
//  Created by Ardhika Maulidani on 7/31/25.
//

import Foundation
import AVFoundation

// MARK: - Camera Configuration
struct CameraConfiguration {
    enum Resolution: CaseIterable {
        case hd720p    // 1280x720
        case hd1080p   // 1920x1080
        case li1440p   // 1920x1440
        case hd4k      // 3840x2160
        
        var width: Int {
            switch self {
            case .hd720p: return 1280
            case .hd1080p: return 1920
            case .li1440p: return 1920
            case .hd4k: return 3840
            }
        }
        
        var height: Int {
            switch self {
            case .hd720p: return 720
            case .hd1080p: return 1080
            case .li1440p: return 1440
            case .hd4k: return 2160
            }
        }
        
        var description: String {
            switch self {
            case .hd720p: return "720p"
            case .hd1080p: return "1080p"
            case .li1440p: return "1440p"
            case .hd4k: return "4K"
            }
        }
        
        var shortDescription: String {
            switch self {
            case .hd720p: return "HD"
            case .hd1080p: return "FHD"
            case .li1440p: return "QHD"
            case .hd4k: return "4K"
            }
        }
        
        func next() -> Resolution {
            let allResolutions = Resolution.allCases
            guard let currentIndex = allResolutions.firstIndex(of: self) else {
                return .hd720p
            }
            let nextIndex = (currentIndex + 1) % allResolutions.count
            return allResolutions[nextIndex]
        }
    }
    
    enum FrameRate: Int, CaseIterable {
        case fps24 = 24
        case fps30 = 30
        case fps60 = 60
        
        var description: String {
            return "\(self.rawValue)"
        }
        
        static func availableForResolution(_ resolution: Resolution) -> [FrameRate] {
            switch resolution {
            case .hd720p, .hd1080p, .li1440p:
                return [.fps30, .fps60]
            case .hd4k:
                return [.fps24, .fps30]
            }
        }
        
        func nextForResolution(_ resolution: Resolution) -> FrameRate {
            let availableRates = FrameRate.availableForResolution(resolution)
            guard let currentIndex = availableRates.firstIndex(of: self) else {
                return availableRates.first ?? .fps30
            }
            let nextIndex = (currentIndex + 1) % availableRates.count
            return availableRates[nextIndex]
        }
    }
    
    let resolution: Resolution
    let frameRate: FrameRate
    let enableLiDAR: Bool
    let enableDepthFiltering: Bool
    let cameraPosition: AVCaptureDevice.Position
    
    init(resolution: Resolution = .hd720p,
         frameRate: FrameRate = .fps30,
         enableLiDAR: Bool = false,
         enableDepthFiltering: Bool = true,
         cameraPosition: AVCaptureDevice.Position = .back) {
        
        self.resolution = resolution
        self.enableLiDAR = enableLiDAR
        self.enableDepthFiltering = enableDepthFiltering
        self.cameraPosition = cameraPosition
        
        // Always enforce 30fps if LiDAR is enabled
        if enableLiDAR {
            self.frameRate = .fps30
        } else {
            let availableRates = FrameRate.availableForResolution(resolution)
            self.frameRate = availableRates.contains(frameRate) ? frameRate : availableRates.first ?? .fps30
        }
    }
    
    // Cycle to next resolution
    func cycleResolution() -> CameraConfiguration {
        let nextResolution = resolution.next()
        return withResolution(nextResolution)
    }
    
    // Cycle to next frame rate for current resolution
    func cycleFrameRate() -> CameraConfiguration {
        guard !enableLiDAR else { return self } // locked
        let nextFrameRate = frameRate.nextForResolution(resolution)
        return withFrameRate(nextFrameRate)
    }
    
    private func withResolution(_ newResolution: Resolution) -> CameraConfiguration {
        return CameraConfiguration(
            resolution: newResolution,
            frameRate: frameRate, // initializer will fix if invalid
            enableLiDAR: enableLiDAR,
            enableDepthFiltering: enableDepthFiltering,
            cameraPosition: cameraPosition
        )
    }
    
    private func withFrameRate(_ newFrameRate: FrameRate) -> CameraConfiguration {
        return CameraConfiguration(
            resolution: resolution,
            frameRate: newFrameRate, // initializer will fix if invalid
            enableLiDAR: enableLiDAR,
            enableDepthFiltering: enableDepthFiltering,
            cameraPosition: cameraPosition
        )
    }
    
    // Toggle LiDAR mode
    func withLiDAR(_ enabled: Bool) -> CameraConfiguration {
        return CameraConfiguration(
            resolution: resolution,
            frameRate: frameRate, // initializer will force 30 if enabled
            enableLiDAR: enabled,
            enableDepthFiltering: enableDepthFiltering,
            cameraPosition: cameraPosition
        )
    }
}

