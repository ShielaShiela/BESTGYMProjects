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
    @ObservedObject var appState: MainAppState
    @State private var chartBuilderVM: ChartBuilderVM
    @State private var mediaManager: MediaManagerVM
    
    // Define Options Variable
    @State private var selectedOptions: Set<String> = []
    private let selectedView: RightViewModel

    // Define Variable Units
    @State private var AxisUnits: String = ""
    
    // MARK: - Initialization
    
    init (appState: MainAppState, selectedView: RightViewModel, chartBuilderVM: ChartBuilderVM, mediaManager: MediaManagerVM) {
        self.appState = appState
        self.selectedView = selectedView
        self.chartBuilderVM = chartBuilderVM
        self.mediaManager = mediaManager
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
                    case .position:
                        Text("Position Analysis")
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
                    default: Text("")
                    }
                    
                    // Notify Text if No Joint Selected
                    if self.chartBuilderVM.chartDataFirst.isEmpty {
                        Text("Select Joint to Analyze")
                            .font(.body)
                            .fontWeight(.medium)
                            .foregroundColor(.gray)
                            .frame(maxWidth: .infinity, minHeight: geometry.size.height - 40)
                            .background(Color(.systemGray6))
                            .cornerRadius(16)
                    } else {
                        // Single Charts
                        if self.chartBuilderVM.chartDataSecond.isEmpty {
                            ChartView(chartData: self.chartBuilderVM.chartDataFirst,
                                      currentFrame: mediaManager.currentFrameIndex,
                                      eventsData: mediaManager.EventsData,
                                      xAxisUnit: self.appState.timeUnit.id,
                                      yAxisUnit: AxisUnits)
                                .frame(width: geometry.size.width, height: (geometry.size.height - 50))
                                .background(Color(.systemGray6))
                                .cornerRadius(10)
                        } else {
                            // Double Charts
                            ChartView(chartData: self.chartBuilderVM.chartDataFirst,
                                      currentFrame: mediaManager.currentFrameIndex,
                                      eventsData: mediaManager.EventsData,
                                      xAxisUnit: self.appState.timeUnit.id,
                                      yAxisUnit: AxisUnits)
                                .frame(width: geometry.size.width, height: (geometry.size.height - 50) * 0.5)
                                .background(Color(.systemGray6))
                                .cornerRadius(10)

                            ChartView(chartData: self.chartBuilderVM.chartDataSecond,
                                      currentFrame: mediaManager.currentFrameIndex,
                                      eventsData: mediaManager.EventsData,
                                      xAxisUnit: self.appState.timeUnit.id,
                                      yAxisUnit: AxisUnits)
                                .frame(width: geometry.size.width, height: (geometry.size.height - 50) * 0.5)
                                .background(Color(.systemGray6))
                                .cornerRadius(10)
                        }
                    }
                }

                // Dropdown overlay
                MultiDropdownView(
                    options: self.getOptionsForView(),
                    selectedOptions: $selectedOptions
                )
            }
        }
        .onChange(of: selectedOptions) {
            self.updateChart()
        }
        .onChange(of: selectedView) {
            self.clearSelections()
            self.updateChart()
        }
    }
    
    private func getOptionsForView() -> [String] {
        switch selectedView {
        case .angle:
            return ["Shoulder", "Hip", "Knee", "vArm", "vTorso", "vThigh", "vLowerLeg", "CoM"]
        case .position:
            return ["Head-Bar", "Wrist-Bar"]
        case .velocity:
            return ["Shoulder", "Hip", "Knee", "vArm", "vTorso", "vThigh", "vLowerLeg"]
        default:
            return []
        }
    }
    
    private func clearSelections() {
        selectedOptions.removeAll()
    }
    
    private func updateChart() {
        self.chartBuilderVM.clearAllData()
        self.chartBuilderVM.BuildChartData(selectedView: selectedView,
                                           selectedOptions: selectedOptions)
        
        switch(selectedView) {
        case .angle:
            self.AxisUnits = self.appState.angleUnit.id
        case .position:
            self.AxisUnits = self.appState.distanceUnit.id
        case .velocity:
            self.AxisUnits = self.appState.angleUnit.id + "/" + self.appState.timeUnit.id
        default: self.AxisUnits = String("")
        }
    }
}
