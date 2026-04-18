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
    @State var barPointVM: BarPointVM
    @State var mediaManager: MediaManagerVM
    
    // Processing VM
    @State var imageProcessingVM: ImageProcessingVM
    @State var featuresVM: FeaturesVM
    
    @State var selectedView: RightViewModel = .info
    @State private var featureExtractionVM: FeatureExtractionVM
    
    init(appState: MainAppState, ROIModel: ROIViewModel, barPointVM: BarPointVM, mediaManager: MediaManagerVM) {
        self.appState = appState
        self.ROIModel = ROIModel
        self.barPointVM = barPointVM
        self.mediaManager = mediaManager
        
        // Initialize the PoseJointLandscapeVM with the provided BoxModel and mediaManager
        self._featureExtractionVM = State(wrappedValue: FeatureExtractionVM(appState: appState,
                                                                            barPointVM: barPointVM,
                                                                            mediaManager: mediaManager))
        
        self._imageProcessingVM = State(initialValue: ImageProcessingVM(mediaManager: mediaManager))
        self._featuresVM = State(initialValue: FeaturesVM(barPointVM: barPointVM,
                                                          mediaManager: mediaManager))
    }
    
    var body: some View {
           GeometryReader { geometry in
               currentView
                   .frame(height: geometry.size.height)
                   .padding(.horizontal)
                   .overlay(alignment: .bottomTrailing) {
                       if appState.sourceFileName != "" {
                           menuButton
                               .padding(.trailing, 16)
                               .padding(.bottom, 20)
                       }
                   }
           }
           .onChange(of: appState.angleUnit) { oldValue, newValue in
               if oldValue != newValue && appState.isAnalysisAvailable {
                   appState.isAnalysisAvailable = false
//                   updateAnalysis()
               }
           }
       }

   // MARK: - View pieces

   @ViewBuilder
   private var currentView: some View {
       switch selectedView {
       case .info:
           InformationView(appState: appState,
                           ROIModel: ROIModel,
                           barPointVM: barPointVM,
                           mediaManager: mediaManager)
               .frame(maxHeight: .infinity)

       case .dataMetrics:
           DataMetricsView(appState: appState,
                           featureExtractionVM: featureExtractionVM)
               .frame(maxHeight: .infinity)

       case .swing:
           SwingAnalysisView(appState: appState,
                             featureExtractionVM: featureExtractionVM,
                             mediaManager: mediaManager)
               .frame(maxHeight: .infinity)

       default:
           PoseAnalysisView(appState: appState,
                            selectedView: selectedView,
                            featureExtractionVM: featureExtractionVM,
                            mediaManager: mediaManager)
               .frame(maxHeight: .infinity)
       }
   }

   private var menuButton: some View {
       Menu {
           Group {
               Button(action: { selectedView = .info }) {
                   Text("Media Information")
                       .font(.system(size: 10))
                       .padding(2)
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

                   Button(action: { Task { await updateData() } }) {
                       Text("ReAnalyze!")
                           .font(.system(size: 10))
                           .padding(2)
                   }
               } else {
                   Button(action: {
                       if barPointVM.isFirstPointAvailable && barPointVM.isSecondPointAvailable {
                           Task {
                               await updateData()
                           }
                       } else {
                           self.appState.informationMsg = InformationMessage(text: "No bar points is selected!", type: .error)
                       }
                   }) {
                       Text("Start Analysis!")
                           .font(.system(size: 10))
                           .padding(2)
                   }
               }
           }
       } label: {
           Image(systemName: "waveform.path.ecg")
               .resizable()
               .scaledToFit()
               .frame(width: 26, height: 24)
               .foregroundColor(.white)
               .padding(20)
               .background(
                   Circle()
                       .fill(
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
    
    private func updateData() async {
        // Initialize Processsing Manager
        let operationId = "processMedia_\(UUID().uuidString)"
        
        // Start tracking loadMedia process
        Task { @MainActor in
            ProcessingManagerVM.shared.startOperation(
                id: operationId,
                status: "Processing media...",
                isPrimary: true
            )
        }
        
        // Set App to Processing Mode
        DispatchQueue.main.async {
            appState.isAnalysisAvailable = false
        }
        
        // Pass ROI information to the Model
        if let roiImageCoordinates = self.ROIModel.roiImageSpace {
            self.imageProcessingVM.setROI(rect: roiImageCoordinates)
        }
        
        // Pass to ML Model Inference System
        await self.imageProcessingVM.process() { progressValue in
            // Update progress on main thread
            Task { @MainActor in
                ProcessingManagerVM.shared.updateOperation(
                    id: operationId,
                    status: "Processing video frames...",
                    progress: progressValue
                )
            }
        } completion: { success, error in
            if success {
                // Get Final Statistics
                let processedFrames = self.mediaManager.keypointData.count
                let totalFrames = self.mediaManager.mediaPlayerVM.totalFrames
                
                log("Processing complete: \(processedFrames)/\(totalFrames) frames processed", level: .debug)
                
            } else if let processingError = error {
                self.appState.informationMsg = InformationMessage(text: "Processing keypoints failed, see logs.", type: .error)
                log("Pose detection error: \(processingError)", level: .error)
            }
        }
        log("Pose detection results: \(self.mediaManager.keypointData.count > 0)", level: .info)

        if self.mediaManager.keypointData.count > 0 {
            self.mediaManager.isKeypointAvailable = true
            await self.featuresVM.buildFeatures() {
                self.exportFeaturesToJSON()
            }
        }
        
        DispatchQueue.main.async {
            // Export Keypoints to JSON
            self.exportKeypointsToJSON() {
                // Do Pose Analyze Processing
                featureExtractionVM.buildCompleteData { success in
                    // Set State when finished
                    appState.isAnalysisAvailable = success
                    appState.isProcessing = false
                }
            }
        }
            
        // Complete the operation
        ProcessingManagerVM.shared.completeOperation(id: operationId)
    }
    
    private func exportFeaturesToJSON() {
        guard self.mediaManager.FeaturesData.count > 0 else {
            self.appState.informationMsg = InformationMessage(text: "No features available to export", type: .error)
            return
        }
        
        // Create output filename
        let filename = "features.json"
        
        // Determine target directory
        let fileManager = FileManager.default
        var targetURL: URL

        if let sourceURL = appState.sourceURL {
            // Check if source URL is a directory or file
            var isDirectory: ObjCBool = false
            if fileManager.fileExists(atPath: sourceURL.path, isDirectory: &isDirectory) {
                if isDirectory.boolValue {
                    // It's a directory, save directly in it
                    targetURL = sourceURL.appendingPathComponent(filename)
                } else {
                    // It's a file, save in the same directory
                    targetURL = sourceURL.deletingLastPathComponent().appendingPathComponent(filename)
                }
            } else {
                // Source URL doesn't exist (unusual), fallback to documents directory
                let documentsDirectory = fileManager.urls(for: .documentDirectory, in: .userDomainMask).first!
                targetURL = documentsDirectory.appendingPathComponent(filename)
            }
        } else {
            // Fallback to documents directory
            let documentsDirectory = fileManager.urls(for: .documentDirectory, in: .userDomainMask).first!
            targetURL = documentsDirectory.appendingPathComponent(filename)
        }
                
        // Perform export in background
        DispatchQueue.global(qos: .userInitiated).async {
            do {
                // First, make sure the parent directory exists
                let directoryURL = targetURL.deletingLastPathComponent()
                if !FileManager.default.fileExists(atPath: directoryURL.path) {
                    try FileManager.default.createDirectory(at: directoryURL, withIntermediateDirectories: true)
                }
                
                // Export all frames to JSON
                try self.featuresVM.exportFeatures(to: targetURL)
                
                // Update UI on main thread
                DispatchQueue.main.async {
                    log("Successfully exported features to: \(targetURL.path)", level: .info)
                }
            } catch {
                // Handle export error
                DispatchQueue.main.async {
                    self.appState.informationMsg = InformationMessage(text: "Failed to export features, see logs.", type: .error)
                    log("Error exporting features: \(targetURL)", level: .error)
                }
            }
        }
    }
    
    private func exportKeypointsToJSON(completion: @escaping () -> Void) {
        // Ensure we have keypoints to export
        guard self.mediaManager.keypointData.count > 0 else {
            self.appState.informationMsg = InformationMessage(text: "No keypoints available to export", type: .error)
            return
        }
        
        // Create output filename
        let keypointFilename = "keypoints.json"
        let CoMFilename = "com.json"
        
        // Determine target directory
        let fileManager = FileManager.default
        var targetURL: URL
        var targetURLCoM: URL
        
        if let sourceURL = appState.sourceURL {
            // Check if source URL is a directory or file
            var isDirectory: ObjCBool = false
            if fileManager.fileExists(atPath: sourceURL.path, isDirectory: &isDirectory) {
                if isDirectory.boolValue {
                    // It's a directory, save directly in it
                    targetURL = sourceURL.appendingPathComponent(keypointFilename)
                    targetURLCoM = sourceURL.appendingPathComponent(CoMFilename)
                } else {
                    // It's a file, save in the same directory
                    targetURL = sourceURL.deletingLastPathComponent().appendingPathComponent(keypointFilename)
                    targetURLCoM = sourceURL.deletingLastPathComponent().appendingPathComponent(CoMFilename)
                }
            } else {
                // Source URL doesn't exist (unusual), fallback to documents directory
                let documentsDirectory = fileManager.urls(for: .documentDirectory, in: .userDomainMask).first!
                targetURL = documentsDirectory.appendingPathComponent(keypointFilename)
                targetURLCoM = documentsDirectory.appendingPathComponent(CoMFilename)
            }
        } else {
            // Fallback to documents directory
            let documentsDirectory = fileManager.urls(for: .documentDirectory, in: .userDomainMask).first!
            targetURL = documentsDirectory.appendingPathComponent(keypointFilename)
            targetURLCoM = documentsDirectory.appendingPathComponent(CoMFilename)
        }
        
        log("Exporting keypoints to: \(targetURL.path)", level: .debug)
                
        // Create metadata
        var metadata: [String: Any] = [
            "exportDate": Date().timeIntervalSince1970,
            "totalFrames": mediaManager.keypointData.count
        ]
        
        // Add source information if available
        if let sourceURL = appState.sourceURL {
            metadata["sourceFile"] = sourceURL.lastPathComponent
        } else if !appState.sourceFileName.isEmpty {
            metadata["sourceFile"] = appState.sourceFileName
        }
        
        // Add athlete info if available
        if !appState.athleteName.isEmpty {
            metadata["athleteName"] = appState.athleteName
        }
        
        if !appState.actionType.isEmpty {
            metadata["actionType"] = appState.actionType
        }
        
        // Perform export in background
        DispatchQueue.global(qos: .userInitiated).async {
            do {
                // First, make sure the parent directory exists
                let directoryURL = targetURL.deletingLastPathComponent()
                if !FileManager.default.fileExists(atPath: directoryURL.path) {
                    try FileManager.default.createDirectory(at: directoryURL, withIntermediateDirectories: true)
                }
                
                // Export all frames to JSON
                try self.imageProcessingVM.exportKeypoints(to: targetURL, sourceInfo: metadata)
                try self.imageProcessingVM.exportCoM(to: targetURLCoM)
                
                // Update UI on main thread
                DispatchQueue.main.async {
                    log("Successfully exported keypoints to: \(targetURL.path)", level: .info)
                    completion()
                }
            } catch {
                // Handle export error
                DispatchQueue.main.async {
                    self.appState.informationMsg = InformationMessage(text: "Failed to export keypoints, see logs.", type: .error)
                    log("Error exporting keypoints: \(targetURL)", level: .error)
                    completion()
                }
            }
        }
    }
}
