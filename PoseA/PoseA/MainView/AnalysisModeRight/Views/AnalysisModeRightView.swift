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
    @State var featuresExtractionVM: FeaturesExtractionVM
    @State var eventsExtractionVM: EventsExtractionVM
    @State var gcnClassifierVM: GCNClassifierVM
    @State var postureProcessingVM: PostureProcessingVM
    
    // Display VM
    @State var chartBuilderVM: ChartBuilderVM
    @State var selectedView: RightViewModel = .info
    
    init(appState: MainAppState, ROIModel: ROIViewModel, barPointVM: BarPointVM, mediaManager: MediaManagerVM) {
        self.appState = appState
        self.ROIModel = ROIModel
        self.barPointVM = barPointVM
        self.mediaManager = mediaManager
        
        self._imageProcessingVM = State(initialValue: ImageProcessingVM(mediaManager: mediaManager))
        self._featuresExtractionVM = State(initialValue: FeaturesExtractionVM(mediaManager: mediaManager))
        self._eventsExtractionVM = State(initialValue: EventsExtractionVM(mediaManager: mediaManager))
        self._postureProcessingVM = State(initialValue: PostureProcessingVM(mediaManager: mediaManager))
        self._gcnClassifierVM = State(initialValue: GCNClassifierVM(mediaManager: mediaManager))
        self._chartBuilderVM = State(initialValue: ChartBuilderVM(mediaManager: mediaManager))
        
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
           .onAppear {
               Task {
                   await self.loadModel()
               }
           }
       }

    private func loadModel() async {
        let operationId = "loadMLModel_\(UUID().uuidString)"
        ProcessingManagerVM.shared.startOperation(id: operationId,
                                                   status: "Loading ML Model...",
                                                   isPrimary: true)

        if let errMsg = await gcnClassifierVM.load() {
            self.appState.informationMsg = InformationMessage(text: errMsg, type: .error)
        } else {
            self.appState.informationMsg = InformationMessage(text: "Successfully loaded ML Model.", type: .info)
        }

        ProcessingManagerVM.shared.completeOperation(id: operationId)
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

       case .posture:
           PostureAnalysisView(chartBuilderVM: chartBuilderVM,
                               mediaManager: mediaManager)
                .frame(maxHeight: .infinity)

       default:           
           PoseAnalysisView(appState: appState,
                            selectedView: selectedView,
                            chartBuilderVM: chartBuilderVM,
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
                   Button(action: { selectedView = .angle }) {
                       Text("Angle Analysis")
                           .font(.system(size: 8))
                           .padding(2)
                   }

                   Button(action: { selectedView = .position }) {
                       Text("Position Analysis")
                           .font(.system(size: 8))
                           .padding(2)
                   }

                   Button(action: { selectedView = .velocity }) {
                       Text("Angular Velocity Analysis")
                           .font(.system(size: 8))
                           .padding(2)
                   }

                   Button(action: { selectedView = .posture }) {
                       Text("Posture Analysis")
                           .font(.system(size: 8))
                           .padding(2)
                   }

                   Divider()

                   Button(action: { Task { await updateData() } }) {
                       Text("ReAnalyze!")
                           .font(.system(size: 8))
                           .padding(2)
                   }
               } else {
                   Button(action: {
                       if !appState.isAnalysisAvailable && barPointVM.isFirstPointAvailable && barPointVM.isSecondPointAvailable {
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
    
    @MainActor
    private func updateData() async {
        let operationId = "processMedia_\(UUID().uuidString)"

        ProcessingManagerVM.shared.startOperation(
            id: operationId,
            status: "Processing media...",
            isPrimary: true
        )

        defer {
            ProcessingManagerVM.shared.completeOperation(id: operationId)
        }

        do {
            // Stage 1: Image / Pose Processing
            if let roi = ROIModel.roiImageSpace {
                imageProcessingVM.setROI(rect: roi)
            }
            
            try await imageProcessingVM.process { progress in
                await MainActor.run {
                    ProcessingManagerVM.shared.updateOperation(
                        id: operationId,
                        status: "Processing video frames...",
                        progress: progress
                    )
                }
            }

            let processedCount = mediaManager.keypointData.count
            let totalFrames    = mediaManager.mediaPlayerVM.totalFrames
            log("Processing complete: \(processedCount)/\(totalFrames) frames", level: .debug)

            // Stage 2: Feature Extraction
            guard processedCount > 0 else {
                log("No keypoints detected — skipping feature extraction", level: .info)
                return
            }

            mediaManager.isKeypointAvailable = true

            try await featuresExtractionVM.buildFeatures()
            exportFeaturesToJSON()
            exportKeypointsToJSON()

            // Stage 3: Event Extraction
            try await eventsExtractionVM.buildEvents()
            exportEventsToJSON()

            // Stage 4: Skill Classification
            let (skillClassfication, err) = await gcnClassifierVM.classify()
            
            // Stage 5: Reference Comparison
            if let err = err {
                appState.informationMsg = InformationMessage(
                    text: "Analysis failed: \(err)",
                    type: .error
                )
            }
            if let skillClassfication = skillClassfication {
                log("skillClassification: \(skillClassfication.topLabel)", level: .debug)
                log("skillClassification confidence: \(skillClassfication.confidence)", level: .debug)
                log("skillClassification prob: \(skillClassfication.probabilities)", level: .debug)
                let ref = try await ReferencesModel.loadFromBundle(named: skillClassfication.topLabel+"Ref")
                try await postureProcessingVM.compare(reference: ref)
            }

            appState.isProcessing = false
            appState.isAnalysisAvailable = true

        } catch {
            appState.informationMsg = InformationMessage(
                text: "Analysis failed: \(error.localizedDescription)",
                type: .error
            )
            log("Pipeline error: \(error)", level: .error)
        }
    }
}


extension AnalysisModeRightView {
    
    private func exportEventsToJSON() {
        guard self.mediaManager.EventsData.rotationDir != "" else {
            self.appState.informationMsg = InformationMessage(text: "No features available to export", type: .error)
            return
        }
        
        // Create output filename
        let filename = "events.json"
        
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
                try self.eventsExtractionVM.exportEvents(to: targetURL)
                
                // Update UI on main thread
                DispatchQueue.main.async {
                    log("Successfully exported events idx to: \(targetURL.path)", level: .info)
                }
            } catch {
                // Handle export error
                DispatchQueue.main.async {
                    self.appState.informationMsg = InformationMessage(text: "Failed to export event json, see logs.", type: .error)
                    log("Error exporting events idx: \(targetURL)", level: .error)
                }
            }
        }
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
                try self.featuresExtractionVM.exportFeatures(to: targetURL)
                
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
    
    private func exportKeypointsToJSON() {
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
                }
            } catch {
                // Handle export error
                DispatchQueue.main.async {
                    self.appState.informationMsg = InformationMessage(text: "Failed to export keypoints, see logs.", type: .error)
                    log("Error exporting keypoints: \(targetURL)", level: .error)
                }
            }
        }
    }
}
