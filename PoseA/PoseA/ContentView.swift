// --------------------------------------
// ------------- Main Files -------------
// --------------------------------------

// Import Libraries
import SwiftUI
import AVFoundation
import Photos
import PhotosUI
import Foundation

// Main Structure
struct BESTGYMPoseApp: View {
    // Declare State Variable
    @StateObject private var cameraManager = CameraLiDARManager() // Camera Driver
    @StateObject private var appState = AppState() // Application View State Class
    @State private var showSettingsView = false // Settings View
    
    // Body View
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
                
                // Processing overlay
                if appState.isProcessing {
                    ProcessingOverlayView(status: appState.processingStatus)
                }
                
                // Error overlay
                if let error = appState.errorMessage {
                    ErrorOverlayView(message: error) {
                        appState.errorMessage = nil
                    }
                }
            }
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
            .background(Color(.systemBackground))
            .sheet(isPresented: $showSettingsView) {
                SettingsView(appState: appState)
            }
            .sheet(isPresented: $appState.isFilePickerPresented) {
                DocumentPickerUI { urls in
                    if let url = urls.first {
                        loadData(from: url)
                    }
                }
            }
            .sheet(isPresented: $appState.isVideoPickerPresented) {
                videoFilePickerUI { url in
                    loadVideo(from: url)
                }
            }
            .sheet(isPresented: $appState.isPhotoLibraryPresented) {
                PhotoLibraryVideoPicker(isPresented: $appState.isPhotoLibraryPresented) { url in
                    if let url = url {
                        loadVideo(from: url)
                    }
                }
            }
            .sheet(isPresented: $appState.isKeypointImportPresented) {
                KeypointFilePickerUI { url in
                    loadKeypointFile(url)
                }
            }
            .sheet(isPresented: $appState.showAnalysisView) {
                PoseAnalysisView(
                    poseProcessor: appState.poseProcessor,
                    currentFrameIndex: cameraManager.currentFrameIndex, // MARK: Currently not used
                    showAnalysisView: $appState.showAnalysisView
                )
                .edgesIgnoringSafeArea(.all)
            }
            .onAppear {
                setupInitialState()
                
                NotificationCenter.default.addObserver(
                        forName: NSNotification.Name("FrameChanged"),
                        object: nil,
                        queue: .main
                    ) { notification in
                        if let frameIndex = notification.userInfo?["frameIndex"] as? Int {
                            print("🔶 Received frame change notification for frame \(frameIndex)")
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
                        print("Recording completed at: \(url.path)")
                        
                        // For LiDAR recordings you can enable this if desired:
                        // if appState.useLiDAR {
                        //     self.loadVideo(from: url)
                        // }
                    }
                }
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
    
//    private func setupPlaybackHandler() {
//        cameraManager.onFrameChange = { index in
//            // Update UI based on current frame
//            if appState.showKeypoints {
//                self.updateDisplayWithKeypoints(for: index)
//            }
//        }
//    }
    
    private func loadData(from url: URL) {
        appState.isProcessing = true
        appState.processingStatus = "Loading data..."
        
        // First check if it's a directory or file
        let fileManager = FileManager.default
        var isDirectory: ObjCBool = false
        
        if fileManager.fileExists(atPath: url.path, isDirectory: &isDirectory) {
            if isDirectory.boolValue {
                // It's a folder - could be LiDAR data or folder with video
                loadDataFromFolder(url)
            } else {
                // It's a file - check extension
                let fileExtension = url.pathExtension.lowercased()
                
                if fileExtension == "json" {
                    // It's a keypoint file
                    loadKeypointFile(url)
                } else if ["mp4", "mov", "m4v"].contains(fileExtension) {
                    // It's a video file
                    loadVideo(from: url)
                } else {
                    // Unknown file type
                    DispatchQueue.main.async {
                        self.appState.isProcessing = false
                        self.appState.errorMessage = "Unsupported file format: \(fileExtension)"
                    }
                }
            }
        } else {
            // File or folder doesn't exist
            DispatchQueue.main.async {
                self.appState.isProcessing = false
                self.appState.errorMessage = "Selected file or folder doesn't exist"
            }
        }
    }

    private func loadDataFromFolder(_ url: URL) {
        appState.isVideoSource = false
        appState.processingStatus = "Loading data from folder..."
        
        DispatchQueue.global(qos: .userInitiated).async {
            do {
                let fileManager = FileManager.default
                
                // Start accessing the security-scoped resource if needed
                let shouldStopAccessing = url.startAccessingSecurityScopedResource()
                defer {
                    if shouldStopAccessing {
                        url.stopAccessingSecurityScopedResource()
                    }
                }
                
                // Get all items in the folder
                let contents = try fileManager.contentsOfDirectory(
                    at: url,
                    includingPropertiesForKeys: [.isDirectoryKey],
                    options: [.skipsHiddenFiles]
                )
                
                print("Found \(contents.count) items in folder \(url.lastPathComponent)")
                
                // Check folder structure to determine type
                
                // 1. Check for video file (standard recording or video+metadata)
                let videoFiles = contents.filter {
                    ["mp4", "mov", "m4v"].contains($0.pathExtension.lowercased())
                }
                
                // 2. Check for frame directories (LiDAR recording)
                let frameDirectories = contents.filter {
                    var isDir: ObjCBool = false
                    return fileManager.fileExists(atPath: $0.path, isDirectory: &isDir) &&
                           isDir.boolValue &&
                           $0.lastPathComponent.hasPrefix("frame_")
                }
                
                // 3. Check for direct depth data files
                let hasDepthData = contents.contains {
                    $0.lastPathComponent == "depthData.dat"
                }
                
                // 4. Check for metadata file
                let hasMetadata = contents.contains {
                    $0.lastPathComponent == "recording_metadata.json"
                }
                
                // Now determine what type of folder this is
                
                if !videoFiles.isEmpty {
                    // Found video file(s)
                    print("Found video file(s) in folder")
                    
                    // If we have multiple video files, choose the first one
                    // You could add more logic here to select the appropriate one
                    let videoURL = videoFiles.first!
                    
                    print("Loading video from folder: \(videoURL.path)")
                    
                    // Load on main thread
                    DispatchQueue.main.async {
                        self.loadVideo(from: videoURL)
                        
                        // If we have metadata, update the app state to indicate this
                        if hasMetadata {
                            self.appState.processingStatus = "Loaded video with metadata"
                        }
                    }
                } else if !frameDirectories.isEmpty {
                    // LiDAR recording with frame folders
                    print("Loading as LiDAR frame folder with \(frameDirectories.count) frames")
                    
                    // Use the proper CameraLiDARManager method
                    self.cameraManager.loadVideoFolder(from: url)
                    
                    // Update AppState
                    DispatchQueue.main.async {
                        self.appState.processingStatus = "Loaded \(self.cameraManager.totalFrames) frames from \(url.lastPathComponent)"
                        self.appState.sourceFileName = url.lastPathComponent
                        self.appState.sourceURL = url
                        self.appState.isProcessing = false
                    }
                } else if hasDepthData {
                    // Direct LiDAR data files
                    print("Loading as LiDAR depth data")
                    
                    if let device = MTLCreateSystemDefaultDevice() {
                        self.cameraManager.loadCapturedData(from: url, device: device)
                        
                        DispatchQueue.main.async {
                            self.appState.processingStatus = "Loaded depth data from \(url.lastPathComponent)"
                            self.appState.sourceFileName = url.lastPathComponent
                            self.appState.sourceURL = url
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
                        print("Error: Folder does not contain recognized data: \(url.path)")
                    }
                }
            } catch {
                DispatchQueue.main.async {
                    self.appState.errorMessage = "Failed to load data: \(error.localizedDescription)"
                    self.appState.isProcessing = false
                    print("Error loading folder: \(error)")
                }
            }
        }
    }
    
    private func loadVideo(from url: URL) {
        appState.isProcessing = true
        appState.processingStatus = "Loading video..."
        appState.isVideoSource = true
        
        // Reset keypoint-related states
        appState.hasImportedKeypoints = false
        appState.showKeypoints = false
        
        print("Loading video from: \(url.path)")
        
        // Check if this is a recording folder rather than a direct video file
        var isFolder = false
        do {
            let resourceValues = try url.resourceValues(forKeys: [.isDirectoryKey])
            isFolder = resourceValues.isDirectory ?? false
        } catch {
            print("Error checking if URL is directory: \(error)")
        }
        
        if isFolder {
            print("Loading as a recording folder")
            loadDataFromFolder(url)
        } else {
            // Check if there's metadata in the same folder
            let folderURL = url.deletingLastPathComponent()
            let metadataURL = folderURL.appendingPathComponent("recording_metadata.json")
            
            var hasMetadata = false
            if FileManager.default.fileExists(atPath: metadataURL.path) {
                print("Found metadata file alongside video")
                hasMetadata = true
                // Optionally load metadata here if needed for video processing
            }
            
            // Load as a direct video file
            cameraManager.loadVideoFile(url) { success, totalFrames, error in
                DispatchQueue.main.async {
                    self.appState.isProcessing = false
                    
                    if success {
                        self.appState.processingStatus = "Video loaded with \(totalFrames) frames" + (hasMetadata ? " and metadata" : "")
                        self.appState.sourceFileName = url.lastPathComponent
                        self.appState.sourceURL = url
                        
                        // Show guidance message about next steps
                        DispatchQueue.main.asyncAfter(deadline: .now() + 1.0) {
                            self.appState.processingStatus = "Video loaded. Select 'Detect Pose' to analyze."
                        }
                    } else if let error = error {
                        self.appState.errorMessage = "Failed to load video: \(error)"
                    }
                }
            }
        }
    }
    
    private func loadKeypointFile(_ url: URL) {
        appState.isProcessing = true
        appState.processingStatus = "Loading keypoints..."
        
        // Load keypoints into pose processor
        appState.poseProcessor.loadKeypoints(from: url) { success, frameCount, error in
            DispatchQueue.main.async {
                appState.isProcessing = false
                
                if success {
                    // Set flags to indicate we have keypoints
                    appState.hasImportedKeypoints = true
                    appState.showKeypoints = true  // Automatically show keypoints
                    appState.processingStatus = "Loaded keypoints for \(frameCount) frames"
                    appState.originalKeypointFileURL = url
                    
                    // Update sourceFileName for proper display in UI
                    appState.sourceFileName = url.lastPathComponent
                    
                    // Validate the loaded keypoints
                    if !appState.poseProcessor.validateLoadedKeypoints() {
                        appState.processingStatus = "Warning: Keypoint data may be invalid"
                    }
                    
                    // Update UI to show first frame with keypoints
                    if frameCount > 0 {
                        cameraManager.currentFrameIndex = 0
                        DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
                            self.updateDisplayWithKeypoints(for: 0)
                        }
                    }
                } else if let error = error {
                    appState.errorMessage = "Failed to load keypoints: \(error)"
                }
            }
        }
    }
    
    
    private func autoLoadDefaultData() {
        // Implementation for auto-loading default data
        // This would depend on your specific requirements
    }
    
 
    // In BESTGYMPoseApp.swift - fully thread-safe updateDisplayWithKeypoints method
    // In BESTGYMPoseApp.swift - replace the existing updateDisplayWithKeypoints method
    // Also update the updateDisplayWithKeypoints in BESTGYMPoseApp
//    private func updateDisplayWithKeypoints(for frameIndex: Int) {
//        // Ensure we're on the main thread
//        if !Thread.isMainThread {
//            DispatchQueue.main.async {
//                self.updateDisplayWithKeypoints(for: frameIndex)
//            }
//            return
//        }
//        
//        print("CRITICAL: Updating display with keypoints for frame \(frameIndex)")
//        
//        // Defensive bounds check
//        guard frameIndex >= 0 && frameIndex < cameraManager.totalFrames else {
//            print("⚠️ Frame index \(frameIndex) out of bounds (0..\(cameraManager.totalFrames-1))")
//            return
//        }
//        
//        // EXPLICITLY force showKeypoints to true
//        appState.showKeypoints = true
//        
//        // Get the original frame
//        if let originalFrame = cameraManager.getFrame(at: frameIndex) {
//            // First update the frame image - do this BEFORE sending notifications
//            cameraManager.currentFrameImage = originalFrame
//            cameraManager.currentFrameIndex = frameIndex
//            
//            // Check if we have keypoints for this frame
//            if let keypoints = appState.poseProcessor.getKeypoints(for: frameIndex), !keypoints.isEmpty {
//                print("CRITICAL: Have \(keypoints.count) keypoints for frame \(frameIndex)")
//                
//                // Set flags
//                appState.hasImportedKeypoints = true
//                appState.showKeypoints = true
//                
//                // Add a small delay before sending notification
//                DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
//                    // Signal that keypoints need updating
//                    NotificationCenter.default.post(
//                        name: NSNotification.Name("KeypointDisplayUpdated"),
//                        object: nil,
//                        userInfo: ["frameIndex": frameIndex]
//                    )
//                    
//                    print("✅ Sent keypoint update notification for frame \(frameIndex)")
//                }
//            } else {
//                print("CRITICAL: No keypoints found for frame \(frameIndex)")
//                appState.showKeypoints = false
//            }
//        } else {
//            print("⚠️ No image found for frame \(frameIndex)")
//        }
//    }
    // In BESTGYMPoseApp.swift - replace the existing processData method with this improved version
    // In BESTGYMPoseApp.swift - replace the existing processData method
    // In BESTGYMPoseApp.swift - completely revised processData method
//    private func processData() {
//        // Always execute on main thread
//        DispatchQueue.main.async {
//            // Verify we have frames and not already processing
//            guard self.cameraManager.totalFrames > 0 else {
//                print("Error: No frames available for processing")
//                self.appState.errorMessage = "No frames available for processing"
//                return
//            }
//            
//            guard !self.appState.isProcessing else {
//                print("Already processing frames")
//                return
//            }
//            
//            // Show processing indicator - done directly on main thread
//            self.appState.isProcessing = true
//            self.appState.processingStatus = "Preparing for pose detection..."
//            
//            print("Beginning pose detection on \(self.cameraManager.totalFrames) frames")
//            
//            // Short delay to ensure UI updates before starting
//            DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
//                // Update status text
//                self.appState.processingStatus = "Detecting poses in \(self.cameraManager.totalFrames) frames..."
//                
//                // Start processing
//                self.appState.poseProcessor.processFrames(from: self.cameraManager) { progressValue in
//                    // Update progress (guaranteed on main thread)
//                    let percentage = Int(progressValue * 100)
//                    self.appState.processingStatus = "Processing: \(percentage)%"
//                } completion: { success, error in
//                    // All updates here are guaranteed to be on main thread
//                    
//                    // First, mark processing as complete
//                    self.appState.isProcessing = false
//                    
//                    if success {
//                        // Call our dedicated method to handle completion
//                        self.finishPoseDetection()
//                    } else if let processingError = error {
//                        // Show error message
//                        self.appState.isProcessing = false
//                        self.appState.errorMessage = "Processing failed: \(processingError.localizedDescription)"
//                        print("Pose detection error: \(processingError)")
//                    }
//                }
//            }
//        }
//    }
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
            
            print("Beginning pose detection on \(self.cameraManager.totalFrames) frames")
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
                
                self.appState.poseProcessor.processFrames(from: self.cameraManager) { progressValue in
                    let percentage = Int(progressValue * 100)
                    let statusText = self.appState.hasROI ?
                        "Processing ROI frames: \(percentage)%" :
                        "Processing frames: \(percentage)%"
                    self.appState.processingStatus = statusText
                } completion: { success, error in
                    self.appState.isProcessing = false
                    
                    if success {
                        self.finishPoseDetection()
                    } else if let processingError = error {
                        self.appState.errorMessage = "Processing failed: \(processingError.localizedDescription)"
                        print("Pose detection error: \(processingError)")
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
        switchToAnalysisMode()
        appState.isFilePickerPresented = true
    }
    
    private func selectVideoFile() {
        switchToAnalysisMode()
        appState.isVideoPickerPresented = true
    }
    
    private func selectVideoFromLibrary() {
        switchToAnalysisMode()
        appState.isPhotoLibraryPresented = true
    }
    
    private func selectKeypointFile() {
        switchToAnalysisMode()
        appState.isKeypointImportPresented = true
    }
    
    // Helper to ensure we exit record mode when loading files
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
            
            // Reset states before loading new file
            appState.resetFileAndKeypointState()
            appState.resetStatusState()
        }
    }
    
//    // Add this method to BESTGYMPoseApp
//    private func finishPoseDetection() {
//        // This method should only be called on the main thread
//        assert(Thread.isMainThread, "finishPoseDetection must be called on main thread")
//        
//        // Update state to indicate processing is complete
//        appState.isProcessing = false
//        appState.processingStatus = "Pose detection complete!"
//        
//        // Mark that we now have keypoints to show
//        appState.showKeypoints = true
//        
//        print("Detection complete - showing keypoints")
//        
//        // Reset to the first frame
//        cameraManager.currentFrameIndex = 0
//        
//        // Give the UI a moment to update before trying to display keypoints
//        DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
//            // Now update the display with keypoints (for frame 0)
//            self.appState.processingStatus = "Loading visualization..."
//            
//            // Get the first frame image and keypoints
//            guard let firstFrameImage = self.cameraManager.getFrame(at: 0),
//                  let keypoints = self.appState.poseProcessor.getKeypoints(for: 0) else {
//                self.appState.errorMessage = "Could not load detected keypoints"
//                return
//            }
//            
//            // Set current frame image without any direct keypoint overlay
//            self.cameraManager.currentFrameImage = firstFrameImage
//            
//            // Update status
//            self.appState.processingStatus = "Ready"
//            
//            print("Display updated with keypoints for first frame")
//            
//            self.exportKeypointsToJSON()
//        }
//    }
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
    
    // Add to BESTGYMPoseApp
    private func checkForAssociatedKeypointFile(videoURL: URL) {
        // Don't search if we already have keypoints
        if appState.hasImportedKeypoints || appState.showKeypoints {
            return
        }

        let fileManager = FileManager.default
        let videoDirectory = videoURL.deletingLastPathComponent()
        let videoNameWithoutExtension = videoURL.deletingPathExtension().lastPathComponent
        
        print("Checking for associated keypoint files for \(videoNameWithoutExtension)")
        
        // Try to find matching keypoint files
        do {
            let directoryContents = try fileManager.contentsOfDirectory(
                at: videoDirectory,
                includingPropertiesForKeys: nil,
                options: [.skipsHiddenFiles]
            )
            
            // Look for keypoint files with the video name
            let keypointFiles = directoryContents.filter { url in
                return url.pathExtension.lowercased() == "json" &&
                       url.lastPathComponent.lowercased().contains("keypoint") &&
                       url.lastPathComponent.lowercased().contains(videoNameWithoutExtension.lowercased())
            }
            
            // If none found, try any keypoint file in the same directory
            let anyKeypointFiles = directoryContents.filter { url in
                return url.pathExtension.lowercased() == "json" &&
                       url.lastPathComponent.lowercased().contains("keypoint")
            }
            
            if let keypointURL = keypointFiles.first ?? anyKeypointFiles.first {
                print("Found associated keypoint file: \(keypointURL.lastPathComponent)")
                
                // Show message
                appState.processingStatus = "Found keypoint file, loading..."
                
                // Load after a small delay to allow UI to update
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
                    self.loadKeypointFile(keypointURL)
                }
            } else {
                print("No associated keypoint files found")
                
                // If auto-detect is enabled, run detection
                if appState.autoDetectKeypoints {
                    appState.processingStatus = "Auto-detecting poses..."
                    
                    // Start detection after a short delay
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
                        self.processData()
                    }
                }
            }
        } catch {
            print("Error searching for keypoint files: \(error)")
        }
    }
    private func updateDisplayWithKeypoints(for frameIndex: Int) {
        // Ensure we're on the main thread
        DispatchQueue.main.async {
            print("🔍 Updating display with keypoints for frame \(frameIndex)")
            
            // Bounds check
            guard frameIndex >= 0 && frameIndex < self.cameraManager.totalFrames else {
                print("⚠️ Frame index \(frameIndex) out of bounds")
                return
            }
            
            // Update current frame
            self.cameraManager.currentFrameIndex = frameIndex
            
            // Get the frame image
            if let frameImage = self.cameraManager.getFrame(at: frameIndex) {
                self.cameraManager.currentFrameImage = frameImage
                
                // Check if we have keypoints for this frame
                if let keypoints = self.appState.poseProcessor.getKeypoints(for: frameIndex), !keypoints.isEmpty {
                    print("✅ Found \(keypoints.count) keypoints for frame \(frameIndex)")
                    
                    // Enable keypoint display
                    self.appState.showKeypoints = true
                    self.appState.hasImportedKeypoints = true
                    
                    print("✅ Keypoints enabled for display")
                } else {
                    print("⚠️ No keypoints found for frame \(frameIndex)")
                    self.appState.showKeypoints = false
                }
            } else {
                print("⚠️ No image found for frame \(frameIndex)")
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
}

// MARK: - App State
class AppState: ObservableObject {
    // UI state
    @Published var isProcessing = false
    @Published var processingStatus = ""
    @Published var errorMessage: String? = nil
    @Published var showKeypoints = false
    @Published var isAnnotationMode = false
    @Published var isVideoSource = false
    @Published var hasImportedKeypoints = false
    @Published var isRecordMode = false
    
    // Pickers
    @Published var isFilePickerPresented = false
    @Published var isVideoPickerPresented = false
    @Published var isPhotoLibraryPresented = false
    @Published var isKeypointImportPresented = false
    
    // Analysis view
    @Published var showAnalysisView = false
    
    // File metadata
    @Published var sourceFileName = ""
    @Published var sourceURL: URL? = nil
    @Published var originalKeypointFileURL: URL? = nil
    @Published var recordingDate: Date? = nil
    
    // Pose processing
    let poseProcessor = VitPoseProcessor()
    
    // Editing state
    @Published var didEditKeypoints = false
    @Published var selectedKeypointIndex: Int? = nil
    
    @Published var athleteName: String = "Test"
    @Published var actionType: String = "Test"
    @Published var distanceValue: String? = "Test"
    @Published var videoSettings = VideoSettings.defaultSettings
    
    // LiDAR toggle state
    @Published var useLiDAR: Bool = false
    @Published var imageRotation: Int = 0
    
    @Published var autoDetectKeypoints: Bool = false
    
    @Published var isROIMode = false
   @Published var roiRect: CGRect? = nil
   @Published var isSelectingROI = false
   @Published var hasROI = false
   @Published var roiImageCoordinates: CGRect? = nil // ROI in actual image coordinates
   
    
    
    func resetFileAndKeypointState() {
        sourceFileName = ""
        sourceURL = nil
        originalKeypointFileURL = nil
        hasImportedKeypoints = false
        showKeypoints = false
        // Keep default values for athlete info
        if athleteName.isEmpty {
            athleteName = "Test"
        }
        if actionType.isEmpty {
            actionType = "Test"
        }
        if distanceValue == nil {
            distanceValue = "Test"
        }
    }
    
    // Helper to reset processing/error state
    func resetStatusState() {
        isProcessing = false
        processingStatus = ""
        errorMessage = nil
    }
    func rotateImageClockwise() {
        // Increment and wrap around to keep in range 0-3
        imageRotation = (imageRotation + 1) % 4
    }
    
    func rotateImageCounterClockwise() {
        // Decrement and wrap around to keep in range 0-3
        imageRotation = (imageRotation - 1 + 4) % 4
    }
    
    func loadUserPreferences() {
        autoDetectKeypoints = UserDefaults.standard.bool(forKey: "AutoDetectKeypoints")
    }
    
    // Save preferences to UserDefaults
    func saveUserPreferences() {
        UserDefaults.standard.set(autoDetectKeypoints, forKey: "AutoDetectKeypoints")
    }
    // Thread-safe way to update processing state
    func setProcessingState(isProcessing: Bool, status: String = "") {
        ensureMainThread {
            self.isProcessing = isProcessing
            if !status.isEmpty {
                self.processingStatus = status
            }
        }
    }
    
    // Thread-safe way to update error message
    func setErrorMessage(_ message: String?) {
        ensureMainThread {
            self.errorMessage = message
        }
    }
    
    // Thread-safe way to update keypoint visibility
    func setShowKeypoints(_ show: Bool) {
        ensureMainThread {
            self.showKeypoints = show
        }
    }
    
    // Helper function to ensure code runs on main thread
    private func ensureMainThread(_ updates: @escaping () -> Void) {
        if Thread.isMainThread {
            updates()
        } else {
            DispatchQueue.main.async {
                updates()
            }
        }
    }
    
    func enableROIMode() {
            isROIMode = true
            isSelectingROI = true
            showKeypoints = false // Hide keypoints while selecting ROI
        }
        
        func disableROIMode() {
            isROIMode = false
            isSelectingROI = false
            roiRect = nil
            hasROI = false
            roiImageCoordinates = nil
        }
        
        func setROI(_ displayRect: CGRect, imageCoordinates: CGRect) {
            roiRect = displayRect // For display purposes
            roiImageCoordinates = imageCoordinates // For actual processing
            hasROI = true
            isSelectingROI = false
            // Re-enable keypoints after ROI selection
            if poseProcessor.getTotalFrames() > 0 {
                showKeypoints = true
            }
        }
        
        func clearROI() {
            roiRect = nil
            roiImageCoordinates = nil
            hasROI = false
            isROIMode = false
            isSelectingROI = false
        }
    
}

// MARK: - App Header
struct AppHeader: View {
    @ObservedObject var appState: AppState
    @ObservedObject var cameraManager: CameraLiDARManager
    var processAction: () -> Void
    var exportAction: () -> Void
    
    var body: some View {
        VStack(spacing: 0) {
            // Row 1: Title and mode selector
            HStack {
                Text("BESTGYM PoseAPP")
                    .font(.title2)
                    .fontWeight(.bold)
                
                Spacer()
                
                // Mode selector
                Picker("Mode", selection: $appState.isRecordMode) {
                    Text("Analysis").tag(false)
                    Text("Record").tag(true)
                }
                .pickerStyle(SegmentedPickerStyle())
                .frame(width: 200)
                .onChange(of: appState.isRecordMode) { oldValue, newValue in
                    handleModeChange(isRecordMode: newValue)
                }
            }
            .padding()
            .background(Color(.secondarySystemBackground))
            
            // Row 2: Mode-specific controls
            if appState.isRecordMode {
                // RECORD MODE: Athlete info fields
                recordModeHeaderControls
            } else {
                // ANALYSIS MODE: Detect Pose / Analyze buttons
                analysisModeHeaderControls
            }
            
            // Row 3: File information bar (hide in record mode)
            if !appState.isRecordMode && (cameraManager.totalFrames > 0 || appState.hasImportedKeypoints) {
                fileInfoBar
            }
        }
    }
    
    // MARK: - Header Components
    
    private var recordModeHeaderControls: some View {
        HStack(spacing: 8) {
            HStack {
                Text("Athlete:")
                    .foregroundColor(.white)
                    .fontWeight(.bold)
                    .font(.system(size: 12))
                TextField("Test", text: $appState.athleteName)
                    .textFieldStyle(RoundedBorderTextFieldStyle())
                    .foregroundColor(.black)
                    .font(.system(size: 12))
                    .background(Color.white.opacity(0.8))
                    .cornerRadius(5)
            }
            
            HStack {
                Text("Action:")
                    .foregroundColor(.white)
                    .fontWeight(.bold)
                    .font(.system(size: 12))
                TextField("Test", text: $appState.actionType)
                    .textFieldStyle(RoundedBorderTextFieldStyle())
                    .foregroundColor(.black)
                    .font(.system(size: 12))
                    .background(Color.white.opacity(0.8))
                    .cornerRadius(5)
            }
            
            HStack {
                Text("Distance:")
                    .foregroundColor(.white)
                    .fontWeight(.bold)
                    .font(.system(size: 12))
                TextField("Test", text: Binding(
                    get: { appState.distanceValue ?? "Test" },
                    set: { appState.distanceValue = $0 }
                ))
                .textFieldStyle(RoundedBorderTextFieldStyle())
                .foregroundColor(.black)
                .font(.system(size: 12))
                .background(Color.white.opacity(0.8))
                .cornerRadius(5)
            }
        }
        .padding(.horizontal)
        .padding(.vertical, 8)
        .background(Color.black.opacity(0.7))
    }
    
    // Modify the analysisModeHeaderControls in AppHeader.swift
//    private var analysisModeHeaderControls: some View {
//        HStack {
//            Spacer()
//            
//            // Status indicator
//            if cameraManager.totalFrames > 0 {
//                HStack(spacing: 8) {
//                    // Visual indicator for keypoint status - check if keypoints actually exist
//                    let hasKeypoints = appState.hasImportedKeypoints ||
//                                      (appState.showKeypoints && appState.poseProcessor.getTotalFrames() > 0)
//                    
//                    Circle()
//                        .fill(hasKeypoints ? Color.green : Color.orange)
//                        .frame(width: 10, height: 10)
//                    
//                    Text(hasKeypoints ?
//                         "Keypoints available" :
//                         "Keypoints needed")
//                        .font(.caption)
//                        .foregroundColor(.secondary)
//                }
//                .padding(.horizontal, 12)
//                .padding(.vertical, 6)
//                .background(Color(.tertiarySystemBackground))
//                .cornerRadius(12)
//            }
//            
//            Spacer()
//            
//            // Check for actual keypoint existence
//            let hasKeypoints = appState.hasImportedKeypoints ||
//                              (appState.poseProcessor.getTotalFrames() > 0 &&
//                               appState.poseProcessor.hasKeypoints(for: cameraManager.currentFrameIndex))
//            
//            // Processing / Analysis buttons
//            if cameraManager.totalFrames > 0 && !hasKeypoints && !appState.isProcessing {
//                Button(action: processAction) {
//                    Text("Detect Pose")
//                        .font(.headline)
//                        .padding(.horizontal, 20)
//                        .padding(.vertical, 10)
//                        .background(Color.blue)
//                        .foregroundColor(.white)
//                        .cornerRadius(8)
//                }
//                .disabled(appState.isProcessing)
//            } else if hasKeypoints {
//                // Only show these buttons if we have keypoints
//                HStack(spacing: 12) {
//                    // Export button
//                    Button(action: exportAction) {
//                        Text("Export Keypoints")
//                            .font(.headline)
//                            .padding(.horizontal, 16)
//                            .padding(.vertical, 10)
//                            .background(Color.green)
//                            .foregroundColor(.white)
//                            .cornerRadius(8)
//                    }
//                    
//                    // Analyze button
//                    Button {
//                        appState.showAnalysisView = true
//                    } label: {
//                        Text("Analyze")
//                            .font(.headline)
//                            .padding(.horizontal, 20)
//                            .padding(.vertical, 10)
//                            .background(Color.purple)
//                            .foregroundColor(.white)
//                            .cornerRadius(8)
//                    }
//                }
//            } else {
//                Spacer()
//            }
//        }
//        .padding(.horizontal)
//        .padding(.vertical, 8)
//        .frame(height: 50)
//    }
    
    private var analysisModeHeaderControls: some View {
        HStack {
            Spacer()
            
            // ROI Controls - only show when we have frames loaded
            if cameraManager.totalFrames > 0 {
                HStack(spacing: 8) {
                    // ROI Mode Toggle
                    Button(action: {
                        if appState.isROIMode {
                            appState.disableROIMode()
                        } else {
                            appState.enableROIMode()
                        }
                    }) {
                        HStack(spacing: 4) {
                            Image(systemName: appState.isROIMode ? "viewfinder.circle.fill" : "viewfinder.circle")
                            Text(appState.isROIMode ? "Exit ROI" : "Select ROI")
                        }
                        .font(.caption)
                        .padding(.horizontal, 8)
                        .padding(.vertical, 4)
                        .background(appState.isROIMode ? Color.orange : Color.gray)
                        .foregroundColor(.white)
                        .cornerRadius(6)
                    }
                    
                    // Clear ROI button (only show if we have an ROI)
                    if appState.hasROI {
                        Button(action: {
                            appState.clearROI()
                        }) {
                            HStack(spacing: 4) {
                                Image(systemName: "trash")
                                Text("Clear ROI")
                            }
                            .font(.caption)
                            .padding(.horizontal, 8)
                            .padding(.vertical, 4)
                            .background(Color.red)
                            .foregroundColor(.white)
                            .cornerRadius(6)
                        }
                    }
                }
                .padding(.trailing, 8)
            }
            
            // Status indicator
            if cameraManager.totalFrames > 0 {
                HStack(spacing: 8) {
                    // ROI Status
                    if appState.hasROI {
                        HStack(spacing: 4) {
                            Circle()
                                .fill(Color.orange)
                                .frame(width: 8, height: 8)
                            Text("ROI Set for All Frames")
                                .font(.caption)
                                .foregroundColor(.orange)
                        }
                    }
                    
                    // Keypoint Status
                    let hasKeypoints = appState.hasImportedKeypoints ||
                                      (appState.showKeypoints && appState.poseProcessor.getTotalFrames() > 0)
                    
                    HStack(spacing: 4) {
                        Circle()
                            .fill(hasKeypoints ? Color.green : Color.orange)
                            .frame(width: 8, height: 8)
                        
                        Text(hasKeypoints ? "Keypoints available" : "Keypoints needed")
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                }
                .padding(.horizontal, 12)
                .padding(.vertical, 6)
                .background(Color(.tertiarySystemBackground))
                .cornerRadius(12)
            }
            
            Spacer()
            
            // Detection and Analysis buttons
            let hasKeypoints = appState.hasImportedKeypoints ||
                              (appState.poseProcessor.getTotalFrames() > 0 &&
                               appState.poseProcessor.hasKeypoints(for: cameraManager.currentFrameIndex))
            
            if cameraManager.totalFrames > 0 && !hasKeypoints && !appState.isProcessing && !appState.isSelectingROI {
                Button(action: processAction) {
                    Text(appState.hasROI ? "Detect Pose in ROI (All Frames)" : "Detect Pose (All Frames)")
                        .font(.headline)
                        .padding(.horizontal, 16)
                        .padding(.vertical, 10)
                        .background(appState.hasROI ? Color.orange : Color.blue)
                        .foregroundColor(.white)
                        .cornerRadius(8)
                }
                .disabled(appState.isProcessing)
            } else if hasKeypoints && !appState.isSelectingROI {
                HStack(spacing: 12) {
                    Button(action: exportAction) {
                        Text("Export Keypoints")
                            .font(.headline)
                            .padding(.horizontal, 16)
                            .padding(.vertical, 10)
                            .background(Color.green)
                            .foregroundColor(.white)
                            .cornerRadius(8)
                    }
                    
                    Button {
                        appState.showAnalysisView = true
                    } label: {
                        Text("Analyze")
                            .font(.headline)
                            .padding(.horizontal, 20)
                            .padding(.vertical, 10)
                            .background(Color.purple)
                            .foregroundColor(.white)
                            .cornerRadius(8)
                    }
                }
            } else {
                Spacer()
            }
        }
        .padding(.horizontal)
        .padding(.vertical, 8)
        .frame(height: 60) // Increased height to accommodate ROI controls
    }
    
    private var fileInfoBar: some View {
        HStack(spacing: 8) {
            // Display Data Source Type
            Image(systemName: appState.isVideoSource ? "video.fill" : "cube.transparent.fill")
                .foregroundColor(appState.isVideoSource ? .blue : .green)
            
            Text(appState.isVideoSource ? "Video Source (2D pose only)" : "LiDAR Data Source (3D pose)")
                .font(.caption)
                .fontWeight(.medium)
                .foregroundColor(.secondary)
                
            Divider().frame(height: 15)
                
            // Keypoint status indicator
            if cameraManager.totalFrames > 0 {
                HStack(spacing: 4) {
                    // Check if keypoints actually exist by checking the processor
                    let hasKeypoints = appState.hasImportedKeypoints ||
                                      (appState.poseProcessor.getTotalFrames() > 0 &&
                                       appState.poseProcessor.hasKeypoints(for: cameraManager.currentFrameIndex))
                    
                    Circle()
                        .fill(hasKeypoints ? Color.green : Color.orange)
                        .frame(width: 8, height: 8)
                    
                    Text(hasKeypoints ?
                         "Keypoints: Available" :
                         "Keypoints: Not Detected")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
                
                Divider().frame(height: 15)
            }

            // Display File Name with proper handling
            if !appState.sourceFileName.isEmpty {
                // Use the explicit source file name if available
                Text(appState.sourceFileName)
                    .font(.caption)
                    .lineLimit(1)
                    .truncationMode(.middle)
            } else if let sourceURL = appState.sourceURL ?? appState.originalKeypointFileURL {
                // Fall back to URL's filename if sourceFileName is not set
                Text(sourceURL.lastPathComponent)
                    .font(.caption)
                    .lineLimit(1)
                    .truncationMode(.middle)
            } else {
                Text("No file loaded")
                    .font(.caption)
            }

            Spacer()
        }
        .font(.caption)
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .background(Color(.tertiarySystemBackground))
    }
    // MARK: - Helper Functions
    
    private func handleModeChange(isRecordMode: Bool) {
        if isRecordMode {
            // Switching to Record Mode
            DispatchQueue.global(qos: .userInitiated).async {
                // Use self directly, not weak self (since this is a struct)
                self.cameraManager.resumeStream()
            }
            
            // Reset states
            appState.resetFileAndKeypointState()
            appState.resetStatusState()
        } else {
            // Switching to Analysis Mode
            if cameraManager.isRecording {
                // Stop recording if switching during recording
                if appState.useLiDAR {
                    cameraManager.stopVideoRecording { _ in }
                } else {
                    cameraManager.stopRecording { _ in }
                }
            }
            
            // Stop camera stream (this is safe to call even if not streaming)
            DispatchQueue.global(qos: .userInitiated).async {
                // Use self directly, not weak self (since this is a struct)
                self.cameraManager.pauseStream()
            }
        }
    }
}



struct ROISelectionOverlay: View {
    @ObservedObject var appState: AppState
    let containerSize: CGSize
    let imageSize: CGSize
    let rotation: Int
    
    @State private var startPoint: CGPoint = .zero
    @State private var currentPoint: CGPoint = .zero
    @State private var isDragging = false
    
    var body: some View {
        ZStack {
            // Semi-transparent overlay
            Color.black.opacity(0.3)
                .allowsHitTesting(false)
            
            // ROI selection area
            if appState.isSelectingROI {
                Rectangle()
                    .stroke(Color.orange, lineWidth: 3)
                    .background(Color.orange.opacity(0.1))
                    .frame(
                        width: abs(currentPoint.x - startPoint.x),
                        height: abs(currentPoint.y - startPoint.y)
                    )
                    .position(
                        x: (startPoint.x + currentPoint.x) / 2,
                        y: (startPoint.y + currentPoint.y) / 2
                    )
                    .opacity(isDragging ? 1.0 : 0.0)
            }
            
            // Show existing ROI if available
            if let roiRect = appState.roiRect, !appState.isSelectingROI {
                Rectangle()
                    .stroke(Color.orange, lineWidth: 3)
                    .background(Color.orange.opacity(0.1))
                    .frame(width: roiRect.width, height: roiRect.height)
                    .position(x: roiRect.midX, y: roiRect.midY)
                
                // ROI label
                Text("ROI (Applied to All Frames)")
                    .font(.caption)
                    .fontWeight(.bold)
                    .padding(6)
                    .background(Color.orange)
                    .foregroundColor(.white)
                    .cornerRadius(4)
                    .position(x: roiRect.midX, y: roiRect.minY - 15)
            }
            
            // Instructions overlay
            if appState.isSelectingROI {
                VStack {
                    Text("Select Region of Interest")
                        .font(.headline)
                        .fontWeight(.bold)
                        .padding(.bottom, 4)
                    
                    Text("Draw a rectangle around the person to focus on")
                        .font(.subheadline)
                    
                    Text("This ROI will be applied to all frames in the video")
                        .font(.caption)
                        .foregroundColor(.orange)
                }
                .padding()
                .background(Color.black.opacity(0.8))
                .foregroundColor(.white)
                .cornerRadius(12)
                .position(x: containerSize.width / 2, y: 80)
            }
        }
        .allowsHitTesting(appState.isSelectingROI)
        .gesture(
            DragGesture(minimumDistance: 0)
                .onChanged { value in
                    if !isDragging {
                        startPoint = value.startLocation
                        isDragging = true
                    }
                    currentPoint = value.location
                }
                .onEnded { value in
                    if isDragging {
                        let displayRect = CGRect(
                            x: min(startPoint.x, currentPoint.x),
                            y: min(startPoint.y, currentPoint.y),
                            width: abs(currentPoint.x - startPoint.x),
                            height: abs(currentPoint.y - startPoint.y)
                        )
                        
                        // Only set ROI if the rectangle is large enough
                        if displayRect.width > 50 && displayRect.height > 50 {
                            // Convert display coordinates to image coordinates
                            let imageRect = convertDisplayRectToImageRect(
                                displayRect: displayRect,
                                containerSize: containerSize,
                                imageSize: imageSize
                            )
                            
                            appState.setROI(displayRect, imageCoordinates: imageRect)
                        } else {
                            appState.disableROIMode()
                        }
                        
                        isDragging = false
                    }
                }
        )
    }
    
    // Convert display rectangle to image coordinates
    private func convertDisplayRectToImageRect(
        displayRect: CGRect,
        containerSize: CGSize,
        imageSize: CGSize
    ) -> CGRect {
        // Calculate the actual display size of the image within the container
        let imageAspectRatio = imageSize.width / imageSize.height
        let containerAspectRatio = containerSize.width / containerSize.height
        
        var displaySize: CGSize
        var offsetX: CGFloat = 0
        var offsetY: CGFloat = 0
        
        if imageAspectRatio > containerAspectRatio {
            // Image is wider than container - fit to width
            displaySize = CGSize(
                width: containerSize.width,
                height: containerSize.width / imageAspectRatio
            )
            offsetY = (containerSize.height - displaySize.height) / 2
        } else {
            // Image is taller than container - fit to height
            displaySize = CGSize(
                width: containerSize.height * imageAspectRatio,
                height: containerSize.height
            )
            offsetX = (containerSize.width - displaySize.width) / 2
        }
        
        // Convert display coordinates to image coordinates
        let scaleX = imageSize.width / displaySize.width
        let scaleY = imageSize.height / displaySize.height
        
        return CGRect(
            x: (displayRect.origin.x - offsetX) * scaleX,
            y: (displayRect.origin.y - offsetY) * scaleY,
            width: displayRect.width * scaleX,
            height: displayRect.height * scaleY
        )
    }
}



func transformPoint(x: CGFloat, y: CGFloat, containerSize: CGSize, imageSize: CGSize, rotation: Int) -> CGPoint {
    // Calculate the actual display size of the image within the container
    let imageAspectRatio = imageSize.width / imageSize.height
    let containerAspectRatio = containerSize.width / containerSize.height
    
    var displaySize: CGSize
    
    if imageAspectRatio > containerAspectRatio {
        // Image is wider than container - fit to width
        displaySize = CGSize(
            width: containerSize.width,
            height: containerSize.width / imageAspectRatio
        )
    } else {
        // Image is taller than container - fit to height
        displaySize = CGSize(
            width: containerSize.height * imageAspectRatio,
            height: containerSize.height
        )
    }
    
    // Calculate offset to center the image
    let offsetX = (containerSize.width - displaySize.width) / 2
    let offsetY = (containerSize.height - displaySize.height) / 2
    
    // Convert keypoint coordinates to display coordinates
    var displayX = (x / imageSize.width) * displaySize.width + offsetX
    var displayY = (y / imageSize.height) * displaySize.height + offsetY
    
    // Apply rotation if needed
    if rotation != 0 {
        let centerX = containerSize.width / 2
        let centerY = containerSize.height / 2
        
        // Translate to origin
        displayX -= centerX
        displayY -= centerY
        
        // Apply rotation using CGAffineTransform (cleaner approach)
        let transform = CGAffineTransform(rotationAngle: CGFloat(rotation) * CGFloat.pi / 2)
        let rotatedPoint = CGPoint(x: displayX, y: displayY).applying(transform)
        
        // Translate back
        displayX = rotatedPoint.x + centerX
        displayY = rotatedPoint.y + centerY
    }
    
    return CGPoint(x: displayX, y: displayY)
}

// MARK: - Simplified updateDisplayWithKeypoints method for BESTGYMPoseApp

// MARK: - Fixed Coordinate Transformation
//private func transformPoint(x: CGFloat, y: CGFloat, containerSize: CGSize, imageSize: CGSize, rotation: Int) -> CGPoint {
//    // Calculate the actual display size of the image within the container
//    let imageAspectRatio = imageSize.width / imageSize.height
//    let containerAspectRatio = containerSize.width / containerSize.height
//    
//    var displaySize: CGSize
//    
//    if imageAspectRatio > containerAspectRatio {
//        // Image is wider than container - fit to width
//        displaySize = CGSize(
//            width: containerSize.width,
//            height: containerSize.width / imageAspectRatio
//        )
//    } else {
//        // Image is taller than container - fit to height
//        displaySize = CGSize(
//            width: containerSize.height * imageAspectRatio,
//            height: containerSize.height
//        )
//    }
//    
//    // Calculate offset to center the image
//    let offsetX = (containerSize.width - displaySize.width) / 2
//    let offsetY = (containerSize.height - displaySize.height) / 2
//    
//    // Convert keypoint coordinates to display coordinates
//    var displayX = (x / imageSize.width) * displaySize.width + offsetX
//    var displayY = (y / imageSize.height) * displaySize.height + offsetY
//    
//    // Apply rotation if needed
//    if rotation != 0 {
//        let centerX = containerSize.width / 2
//        let centerY = containerSize.height / 2
//        
//        // Translate to origin
//        displayX -= centerX
//        displayY -= centerY
//        
//        // Apply rotation
//        let angle = Double(rotation) * .pi / 2
//        let rotatedX = displayX * cos(angle) - displayY * sin(angle)
//        let rotatedY = displayX * sin(angle) + displayY * cos(angle)
//        
//        // Translate back
//        displayX = rotatedX + centerX
//        displayY = rotatedY + centerY
//    }
//    
//    return CGPoint(x: displayX, y: displayY)
//}
