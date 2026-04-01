//
//  ButtonState.swift
//  PoseA
//
//  Created by Ardhika Maulidani on 7/13/25.
//

import SwiftUI  

@Observable
class ToolbarButtonVM {
    var activeMode: ToolbarMode = .none {
        didSet { updateContexts() }
    }

    var isMediaAvailable: Bool = true

    var roiContext = ButtonContext()
    var boxContext = ButtonContext()
    var annotateContext = ButtonContext()
    var zoomContext = ButtonContext()
    var calibrateBarContext = ButtonContext()
    var calibrateQuadContext = ButtonContext()

    func activateMode(_ mode: ToolbarMode) {
        guard activeMode == .none else { return }
        activeMode = mode
    }

    func deactivateMode() {
        activeMode = .none
    }

    func context(for mode: ToolbarMode) -> ButtonContext {
        switch mode {
        case .roi:           return roiContext
        case .box:           return boxContext
        case .annotate:      return annotateContext
        case .zoom:          return zoomContext
        case .calibrateBar:  return calibrateBarContext
        case .calibrateQuad: return calibrateQuadContext
        default:             return ButtonContext()
        }
    }


    private func updateContexts() {
        for mode in ToolbarMode.allCases {
            let context = context(for: mode)
            context.isSelected = (mode == activeMode)
            context.isEnabled = (activeMode == .none) // Only enable when no mode is active
        }
    }
}
