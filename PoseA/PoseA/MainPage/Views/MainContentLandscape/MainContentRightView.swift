//
//  MainContentRightView.swift
//  PoseA
//
//  Created by Ardhika Maulidani on 7/9/25.
//

import SwiftUI

struct MainContentRightView: View {
    @ObservedObject var appState: MainAppState
    @ObservedObject var ROIModel: ROIViewModel
    @ObservedObject var BoxModel: BoxViewModel
    @State var mediaManager: MediaManagerVM
    
    @State var selectedView: RightViewModel = .info
    @State private var poseJointVM: PoseJointLandscapeVM
    
    init(appState: MainAppState, ROIModel: ROIViewModel, BoxModel: BoxViewModel, mediaManager: MediaManagerVM) {
        self.appState = appState
        self.ROIModel = ROIModel
        self.BoxModel = BoxModel
        self.mediaManager = mediaManager
        
        self._poseJointVM = State(wrappedValue: PoseJointLandscapeVM(BoxModel: BoxModel,
                                                                     mediaManager: mediaManager))
    }
    
    var body: some View {
        GeometryReader { geometry in
            ZStack() {
                // Set View Screen
                
                if selectedView == .info {
                    // Media Info View
                    InformationView(appState: appState,
                                    ROIModel: ROIModel,
                                    BoxModel: BoxModel,
                                    mediaManager: mediaManager)
                    .frame(height: geometry.size.height)
                    .padding(.horizontal)
                    
                } else {
                    // Pose Analysis View
                    PoseAnalysisLandscapeView(selectedView: selectedView,
                                              poseJointVM: poseJointVM,
                                              mediaManager: mediaManager)
                    .frame(height: geometry.size.height)
                    .padding(.horizontal)
                    
                }
                
                
                // MENU CHANGER
                // TODO: Change the layout and UI to be more compact. For now focusing on Pose Analysis Rework
                VStack(alignment: .trailing) {
                    Spacer()
                    
                    if !appState.sourceFileName.isEmpty {
                        Menu {
                            Group {
                                Button(action: { selectedView = .info }) {
                                    Text("Media Information")
                                        .font(.system(size: 10)) // Smaller font
                                        .padding(2)              // Less padding
                                }
                                
                                Divider()
                                
                                if appState.isAnalysisAvailable {
                                    Button(action: { selectedView = .angle }) {
                                        Text("Angle Analysis")
                                            .font(.system(size: 10))
                                            .padding(2)
                                    }
                                    Button(action: { selectedView = .trajectory }) {
                                        Text("Trajectory Analysis")
                                            .font(.system(size: 10))
                                            .padding(2)
                                    }
                                    Button(action: { selectedView = .trajectoryAxes }) {
                                        Text("Single Axes Analysis")
                                            .font(.system(size: 10))
                                            .padding(2)
                                    }
                                    
                                    Divider()
                                    
                                    Button(action: { selectedView = .velocity }) {
                                        Text("Velocity Analysis")
                                            .font(.system(size: 10))
                                            .padding(2)
                                    }
                                    Button(action: { selectedView = .acceleration }) {
                                        Text("Acceleration Analysis")
                                            .font(.system(size: 10))
                                            .padding(2)
                                    }
                                    Button(action: { updateData() }) {
                                        Text("ReAnalyze!")
                                            .font(.system(size: 10))
                                            .padding(2)
                                    }
                                } else {
                                    Button(action: { updateData() }) {
                                        Text("Start Analysis!")
                                            .font(.system(size: 10))
                                            .padding(2)
                                    }
                                }
                                
                            }
                        } label: {
                            // This stays exactly as you had it
                            Image(systemName: "waveform.path.ecg")
                                .resizable()
                                .scaledToFit()
                                .frame(width: 26, height: 24)
                                .foregroundColor(.white)
                                .padding(20)
                                .background(
                                    Circle().fill(
                                        LinearGradient(
                                            gradient: Gradient(colors: [Color.blue, Color.cyan]),
                                            startPoint: .topLeading,
                                            endPoint: .bottomTrailing
                                        ).opacity(0.5)
                                    )
                                )
                                .shadow(color: Color.black.opacity(0.2), radius: 4, x: 2, y: 2)
                        }
                    }
                }
            }
        }
    }
    
    private func updateData() {
        // Revert State
        appState.isProcessing = true
        appState.isAnalysisAvailable = false
        
        // Do Pose Analyze Processing
        poseJointVM.buildCompleteData { success in
            // Set State when finished
            appState.isAnalysisAvailable = success
            appState.isProcessing = false
        }
    }
}
