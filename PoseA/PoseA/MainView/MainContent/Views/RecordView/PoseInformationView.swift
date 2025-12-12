//
//  PoseInformationView.swift
//  PoseA
//
//  Created by Ardhika Maulidani on 8/26/25.
//

import SwiftUI

// Overlay to draw pose information
struct PoseInformationView: View {


    var body: some View {
        GeometryReader { geo in
            ZStack {
                VStack(spacing: 4) {
                    Text("Pose Information")
                        .foregroundColor(.white)
                        .font(.body)
                    
                    Text("Bar Status: Available")
                        .foregroundColor(.white)
                        .font(.caption)
                    
                    Text("Cam to Bar Distance: 8.3m")
                        .foregroundColor(.white)
                        .font(.caption)
                    
                    Text("Height: 1.8m")
                        .foregroundColor(.white)
                        .font(.caption)
                    
                    Text("Height: 1.8m")
                        .foregroundColor(.white)
                        .font(.caption)
                }
                .frame(width: 175, height: 125) // fixes the size
                .background(
                    RoundedRectangle(cornerRadius: 12)
                        .fill(Color.black.opacity(0.3))
                )
                .position(x: geo.size.width - 100, y: 75)
            }
        }
    }
}

