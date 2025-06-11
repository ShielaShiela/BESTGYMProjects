import SwiftUI
import AVFoundation
import Photos
import PhotosUI
import Foundation

struct BESTGYMPoseApp: View {
    // MARK: - Properties
    @StateObject private var cameraManager = CameraLiDARManager()
    @StateObject private var appState = AppState()
    @State private var showSettingsView = false
    
    // MARK: - Body
    var body: some View {
        NavigationView {
            ZStack {
                // Main content
                VStack(spacing: 0) {
                    // Top app header with mode selector
                    AppHeader(
                        appState: appState,
                        cameraManager: cameraManager,
                        processAction: processData,
                        exportAction: exportKeypointsToJSON  // Add this line
                    )
                    
                    // Main content container
                    MainContentView(appState: appState, cameraManager: cameraManager)
                }
                
                // Loading Overlay View
                if appState.isProcessing {
                    ProcessingOverlayView(status: appState.processingStatus)
                }
                
                // Error Overlay
                if let error = appState.errorMessage {
                    ErrorOverlayView(message: error) {
                        appState.errorMessage = nil
                    }
                }
            }
            // Options Toolbar
            .toolbar {
                ToolbarItemGroup(placement: .navigationBarTrailing) {
                    Button {
                        showSettingsView = true
                    } label: {
                        Image(systemName: "gear")
                    }
                    Menu {
                        // Mode Toggle Section
                        Button { toggleMode() } label: {
                            Label(appState.isRecordMode ? "Switch to Analysis Mode" : "Switch to Record Mode",
                                  systemImage: appState.isRecordMode ? "waveform.path.ecg" : "record.circle")
                        }
                        
                        Divider() // Separator
                        
                        // Context-sensitive actions based on current mode
                        if !appState.isRecordMode {
                            // Analysis Mode actions
                            Button { selectFileOrFolder() } label: {
                                Label("Open File/Folder", systemImage: "folder")
                            }
                            Button { selectVideoFile() } label: {
                                Label("Open Video File", systemImage: "film")
                            }
                            Button { selectVideoFromLibrary() } label: {
                                Label("Video from Library", systemImage: "photo.on.rectangle")
                            }
                            
                            Divider()
                            
                            Button { selectKeypointFile() } label: {
                                Label("Import Keypoints (.json)", systemImage: "square.and.arrow.down")
                            }
                        } else {
                            // Record Mode actions
                            Button {
                                // Toggle LiDAR setting
                                appState.useLiDAR.toggle()
                            } label: {
                                Label(appState.useLiDAR ? "Disable LiDAR" : "Enable LiDAR",
                                      systemImage: appState.useLiDAR ? "cube.fill" : "cube") // Using cube symbol instead of lidar.horizontal
                            }
                            
                            Divider()
                            
                            Button {
                                resetRecordModeSettings()
                            } label: {
                                Label("Reset Capture Settings", systemImage: "arrow.counterclockwise")
                            }
                        }
                        
                        Button {
                            showSettingsView = true
                        } label: {
                            Label("Settings", systemImage: "gear")
                        }
                    } label: {
                        Label("Actions", systemImage: "ellipsis.circle")
                    }
                }
            }
            // Set Background
            .background(Color(.systemBackground))
            
            // Setting View
            .sheet(isPresented: $showSettingsView) {
                SettingsView(appState: appState)
            }
            
            // File/Folder Picker
            .sheet(isPresented: $appState.isFilePickerPresented) {
                DocumentPickerUI { urls in
                    if let url = urls.first {
                        // Use loadData Function
                        loadData(from: url)
                    }
                }
            }
            
            // Video Picker
            .sheet(isPresented: $appState.isVideoPickerPresented) {
                VideoFilePickerUI { url in
                    // Use loadVideo Function
                    loadVideo(from: url)
                }
            }
            
            // Gallery Picker
            .sheet(isPresented: $appState.isPhotoLibraryPresented) {
                PhotoLibraryVideoPicker(isPresented: $appState.isPhotoLibraryPresented) { url in
                    if let url = url {
                        // Use loadVideo Function
                        loadVideo(from: url)
                    }
                }
            }
            
            // Keypoint Picker
            .sheet(isPresented: $appState.isKeypointImportPresented) {
                KeypointFilePickerUI { url in
                    // Use loadKeypointFile
                    loadKeypointFile(url)
                }
            }
            
            // Analysis View
            .sheet(isPresented: $appState.showAnalysisView) {
                PoseAnalysisView(
                    poseProcessor: appState.poseProcessor,
                    currentFrameIndex: cameraManager.currentFrameIndex,
                    cameraManager: cameraManager,
                    showAnalysisView: $appState.showAnalysisView
                )
                .edgesIgnoringSafeArea(.all)
            }
            
            // First Launch Setup
            .onAppear {
                setupInitialState()
                
                NotificationCenter.default.addObserver(
                        forName: NSNotification.Name("FrameChanged"),
                        object: nil,
                        queue: .main
                    ) { notification in
                        if let frameIndex = notification.userInfo?["frameIndex"] as? Int {
                            log("Received frame change notification for frame \(frameIndex). Updating display...", level: .debug)
                            self.updateDisplayWithKeypoints(for: frameIndex)
                        }
                    }
                
                // Listen for recording completion
                NotificationCenter.default.addObserver(
                    forName: Notification.Name("RecordingFinished"),
                    object: nil,
                    queue: .main
                ) { notification in
                    if let url = notification.object as? URL {
                        // Don't automatically load video after recording, just show confirmation
                        log("Recording completed at: \(url.path)", level: .info)
                        
                        // For LiDAR recordings you can enable this if desired:
                        // if appState.useLiDAR {
                        //     self.loadVideo(from: url)
                        // }
                    }
                }
            }
            .onReceive(NotificationCenter.default.publisher(for: UIApplication.willResignActiveNotification)) { _ in
               log("App will resign active - keeping folder access alive", level: .info)
               // Don't clean up resources when app goes to background
               // This allows continued access when returning to the app
           }
           .onReceive(NotificationCenter.default.publisher(for: UIApplication.didBecomeActiveNotification)) { _ in
               log("App did become active", level: .info)
               // Resources should still be accessible
           }
           .onReceive(NotificationCenter.default.publisher(for: UIApplication.willTerminateNotification)) { _ in
               log("App will terminate - cleaning up all resources", level: .info)
               SecurityScopedResourceManager.shared.stopAccessingAll()
           }
            
        }
    }
    
    // MARK: - Helper Functions
    private func setupInitialState() {
        // Request necessary permissions on a background thread
        DispatchQueue.global(qos: .userInitiated).async {
            PHPhotoLibrary.requestAuthorization(for: .readWrite) { _ in }
        }
        
        // Load user preferences
        appState.loadUserPreferences()
        
        // Setup playback handler if not in annotation mode
        if !appState.isAnnotationMode {
            setupPlaybackHandler()
        }
        
        // Auto-load default data if configured (on a slight delay)
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
            if UserDefaults.standard.bool(forKey: "AutoLoadEnabled") {
                autoLoadDefaultData()
            }
        }
    }

    // MARK: - Enhanced checkForAssociatedKeypointFile function
    private func checkForAssociatedKeypointFile(videoURL: URL) {
        // Don't search if we already have keypoints
        if appState.hasImportedKeypoints || appState.showKeypoints {
            print("📁 Keypoints already loaded, skipping automatic detection")
            return
        }

        let fileManager = FileManager.default
        let videoDirectory = videoURL.deletingLastPathComponent()
        let videoNameWithoutExtension = videoURL.deletingPathExtension().lastPathComponent
        
        print("🔍 Checking for associated keypoint files for '\(videoNameWithoutExtension)' in: \(videoDirectory.path)")
        
        do {
            let directoryContents = try fileManager.contentsOfDirectory(
                at: videoDirectory,
                includingPropertiesForKeys: [.isRegularFileKey],
                options: [.skipsHiddenFiles]
            )
            
            // Priority 1: Look for exact match with video name + keypoints
            let exactMatchFiles = directoryContents.filter { url in
                let filename = url.lastPathComponent.lowercased()
                return url.pathExtension.lowercased() == "json" &&
                       (filename.contains("\(videoNameWithoutExtension.lowercased())_keypoint") ||
                        filename.contains("keypoint") && filename.contains(videoNameWithoutExtension.lowercased()))
            }
            
            // Priority 2: Look for any keypoint files with similar naming patterns
            let keypointFiles = directoryContents.filter { url in
                let filename = url.lastPathComponent.lowercased()
                return url.pathExtension.lowercased() == "json" &&
                       (filename.contains("keypoint") || filename.contains("pose") || filename.contains("joint"))
            }
            
            // Priority 3: Look for timestamped keypoint files (most recent)
            let timestampedKeypointFiles = keypointFiles.filter { url in
                let filename = url.lastPathComponent.lowercased()
                return filename.contains("_") &&
                       (filename.contains("202") || filename.contains("keypoint")) // Contains year or explicit keypoint
            }.sorted { url1, url2 in
                // Sort by modification date (most recent first)
                let date1 = (try? url1.resourceValues(forKeys: [.contentModificationDateKey]))?.contentModificationDate ?? Date.distantPast
                let date2 = (try? url2.resourceValues(forKeys: [.contentModificationDateKey]))?.contentModificationDate ?? Date.distantPast
                return date1 > date2
            }
            
            // Choose the best keypoint file
            let selectedKeypointFile: URL?
            
            if !exactMatchFiles.isEmpty {
                selectedKeypointFile = exactMatchFiles.first
                print("✅ Found exact match keypoint file: \(exactMatchFiles.first!.lastPathComponent)")
            } else if !timestampedKeypointFiles.isEmpty {
                selectedKeypointFile = timestampedKeypointFiles.first
                print("📅 Found timestamped keypoint file: \(timestampedKeypointFiles.first!.lastPathComponent)")
            } else if !keypointFiles.isEmpty {
                selectedKeypointFile = keypointFiles.first
                print("📄 Found generic keypoint file: \(keypointFiles.first!.lastPathComponent)")
            } else {
                selectedKeypointFile = nil
                print("❌ No keypoint files found in directory")
            }
            
            if let keypointURL = selectedKeypointFile {
                print("🎯 Loading keypoint file: \(keypointURL.lastPathComponent)")
                
                // Show loading message
                appState.processingStatus = "Found keypoint file: \(keypointURL.lastPathComponent)"
                
                // Load keypoints after a small delay
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
                    self.loadKeypointFile(keypointURL)
                }
            } else {
                // No keypoint files found - check if auto-detect is enabled
                print("🔍 No keypoint files found")
                
                if appState.autoDetectKeypoints {
                    appState.processingStatus = "No keypoints found. Auto-detecting poses..."
                    print("🤖 Auto-detecting keypoints...")
                    
                    DispatchQueue.main.asyncAfter(deadline: .now() + 1.0) {
                        self.processData()
                    }
                } else {
                    appState.processingStatus = "Video loaded. Select 'Detect Pose' to analyze or import keypoint file."
                    print("💡 Tip: Enable auto-detect in settings or manually select 'Detect Pose'")
                }
            }
        } catch {
            print("❌ Error searching for keypoint files: \(error)")
            appState.processingStatus = "Video loaded. Select 'Detect Pose' to analyze."
        }
    }

    // MARK: - Helper function to validate keypoint file before loading
    private func validateKeypointFile(_ url: URL) -> Bool {
        do {
            let data = try Data(contentsOf: url)
            let json = try JSONSerialization.jsonObject(with: data, options: [])
            
            // Basic validation - check if it looks like a keypoint file
            if let dict = json as? [String: Any] {
                // Check for common keypoint file structures
                return dict.keys.contains { key in
                    key.lowercased().contains("keypoint") ||
                    key.lowercased().contains("frame") ||
                    key.lowercased().contains("pose")
                }
            } else if let array = json as? [[String: Any]] {
                // Array of frames format
                return !array.isEmpty && array.first?.keys.contains { key in
                    key.lowercased().contains("keypoint") ||
                    key.lowercased().contains("x") ||
                    key.lowercased().contains("joint")
                } == true
            }
            
            return false
        } catch {
            print("❌ Error validating keypoint file: \(error)")
            return false
        }
    }
    
    private func autoLoadDefaultData() {
        // Implementation for auto-loading default data
        // This would depend on your specific requirements
    }

    
    // MARK: - Updated processData() function with optimized processing
    private func processData() {
        DispatchQueue.main.async {
            guard self.cameraManager.totalFrames > 0 else {
                print("Error: No frames available for processing")
                self.appState.errorMessage = "No frames available for processing"
                return
            }
            
            guard !self.appState.isProcessing else {
                print("Already processing frames")
                return
            }
            
            self.appState.isProcessing = true
            
            // Update status based on ROI
            if self.appState.hasROI {
                self.appState.processingStatus = "Preparing ROI-based pose detection for all frames..."
            } else {
                self.appState.processingStatus = "Preparing pose detection for all frames..."
            }
            
            print("Beginning optimized pose detection on \(self.cameraManager.totalFrames) frames")
            if self.appState.hasROI {
                print("Using ROI: \(self.appState.roiImageCoordinates!)")
            }
            
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
                let statusText = self.appState.hasROI ?
                    "Detecting poses in ROI across \(self.cameraManager.totalFrames) frames..." :
                    "Detecting poses across \(self.cameraManager.totalFrames) frames..."
                
                self.appState.processingStatus = statusText
                
                // Pass ROI information to the pose processor
                if let roiImageCoordinates = self.appState.roiImageCoordinates {
                    self.appState.poseProcessor.setROI(roiImageCoordinates)
                } else {
                    self.appState.poseProcessor.clearROI()
                }
                
                // Use optimized processing with retry mechanism
                self.appState.poseProcessor.processFramesWithRetry(
                    from: self.cameraManager,
                    maxRetries: 2
                ) { progressValue in
                    // Update progress on main thread
                    DispatchQueue.main.async {
                        let percentage = Int(progressValue * 100)
                        let statusText = self.appState.hasROI ?
                            "Processing ROI frames: \(percentage)%" :
                            "Processing frames: \(percentage)%"
                        self.appState.processingStatus = statusText
                    }
                } completion: { success, error in
                    DispatchQueue.main.async {
                        self.appState.isProcessing = false
                        
                        if success {
                            // Get final statistics
                            let processedFrames = self.appState.poseProcessor.getFrameIndicesWithKeypoints().count
                            let totalFrames = self.cameraManager.totalFrames
                            
                            print("✅ Processing complete: \(processedFrames)/\(totalFrames) frames processed")
                            
                            if processedFrames < totalFrames {
                                self.appState.processingStatus = "Completed with \(processedFrames)/\(totalFrames) frames processed"
                            }
                            
                            self.finishPoseDetection()
                        } else if let processingError = error {
                            self.appState.errorMessage = "Processing failed: \(processingError.localizedDescription)"
                            print("Pose detection error: \(processingError)")
                        }
                    }
                }
            }
        }
    }

    
    // MARK: - Mode Switching
    
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
        } else {
            // Switching FROM Record Mode TO Analysis Mode
            appState.isRecordMode = false
            
            // First stop any recording
            if cameraManager.isRecording {
                if appState.useLiDAR {
                    cameraManager.stopVideoRecording { _ in }
                } else {
                    cameraManager.stopRecording { _ in }
                }
            }
            
            // Important: Make sure live capture is disabled
            DispatchQueue.global(qos: .userInitiated).async {
                self.cameraManager.pauseStream()
                
                // Make extra sure isLiveCapture is set to false
                DispatchQueue.main.async {
                    self.cameraManager.isLiveCapture = false
                    print("📢 Live capture mode disabled during mode switch")
                }
            }
            
            setupAnalysisMode()
        }
    }
    
    private func setupRecordMode() {
        cameraManager.debugCameraSetup()
        // Reset states
        appState.resetFileAndKeypointState()
        appState.resetStatusState()
        
        
        // Set default values for athlete info
        if appState.athleteName.isEmpty {
            appState.athleteName = "Test"
        }
        
        if appState.actionType.isEmpty {
            appState.actionType = "Test"
        }
        
        if appState.distanceValue == nil {
            appState.distanceValue = "Test"
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
    
    // Corrected setupAnalysisMode function for BESTGYMPoseApp
    private func setupAnalysisMode() {
        // Stop recording if it's active
        if cameraManager.isRecording {
            if appState.useLiDAR {
                cameraManager.stopVideoRecording { _ in
                    // Recording stopped callback
                    print("LiDAR recording stopped during mode switch")
                }
            } else {
                // Fix for the error - make sure we're calling the method correctly
                cameraManager.stopRecording { _ in
                    // Recording stopped callback
                    print("Standard recording stopped during mode switch")
                }
            }
        }
        
        // Reset analysis-specific states if needed
        appState.showKeypoints = false
        
        // Stop camera stream
        DispatchQueue.global(qos: .userInitiated).async {
            self.cameraManager.pauseStream()
        }
    }
    
    private func resetRecordModeSettings() {
        // Reset athlete info
        appState.athleteName = "Test"
        appState.actionType = "Test"
        appState.distanceValue = "Test"
        
        // Reset LiDAR setting
        appState.useLiDAR = false
    }
    
    // MARK: - Picker Functions
    
    private func selectFileOrFolder() {
        // Do cleanup BEFORE switching modes
        if appState.hasImportedKeypoints || appState.poseProcessor.getTotalFrames() > 0 {
            print("🧹 Cleaning up before folder selection...")
            cleanupPreviousData()
        }
        // Then switch to analysis mode if needed
        if appState.isRecordMode {
            appState.isRecordMode = false
            cameraManager.pauseStream()
        }
        
        // Small delay to ensure cleanup completes
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
            self.appState.isFilePickerPresented = true
        }
    }

    private func selectVideoFile() {
        // Do cleanup BEFORE switching modes
        if appState.hasImportedKeypoints || appState.poseProcessor.getTotalFrames() > 0 {
                print("🧹 Cleaning up before folder selection...")
                cleanupPreviousData()
            }
        // Then switch to analysis mode if needed
        if appState.isRecordMode {
            appState.isRecordMode = false
            cameraManager.pauseStream()
        }
        
        // Small delay to ensure cleanup completes
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
            self.appState.isVideoPickerPresented = true
        }
    }

    private func selectVideoFromLibrary() {
        // Do cleanup BEFORE switching modes
        if appState.hasImportedKeypoints || appState.poseProcessor.getTotalFrames() > 0 {
                print("🧹 Cleaning up before folder selection...")
                cleanupPreviousData()
            }
        // Then switch to analysis mode if needed
        if appState.isRecordMode {
            appState.isRecordMode = false
            cameraManager.pauseStream()
        }
        
        // Small delay to ensure cleanup completes
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
            self.appState.isPhotoLibraryPresented = true
        }
    }
    
        private func selectKeypointFile() {
            if appState.hasImportedKeypoints || appState.poseProcessor.getTotalFrames() > 0 {
                    print("🧹 Cleaning up before folder selection...")
                    cleanupPreviousData()
                }
                        
            // Then switch to analysis mode if needed
            if appState.isRecordMode {
                appState.isRecordMode = false
                cameraManager.pauseStream()
            }
            
            // Small delay to ensure cleanup completes
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
                self.appState.isKeypointImportPresented = true
            }
//            switchToAnalysisMode()
       
        }
    
    // Replace the exportKeypointsToJSON method in BESTGYMPoseApp.swift
    private func exportKeypointsToJSON() {
        // Ensure we have keypoints to export
        guard appState.poseProcessor.getTotalFrames() > 0 else {
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
            "totalFrames": cameraManager.totalFrames
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
        
        if let distanceValue = appState.distanceValue {
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
                try self.appState.poseProcessor.exportKeypoints(
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
    private func setupUserPreferences() {
        // Load user preferences
        appState.loadUserPreferences()
    }
    
    private func updateDisplayWithKeypoints(for frameIndex: Int) {
        // Ensure we're on the main thread
        DispatchQueue.main.async {
            log("🔍 Updating display with keypoints for frame \(frameIndex)...", level: .debug)
            
            // Bounds check
            guard frameIndex >= 0 && frameIndex < self.cameraManager.totalFrames else {
                log("Frame index \(frameIndex) out of bounds", level: .error)
                return
            }
            
            // Update current frame
            self.cameraManager.currentFrameIndex = frameIndex
            
            // Get the frame image
            if let frameImage = self.cameraManager.getFrame(at: frameIndex) {
                self.cameraManager.currentFrameImage = frameImage
                
                // Check if we have keypoints for this frame
                if let keypoints = self.appState.poseProcessor.getKeypoints(for: frameIndex), !keypoints.isEmpty {
                    // Enable keypoint display
                    self.appState.showKeypoints = true
                    self.appState.hasImportedKeypoints = true
                    
                    log("Found \(keypoints.count) keypoints for frame \(frameIndex)", level: .debug)
                } else {
                    log("No keypoints found for frame \(frameIndex)", level: .debug)
                    self.appState.showKeypoints = false
                }
            } else {
                log("No image found for frame \(frameIndex)", level: .error)
            }
        }
    }

    // MARK: - Simplified finishPoseDetection method
    private func finishPoseDetection() {
        print("🎉 Pose detection complete")
        
        // Update state
        self.appState.isProcessing = false
        self.appState.processingStatus = "Pose detection complete!"
        
        // Enable keypoint display
        self.appState.showKeypoints = true
        self.appState.hasImportedKeypoints = true
        
        // Reset to first frame and display keypoints
        self.cameraManager.currentFrameIndex = 0
        
        // Get first frame image
        if let firstFrameImage = self.cameraManager.getFrame(at: 0) {
            self.cameraManager.currentFrameImage = firstFrameImage
            
            // Check if we have keypoints
            if let keypoints = self.appState.poseProcessor.getKeypoints(for: 0), !keypoints.isEmpty {
                print("✅ Ready to display \(keypoints.count) keypoints on first frame")
                self.appState.processingStatus = "Ready - \(keypoints.count) keypoints detected"
            } else {
                print("⚠️ No keypoints detected for first frame")
                self.appState.processingStatus = "No keypoints detected"
            }
        }
        
        // Auto-export keypoints
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
            self.exportKeypointsToJSON()
        }
    }

    private func setupPlaybackHandler() {
        cameraManager.onFrameChange = { index in
            DispatchQueue.main.async {
                // Update UI based on current frame
                if self.appState.showKeypoints {
                    // Get the frame image and update it
                    if let frameImage = self.cameraManager.getFrame(at: index) {
                        self.cameraManager.currentFrameImage = frameImage
                        print("🔄 Frame changed to \(index), image updated")
                    }
                    
                    // Check if we have keypoints for this frame
                    if let keypoints = self.appState.poseProcessor.getKeypoints(for: index), !keypoints.isEmpty {
                        print("✅ Keypoints available for frame \(index): \(keypoints.count)")
                    } else {
                        print("⚠️ No keypoints for frame \(index)")
                    }
                }
            }
        }
    }
    // MARK: - Improved PlaybackControlView frame navigation
    private func notifyFrameChanged(_ frameIndex: Int) {
        print("📱 Frame changed to: \(frameIndex)")
        
        // Update the display directly instead of using notifications
        DispatchQueue.main.async {
            self.updateDisplayWithKeypoints(for: frameIndex)
        }
    }
    
    private func loadData(from url: URL) {
        appState.isProcessing = true
        appState.processingStatus = "Loading data..."
        
        let fileManager = FileManager.default
        var isDirectory: ObjCBool = false
        
        // Start accessing the selected resource
        guard SecurityScopedResourceManager.shared.startAccessing(url) else {
            DispatchQueue.main.async {
                self.appState.isProcessing = false
                self.appState.errorMessage = "Permission denied: Cannot access selected file or folder"
            }
            return
        }
        
        guard fileManager.fileExists(atPath: url.path, isDirectory: &isDirectory) else {
            DispatchQueue.main.async {
                self.appState.isProcessing = false
                self.appState.errorMessage = "Selected file or folder doesn't exist"
            }
            return
        }
        
        if isDirectory.boolValue {
            // It's a folder - load directly (keep access alive)
            loadDataFromFolder(url)
        } else {
            // It's a file - check extension and process
            let fileExtension = url.pathExtension.lowercased()
            
            switch fileExtension {
            case "json":
                loadKeypointFile(url)
            case "mp4", "mov", "m4v":
                loadVideo(from: url)
            default:
                DispatchQueue.main.async {
                    self.appState.isProcessing = false
                    self.appState.errorMessage = "Unsupported file format: \(fileExtension)"
                }
            }
        }
    }
    
    private func cleanupPreviousData() {
        // DEBUGGER
        let _debugPrefix = "BESTGYMPoseApp - cleanupPreviousData:"
        // DEBUGGER
        
        print("\(_debugPrefix) Cleaning up previous data...")
        
        // 1. Stop accessing previous folder/file
        if let previousURL = appState.sourceURL {
            SecurityScopedResourceManager.shared.stopAccessing(previousURL)
            print("\(_debugPrefix) Stopped accessing: \(previousURL.lastPathComponent)")
        }
        // 2. Clear camera manager data - using the enhanced method
        cameraManager.clearAllFrames()
        print("\(_debugPrefix) Cleared camera frames")
        
        // 3. Clear app state (this calls poseProcessor.clearAllKeypoints())
        appState.resetFileAndKeypointState()
        appState.resetStatusState()
        print("\(_debugPrefix) Reset app state")
        
        // 4. Force UI update
        DispatchQueue.main.async {
            // Ensure UI reflects the cleared state
            self.cameraManager.currentFrameImage = nil
            
            // Debug print to verify cleanup
            self.cameraManager.debugPrintState()
            self.appState.poseProcessor.debugPrintState()
        }
        
        print("\(_debugPrefix) Cleanup complete ✅")
    }

    // Enhanced loadVideo method
    private func loadVideo(from url: URL) {
        // DEBUGGER
        let _debugPrefix = "BESTGYMPoseApp - loadVideo:"
        // DEBUGGER
        
        appState.isProcessing = true
        appState.processingStatus = "Loading video..."
        appState.isVideoSource = true
        
        // Reset keypoint-related states
        appState.hasImportedKeypoints = false
        appState.showKeypoints = false
        
        print("\(_debugPrefix) Loading video from: \(url.path)")
        
        // Check if this is a recording folder rather than a direct video file
        var isFolder = false
        do {
            let resourceValues = try url.resourceValues(forKeys: [.isDirectoryKey])
            isFolder = resourceValues.isDirectory ?? false
        } catch {
            print("\(_debugPrefix) Error checking if URL is directory: \(error)")
        }
        
        if isFolder {
            print("\(_debugPrefix) Loading as a recording folder")
            loadDataFromFolder(url)
        } else {
            // Load as a direct video file
            cameraManager.loadVideoFile(url) { success, totalFrames, error in
                DispatchQueue.main.async {
                    self.appState.isProcessing = false
                    
                    if success {
                        self.appState.processingStatus = "\(_debugPrefix) Video loaded with \(totalFrames) frames"
                        self.appState.sourceFileName = url.lastPathComponent
                        self.appState.sourceURL = url
                        
                        // Check for associated keypoint files
                        DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
                            self.checkForAssociatedKeypointFile(videoURL: url)
                        }
                    } else if let error = error {
                        self.appState.errorMessage = "\(_debugPrefix) ERROR: Failed to load video: \(error)"
                    }
                }
            }
        }
    }

    // Enhanced loadKeypointFile method
    private func loadKeypointFile(_ url: URL) {
        // DEBUGGER
        let _debugPrefix = "BESTGYMPoseApp - loadKeypointFile:"
        // DEBUGGER
        
        appState.isProcessing = true
        appState.processingStatus = "\(_debugPrefix) Loading keypoints..."
        
        // Ensure we have access to this file (might be a child of an already-accessed folder)
        if !SecurityScopedResourceManager.shared.isAccessing(url) {
            _ = SecurityScopedResourceManager.shared.startAccessing(url)
        }
        
        // Load keypoints into pose processor
        appState.poseProcessor.loadKeypoints(from: url) { success, frameCount, error in
            DispatchQueue.main.async {
                self.appState.isProcessing = false
                
                if success {
                    // Set flags to indicate we have keypoints
                    self.appState.hasImportedKeypoints = true
                    self.appState.showKeypoints = true
                    self.appState.processingStatus = "\(_debugPrefix) Loaded keypoints for \(frameCount) frames"
                    self.appState.originalKeypointFileURL = url
                    
                    // Only update sourceFileName if we don't have a video source
                    if self.appState.sourceFileName.isEmpty {
                        self.appState.sourceFileName = url.lastPathComponent
                    }
                    
                    // Validate the loaded keypoints
                    if !self.appState.poseProcessor.validateLoadedKeypoints() {
                        self.appState.processingStatus = "\(_debugPrefix) WARN: Keypoint data may be invalid"
                    }
                    
                    // Update UI to show first frame with keypoints
                    if frameCount > 0 {
                        self.cameraManager.currentFrameIndex = 0
                        DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
                            self.updateDisplayWithKeypoints(for: 0)
                        }
                    }
                } else if let error = error {
                    self.appState.errorMessage = "\(_debugPrefix) ERROR: Failed to load keypoints: \(error)"
                }
            }
        }
    }

    // CORRECTED: Enhanced loadDataFromFolder method that handles nested folder access properly
    private func loadDataFromFolder(_ url: URL) {
        appState.isVideoSource = false
        appState.processingStatus = "Loading data from folder..."
        
        DispatchQueue.global(qos: .userInitiated).async {
            do {
                // Start accessing the main folder - keep it alive for all operations
                guard SecurityScopedResourceManager.shared.startAccessing(url) else {
                    throw FileAccessError.accessDenied
                }
                
                // Store reference to keep folder access alive
                let folderURL = url
                
                let fileManager = FileManager.default
                
                // Get all items in the folder (no need to access each individually)
                let contents = try fileManager.contentsOfDirectory(
                    at: folderURL,
                    includingPropertiesForKeys: [.isDirectoryKey, .contentAccessDateKey],
                    options: [.skipsHiddenFiles]
                )
                
                log("Found \(contents.count) items in folder \(folderURL.lastPathComponent)", level: .debug)
                
                // NO NEED to start accessing each file - they inherit from parent folder access
                
                // Analyze folder contents
                let videoFiles = contents.filter {
                    ["mp4", "mov", "m4v"].contains($0.pathExtension.lowercased())
                }
                
                let keypointFiles = contents.filter {
                    let filename = $0.lastPathComponent.lowercased()
                    return $0.pathExtension.lowercased() == "json" &&
                           (filename.contains("keypoint") || filename.contains("pose"))
                }
                
                // Check for frame directories (LiDAR recording)
                let frameDirectories = contents.filter {
                    var isDir: ObjCBool = false
                    return fileManager.fileExists(atPath: $0.path, isDirectory: &isDir) &&
                           isDir.boolValue &&
                           $0.lastPathComponent.hasPrefix("frame_")
                }
                
                // Check for direct depth data files
                let hasDepthData = contents.contains { $0.lastPathComponent == "depthData.dat" }
                
                // Process based on folder content
                if !videoFiles.isEmpty {
                    // Found video file(s) - load video and check for keypoints
                    let videoURL = videoFiles.first!
                    log("Loading video from folder: \(videoURL.path)", level: .debug)

                    DispatchQueue.main.async {
                        self.appState.sourceFileName = videoURL.lastPathComponent
                        self.appState.sourceURL = folderURL // Keep folder as source URL
                        
                        // Load video (folder access is still active)
                        self.cameraManager.loadVideoFile(videoURL) { success, totalFrames, error in
                            DispatchQueue.main.async {
                                if success {
                                    self.appState.processingStatus = "Video loaded with \(totalFrames) frames"
                                    self.appState.isVideoSource = true
                                    self.appState.isProcessing = false
                                    
                                    // Check for keypoints in the same folder
                                    if !keypointFiles.isEmpty {
                                        let keypointURL = keypointFiles.first!
                                        log("Found keypoint file in folder: \(keypointURL.lastPathComponent)", level: .debug)
                                        
                                        DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
                                            self.appState.processingStatus = "Loading keypoints from folder..."
                                            self.loadKeypointFile(keypointURL)
                                        }
                                    } else if self.appState.autoDetectKeypoints {
                                        DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
                                            self.appState.processingStatus = "Auto-detecting poses..."
                                            self.processData()
                                        }
                                    } else {
                                        self.appState.processingStatus = "Video loaded. Select 'Detect Pose' to analyze."
                                    }
                                } else if let error = error {
                                    self.appState.errorMessage = "ERROR: Failed to load video: \(error)"
                                    self.appState.isProcessing = false
                                }
                            }
                        }
                    }
                } else if !frameDirectories.isEmpty {
                    // LiDAR recording with frame folders
                    log("Loading as LiDAR frame folder with \(frameDirectories.count) frames", level: .debug)

                    self.cameraManager.loadVideoFolder(from: folderURL)
                    
                    DispatchQueue.main.async {
                        self.appState.processingStatus = "Loaded \(self.cameraManager.totalFrames) frames from \(folderURL.lastPathComponent)"
                        self.appState.sourceFileName = folderURL.lastPathComponent
                        self.appState.sourceURL = folderURL
                        self.appState.isProcessing = false
                        
                        // Check for keypoints in LiDAR folder
                        if !keypointFiles.isEmpty {
                            let keypointURL = keypointFiles.first!
                            log("Found keypoint file in LiDAR folder: \(keypointURL.lastPathComponent)", level: .debug)

                            DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
                                self.loadKeypointFile(keypointURL)
                            }
                        }
                    }
                } else if hasDepthData {
                    // Direct LiDAR data files
                    log("Loading as LiDAR depth data...", level: .debug)
                    
                    if let device = MTLCreateSystemDefaultDevice() {
                        self.cameraManager.loadCapturedData(from: folderURL, device: device)
                        
                        DispatchQueue.main.async {
                            self.appState.processingStatus = "Loaded depth data from \(folderURL.lastPathComponent)"
                            self.appState.sourceFileName = folderURL.lastPathComponent
                            self.appState.sourceURL = folderURL
                            self.appState.isProcessing = false
                        }
                    } else {
                        DispatchQueue.main.async {
                            self.appState.errorMessage = "Metal is not available on this device"
                            self.appState.isProcessing = false
                        }
                    }
                } else {
                    // Unknown folder structure
                    DispatchQueue.main.async {
                        self.appState.errorMessage = "Could not identify folder content type"
                        self.appState.isProcessing = false
                        log("Folder does not contain recognized data: \(folderURL.path)", level: .error)
                    }
                }
                
                // Don't stop folder access here - let it stay alive for continued use
                // It will be cleaned up when switching to a different folder or app lifecycle events
                
            } catch {
                DispatchQueue.main.async {
                    self.appState.errorMessage = "ERROR: Failed to load data: \(error.localizedDescription)"
                    self.appState.isProcessing = false
                    log("Error loading folder: \(error)", level: .error)
                }
            }
        }
    }
    
    private func switchToAnalysisMode() {
        if appState.isRecordMode {
            appState.isRecordMode = false
            if cameraManager.isRecording {
                cameraManager.stopRecording { _ in }
            }
            
            // Stop camera stream on background thread
            DispatchQueue.global(qos: .userInitiated).async {
                self.cameraManager.pauseStream()
            }
            
            // Clean up previous folder access when switching modes
            cleanupPreviousData()
            
            // Reset states before loading new file
            appState.resetFileAndKeypointState()
            appState.resetStatusState()
        }
    }
 
    
}
