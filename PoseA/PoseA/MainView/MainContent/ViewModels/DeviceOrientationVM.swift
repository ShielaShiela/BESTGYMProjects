//
//  DeviceOrientationVM.swift
//  PoseA
//
//  Created by Ardhika Maulidani on 6/24/25.
//

import UIKit
import Observation

@Observable
final class OrientationCache {
    static let shared = OrientationCache()

    var orientation: DeviceOrientationModel

    private init() {
        // Initialize with current interface orientation
        if let firstScene = UIApplication.shared.connectedScenes.first as? UIWindowScene {
            let current = firstScene.interfaceOrientation
            orientation = OrientationCache.mapUIOrientation(current)
        } else {
            orientation = .portrait
        }

        // Observe scene changes to update orientation
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(handleOrientationChange),
            name: UIApplication.didChangeStatusBarOrientationNotification, // optional for iOS <17
            object: nil
        )
    }

    @objc private func handleOrientationChange() {
        updateOrientation()
    }

    private func updateOrientation() {
        guard let scene = UIApplication.shared.connectedScenes.first as? UIWindowScene else { return }
        let newOrientation = OrientationCache.mapUIOrientation(scene.interfaceOrientation)
        if orientation != newOrientation {
            orientation = newOrientation
        }
    }

    private static func mapUIOrientation(_ orientation: UIInterfaceOrientation) -> DeviceOrientationModel {
        switch orientation {
        case .portrait: return .portrait
        case .landscapeRight: return .landscapeRight
        case .landscapeLeft: return .landscapeLeft
        case .portraitUpsideDown: return .portraitUpsideDown
        default: return .portrait
        }
    }
}
