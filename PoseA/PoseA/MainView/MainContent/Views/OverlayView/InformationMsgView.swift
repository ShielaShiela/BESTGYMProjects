//
//  ErrorOverlayView.swift
//  PoseA
//
//  Created by Ardhika Maulidani on 16/4/26.


import SwiftUI

// MARK: - Information Message View
struct InformationMsgView: View {
    let message: InformationMessage
    let onDismiss: () -> Void
    
    @State private var isVisible = false
    @State private var dismissTimer: Timer?
    
    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: message.type.icon)
                .foregroundColor(message.type.color)
                .font(.caption)
            
            Text(message.text)
                .font(.caption)
                .foregroundColor(.primary)
                .lineLimit(2)
                .fixedSize(horizontal: false, vertical: true)
            
            if !message.autoDismiss {
                Button(action: onDismiss) {
                    Image(systemName: "xmark")
                        .font(.caption2)
                        .foregroundColor(.secondary)
                }
                .buttonStyle(PlainButtonStyle())
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .background(
            RoundedRectangle(cornerRadius: 16)
                .fill(.regularMaterial)
                .shadow(color: .black.opacity(0.1), radius: 4, x: 0, y: 2)
        )
        .scaleEffect(isVisible ? 1.0 : 0.8)
        .opacity(isVisible ? 1.0 : 0.0)
        .onAppear {
            withAnimation(.spring(response: 0.3, dampingFraction: 0.7)) {
                isVisible = true
            }
            
            if message.autoDismiss {
                dismissTimer = Timer.scheduledTimer(withTimeInterval: message.duration, repeats: false) { _ in
                    withAnimation(.easeOut(duration: 0.2)) {
                        isVisible = false
                    }
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.2) {
                        onDismiss()
                    }
                }
            }
        }
        .onDisappear {
            dismissTimer?.invalidate()
        }
    }
}
