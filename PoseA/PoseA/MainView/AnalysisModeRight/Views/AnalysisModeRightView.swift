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
                                    mediaManager: mediaManager)
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
                    
                    log("Processing complete: \(processedFrames)/\(totalFrames) frames processed", level: .debug)
                    
                    if processedFrames < totalFrames {
                        self.appState.processingStatus = "Completed with \(processedFrames)/\(totalFrames) frames processed"
                    }
                    
                    // Update Main App State
                    self.appState.processingStatus = "Pose detection complete!"
                    self.appState.showKeypoints = true
                    self.appState.hasImportedKeypoints = true
                    
                    // TODO: - Export To JSON
                    self.exportKeypointsToJSON()
                    
                    // Load Keypoints into File Loader ViewModel
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
                    log("Pose detection error: \(processingError)", level: .error)
                }
            }
        }
    }
    
    // Replace the exportKeypointsToJSON method in BESTGYMPoseApp.swift
    private func exportKeypointsToJSON() {
        // Ensure we have keypoints to export
        guard MLModel.getTotalFrames() > 0 else {
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
        
        metadata["distance"] = 0
        
        
        // Perform export in background
        DispatchQueue.global(qos: .userInitiated).async {
            do {
                // First, make sure the parent directory exists
                let directoryURL = targetURL.deletingLastPathComponent()
                if !FileManager.default.fileExists(atPath: directoryURL.path) {
                    try FileManager.default.createDirectory(at: directoryURL, withIntermediateDirectories: true)
                }
                
                // Export all frames to JSON
                try self.MLModel.exportKeypoints(
                    to: targetURL,
                    format: "json",
                    sourceInfo: metadata
                )
                
                // Update UI on main thread
                DispatchQueue.main.async {
                    self.appState.processingStatus = "Keypoints exported to \(targetURL.lastPathComponent)"
                    self.appState.originalKeypointFileURL = targetURL
                    
                    log("Successfully exported keypoints to: \(targetURL.path)", level: .info)
                }
            } catch {
                // Handle export error
                DispatchQueue.main.async {
                    self.appState.errorMessage = "Failed to export keypoints: \(error.localizedDescription)"
                    log("Error exporting keypoints: \(targetURL)", level: .error)
                }
            }
        }
    }
}
