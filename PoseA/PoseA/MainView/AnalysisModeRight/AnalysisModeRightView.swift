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
    @State var MLModel: VitPoseProcessor
    
    @State var selectedView: RightViewModel = .info
    @State private var poseJointVM: PoseJointLandscapeVM
    
    init(appState: MainAppState, ROIModel: ROIViewModel, BoxModel: BoxViewModel, mediaManager: MediaManagerVM, MLModel: VitPoseProcessor) {
        self.appState = appState
        self.ROIModel = ROIModel
        self.BoxModel = BoxModel
        self.mediaManager = mediaManager
        self.MLModel = MLModel
        
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
                                    mediaManager: mediaManager)
                    .frame(height: geometry.size.height)
                    .padding(.horizontal)
                
                case .dataMetrics:
                    DataMetricsView(poseJointVM: poseJointVM)
                    .frame(height: geometry.size.height)
                    .padding(.horizontal)
                    
                case .swing:
                    SwingAnalysisView(poseJointVM: poseJointVM,
                                      mediaManager: mediaManager)
                    .frame(height: geometry.size.height)
                    .padding(.horizontal)
                
                default:
                    // Pose Analysis View
                    PoseAnalysisView(selectedView: selectedView,
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
                                    
                                    Divider()
                                    
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
        // Check if app processing something
        guard !self.appState.isProcessing else {
            log("App still processing...", level: .info)
            return
        }
        
        // Set App to Processing Mode
        appState.isProcessing = true
        appState.isAnalysisAvailable = false
        appState.processingStatus = "Processing Frame..."
        
        // Pass ROI information to the Model
        if let roiImageCoordinates = self.ROIModel.roiImageSpace {
            self.MLModel.setROI(roiImageCoordinates)
        } else {
            self.MLModel.clearROI()
        }
        
        // Pass to ML Model Inference System
        self.MLModel.processFrames(from: self.mediaManager, maxRetries: 2) { progressValue in
            // Update progress on main thread
            DispatchQueue.main.async {
                let percentage = Int(progressValue * 100)
                let statusText = self.ROIModel.isROIAvailable ? "Processing ROI frames: \(percentage)%" : "Processing frames: \(percentage)%"
                self.appState.processingStatus = statusText
            }
        } completion: { success, error in
            DispatchQueue.main.async {
                self.appState.isProcessing = false
                
                if success {
                    // Get Final Statistics
                    let processedFrames = self.MLModel.getFrameIndicesWithKeypoints().count
                    let totalFrames = self.mediaManager.mediaPlayerViewModel.totalFrames
                    
                    print("✅ Processing complete: \(processedFrames)/\(totalFrames) frames processed")
                    
                    if processedFrames < totalFrames {
                        self.appState.processingStatus = "Completed with \(processedFrames)/\(totalFrames) frames processed"
                    }
                    
                    // Update Main App State
                    self.appState.processingStatus = "Pose detection complete!"
                    self.appState.showKeypoints = true
                    self.appState.hasImportedKeypoints = true
                    
                    // TODO: - Export To JSON
//                    self.finishPoseDetection()
                    self.mediaManager.fileLoaderViewModel.loadKeypoints(from: self.MLModel.getKeypoints())
                    
                    // Process Keypoints
                    // Do Pose Analyze Processing
                    poseJointVM.buildCompleteData { success in
                        // Set State when finished
                        appState.isAnalysisAvailable = success
                        appState.isProcessing = false
                    }
                    
                } else if let processingError = error {
                    self.appState.errorMessage = "Processing failed: \(processingError.localizedDescription)"
                    print("Pose detection error: \(processingError)")
                }
            }
        }


        appState.isProcessing = false
    }
}
