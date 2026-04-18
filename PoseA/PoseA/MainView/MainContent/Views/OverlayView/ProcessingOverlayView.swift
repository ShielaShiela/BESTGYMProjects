//
//  ProcessingOverlayView.swift
//  PoseA
//
//  Created by Ardhika Maulidani on 5/27/25.
//  Refactor from Shiela Cabahug's codebase

import SwiftUI

struct ProcessingOverlayView: View {
    let status: String
    let progress: Double
    var boxSize: CGSize = CGSize(width: 250, height: 180) // Slightly larger for progress bar

    var body: some View {
        ZStack {
            // Blur background
            Color.black.opacity(0.3)
                .background(.ultraThinMaterial.opacity(0.5))
                .ignoresSafeArea()

            // Progress Content
            VStack(spacing: 20) {
                // Circular Progress Indicator
                if progress > 0 {
                    ProgressView(value: progress)
                        .scaleEffect(2)
                        .progressViewStyle(CircularProgressViewStyle(tint: .white))
                        .padding(.top)
                } else {
                    ProgressView()
                        .scaleEffect(2)
                        .progressViewStyle(CircularProgressViewStyle(tint: .white))
                        .padding(.top)
                }
                
                // Status Text
                Text(status)
                    .font(.caption)
                    .fontWeight(.medium)
                    .foregroundColor(.white)
                    .multilineTextAlignment(.center)
                    .lineLimit(nil)
                    .fixedSize(horizontal: false, vertical: true)
                    .frame(maxWidth: .infinity)
                
                // Linear Progress Bar (if progress is available)
                if progress > 0 {
                    VStack(spacing: 8) {
                        ProgressView(value: progress)
                            .progressViewStyle(LinearProgressViewStyle(tint: .blue))
                            .frame(width: 180)
                        
                        Text("\(Int(progress * 100))%")
                            .font(.system(size: 12))
                            .foregroundColor(.white.opacity(0.8))
                    }
                }
            }
            .padding(20)
            .frame(width: boxSize.width, height: boxSize.height)
            .background(
                RoundedRectangle(cornerRadius: 20)
                    .fill(Color.black.opacity(0.6))
            )
        }
        .transition(.opacity)
        .animation(.easeInOut(duration: 0.2), value: status)
        .animation(.easeInOut(duration: 0.2), value: progress)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .ignoresSafeArea()
    }
}

