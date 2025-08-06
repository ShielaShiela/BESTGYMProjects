//
//  DataMetricsView.swift
//  PoseA
//
//  Created by Ardhika Maulidani on 7/28/25.
//

import SwiftUI

struct DataMetricsView: View {
    // MARK: - Properties
    @State private var poseJointVM: PoseJointLandscapeVM
    @State private var chartBuilderViewModel: ChartBuilderLandscapeVM

    @State private var selectedOption: String? = nil
    private let options: [String] = ["Trajectory", "Velocity", "Acceleration", "Angle", "Swing"]
    
    @State private var expandedJoints: Set<String> = []
    
    // MARK: - Initialization
    init(poseJointVM: PoseJointLandscapeVM) {
        self.poseJointVM = poseJointVM
        self._chartBuilderViewModel = State(wrappedValue: ChartBuilderLandscapeVM(poseJointViewModel: poseJointVM))
    }

    // MARK: - Body
    var body: some View {
        GeometryReader { geometry in
            ZStack(alignment: .topTrailing) {
                VStack(alignment: .leading, spacing: 10) {
                    Text("Data Metrics")
                        .font(.body)
                        .fontWeight(.bold)
                        .lineLimit(2)
                        .frame(width: geometry.size.width * 0.5,
                               height: 30,
                               alignment: .leading)
   
                    ScrollView {
                        if self.chartBuilderViewModel.rawCompleteJointData.isEmpty {
                            Text("Select Aspect to Analyze")
                                .font(.body)
                                .fontWeight(.medium)
                                .foregroundColor(.gray)
                                .frame(maxWidth: .infinity, minHeight: geometry.size.height - 40)
                                .background(Color(.systemGray6))
                                .cornerRadius(16)
                        } else {
                            VStack(spacing: 8) {
                                ForEach(self.chartBuilderViewModel.rawCompleteJointData) { jointData in
                                    ExpandableJointView(
                                        selectedOptions: selectedOption,
                                        jointData: jointData,
                                        isExpanded: expandedJoints.contains(jointData.joint),
                                        toggleExpand: {
                                            withAnimation {
                                                if expandedJoints.contains(jointData.joint) {
                                                    expandedJoints.remove(jointData.joint)
                                                } else {
                                                    expandedJoints.insert(jointData.joint)
                                                }
                                            }
                                        }
                                    )
                                }
                            }
                        }
                    }
                }
                
                // Dropdown overlay
                SingleDropdownView(
                    options: options,
                    selectedOption: $selectedOption
                )
                .zIndex(1)
            }
        }
        .onChange(of: selectedOption) {
            self.updateChart()
        }
    }
    
    private func updateChart() {
        self.chartBuilderViewModel.clearAllData()
        self.chartBuilderViewModel.BuildDataMetricsData(selectedView: selectedOption)
    }
}

struct ExpandableJointView: View {
    var selectedOptions: String?
    var jointData: JointData
    var isExpanded: Bool
    var toggleExpand: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Text(jointData.joint)
                    .font(.system(size: 14))
                    .fontWeight(.medium)
                
                Spacer()
                
                Image(systemName: isExpanded ? "chevron.up" : "chevron.down")
                    .foregroundColor(.gray)
                    .imageScale(.small)
            }
            .contentShape(Rectangle())
            .onTapGesture {
                toggleExpand()
            }

            if isExpanded {
                VStack(alignment: .leading, spacing: 4) {
                    if selectedOptions == "Angle" || selectedOptions == "Swing" {
                        Text("Max: \(String(format: "%.2f", jointData.dataMetrics.maxX))")
                        Text("Min: \(String(format: "%.2f", jointData.dataMetrics.minX))")
                    } else{
                        Text("Max X: \(String(format: "%.2f", jointData.dataMetrics.maxX))")
                        Text("Min X: \(String(format: "%.2f", jointData.dataMetrics.minX))")
                        Text("Max Y: \(String(format: "%.2f", jointData.dataMetrics.maxY))")
                        Text("Min Y: \(String(format: "%.2f", jointData.dataMetrics.minY))")
                    }
                }
                .font(.caption)
                .foregroundColor(.secondary)
                .padding(.leading, 10)
                .transition(.opacity.combined(with: .move(edge: .top)))
            }
        }
        .padding()
        .background(Color(.systemGray6))
        .cornerRadius(12)
        .shadow(color: Color.black.opacity(0.05), radius: 2, x: 0, y: 1)
    }
}
