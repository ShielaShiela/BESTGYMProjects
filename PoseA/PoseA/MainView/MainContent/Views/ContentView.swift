import SwiftUI
import AVFoundation
import Photos
import PhotosUI
import Foundation

struct BESTGYMPoseApp: View {
    // MARK: - Properties
    // Camera VM
    @StateObject private var cameraManager = CameraManagerVM()
    
    // Media Related VM
    @State private var mediaManager = MediaManagerVM()
    @State private var ROIModel = ROIViewModel()
    @State private var BoxModel = BoxViewModel()
    
    // UI/UX Related VM
    @StateObject private var appState = MainAppState()
    @State private var toolbarVM = ToolbarButtonVM()
    
    // ML Model Related VM
    @State private var MLModel = VitPoseProcessor()
    
    // MARK: - Body
    var body: some View {
        ZStack {
            // Check for Device Orientation
            DeviceOrientationVM(orientation: $appState.orientation)
            
            // Landscape Main Content
            NavigationView {
                ZStack {
                    GeometryReader { geometry in
                        HStack(spacing: 10) {
                            // Left half: MainContentLeftView with padding inside its half
                            AnalysisModeLeftView(appState: self.appState,
                                                 ROIModel: $ROIModel,
                                                 BoxModel: $BoxModel,
                                                 mediaManager: self.mediaManager)
                            .frame(width: geometry.size.width / 2 - 10) // Half of screen minus spacing
                            
                            Spacer()
                            
                            
                            // Right half: MainContentRightView with padding inside its half
                            AnalysisModeRightView(appState: self.appState,
                                                  ROIModel: self.ROIModel,
                                                  BoxModel: self.BoxModel,
                                                  mediaManager: self.mediaManager,
                                                  MLModel: self.MLModel)
                            .frame(width: geometry.size.width / 2 - 10)
                        }
                        .frame(width: geometry.size.width, height: geometry.size.height)
                        .padding(.top, 5)
                    }
                    
                    .toolbar {
                        // Left Toolbar
                        ToolbarItemGroup(placement: .topBarLeading) {
                            if !appState.isRecordMode {
                                Button {
                                    self.toggleMode()
                                } label: {
                                    HStack(spacing: 6) {
                                        Image(systemName: "record.circle")
                                        Text("Record Mode")
                                    }
                                }
                                .frame(height: 22)
                                .toolbarCapsuleStyle()
                            } else {
                                EmptyView()
                            }
                        }
                        

                        // Principal Toolbar
                        ToolbarItemGroup(placement: .topBarTrailing) {
                            Group {
                                if toolbarVM.activeMode == .roi {
                                    HStack(spacing: 6) {
                                        Button {
                                            ROIModel.clearROI()
                                        } label: {
                                            Label("ROI", systemImage: "trash").foregroundStyle(.red)
                                        }
                                        
                                        Button {
                                            ROIModel.setROIMode(false)
                                            toolbarVM.deactivateMode()
                                        } label: {
                                            Label("ROI", systemImage: "xmark").foregroundStyle(.gray)
                                        }
                                    }
                                    .toolbarCapsuleStyle()
                                } else if toolbarVM.activeMode == .box {
                                    HStack(spacing: 6) {
                                        Button {
                                            BoxModel.clearBox()
                                        } label: {
                                            Label("Box", systemImage: "trash").foregroundStyle(.red)
                                        }
                                        
                                        Button {
                                            BoxModel.setBoxMode(false)
                                            toolbarVM.deactivateMode()
                                        } label: {
                                            Label("Box", systemImage: "xmark").foregroundStyle(.gray)
                                        }
                                    }
                                    .toolbarCapsuleStyle()
                                } else if toolbarVM.activeMode == .annotate {
                                    HStack(spacing: 6) {
                                        Button {
                                            print("Return Annotate")
                                        } label: {
                                            Label("Annotate", systemImage: "trash").foregroundStyle(.red)
                                        }
                                        
                                        Button {
                                            appState.isAnnotationMode = false
                                            toolbarVM.deactivateMode()
                                        } label: {
                                            Label("Annotate", systemImage: "xmark").foregroundStyle(.gray)
                                        }
                                    }
                                    .toolbarCapsuleStyle()
                                } else if toolbarVM.activeMode == .zoom {
                                    HStack(spacing: 6) {
                                        Button {
                                            print("Return Zoom")
                                        } label: {
                                            Label("Zoom", systemImage: "trash").foregroundStyle(.red)
                                        }
                                        
                                        Button {
                                            appState.isZoomMode = false
                                            toolbarVM.deactivateMode()
                                        } label: {
                                            Label("Zoom", systemImage: "xmark").foregroundStyle(.gray)
                                        }
                                    }
                                    .frame(height: 22)
                                    .toolbarCapsuleStyle()
                                } else {
                                    EmptyView()
                                }
                            }
                        }
                        
                        // Principal Toolbar
                        ToolbarItemGroup(placement: .topBarTrailing) {
                            Group {
                                if mediaManager.isMediaAvailable {
                                    HStack(spacing: 6) {
                                        ToolbarButtonView(mode: .roi, icon: "crop", title: "ROI", viewModel: toolbarVM) {
                                            // ROI Mode activated
                                            ROIModel.setROIMode(true)
                                        }
                                        ToolbarButtonView(mode: .box, icon: "square.dashed", title: "Box", viewModel: toolbarVM) {
                                            // Box Mode activated
                                            BoxModel.setBoxMode(true)
                                        }
                                        ToolbarButtonView(mode: .annotate, icon: "figure", title: "Annotate", viewModel: toolbarVM) {
                                            // Annotate logic
                                            appState.isAnnotationMode = true
                                        }
                                        ToolbarButtonView(mode: .zoom, icon: "plus.magnifyingglass", title: "Zoom", viewModel: toolbarVM) {
                                            // Zoom logic
                                            appState.isZoomMode = true
                                        }
                                    }
                                    .toolbarCapsuleStyle()
                                } else {
                                    EmptyView()
                                }
                            }
                        }
                        

                        // Right Toolbar
                        ToolbarItemGroup(placement: .topBarTrailing) {
                            if !appState.isRecordMode {
                                HStack(spacing: 6) {
                                    Button { selectFileOrFolder() } label: {
                                        Image(systemName: "folder")
                                    }
                                    
                                    Button { selectVideoFromLibrary() } label: {
                                        Image(systemName: "photo.on.rectangle")
                                    }
                                    
                                    Menu {
                                        Button { selectFileOrFolder() } label: {
                                            Label("Open File/Folder", systemImage: "folder")
                                        }
                                        
                                        Button { selectVideoFromLibrary() } label: {
                                            Label("Video from Library", systemImage: "photo.on.rectangle")
                                        }
                                        
                                        Divider()
                                        
                                        Button { selectKeypointFile() } label: {
                                            Label("Import Keypoints (.json)", systemImage: "square.and.arrow.down")
                                        }
                                        
                                        Button { saveProject() } label: {
                                            Label("Save Projects", systemImage: "square.and.arrow.down")
                                        }
                                        
                                        Divider()
                                        
                                        // Setting Button
                                        Button { self.appState.showSettingsView = true } label: {
                                            Label("Settings", systemImage: "gear")
                                        }
                                        
                                    } label: {
                                        Label("Actions", systemImage: "ellipsis.circle")
                                    }
                                }
                                .frame(height: 22)
                                .toolbarCapsuleStyle()
                            }
                        }
                    }
                    
                    // File/Folder Picker
                    .fullScreenCover(isPresented: $appState.isFilePickerPresented) {
                        DocumentPickerUI { urls in
                            if let url = urls.first {
                                // Use loadData Function
                                appState.isProcessing = true
                                appState.processingStatus = "Loading data..."
                                
                                let errMsg = mediaManager.loadMedia(url: url)
                                
                                if let errMsg = errMsg {
                                    DispatchQueue.main.async {
                                        self.appState.errorMessage = errMsg
                                        self.appState.isProcessing = false
                                    }
                                } else {
                                    DispatchQueue.main.async {
                                        self.appState.processingStatus = "Loaded frames from \(url.lastPathComponent)"
                                        self.appState.sourceFileName = url.lastPathComponent
                                        self.appState.sourceURL = url
                                        self.appState.isProcessing = false
                                        self.appState.showKeypoints = true
                                        self.appState.isVideoSource = !mediaManager.isDataLIDAR
                                    }
                                }
                            }
                        }
                    }
                    
                    // Gallery Picker
                    .fullScreenCover(isPresented: $appState.isPhotoLibraryPresented) {
                        PhotoLibraryVideoPicker(isPresented: $appState.isPhotoLibraryPresented) { url in
                            if let url = url {
                                // Use loadData Function
                                appState.isProcessing = true
                                appState.processingStatus = "Loading data..."
                                
                                mediaManager.loadGalleryFile(url: url) { errMsg in
                                    if let errMsg = errMsg {
                                        DispatchQueue.main.async {
                                            self.appState.errorMessage = errMsg
                                            self.appState.isProcessing = false
                                        }
                                    } else {
                                        DispatchQueue.main.async {
                                            self.appState.processingStatus = "Loaded frames from \(url.lastPathComponent)"
                                            self.appState.sourceFileName = url.lastPathComponent
                                            self.appState.sourceURL = url
                                            self.appState.isProcessing = false
                                            self.appState.showKeypoints = false
                                            self.appState.isVideoSource = !mediaManager.isDataLIDAR
                                            self.appState.isTempFiles = mediaManager.isDataTemp
                                        }
                                    }
                                }
                            }
                        }
                    }
                    
                    if appState.isRecordMode {
                        RecordLandscapeView(appState: self.appState,
                                            cameraManager: self.cameraManager)
                    }
                    
                    // Loading Overlay View
                    if appState.isProcessing {
                        ProcessingOverlayView(status: appState.processingStatus)
                            .zIndex(1)
                    }
                    
                    // Error Overlay
                    if let error = appState.errorMessage {
                        ErrorOverlayView(message: error) {
                            appState.errorMessage = nil
                        }
                            .zIndex(1)
                    }
                }
                
                .fullScreenCover(isPresented: $appState.showSettingsView) {
                    SettingsView(appState: appState)
                }
                
                // Add Something Here
            }
        }
    }
    
    // MARK: - Helper Functions
    
    // Update your toggleMode method to ensure isLiveCapture is properly set
    private func toggleMode() {
        // If not currently in record mode, switch TO record mode
        if !appState.isRecordMode {
            // First start the camera on background thread
            DispatchQueue.global(qos: .userInitiated).async {
                self.cameraManager.resumeStream()
                
                // Set isLiveCapture to true (redundant but to be safe)
                DispatchQueue.main.async {
                    self.cameraManager.isLiveCapture = true
                    self.appState.isRecordMode = true
                    self.setupRecordMode()
                }
            }
        }
    }
    
    private func setupRecordMode() {
        // Reset states
        
        // Set default values for athlete info
        if appState.RecordingData.athleteName.isEmpty {
            appState.RecordingData.athleteName = "Test"
        }
        
        if appState.RecordingData.actionType.isEmpty {
            appState.RecordingData.actionType = "Test"
        }
        
        if appState.RecordingData.distanceValue == nil {
            appState.RecordingData.distanceValue = "Test"
        }
        
        // Reset LiDAR toggle to default state
        appState.useLiDAR = false
        
        // Make sure the camera is not already running before starting it
        if !cameraManager.isLiveCapture {
            // First make sure the camera session exists and is set up correctly
            print("Starting camera for record mode...")
            
            // Start camera on background thread
            DispatchQueue.global(qos: .userInitiated).async {
                self.cameraManager.resumeStream()
                
                // Print status after a brief delay to confirm
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
                    print("Camera live capture status: \(self.cameraManager.isLiveCapture)")
                }
            }
        } else {
            print("Camera is already running")
        }
    }
    
    private func resetRecordModeSettings() {
        // Reset athlete info
        appState.RecordingData.athleteName = "Test"
        appState.RecordingData.actionType = "Test"
        appState.RecordingData.distanceValue = "Test"
        
        // Reset LiDAR setting
        appState.useLiDAR = false
    }
    
    // MARK: - Picker Functions
    
    private func selectFileOrFolder() {
        // Do cleanup BEFORE switching modes
        if mediaManager.isKeypointAvailable || mediaManager.isMediaAvailable {
            log("Cleaning up before folder selection...", level: .info)
            cleanupPreviousData()
        }
        
        // Small delay to ensure cleanup completes
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
            self.appState.isFilePickerPresented = true
        }
    }

    private func selectVideoFromLibrary() {
        // Do cleanup BEFORE switching modes
        if mediaManager.isKeypointAvailable || mediaManager.isMediaAvailable {
            log("Cleaning up before folder selection...", level: .info)
            cleanupPreviousData()
        }
        
        // Small delay to ensure cleanup completes
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
            self.appState.isPhotoLibraryPresented = true
        }
    }
    
    private func selectKeypointFile() {
        if mediaManager.isKeypointAvailable || mediaManager.isMediaAvailable {
            log("Cleaning up before folder selection...", level: .info)
            cleanupPreviousData()
        }
        
        // Small delay to ensure cleanup completes
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
            self.appState.isKeypointImportPresented = true
        }
    }
    
    // Save Project
    private func saveProject() {
        if self.appState.isTempFiles {
            do {
                // Export to Apps
                appState.isProcessing = true

                let url = try mediaManager.exportFramesContentsToAppDirectory(originalFileURL: appState.sourceURL!)
                
                if mediaManager.isKeypointAvailable || mediaManager.isMediaAvailable {
                    log("Cleaning up before folder selection...", level: .info)
                    cleanupPreviousData()
                }
                
                // Load from copy source
                appState.processingStatus = "Loading data..."
                
                let errMsg = mediaManager.loadMedia(url: url)
                
                if let errMsg = errMsg {
                    DispatchQueue.main.async {
                        self.appState.errorMessage = errMsg
                        self.appState.isProcessing = false
                    }
                } else {
                    DispatchQueue.main.async {
                        self.appState.processingStatus = "Loaded frames from \(url.lastPathComponent)"
                        self.appState.sourceFileName = url.lastPathComponent
                        self.appState.sourceURL = url
                        self.appState.isProcessing = false
                        self.appState.showKeypoints = true
                        self.appState.isVideoSource = !mediaManager.isDataLIDAR
                    }
                }
            } catch {
                appState.errorMessage = "Failed to export to apps: \(error)"
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
        } else if appState.isPhotoLibraryPresented || appState.sourceFileName.contains("IMG_") || appState.sourceFileName.contains("MOV_") {
            // Likely from photo library, create dedicated folder
            let documentsDirectory = fileManager.urls(for: .documentDirectory, in: .userDomainMask).first!
            
            // Create a folder with the video name
            let folderName = sourceFilenameBase
            let folderURL = documentsDirectory.appendingPathComponent(folderName, isDirectory: true)
            
            // Create the folder if it doesn't exist
            if !fileManager.fileExists(atPath: folderURL.path) {
                do {
                    try fileManager.createDirectory(at: folderURL, withIntermediateDirectories: true)
                } catch {
                    print("Error creating directory: \(error)")
                    // Fallback to documents directory
                    targetURL = documentsDirectory.appendingPathComponent(keypointFilename)
                    
                    // Show processing indicator and continue with export
                    appState.processingStatus = "Exporting keypoints..."
                    performExport(to: targetURL)
                    return
                }
            }
            
            // Save in the new folder
            targetURL = folderURL.appendingPathComponent(keypointFilename)
        } else {
            // Fallback to documents directory
            let documentsDirectory = fileManager.urls(for: .documentDirectory, in: .userDomainMask).first!
            targetURL = documentsDirectory.appendingPathComponent(keypointFilename)
        }
        
        print("Exporting keypoints to: \(targetURL.path)")
        
        // Show processing indicator
        appState.processingStatus = "Exporting keypoints..."
        
        // Perform the actual export
        performExport(to: targetURL)
    }

    // Helper method to perform the actual export
    private func performExport(to fileURL: URL) {
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
        if !appState.RecordingData.athleteName.isEmpty {
            metadata["athleteName"] = appState.RecordingData.athleteName
        }
        
        if !appState.RecordingData.actionType.isEmpty {
            metadata["actionType"] = appState.RecordingData.actionType
        }
        
        if let distanceValue = appState.RecordingData.distanceValue {
            metadata["distance"] = distanceValue
        }
        
        // Perform export in background
        DispatchQueue.global(qos: .userInitiated).async {
            do {
                // First, make sure the parent directory exists
                let directoryURL = fileURL.deletingLastPathComponent()
                if !FileManager.default.fileExists(atPath: directoryURL.path) {
                    try FileManager.default.createDirectory(at: directoryURL, withIntermediateDirectories: true)
                }
                
                // Export all frames to JSON
                try self.MLModel.exportKeypoints(
                    to: fileURL,
                    format: "json",
                    sourceInfo: metadata
                )
                
                // Update UI on main thread
                DispatchQueue.main.async {
                    self.appState.processingStatus = "Keypoints exported to \(fileURL.lastPathComponent)"
                    self.appState.originalKeypointFileURL = fileURL
                    
                    print("✅ Successfully exported keypoints to: \(fileURL.path)")
                }
            } catch {
                // Handle export error
                DispatchQueue.main.async {
                    self.appState.errorMessage = "Failed to export keypoints: \(error.localizedDescription)"
                    print("❌ Error exporting keypoints: \(error)")
                }
            }
        }
    }
    
    private func cleanupPreviousData() {

        print("Cleaning up previous data...")
        
        // 1. Stop accessing previous folder/file
        if let previousURL = appState.sourceURL {
            SecurityScopedResourceManager.shared.stopAccessing(previousURL)
            print("Stopped accessing: \(previousURL.lastPathComponent)")
        }
        // 2. Clear camera manager data - using the enhanced method
        cameraManager.clearAllFrames()
        print("Cleared camera frames")
        
        // 3. Clear app state (this calls poseProcessor.clearAllKeypoints())
        appState.resetFileAndKeypointState()
        appState.resetStatusState()
        print("Reset app state")
        
        // Clear Media Manager
        mediaManager.clearAllData()
        
        print("Cleanup complete")
    }
}
