
//
//  Extensions.swift
//  DataCaptureTest
//
//  Created by Shiela Cabahug on 2024/7/4.
//

import SwiftUI
extension CGRect {
    var center: CGPoint {
        CGPoint(x: self.midX, y: self.midY)
    }
}
extension View{
    
    func calcAspect(orientation: UIImage.Orientation, texture: MTLTexture?) -> CGFloat {
        guard let texture = texture else { return 1 }
        switch orientation {
        case .up:
            return CGFloat(texture.width) / CGFloat(texture.height)
        case .down:
            return CGFloat(texture.width) / CGFloat(texture.height)
        case .left:
            return  CGFloat(texture.height) / CGFloat(texture.width)
        case .right:
            return  CGFloat(texture.height) / CGFloat(texture.width)
        default:
            return CGFloat(texture.width) / CGFloat(texture.height)
        }
    }
    
    var rotationAngle: Double {
        var angle = 0.0
        switch viewOrientation {
        
        case .up:
            angle = -Double.pi / 2
        case .down:
            angle = Double.pi / 2
        case .left:
            angle = Double.pi
        case .right:
            angle = 0
        default:
            angle = 0
        }
        return angle
    }

    var viewOrientation: UIImage.Orientation {
        var result = UIImage.Orientation.up
       
        guard let currentWindowScene = UIApplication.shared.connectedScenes.first(
            where: { $0.activationState == .foregroundActive }) as? UIWindowScene
        else { return result }
        
        let interfaceOrientation = currentWindowScene.interfaceOrientation
        switch interfaceOrientation {
        case .portrait:
            result = .right
        case .portraitUpsideDown:
            result = .left
        case .landscapeLeft:
            result = .down
        case .landscapeRight:
            result = .up
        default:
            result = .up
        }
            
        return result
    }
}


