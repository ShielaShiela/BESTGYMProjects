//
//  PoseAnalysisView.swift
//  PoseA
//
//  Created by Ardhika Maulidani on 5/27/25.
//  Refactor from Shiela Cabahug's codebase

import SwiftUI

// MARK: - Pose Analysis View

struct PoseAnalysisView: View {
    // MARK: - Input Properties
    let poseProcessor: VitPoseProcessor
    @Binding var showAnalysisView: Bool

    // MARK: - State Properties
    @StateObject private var poseJointViewModel: PoseJointViewModel
    @StateObject private var chartBuilderViewModel: ChartBuilderViewModel
    @State private var selectedAnalysisType = AnalysisType.jointAngles
    @State private var selectedJoints: [String] = []
    @State private var isDataLoading = false

    // MARK: - Init
    init(poseProcessor: VitPoseProcessor, showAnalysisView: Binding<Bool>) {
        self.poseProcessor = poseProcessor
        self._showAnalysisView = showAnalysisView
        
        // Initialize ViewModels
        let poseJointVM = PoseJointViewModel(poseProcessor: poseProcessor)
        self._poseJointViewModel = StateObject(wrappedValue: poseJointVM)
        self._chartBuilderViewModel = StateObject(wrappedValue: ChartBuilderViewModel(poseJointViewModel: poseJointVM))
    }
   
    // MARK: - Custom Variable
    enum AnalysisType: String, CaseIterable, Identifiable {
        // Identifier
        var id: String { self.rawValue }
        
        // Enum Case
        case jointAngles = "Angle"
        case trajectories = "Traj"
        case velocities = "Vel"
        case accelerations = "Acc"
        case comparison = "Compare"
    }
    
    var body: some View {
        NavigationView {
            VStack(spacing: 0) {
                // Fixed Picker at the Top
                Picker("Analysis Type", selection: $selectedAnalysisType) {
                    ForEach(AnalysisType.allCases) { type in
                        Text(type.rawValue).tag(type)
                    }
                }
                .pickerStyle(SegmentedPickerStyle())
                .padding()
                .onChange(of: selectedAnalysisType) { _, _ in
                    updateChartData()
                }
                
                // Fixed Horizontal Joint Selection
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 10) {
                        ForEach(availableJoints, id: \.self) { joint in
                            // Disable Ankle Measurement for Joint Angle
                            if (joint == "L Ankle" || joint == "R Ankle" || joint == "L Wrist" || joint == "R Wrist")
                                && selectedAnalysisType == .jointAngles {
                                EmptyView()
                            } else {
                                JointSelectionButton(
                                    jointName: joint,
                                    isSelected: selectedJoints.contains(joint),
                                    onToggle: {
                                        toggleJointSelection(joint)
                                    }
                                )
                            }
                        }
                    }
                    .padding(.horizontal)
                    .padding(.bottom)
                }
                
                // Scrollable content below
                if isDataLoading {
                    VStack {
                        Spacer()
                        
                        ProgressView("Loading data...")
                            .frame(maxWidth: .infinity)
                        
                        Spacer()
                    }
                    .frame(maxWidth: .infinity)
                } else {
                    ScrollView {
                        VStack(alignment: .leading, spacing: 16) {
                            // Analysis Graph
                            PoseGraphView(
                                analysisType: selectedAnalysisType,
                                selectedJoints: selectedJoints,
                                chartBuilderViewModel: chartBuilderViewModel
                            )
                            .padding()
                            .background(Color(.secondarySystemBackground))
                            .cornerRadius(12)
                            .padding(.horizontal)
                            
                            // Optional Analysis Metrics
                            if !selectedJoints.isEmpty {
                                PoseMetricsView(
                                    analysisType: selectedAnalysisType,
                                    selectedJoints: selectedJoints,
                                    chartBuilderViewModel: chartBuilderViewModel
                                )
                                .padding(.horizontal)
                            }

                            Spacer(minLength: 32)
                        }
                    }
                }
                
            }
            .navigationTitle("Pose Analysis")
            .navigationBarItems(
                trailing: Button("Done") {
                    showAnalysisView = false
                }
            )
        }
    }
    
    private func toggleJointSelection(_ joint: String) {
        if selectedJoints.contains(joint) {
            selectedJoints.removeAll { $0 == joint }
        } else {
            selectedJoints.append(joint)
        }
        
        // Clear existing data before updating
        chartBuilderViewModel.clearData(for: selectedAnalysisType)
        
        // Update with new data
        updateChartData()
    }
    
    private func updateChartData() {
        guard !selectedJoints.isEmpty else { return }
        
        isDataLoading = true
        
        // Clear existing data before building new data
        chartBuilderViewModel.clearData(for: selectedAnalysisType)
        
        // Build new data
        switch selectedAnalysisType {
        case .jointAngles:
            chartBuilderViewModel.buildAngleData(joints: selectedJoints)
        case .trajectories:
            chartBuilderViewModel.buildPositionData(joints: selectedJoints)
        case .velocities:
            chartBuilderViewModel.buildVelocityData(joints: selectedJoints)
        case .accelerations:
            chartBuilderViewModel.buildAccelerationData(joints: selectedJoints)
        case .comparison:
            break
        }
        
        // Reset loading state after a short delay to ensure smooth UI
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
            isDataLoading = false
        }
    }
}


// MARK: - Joint Selection Button
struct JointSelectionButton: View {
    let jointName: String
    let isSelected: Bool
    let onToggle: () -> Void
    
    var body: some View {
        Button(action: onToggle) {
            Text(jointName)
                .font(.caption)
                .padding(.horizontal, 12)
                .padding(.vertical, 8)
                .background(isSelected ? Color.blue : Color(.systemGray5))
                .foregroundColor(isSelected ? .white : .primary)
                .cornerRadius(16)
        }
    }
}
