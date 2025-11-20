//
//  DataMetricsView.swift
//  PoseA
//
//  Created by Ardhika Maulidani on 7/28/25.
//

import SwiftUI

struct DataMetricsView: View {
    // MARK: - Properties
    @ObservedObject var appState: MainAppState
    @State private var poseJointVM: PoseJointLandscapeVM
    @State private var chartBuilderViewModel: ChartBuilderLandscapeVM

    @State private var selectedOption: String? = nil
    private let options: [String] = ["Trajectory", "Velocity", "Acceleration", "Angle", "Swing"]
    
    @State private var expandedJoints: Set<String> = []
        
    // MARK: - Initialization
    init(appState: MainAppState, poseJointVM: PoseJointLandscapeVM) {
        self.appState = appState
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
                                        appState: appState,
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
    // MARK: - Properties
    var appState: MainAppState
    var selectedOptions: String?
    var jointData: JointData3D
    var isExpanded: Bool
    var toggleExpand: () -> Void

    @State private var dataUnits: String = ""

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
                        Text("Max: \(String(format: "%.2f ", jointData.dataMetrics.maxX))" + getDataUnits(selectedOption: selectedOptions, jointName: jointData.joint))
                        Text("Min: \(String(format: "%.2f ", jointData.dataMetrics.minX))" + getDataUnits(selectedOption: selectedOptions, jointName: jointData.joint))
                    } else{
                        Text("Max X: \(String(format: "%.2f ", jointData.dataMetrics.maxX))" + getDataUnits(selectedOption: selectedOptions, jointName: jointData.joint))
                        Text("Min X: \(String(format: "%.2f ", jointData.dataMetrics.minX))" + getDataUnits(selectedOption: selectedOptions, jointName: jointData.joint))
                        Text("Max Y: \(String(format: "%.2f ", jointData.dataMetrics.maxY))" + getDataUnits(selectedOption: selectedOptions, jointName: jointData.joint))
                        Text("Min Y: \(String(format: "%.2f ", jointData.dataMetrics.minY))" + getDataUnits(selectedOption: selectedOptions, jointName: jointData.joint))
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
    
    private func getDataUnits(selectedOption: String?, jointName: String) -> String {
        switch(selectedOption) {
        case "Angle":
            return self.appState.angleUnit.id
        case "Trajectory":
            return self.appState.distanceUnit.id
        case "Velocity":
            return self.appState.distanceUnit.id + "/" + self.appState.timeUnit.id
        case "Acceleration":
            return self.appState.distanceUnit.id + "/" + self.appState.timeUnit.id + "2"
        case "Swing":
            if jointName == "Swing Angle" {
                return self.appState.angleUnit.id
            } else if jointName == "Swing Angle Velocity" {
                return self.appState.angleUnit.id + "/" + self.appState.timeUnit.id
            } else {
                return ""
            }
            
        default: return String("")
        }
    }
}
