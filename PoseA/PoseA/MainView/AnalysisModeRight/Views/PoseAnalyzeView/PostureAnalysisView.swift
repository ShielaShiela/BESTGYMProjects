//
//  PostureAnalysisView.swift
//  PoseA
//
//  Created by Ardhika Maulidani on 4/22/26.
//

import SwiftUI

struct PostureAnalysisView: View {
    // MARK: - Properties
    
    // Declare State ViewModel Variable
    @State private var chartBuilderVM: ChartBuilderVM
    @State private var mediaManager: MediaManagerVM
    
    // Define Options Variable
    @State private var selectedOptions: Set<String> = []
    
    // MARK: - Initialization
    
    init (chartBuilderVM: ChartBuilderVM, mediaManager: MediaManagerVM) {
        self.chartBuilderVM = chartBuilderVM
        self.mediaManager = mediaManager
    }

    // MARK: - Body
    
    var body: some View {
        GeometryReader { geometry in
            ZStack(alignment: .topTrailing) {
                VStack(alignment: .leading, spacing: 10) {
                    // Set Title Name
                    Text("Posture Analysis")
                        .font(.body)
                        .fontWeight(.bold)
                        .lineLimit(2)
                        .frame(width: geometry.size.width * 0.5,
                               height: 30,
                               alignment: .leading)
                    
                    // Notify Text if No Joint Selected
                    if self.chartBuilderVM.chartDataFirst.isEmpty && self.chartBuilderVM.chartDataSecond.isEmpty {
                        Text("Select Joint to Analyze")
                            .font(.body)
                            .fontWeight(.medium)
                            .foregroundColor(.gray)
                            .frame(maxWidth: .infinity, minHeight: geometry.size.height - 40)
                            .background(Color(.systemGray6))
                            .cornerRadius(16)
                    } else {
                        // Double Charts
                        ChartView(chartData: self.chartBuilderVM.chartDataFirst,
                                  currentX: self.getCurrentX(),
                                  eventsData: mediaManager.EventsData,
                                  xAxisUnit: "s",
                                  yAxisUnit: "deg")
                        .frame(width: geometry.size.width, height: (geometry.size.height - 50) * 0.5)
                        .background(Color(.systemGray6))
                        .cornerRadius(10)
                        
                        ChartView(chartData: self.chartBuilderVM.chartDataSecond,
                                  currentX: self.getCurrentX(),
                                  eventsData: mediaManager.EventsData,
                                  xAxisUnit: "s",
                                  yAxisUnit: "deg")
                        .frame(width: geometry.size.width, height: (geometry.size.height - 50) * 0.5)
                        .background(Color(.systemGray6))
                        .cornerRadius(10)
                    }
                }
                
                // Dropdown overlay
                MultiDropdownView(
                    options: ["Release Phase", "Flight Phase"],
                    selectedOptions: $selectedOptions
                )
            }
            .onChange(of: selectedOptions) {
                self.updateChart()
            }
        }
    }
    
    private func clearSelections() {
        selectedOptions.removeAll()
    }
    
    private func updateChart() {
        self.chartBuilderVM.clearAllData()
        self.chartBuilderVM.BuildChartData(selectedView: .posture,
                                           selectedOptions: selectedOptions)
    }
    
    private func getCurrentX() -> Double? {
        if selectedOptions.isEmpty { return nil }
        let currentFrame = mediaManager.currentFrameIndex
        let anchorIdx = selectedOptions.first! == "Release Phase" ? mediaManager.EventsData.release180PoseIdx : mediaManager.EventsData.ankleCrossIdx
        if let anchor = anchorIdx {
            return Double(currentFrame - anchor) / mediaManager.fps
        }
        return nil
    }
}
