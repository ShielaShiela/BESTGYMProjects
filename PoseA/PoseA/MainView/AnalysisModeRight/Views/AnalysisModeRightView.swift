//
//  MainContentRightView.swift
//  PoseA
//
//  Created by Ardhika Maulidani on 7/9/25.
//

import SwiftUI

struct AnalysisModeRightView: View {
    @ObservedObject var appState: MainAppState
    @State var ROIModel: ROIViewModel
    @State var BoxModel: BoxViewModel
    @State var mediaManager: MediaManagerVM
//    @State var MLModel: VitPoseProcessor
    
    @State var selectedView: RightViewModel = .info
    @State private var poseJointVM: PoseJointLandscapeVM
    
    // ✅ ADD: one coordinator, lives with the view
    @State private var inferenceCoordinator = InferenceCoordinator()
    @State var calibrationModel: CalibrationModel
    let resetToken: UUID
    

    
    init(appState: MainAppState, ROIModel: ROIViewModel, BoxModel: BoxViewModel, mediaManager: MediaManagerVM, calibrationModel: CalibrationModel,resetToken: UUID) {
        self.appState = appState
        self.ROIModel = ROIModel
        self.BoxModel = BoxModel
        self.mediaManager = mediaManager
        self.calibrationModel = calibrationModel
        self.resetToken = resetToken
//        self.MLModel = MLModel
        
        // Initialize the PoseJointLandscapeVM with the provided BoxModel and mediaManager
        self._poseJointVM = State(wrappedValue: PoseJointLandscapeVM(BoxModel: BoxModel,
                                                                     mediaManager: mediaManager))
   
    }
    
    var body: some View {
        GeometryReader { geometry in
            ZStack() {
                // Set View Screen
                switch(selectedView) {
                case .info:
                    // Media Info View
                    InformationView(appState: appState,
                                    ROIModel: ROIModel,
                                    BoxModel: BoxModel,
                                    mediaManager: mediaManager,
                                    calibrationModel: calibrationModel)
                    .frame(height: geometry.size.height)
                    .padding(.horizontal)
                
                case .dataMetrics:
                    DataMetricsView(appState: appState,
                                    poseJointVM: poseJointVM)
                    .frame(height: geometry.size.height)
                    .padding(.horizontal)
                    
                case .swing:
                    SwingAnalysisView(appState: appState,
                                      poseJointVM: poseJointVM,
                                      mediaManager: mediaManager)
                    .frame(height: geometry.size.height)
                    .padding(.horizontal)
                
                case .flightHeight:
                    FlightHeightView(
                        appState: appState,
                        poseJointVM: poseJointVM,
                        mediaManager: mediaManager,
                        calibrationModel: calibrationModel   // pass through
                    )
                    .frame(height: geometry.size.height)
                    .padding(.horizontal)
                
                default:
                    // Pose Analysis View
                    PoseAnalysisView(appState: appState,
                                     selectedView: selectedView,
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
                                    Button(action: { selectedView = .swing }) {
                                        Text("Giant Swing Analysis")
                                            .font(.system(size: 10))
                                            .padding(2)
                                    }
                                    
                                    Divider()
                                    
                                    Button(action: { selectedView = .angle }) {
                                        Text("Angle Analysis")
                                            .font(.system(size: 10))
                                            .padding(2)
                                    }

                                    Button(action: { selectedView = .trajectoryAxes }) {
                                        Text("Single Axes Analysis")
                                            .font(.system(size: 10))
                                            .padding(2)
                                    }
                                    
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
                                    
                                    Button(action: { selectedView = .dataMetrics }) {
                                        Text("Data Metrics")
                                            .font(.system(size: 10))
                                            .padding(2)
                                    }
                                    
                                    Button(action: { selectedView = .flightHeight }) {
                                            Text("Flight Height")
                                                .font(.system(size: 10))
                                                .padding(2)
                                        }
                                    
                                    Divider()
                                    
                                    Button(action: { updateData() }) {
                                        Text("ReAnalyze!")
                                            .font(.system(size: 10))
                                            .padding(2)
                                    }
                                } else {
                                    Button(action: {
                                        if !mediaManager.isKeypointAvailable {
                                            updateData()
                                        } else {
                                            updateAnalysis()
                                        }
                                    }) {
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
        .onChange(of: resetToken) { _, _ in   // ← ADD THIS BLOCK
//               poseJointVM.clearAllData()
               poseJointVM = PoseJointLandscapeVM(BoxModel: BoxModel, mediaManager: mediaManager)
               selectedView = .info
               appState.isAnalysisAvailable = false
           }
    }
    
    private func updateAnalysis() {
        // Check if app processing something
        guard !self.appState.isProcessing else {
            log("App still processing...", level: .info)
            return
        }
        
        // Set App to Processing Mode
        DispatchQueue.main.async {
            appState.isProcessing = true
            appState.isAnalysisAvailable = false
            appState.processingStatus = "Processing Frame..."
        }
        
        if !appState.isAnalysisAvailable && mediaManager.isKeypointAvailable && mediaManager.isMediaAvailable {
            self.poseJointVM.buildCompleteData { success in
                // Set State when finished
                appState.isAnalysisAvailable = success
                appState.isProcessing = false
            }
        }
    }
    private func updateData() {
        inferenceCoordinator.run(
            mediaManager: mediaManager,
            appState:     appState,
            poseJointVM:  poseJointVM
        )
    }

}
