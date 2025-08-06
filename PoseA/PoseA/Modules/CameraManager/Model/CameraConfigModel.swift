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
        case hd4k       // 3840x2160
        
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
        
        // Get next resolution in cycle
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
        
        // Get available frame rates for a given resolution
        static func availableForResolution(_ resolution: Resolution) -> [FrameRate] {
            switch resolution {
            case .hd720p, .hd1080p, .li1440p:
                return [.fps30, .fps60]
            case .hd4k:
                return [.fps24, .fps30]
            }
        }
        
        // Get next frame rate in cycle for a given resolution
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
    
    init(resolution: Resolution = .hd1080p,
         frameRate: FrameRate = .fps30,
         enableLiDAR: Bool = true,
         enableDepthFiltering: Bool = true,
         cameraPosition: AVCaptureDevice.Position = .back) {
        self.resolution = resolution
        self.frameRate = frameRate
        self.enableLiDAR = enableLiDAR
        self.enableDepthFiltering = enableDepthFiltering
        self.cameraPosition = cameraPosition
    }
    
    // Cycle to next resolution
    func cycleResolution() -> CameraConfiguration {
        let nextResolution = resolution.next()
        return withResolution(nextResolution)
    }
    
    // Cycle to next frame rate for current resolution
    func cycleFrameRate() -> CameraConfiguration {
        let nextFrameRate = frameRate.nextForResolution(resolution)
        return withFrameRate(nextFrameRate)
    }
    
    // Create a new configuration with updated resolution
    private func withResolution(_ newResolution: Resolution) -> CameraConfiguration {
        // Ensure frame rate is compatible with new resolution
        let availableRates = FrameRate.availableForResolution(newResolution)
        let newFrameRate = availableRates.contains(self.frameRate) ? self.frameRate : availableRates.first ?? .fps30
        
        return CameraConfiguration(
            resolution: newResolution,
            frameRate: newFrameRate,
            enableLiDAR: enableLiDAR,
            enableDepthFiltering: enableDepthFiltering,
            cameraPosition: cameraPosition
        )
    }
    
    // Create a new configuration with updated frame rate
    private func withFrameRate(_ newFrameRate: FrameRate) -> CameraConfiguration {
        // Ensure frame rate is compatible with current resolution
        let availableRates = FrameRate.availableForResolution(resolution)
        guard availableRates.contains(newFrameRate) else {
            return self // Return unchanged if frame rate not compatible
        }
        
        return CameraConfiguration(
            resolution: resolution,
            frameRate: newFrameRate,
            enableLiDAR: enableLiDAR,
            enableDepthFiltering: enableDepthFiltering,
            cameraPosition: cameraPosition
        )
    }
}
