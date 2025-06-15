//
//  ProcessingOverlayView.swift
//  PoseA
//
//  Created by Ardhika Maulidani on 5/27/25.
//  Refactor from Shiela Cabahug's codebase

import SwiftUI

struct ProcessingOverlayView: View {
    let status: String
    
    var body: some View {
        ZStack {
            // Blur background
            Color.black.opacity(0.3)
                .background(.ultraThinMaterial.opacity(0.5))
                .ignoresSafeArea()
            
            VStack(spacing: 50) {
                ProgressView()
                    .scaleEffect(2)
                    .progressViewStyle(CircularProgressViewStyle(tint: .white))
                
                Text(status)
                    .font(.body)
                    .fontWeight(.medium)
                    .foregroundColor(.white)
            }
            .padding(30)
            .background(
                RoundedRectangle(cornerRadius: 20)
                    .fill(Color.black.opacity(0.5))
            )
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .ignoresSafeArea()
    }
}
