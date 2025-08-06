//
//  PoseAnalysisLandscapeView.swift
//  PoseA
//
//  Created by Ardhika Maulidani on 7/14/25.
//

import SwiftUI

struct PoseAnalysisView: View {
    // MARK: - Properties
    
    // Declare State ViewModel Variable
    @State private var poseJointVM: PoseJointLandscapeVM
    @State private var chartBuilderViewModel: ChartBuilderLandscapeVM
    @State private var mediaManager: MediaManagerVM
    
    // Define Options Variable
    @State private var selectedOptions: Set<String> = []
    private let selectedView: RightViewModel
    private let exceptionOptions: Set<String> = ["L Ankle", "R Ankle", "L Wrist", "R Wrist"]
    
    // MARK: - Initialization
    
    init (selectedView: RightViewModel, poseJointVM: PoseJointLandscapeVM, mediaManager: MediaManagerVM) {
        self.selectedView = selectedView
        self.poseJointVM = poseJointVM
        self.mediaManager = mediaManager
        self._chartBuilderViewModel = State(wrappedValue: ChartBuilderLandscapeVM(poseJointViewModel: poseJointVM))
    }

    // MARK: - Body
    
    var body: some View {
        GeometryReader { geometry in
            ZStack(alignment: .topTrailing) {
                VStack(alignment: .leading, spacing: 10) {
                    // Set Title Name
                    switch(selectedView) {
                    case .angle:
                        Text("Angle Analysis")
                            .font(.body)
                            .fontWeight(.bold)
                            .lineLimit(2)
                            .frame(width: geometry.size.width * 0.5,
                                   height: 30,
                                   alignment: .leading)
                    case .trajectoryAxes:
                        Text("Trajectory Analysis")
                            .font(.body)
                            .fontWeight(.bold)
                            .lineLimit(2)
                            .frame(width: geometry.size.width * 0.5,
                                   height: 30,
                                   alignment: .leading)
                    case .velocity:
                        Text("Velocity Analysis")
                            .font(.body)
                            .fontWeight(.bold)
                            .lineLimit(2)
                            .frame(width: geometry.size.width * 0.5,
                                   height: 30,
                                   alignment: .leading)
                    case .acceleration:
                        Text("Acceleration Analysis")
                            .font(.body)
                            .fontWeight(.bold)
                            .lineLimit(2)
                            .frame(width: geometry.size.width * 0.5,
                                   height: 30,
                                   alignment: .leading)
                    default: Text("")
                    }
                    
                    // Notify Text if No Joint Selected
                    if self.chartBuilderViewModel.chartDataFirst.isEmpty {
                        Text("Select Joint to Analyze")
                            .font(.body)
                            .fontWeight(.medium)
                            .foregroundColor(.gray)
                            .frame(maxWidth: .infinity, minHeight: geometry.size.height - 40)
                            .background(Color(.systemGray6))
                            .cornerRadius(16)
                    } else {
                        // Single Charts
                        if self.chartBuilderViewModel.chartDataSecond.isEmpty {
                            ChartLandscapeView(chartData: self.chartBuilderViewModel.chartDataFirst,
                                               currentFrame: mediaManager.currentFrameIndex)
                                .frame(width: geometry.size.width, height: (geometry.size.height - 50))
                                .background(Color(.systemGray6))
                                .cornerRadius(10)
                        } else {
                            // Double Charts
                            ChartLandscapeView(chartData: self.chartBuilderViewModel.chartDataFirst,
                                               currentFrame: mediaManager.currentFrameIndex)
                                .frame(width: geometry.size.width, height: (geometry.size.height - 50) * 0.5)
                                .background(Color(.systemGray6))
                                .cornerRadius(10)

                            ChartLandscapeView(chartData: self.chartBuilderViewModel.chartDataSecond,
                                               currentFrame: mediaManager.currentFrameIndex)
                                .frame(width: geometry.size.width, height: (geometry.size.height - 50) * 0.5)
                                .background(Color(.systemGray6))
                                .cornerRadius(10)
                        }
                    }
                }

                // Dropdown overlay
                MultiDropdownView(
                    options: selectedView == .angle ? availableJoints.filter { !exceptionOptions.contains($0) } : availableJoints,
                    selectedOptions: $selectedOptions
                )
                .zIndex(1)
            }
        }
        .onChange(of: selectedOptions) {
            self.updateChart()
        }
        .onChange(of: selectedView) {
            self.updateChart()
        }
    }
    
    private func updateChart() {
        self.chartBuilderViewModel.clearAllData()
        self.chartBuilderViewModel.BuildChartData(selectedView: selectedView,
                                                  selectedOptions: selectedOptions)
    }
}
