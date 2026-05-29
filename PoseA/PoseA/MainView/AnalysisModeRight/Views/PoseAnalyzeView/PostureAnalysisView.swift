//
//  PostureAnalysisView.swift
//  PoseA
//
//  Created by Ardhika Maulidani on 4/22/26.
//

import SwiftUI

struct PostureAnalysisItem {
    let name: String
    let chartData: [ChartData2D]
}

struct PostureAnalysisView: View {
    // MARK: - Properties
    
    // Declare State ViewModel Variable
    @State private var chartBuilderVM: ChartBuilderVM
    @State private var mediaManager: MediaManagerVM
    
    // Define Options Variable
    @State private var selectedOptions: Set<String> = []
    
    private var jointItems: [PostureAnalysisItem] {
        [
            PostureAnalysisItem(
                name: "Shoulder",
                chartData: chartBuilderVM.chartDataFirst
            ),
            PostureAnalysisItem(
                name: "Hip",
                chartData: chartBuilderVM.chartDataSecond
            ),
            PostureAnalysisItem(
                name: "Knee",
                chartData: chartBuilderVM.chartDataThird
            ),
        ]
    }
    
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
                    if self.chartBuilderVM.chartDataThird.isEmpty {
                        Text("Select Joint to Analyze")
                            .font(.body)
                            .fontWeight(.medium)
                            .foregroundColor(.gray)
                            .frame(maxWidth: .infinity, minHeight: geometry.size.height - 40)
                            .background(Color(.systemGray6))
                            .cornerRadius(16)
                    } else {
                        TabView {
                            ForEach(jointItems.indices, id: \.self) { index in
                                PostureAnalysisTabView(
                                    item: jointItems[index],
                                    currentX: getCurrentX() ?? nil,
                                    deviationData: chartBuilderVM.deviationData[jointItems[index].name] ?? []
                                )
                            }
                        }
                        .tabViewStyle(PageTabViewStyle())
                        .indexViewStyle(.page(backgroundDisplayMode: .always))
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
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
    
    private struct PostureAnalysisTabView: View {
        let item: PostureAnalysisItem
        let currentX: Double?
        let deviationData: [DeviationModel]
        
        var body: some View {
            GeometryReader { geometry in
                VStack(alignment: .leading, spacing: 10) {
                    PostureChartView(
                        chartData: item.chartData,
                        currentX: currentX,
                        deviationData: deviationData,
                        xAxisUnit: "deg",
                        yAxisUnit: "deg"
                    )
                    .frame(width: geometry.size.width, height: (geometry.size.height - 50) * 0.5)
                    .background(Color(.systemGray6))
                    .cornerRadius(10)

                    Text("Suggestion for \(item.name):")
                        .font(.caption)
                        .fontWeight(.bold)
                        .lineLimit(2)

                    ForEach(
                        deviationData
                            .compactMap(\.suggestion)
                            .reduce(into: [String]()) { result, s in
                                if !result.contains(s) { result.append(s) }
                            },
                        id: \.self
                    ) { suggestion in
                        Text("• \(suggestion)")
                            .font(.caption)
                            .fontWeight(.light)
                    }

                }
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
        
        guard let startRelease = mediaManager.EventsData.releaseStartPoseIdx,
              let endRelease = mediaManager.EventsData.releaseEndPoseIdx,
              let startFlight = mediaManager.EventsData.flightStartPoseIdx,
              let endFlight = mediaManager.EventsData.flightEndPoseIdx else {
            return nil
        }
        
        let isCCW = mediaManager.EventsData.rotationDir == "CCW"
        let currentFrame = mediaManager.currentFrameIndex
        
        let insideRelease = selectedOptions.first! == "Release Phase" && currentFrame >= startRelease && currentFrame <= endRelease
        let insideFlight = selectedOptions.first! == "Flight Phase" && currentFrame >= startFlight && currentFrame <= endFlight

        let currentCoM = mediaManager.FeaturesData[currentFrame]?.comAngle ?? nil
        if let currentCoM = currentCoM, (insideRelease || insideFlight) {
            var transformedCoM = isCCW ? 360.0 - currentCoM : currentCoM
            if insideFlight,
               let flightData = mediaManager.PostureData.first(where: { $0.phase == .flight }),
               let anyJoint   = flightData.joints.values.first,
               !anyJoint.refMean.isEmpty {
                let refMid = (anyJoint.refMean.first!.x + anyJoint.refMean.last!.x) / 2.0
                if transformedCoM < refMid - 180.0 {
                    transformedCoM += 360.0
                }
            }
            return transformedCoM
        }
        

        
        return nil
    }

    
}
