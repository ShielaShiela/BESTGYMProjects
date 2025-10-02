//
//  PoseInformationView.swift
//  PoseA
//
//  Created by Ardhika Maulidani on 8/26/25.
//

import SwiftUI
import Charts

// Overlay to draw pose information
struct PoseInformationView: View {
    // MARK: - Properties
    @State var rtPoseJointVM: RealtimePoseJointViewModel
    @State private var isBarAvailable: Bool = false
    
    var body: some View {
        GeometryReader { geo in
            TabView {
                ZStack {
                    VStack(spacing: 4) {
                        Text("Pose Information")
                            .foregroundColor(.white)
                            .font(.body)
                        
                        Text("Bar Status: " + (rtPoseJointVM.barPoints != nil ? "Available" : "Not Available"))
                            .foregroundColor(.white)
                            .font(.caption)
                        
                        Text("Cam to Bar Distance: 8.3m")
                            .foregroundColor(.white)
                            .font(.caption)
                        
                        Text("Athlete on Bar: " + (rtPoseJointVM.isAthleteBar ? "Yes" : "No"))
                            .foregroundColor(.white)
                            .font(.caption)
                        
                        Text("Jump Height: " + (rtPoseJointVM.barPoints == nil ? "Bar Unavailable" :
                                                    (rtPoseJointVM.latched ? "\(String(format: "%.2f ", rtPoseJointVM.distToBar ?? 0.0)) m" : "No Jump Detected")))
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
                
                ZStack() {
                    VStack() {
                        Text("Swing Angle")
                            .font(.caption)
                            .foregroundColor(.white)
                            .padding(.top, 2)
                        
                        Chart {
                            ForEach(rtPoseJointVM.chartData) { jointData in
                                ForEach(jointData.dataPoints) { point in
                                    LineMark(
                                        x: .value("X", point.x),
                                        y: .value("Y", point.y)
                                    )
                                    .lineStyle(StrokeStyle(lineWidth: 2, lineCap: .round, lineJoin: .round))
                                    .foregroundStyle(.white)
                                    .interpolationMethod(.cardinal(tension: 0.4))
                                }
                            }
                        }
                        // Add X Axes
                        .chartXAxis {
                            AxisMarks(preset: .extended, position: .bottom) { value in
                                // Customize X-axis grid line style (dashed line)
                                AxisGridLine(centered: true, stroke: StrokeStyle(lineWidth: 1, dash: [5]))
                                    .foregroundStyle(.white.opacity(0.5)) // Set grid line color with transparency
                                AxisTick()
                                    .foregroundStyle(.gray)
                                AxisValueLabel {
                                    if let doubleValue = value.as(Double.self) {
                                        Text(String(format: "%.1f", doubleValue) + " n")
                                            .foregroundStyle(.gray)
                                    }
                                }
                            }
                        }
                        
                        // Add Y Axes
                        .chartYAxis {
                            AxisMarks(preset: .extended, position: .leading) { value in
                                AxisGridLine()
                                    .foregroundStyle(.white.opacity(0.5))
                                AxisTick()
                                    .foregroundStyle(.gray)
                                AxisValueLabel {
                                    if let doubleValue = value.as(Double.self) {
                                        Text(String(format: "%.1f%", doubleValue) + " deg")
                                            .foregroundStyle(.gray)
                                    }
                                }
                            }
                        }
                        .padding(2)
                    }
                    .frame(width: geo.size.width - 20, height: geo.size.height * 0.20)
                    .background(
                        RoundedRectangle(cornerRadius: 12)
                            .fill(Color.black.opacity(0.3))
                    )
                    .padding(10)
                    .position(x: geo.size.width * 0.5, y: geo.size.height * 0.80)

                }
            }
            .tabViewStyle(.page)
            .indexViewStyle(.page(backgroundDisplayMode: .interactive))
        }
    }
}
