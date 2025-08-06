//
//  SwingAnalysisView.swift
//  PoseA
//
//  Created by Ardhika Maulidani on 7/28/25.
//

import SwiftUI

struct SwingAnalysisView: View {
    // MARK: - Properties
    
    // Declare State ViewModel Variable
    @State private var poseJointVM: PoseJointLandscapeVM
    @State private var chartBuilderViewModel: ChartBuilderLandscapeVM
    @State private var mediaManager: MediaManagerVM
    
    // Define Options Variable
    @State private var selectedOptions: Set<String> = []
    
    // MARK: - Initialization
    
    init (poseJointVM: PoseJointLandscapeVM, mediaManager: MediaManagerVM) {
        self.poseJointVM = poseJointVM
        self.mediaManager = mediaManager
        self._chartBuilderViewModel = State(wrappedValue: ChartBuilderLandscapeVM(poseJointViewModel: poseJointVM))
    }

    // MARK: - Body
    
    var body: some View {
        GeometryReader { geometry in
            VStack(alignment: .leading, spacing: 10) {
                // Set Title Name
                Text("Swing Analysis")
                    .font(.body)
                    .fontWeight(.bold)
                    .lineLimit(2)
                    .frame(width: geometry.size.width * 0.5,
                           height: 30,
                           alignment: .leading)
                
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
            .onAppear {
                self.chartBuilderViewModel.BuildChartData(selectedView: RightViewModel.swing,
                                                          selectedOptions: ["L Hip", "R Hip"])
            }
        }
    }
}
