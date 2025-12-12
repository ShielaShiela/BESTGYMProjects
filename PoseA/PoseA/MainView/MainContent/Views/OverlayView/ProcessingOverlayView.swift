//
//  ProcessingOverlayView.swift
//  PoseA
//
//  Created by Ardhika Maulidani on 5/27/25.
//  Refactor from Shiela Cabahug's codebase

import SwiftUI

struct ProcessingOverlayView: View {
    let status: String
    var boxSize: CGSize = CGSize(width: 200, height: 150) // You can make this dynamic

    var body: some View {
        ZStack {
            // Blur background
            Color.black.opacity(0.3)
                .background(.ultraThinMaterial.opacity(0.5))
                .ignoresSafeArea()

            VStack(spacing: 20) {
                ProgressView()
                    .scaleEffect(2)
                    .progressViewStyle(CircularProgressViewStyle(tint: .white))
                    .padding(.top)
                
                Text(status)
                    .font(.caption)
                    .fontWeight(.medium)
                    .foregroundColor(.white)
                    .multilineTextAlignment(.center)
                    .lineLimit(nil)
                    .fixedSize(horizontal: false, vertical: true)
                    .frame(maxWidth: .infinity)
                    .padding(.top)
            }
            .padding(20)
            .frame(width: boxSize.width, height: boxSize.height)
            .background(
                RoundedRectangle(cornerRadius: 20)
                    .fill(Color.black.opacity(0.6))
            )
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .ignoresSafeArea()
    }
}

