//
//  ChartsLegendView.swift
//  PoseA
//
//  Created by Bestlab on 6/2/25.
//

import SwiftUI

struct ChartsLegendView: View {
    let chartData: [JointData]
    
    // Grid for Legends
    let columns = [
        GridItem(.flexible(minimum: 10), spacing: 5),
        GridItem(.flexible(minimum: 10), spacing: 5),
        GridItem(.flexible(minimum: 10), spacing: 5),
        GridItem(.flexible(minimum: 10), spacing: 5)
    ]
    
    var body: some View {
        VStack {
            if chartData.count <= 4 {
                // Single row
                HStack {
                    ForEach(chartData) { jointData in
                        HStack(spacing: 4) {
                            Circle()
                                .fill(jointColors[jointData.joint] ?? .gray)
                                .frame(width: 5, height: 5)
                            Text(jointData.joint)
                                .font(.system(size: 7))
                        }
                        .padding(.horizontal, 5)
                    }
                }
            } else {
                // 2x4 grid
                LazyVGrid(columns: columns, alignment: .leading, spacing: 4) {
                    ForEach(chartData) { jointData in
                        HStack(spacing: 4) {
                            Circle()
                                .fill(jointColors[jointData.joint] ?? .gray)
                                .frame(width: 5, height: 5)
                            Text(jointData.joint)
                                .font(.system(size: 7))
                        }
                        .padding(.horizontal, 4)
                    }
                }
            }
        }
    }
}
