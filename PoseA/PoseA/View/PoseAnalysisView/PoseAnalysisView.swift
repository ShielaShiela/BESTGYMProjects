//
//  PoseAnalysisView.swift
//  PoseA
//
//  Created by Ardhika Maulidani on 5/27/25.
//  Refactor from Shiela Cabahug's codebase

import SwiftUI

// MARK: - Pose Analysis View
// TODO: Move the calculation here, take one time parse from keypoint data then split into multiple calculation

struct PoseAnalysisView: View {
    // Define Variable
    let poseProcessor: VitPoseProcessor
    let currentFrameIndex: Int // MARK: Currently not used
    let cameraManager: CameraLiDARManager
    
    // Define Binding
    @Binding var showAnalysisView: Bool
    
    // Define State Variable
    @State private var selectedAnalysisType = AnalysisType.jointAngles
    @State private var selectedJoints: [String] = []
    @State private var timeRange: ClosedRange<Double> = 0...1
    
    // Define Enumeration
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
                // Fixed Picker at the top
                Picker("Analysis Type", selection: $selectedAnalysisType) {
                    ForEach(AnalysisType.allCases) { type in
                        Text(type.rawValue).tag(type)
                    }
                }
                .pickerStyle(SegmentedPickerStyle())
                .padding()
                
                // Fixed Horizontal Joint Selection
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 10) {
                        
                        ForEach(availableJoints, id: \.self) { joint in
                            // Disable Ankle Measurement for Joint Angle
                            if (joint == "L Ankle" || joint == "R Ankle" || joint == "L Wrist" || joint == "R Wrist") && selectedAnalysisType == .jointAngles {
                                EmptyView()
                            }
                            else{
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
                ScrollView {
                    VStack(alignment: .leading, spacing: 16) {
                        // Analysis Graph
                        AnalysisGraphView(
                            analysisType: selectedAnalysisType,
                            selectedJoints: selectedJoints,
                            timeRange: timeRange,
                            poseProcessor: poseProcessor,
                            cameraManager: cameraManager,
                            currentFrameIndex: currentFrameIndex // MARK: Currently not used
                        )
                        .padding()
                        .background(Color(.secondarySystemBackground))
                        .cornerRadius(12)
                        .padding(.horizontal)
                        
                        // Optional Analysis Metrics
                        if !selectedJoints.isEmpty {
                            AnalysisMetricsView(
                                analysisType: selectedAnalysisType,
                                selectedJoints: selectedJoints,
                                poseProcessor: poseProcessor,
                                currentFrameIndex: currentFrameIndex // MARK: Currently not used
                            )
                            .padding(.horizontal)
                        }

                        Spacer(minLength: 32)
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
    
    // Helper properties and methods
    private var totalFrames: Int {
        return poseProcessor.getTotalFrames()
    }
    
    private var availableJoints: [String] {
        return [
            "L Shoulder", "R Shoulder",
            "L Elbow", "R Elbow",
            "L Wrist", "R Wrist",
            "L Hip", "R Hip",
            "L Knee", "R Knee",
            "L Ankle", "R Ankle"
        ]
    }
    
    private func toggleJointSelection(_ joint: String) {
        if selectedJoints.contains(joint) {
            selectedJoints.removeAll { $0 == joint }
        } else {
            selectedJoints.append(joint)
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
