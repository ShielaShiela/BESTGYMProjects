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
    let cameraManager: CameraLiDARManager
    @Binding var showAnalysisView: Bool
    
    // MARK: - State Properties
    @StateObject private var poseJointViewModel: PoseJointVM
    @StateObject private var chartBuilderViewModel: ChartBuilderVM
    @StateObject private var swingAnalysisViewModel: SwingDataVM
    
    @State private var selectedAnalysisType = AnalysisType.jointAngles
    @State private var previousSelectedJoints: Set<String> = []
    @State private var selectedJoints: [String] = []
    @State private var isDataLoading = false
    
    // MARK: - Init
    init(poseProcessor: VitPoseProcessor, cameraManager: CameraLiDARManager, showAnalysisView: Binding<Bool>) {
        self.poseProcessor = poseProcessor
        self.cameraManager = cameraManager
        self._showAnalysisView = showAnalysisView
        
        // Initialize ViewModels
        let poseJointVM = PoseJointVM(poseProcessor: poseProcessor, cameraManager: cameraManager)
        self._poseJointViewModel = StateObject(wrappedValue: poseJointVM)
        self._chartBuilderViewModel = StateObject(wrappedValue: ChartBuilderVM(poseJointViewModel: poseJointVM))
        self._swingAnalysisViewModel = StateObject(wrappedValue: SwingDataVM(poseJointViewModel: poseJointVM))
    }
    
    // MARK: - Custom Variable
    enum AnalysisType: String, CaseIterable, Identifiable {
        // Identifier
        var id: String { self.rawValue }
        
        // Enum Case
        case jointAngles = "Angle"
        case trajectories2D = "Traj"
        case velocities = "Vel"
        case accelerations = "Acc"
        case swingMotion = "Swing"
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
                    // Clear All Data
                    previousSelectedJoints = Set(selectedJoints) // sync selection baseline
                    chartBuilderViewModel.clearAllData()
                    // Update the Data
                    updateChartData(addedJoints: selectedJoints, removedJoints: [])
                }

                
                // Fixed Horizontal Joint Selection
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 10) {
                        ForEach(availableJoints, id: \.self) { joint in
                            // Disable Ankle Measurement for Joint Angle
                            if (joint == "L Ankle" || joint == "R Ankle" || joint == "L Wrist" || joint == "R Wrist")
                                && selectedAnalysisType == .jointAngles {
                                EmptyView()
                            }
                            else if selectedAnalysisType == .swingMotion {
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
                                chartBuilderViewModel: chartBuilderViewModel,
                                swingAnalysisViewModel: swingAnalysisViewModel
                            )
                            .padding()
                            .background(Color(.secondarySystemBackground))
                            .cornerRadius(12)
                            .padding(.horizontal)
                            
                            // Optional Analysis Metrics
                            if (selectedJoints.isEmpty && selectedAnalysisType == .swingMotion) || (!selectedJoints.isEmpty) {
                                PoseMetricsView(
                                    analysisType: selectedAnalysisType,
                                    selectedJoints: selectedJoints,
                                    chartBuilderViewModel: chartBuilderViewModel,
                                    swingAnalysisViewModel: swingAnalysisViewModel
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
        let oldSet = Set(selectedJoints)
        if selectedJoints.contains(joint) {
            selectedJoints.removeAll { $0 == joint }
        } else {
            selectedJoints.append(joint)
        }
        
        let newSet = Set(selectedJoints)
        let added = newSet.subtracting(oldSet)
        let removed = oldSet.subtracting(newSet)
        
        // Update the chart incrementally
        self.updateChartData(addedJoints: Array(added), removedJoints: Array(removed))
        
        previousSelectedJoints = newSet
    }
    

    private func updateChartData(addedJoints: [String], removedJoints: [String]) {
        guard (selectedJoints.isEmpty && selectedAnalysisType == .swingMotion) || (!selectedJoints.isEmpty) else {
            chartBuilderViewModel.clearAllData()
            return
        }
        
        isDataLoading = true

        // Clear only removed joints
        chartBuilderViewModel.clearData(for: selectedAnalysisType, joints: removedJoints)
        
        // Swing Data Build (Optional)

        
        // Add only new data for added joints
        switch selectedAnalysisType {
        case .jointAngles:
            chartBuilderViewModel.buildAngleData(joints: addedJoints) {
                isDataLoading = false
            }
        case .trajectories2D:
            chartBuilderViewModel.buildPositionData(joints: addedJoints, useDepth: false) {
                isDataLoading = false
            }
        case .swingMotion:
            chartBuilderViewModel.buildPositionData(joints: ["L Hip", "R Hip"], useDepth: false) {
                swingAnalysisViewModel.estimateBar() {
                    swingAnalysisViewModel.calculateAngleData() {
                        isDataLoading = false
                    }
                }
            }
        case .velocities:
            chartBuilderViewModel.buildVelocityData(joints: addedJoints) {
                isDataLoading = false
            }
        case .accelerations:
            chartBuilderViewModel.buildAccelerationData(joints: addedJoints) {
                isDataLoading = false
            }
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
