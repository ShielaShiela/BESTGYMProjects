//
//  SideMenuModel.swift
//  PoseA
//
//  Created by Ardhika Maulidani on 7/10/25.
//

import Foundation

// MARK: - Buttons Context

enum ToolbarMode: String, CaseIterable {
    case none
    case roi
    case box
    case annotate
    case zoom
}

@Observable
class ButtonContext {
    var isEnabled: Bool = true
    var isHidden: Bool = false
    var isSelected: Bool = false
}

