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
    @State var analysisVM: AnalysisModeVM
    @State var MLModel: YOLOPoseProcessor
    
    @State var selectedView: RightViewModel = .info
    @State private var poseJointVM: PoseJointLandscapeVM
    
    init(appState: MainAppState, ROIModel: ROIViewModel, BoxModel: BoxViewModel, mediaManager: MediaManagerVM, MLModel: YOLOPoseProcessor) {
        self.appState = appState
        self.ROIModel = ROIModel
        self.BoxModel = BoxModel
        self.mediaManager = mediaManager
        self.MLModel = MLModel
        
        // Initialize the PoseJointLandscapeVM with the provided BoxModel and mediaManager
        self._poseJointVM = State(wrappedValue: PoseJointLandscapeVM(appState: appState,
                                                                     BoxModel: BoxModel,
                                                                     mediaManager: mediaManager))
        
        self._analysisVM = State(initialValue: AnalysisModeVM(poseProcessor: MLModel,
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
                   updateAnalysis()
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
                           BoxModel: BoxModel,
                           mediaManager: mediaManager)
               .frame(maxHeight: .infinity)

       case .dataMetrics:
           DataMetricsView(appState: appState,
                           poseJointVM: poseJointVM)
               .frame(maxHeight: .infinity)

       case .swing:
           SwingAnalysisView(appState: appState,
                             poseJointVM: poseJointVM,
                             mediaManager: mediaManager)
               .frame(maxHeight: .infinity)

       default:
           PoseAnalysisView(appState: appState,
                            selectedView: selectedView,
                            poseJointVM: poseJointVM,
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
                       if !mediaManager.isKeypointAvailable {
                           Task { await updateData() }
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
    
    private func updateAnalysis() {
        // Check if app processing something
        guard !self.appState.isProcessing else {
            log("App still processing...", level: .info)
            return
        }
        
        // Change Screen
        self.selectedView = .info
        
        // Set App to Processing Mode
        DispatchQueue.main.async {
            appState.isProcessing = true
            appState.isAnalysisAvailable = false
            appState.processingStatus = "Processing Data..."
        }
        
        if !appState.isAnalysisAvailable && mediaManager.isKeypointAvailable && mediaManager.isMediaAvailable {
            self.poseJointVM.buildCompleteData { success in
                // Set State when finished
                appState.isAnalysisAvailable = success
                appState.isProcessing = false
            }
        }
    }
    
    private func updateData() async {
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
        
        // Pass ROI information to the Model
        if let roiImageCoordinates = self.ROIModel.roiImageSpace {
            self.analysisVM.setROI(rect: roiImageCoordinates)
        }
        
        // Pass to ML Model Inference System
        await self.analysisVM.process() { progressValue in
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
                    let processedFrames = self.analysisVM.processedKeypoints.count
                    let totalFrames = self.mediaManager.mediaPlayerViewModel.totalFrames
                    
                    log("Processing complete: \(processedFrames)/\(totalFrames) frames processed", level: .debug)
                    
                    if processedFrames < totalFrames {
                        self.appState.processingStatus = "Completed with \(processedFrames)/\(totalFrames) frames processed"
                    }
                    
                    // Update Main App State
                    self.appState.processingStatus = "Pose detection complete!"
                    self.appState.showKeypoints = true
                    self.appState.hasImportedKeypoints = true
                    
                    // TODO: - Export To JSON
                    self.exportKeypointsToJSON() {
                        // Load Keypoints into File Loader ViewModel
                        self.mediaManager.fileLoaderViewModel.loadKeypoints(from: self.analysisVM.processedKeypoints)
                        
                        Task {
                            while !self.mediaManager.isKeypointAvailable {
                                if self.mediaManager.fileLoaderViewModel.isKeyLoaded {
                                    self.mediaManager.isKeypointAvailable = true
                                    log("Successfully loaded Keypoints frame data.", level: .debug)
                                }
                                try? await Task.sleep(nanoseconds: 100_000_000) // 100ms polling
                            }
                        }
                        
                        // Process Keypoints
                        // Do Pose Analyze Processing
                        poseJointVM.buildCompleteData { success in
                            // Set State when finished
                            appState.isAnalysisAvailable = success
                            appState.isProcessing = false
                        }
                    }
                    
                } else if let processingError = error {
                    self.appState.errorMessage = "Processing failed: \(processingError.localizedDescription)"
                    log("Pose detection error: \(processingError)", level: .error)
                }
            }
        }
    }
    
    private func exportKeypointsToJSON(completion: @escaping () -> Void) {
        // Ensure we have keypoints to export
        guard self.analysisVM.processedKeypoints.count > 0 else {
            appState.errorMessage = "No keypoints available to export"
            return
        }
        
        // Generate a timestamp for filenames
        let dateFormatter = DateFormatter()
        dateFormatter.dateFormat = "yyyyMMdd_HHmmss"
        let timestamp = dateFormatter.string(from: Date())
        
        // Determine source filename base (without extension)
        let sourceFilenameBase: String
        if let sourceFileName = appState.sourceFileName.isEmpty ? nil : appState.sourceFileName {
            // Remove extension if present
            let components = sourceFileName.components(separatedBy: ".")
            sourceFilenameBase = components.count > 1 ? components.dropLast().joined(separator: ".") : sourceFileName
        } else {
            sourceFilenameBase = "keypoints"
        }
        
        // Create output filename
        let keypointFilename = "\(sourceFilenameBase)_keypoints_\(timestamp).json"
        
        // Determine target directory
        let fileManager = FileManager.default
        var targetURL: URL
        
        if let sourceURL = appState.sourceURL {
            // Check if source URL is a directory or file
            var isDirectory: ObjCBool = false
            if fileManager.fileExists(atPath: sourceURL.path, isDirectory: &isDirectory) {
                if isDirectory.boolValue {
                    // It's a directory, save directly in it
                    targetURL = sourceURL.appendingPathComponent(keypointFilename)
                } else {
                    // It's a file, save in the same directory
                    targetURL = sourceURL.deletingLastPathComponent().appendingPathComponent(keypointFilename)
                }
            } else {
                // Source URL doesn't exist (unusual), fallback to documents directory
                let documentsDirectory = fileManager.urls(for: .documentDirectory, in: .userDomainMask).first!
                targetURL = documentsDirectory.appendingPathComponent(keypointFilename)
            }
        } else {
            // Fallback to documents directory
            let documentsDirectory = fileManager.urls(for: .documentDirectory, in: .userDomainMask).first!
            targetURL = documentsDirectory.appendingPathComponent(keypointFilename)
        }
        
        log("Exporting keypoints to: \(targetURL.path)", level: .debug)
        
        // Show processing indicator
        appState.processingStatus = "Exporting keypoints..."
        
        // Create metadata
        var metadata: [String: Any] = [
            "exportDate": Date().timeIntervalSince1970,
            "totalFrames": mediaManager.fileLoaderViewModel.FrameCounts
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
                try self.analysisVM.exportKeypoints(
                    to: targetURL,
                    sourceInfo: metadata
                )
                
                // Update UI on main thread
                DispatchQueue.main.async {
                    self.appState.processingStatus = "Keypoints exported to \(targetURL.lastPathComponent)"
                    self.appState.originalKeypointFileURL = targetURL
                    
                    log("Successfully exported keypoints to: \(targetURL.path)", level: .info)
                    completion()
                }
            } catch {
                // Handle export error
                DispatchQueue.main.async {
                    self.appState.errorMessage = "Failed to export keypoints: \(error.localizedDescription)"
                    log("Error exporting keypoints: \(targetURL)", level: .error)
                    completion()
                }
            }
        }
    }
}
