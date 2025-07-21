//
//  ToolbarButtonView.swift
//  PoseA
//
//  Created by Ardhika Maulidani on 7/13/25.
//

import SwiftUI

struct ToolbarButtonView: View {
    let mode: ToolbarMode
    let icon: String
    let title: String
    @Bindable var viewModel: ToolbarButtonVM
    let onActivate: () -> Void

    var context: ButtonContext {
        viewModel.context(for: mode)
    }

    var body: some View {
        if !context.isHidden {
            Button {
                viewModel.activateMode(mode)
                onActivate()
            } label: {
                ZStack {
                    Circle()
                        .fill(context.isSelected ? Color.blue : Color.clear)
                        .frame(height: 22)
                    Image(systemName: icon)
                        .foregroundStyle(context.isSelected ? Color.white : Color.blue)
                }
                .contentShape(Circle()) // ensures tap area is circular
            }
            .buttonStyle(.plain)
            .disabled(!context.isEnabled)
            .opacity(context.isEnabled || context.isSelected ? 1.0 : 0.4)
            .help(title)
        }
    }
}
