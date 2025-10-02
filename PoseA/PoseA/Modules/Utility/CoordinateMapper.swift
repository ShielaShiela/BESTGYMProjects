//
//  CoordinateMapper.swift
//  PoseA
//
//  Created by Ardhika Maulidani on 9/5/25.
//

import Foundation

enum ScaleMode {
    case aspectFit
    case aspectFill
}

struct CoordinateMapper {
    let containerSize: CGSize
    let imageSize: CGSize
    let scaleMode: ScaleMode
    
    var displaySize: CGSize {
        let imageAspect = imageSize.width / imageSize.height
        let containerAspect = containerSize.width / containerSize.height
        
        switch scaleMode {
        case .aspectFit:
            if imageAspect > containerAspect {
                return CGSize(width: containerSize.width,
                              height: containerSize.width / imageAspect)
            } else {
                return CGSize(width: containerSize.height * imageAspect,
                              height: containerSize.height)
            }
        case .aspectFill:
            let s = max(containerSize.width / imageSize.width,
                        containerSize.height / imageSize.height)
            return CGSize(width: imageSize.width * s,
                          height: imageSize.height * s)
        }
    }
    
    var offset: CGPoint {
        let dx = (containerSize.width - displaySize.width) / 2
        let dy = (containerSize.height - displaySize.height) / 2
        return CGPoint(x: dx, y: dy)
    }
    
    func mapPoint(_ p: CGPoint, normalized: Bool = false) -> CGPoint {
        let inputX = normalized ? p.x * imageSize.width : p.x
        let inputY = normalized ? p.y * imageSize.height : p.y
        
        let scaleX = displaySize.width / imageSize.width
        let scaleY = displaySize.height / imageSize.height
        
        return CGPoint(
            x: inputX * scaleX + offset.x,
            y: inputY * scaleY + offset.y
        )
    }
    
    func mapPointInverse(_ p: CGPoint, normalized: Bool = false) -> CGPoint {
        let scaleX = displaySize.width / imageSize.width
        let scaleY = displaySize.height / imageSize.height
        
        let imgX = (p.x - offset.x) / scaleX
        let imgY = (p.y - offset.y) / scaleY
        
        if normalized {
            return CGPoint(x: imgX / imageSize.width,
                           y: imgY / imageSize.height)
        } else {
            return CGPoint(x: imgX, y: imgY)
        }
    }
}
