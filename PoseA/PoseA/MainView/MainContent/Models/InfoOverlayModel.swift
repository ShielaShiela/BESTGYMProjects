//
//  InfoOverlayModel.swift
//  PoseA
//
//  Created by Ardhika Maulidani on 4/16/26.
//

import SwiftUI

// MARK: - Information Message Model
struct InformationMessage {
    enum MessageType {
        case info
        case warning
        case error
        
        var color: Color {
            switch self {
            case .info:
                return .black
            case .warning:
                return .orange
            case .error:
                return .red
            }
        }
        
        var icon: String {
            switch self {
            case .info:
                return "info.circle.fill"
            case .warning:
                return "exclamationmark.triangle.fill"
            case .error:
                return "xmark.circle.fill"
            }
        }
    }
    
    let text: String
    let type: MessageType
    let autoDismiss: Bool
    let duration: TimeInterval
    
    init(text: String, type: MessageType, autoDismiss: Bool = true, duration: TimeInterval = 3.0) {
        self.text = text
        self.type = type
        self.autoDismiss = autoDismiss
        self.duration = duration
    }
}
