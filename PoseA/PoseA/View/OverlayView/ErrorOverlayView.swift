//
//  ErrorOverlayView.swift
//  PoseA
//
//  Created by Ardhika Maulidani on 5/27/25.
//  Refactor from Shiela Cabahug's codebase


import SwiftUI

// MARK: - Error Overlay
struct ErrorOverlayView: View {
    let message: String
    let onDismiss: () -> Void
    
    var body: some View {
        VStack {
            Spacer()
            
            HStack {
                Image(systemName: "exclamationmark.triangle.fill")
                    .foregroundColor(.white)
                
                Text(message)
                    .foregroundColor(.white)
                
                Spacer()
                
                Button(action: onDismiss) {
                    Image(systemName: "xmark.circle.fill")
                        .foregroundColor(.white)
                }
            }
            .padding()
            .background(Color.red)
            .cornerRadius(8)
            .padding()
        }
    }
}
