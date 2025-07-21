//
//  NotifyPublisher.swift
//  PoseA
//
//  Created by Ardhika Maulidani on 7/8/25.
//

import Foundation

// MARK: - Update Publisher
class NotifyPublisher {
    static let shared = NotifyPublisher()
    
    private init() {}
    
    // Use NotificationCenter for broadcasting frame changes
    func notifyFrameChanged(frameIndex: Int) {
        NotificationCenter.default.post(
            name: NSNotification.Name("FrameChanged"),
            object: nil,
            userInfo: ["frameIndex": frameIndex]
        )
    }
}
