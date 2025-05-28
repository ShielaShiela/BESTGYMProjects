import SwiftUI
import AVFoundation
import Photos
import PhotosUI
import Foundation

enum FileAccessError: LocalizedError {
    case fileNotFound
    case accessDenied
    case unsupportedFormat(String)
    
    var errorDescription: String? {
        switch self {
        case .fileNotFound:
            return "The selected file or folder could not be found."
        case .accessDenied:
            return "Access to the selected file or folder was denied."
        case .unsupportedFormat(let format):
            return "Unsupported file format: \(format)"
        }
    }
}

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
                
                // Processing overlay
                if appState.isProcessing {
                    ProcessingOverlay(status: appState.processingStatus)
                }
                
                // Error overlay
                if let error = appState.errorMessage {
                    ErrorOverlay(message: error) {
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
                DocumentPicker { urls in
                    if let url = urls.first {
                        loadData(from: url)
                    }
                }
            }
            .sheet(isPresented: $appState.isVideoPickerPresented) {
                VideoFilePicker { url in
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
                KeypointDocumentPicker { url in
                    loadKeypointFile(url)
                }
            }
            .sheet(isPresented: $appState.showAnalysisView) {
                KeypointAnalysisView(
                    poseProcessor: appState.poseProcessor,
                    currentFrameIndex: cameraManager.currentFrameIndex,
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
            .onReceive(NotificationCenter.default.publisher(for: UIApplication.willResignActiveNotification)) { _ in
               print("App will resign active - keeping folder access alive")
               // Don't clean up resources when app goes to background
               // This allows continued access when returning to the app
           }
           .onReceive(NotificationCenter.default.publisher(for: UIApplication.didBecomeActiveNotification)) { _ in
               print("App did become active")
               // Resources should still be accessible
           }
           .onReceive(NotificationCenter.default.publisher(for: UIApplication.willTerminateNotification)) { _ in
               print("App will terminate - cleaning up all resources")
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
    
//    private func setupPlaybackHandler() {
//        cameraManager.onFrameChange = { index in
//            // Update UI based on current frame
//            if appState.showKeypoints {
//                self.updateDisplayWithKeypoints(for: index)
//            }
//        }
//    }
    
//    private func loadData(from url: URL) {
//        appState.isProcessing = true
//        appState.processingStatus = "Loading data..."
//        
//        // First check if it's a directory or file
//        let fileManager = FileManager.default
//        var isDirectory: ObjCBool = false
//        
//        if fileManager.fileExists(atPath: url.path, isDirectory: &isDirectory) {
//            if isDirectory.boolValue {
//                // It's a folder - could be LiDAR data or folder with video
//                loadDataFromFolder(url)
//            } else {
//                // It's a file - check extension
//                let fileExtension = url.pathExtension.lowercased()
//                
//                if fileExtension == "json" {
//                    // It's a keypoint file
//                    loadKeypointFile(url)
//                } else if ["mp4", "mov", "m4v"].contains(fileExtension) {
//                    // It's a video file
//                    loadVideo(from: url)
//                } else {
//                    // Unknown file type
//                    DispatchQueue.main.async {
//                        self.appState.isProcessing = false
//                        self.appState.errorMessage = "Unsupported file format: \(fileExtension)"
//                    }
//                }
//            }
//        } else {
//            // File or folder doesn't exist
//            DispatchQueue.main.async {
//                self.appState.isProcessing = false
//                self.appState.errorMessage = "Selected file or folder doesn't exist"
//            }
//        }
//    }

    
    // MARK: - Enhanced loadVideo function with automatic keypoint detection
//    private func loadVideo(from url: URL) {
//        appState.isProcessing = true
//        appState.processingStatus = "Loading video..."
//        appState.isVideoSource = true
//        
//        // Reset keypoint-related states
//        appState.hasImportedKeypoints = false
//        appState.showKeypoints = false
//        
//        print("Loading video from: \(url.path)")
//        
//        // Check if this is a recording folder rather than a direct video file
//        var isFolder = false
//        do {
//            let resourceValues = try url.resourceValues(forKeys: [.isDirectoryKey])
//            isFolder = resourceValues.isDirectory ?? false
//        } catch {
//            print("Error checking if URL is directory: \(error)")
//        }
//        
//        if isFolder {
//            print("Loading as a recording folder")
//            loadDataFromFolder(url)
//        } else {
//            // Load as a direct video file
//            cameraManager.loadVideoFile(url) { success, totalFrames, error in
//                DispatchQueue.main.async {
//                    self.appState.isProcessing = false
//                    
//                    if success {
//                        self.appState.processingStatus = "Video loaded with \(totalFrames) frames"
//                        self.appState.sourceFileName = url.lastPathComponent
//                        self.appState.sourceURL = url
//                        
//                        // ✅ AUTOMATICALLY CHECK FOR KEYPOINT FILES
//                        DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
//                            self.checkForAssociatedKeypointFile(videoURL: url)
//                        }
//                    } else if let error = error {
//                        self.appState.errorMessage = "Failed to load video: \(error)"
//                    }
//                }
//            }
//        }
//    }

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

    // MARK: - Enhanced loadDataFromFolder to also check for keypoints
//    private func loadDataFromFolder(_ url: URL) {
//        appState.isVideoSource = false
//        appState.processingStatus = "Loading data from folder..."
//        
//        DispatchQueue.global(qos: .userInitiated).async {
//            do {
//                let fileManager = FileManager.default
//                
//                // Start accessing the security-scoped resource if needed
//                let shouldStopAccessing = url.startAccessingSecurityScopedResource()
//                defer {
//                    if shouldStopAccessing {
//                        url.stopAccessingSecurityScopedResource()
//                    }
//                }
//                
//                // Get all items in the folder
//                let contents = try fileManager.contentsOfDirectory(
//                    at: url,
//                    includingPropertiesForKeys: [.isDirectoryKey],
//                    options: [.skipsHiddenFiles]
//                )
//                
//                print("Found \(contents.count) items in folder \(url.lastPathComponent)")
//                
//                // Check for video files
//                let videoFiles = contents.filter {
//                    ["mp4", "mov", "m4v"].contains($0.pathExtension.lowercased())
//                }
//                
//                // Check for keypoint files IN THE SAME FOLDER
//                let keypointFiles = contents.filter {
//                    let filename = $0.lastPathComponent.lowercased()
//                    return $0.pathExtension.lowercased() == "json" &&
//                           (filename.contains("keypoint") || filename.contains("pose"))
//                }
//                
//                // Check for frame directories (LiDAR recording)
//                let frameDirectories = contents.filter {
//                    var isDir: ObjCBool = false
//                    return fileManager.fileExists(atPath: $0.path, isDirectory: &isDir) &&
//                           isDir.boolValue &&
//                           $0.lastPathComponent.hasPrefix("frame_")
//                }
//                
//                // Check for direct depth data files
//                let hasDepthData = contents.contains { $0.lastPathComponent == "depthData.dat" }
//                let hasMetadata = contents.contains { $0.lastPathComponent == "recording_metadata.json" }
//                
//                // Process based on folder content
//                if !videoFiles.isEmpty {
//                    // Found video file(s) - load video and check for keypoints
//                    let videoURL = videoFiles.first!
//                    print("Loading video from folder: \(videoURL.path)")
//                    
//                    DispatchQueue.main.async {
//                        // Set video info
//                        self.appState.sourceFileName = videoURL.lastPathComponent
//                        self.appState.sourceURL = url // Keep folder as source URL
//                        
//                        // Load video
//                        self.cameraManager.loadVideoFile(videoURL) { success, totalFrames, error in
//                            DispatchQueue.main.async {
//                                self.appState.isProcessing = false
//                                
//                                if success {
//                                    self.appState.processingStatus = "Video loaded with \(totalFrames) frames"
//                                    self.appState.isVideoSource = true
//                                    
//                                    // ✅ CHECK FOR KEYPOINTS IN THE SAME FOLDER
//                                    if !keypointFiles.isEmpty {
//                                        let keypointURL = keypointFiles.first!
//                                        print("📁 Found keypoint file in folder: \(keypointURL.lastPathComponent)")
//                                        
//                                        DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
//                                            self.appState.processingStatus = "Loading keypoints from folder..."
//                                            self.loadKeypointFile(keypointURL)
//                                        }
//                                    } else {
//                                        // No keypoints in folder, check if auto-detect is enabled
//                                        DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
//                                            if self.appState.autoDetectKeypoints {
//                                                self.appState.processingStatus = "Auto-detecting poses..."
//                                                self.processData()
//                                            } else {
//                                                self.appState.processingStatus = "Video loaded. Select 'Detect Pose' to analyze."
//                                            }
//                                        }
//                                    }
//                                } else if let error = error {
//                                    self.appState.errorMessage = "Failed to load video: \(error)"
//                                }
//                            }
//                        }
//                    }
//                } else if !frameDirectories.isEmpty {
//                    // LiDAR recording with frame folders
//                    print("Loading as LiDAR frame folder with \(frameDirectories.count) frames")
//                    
//                    self.cameraManager.loadVideoFolder(from: url)
//                    
//                    DispatchQueue.main.async {
//                        self.appState.processingStatus = "Loaded \(self.cameraManager.totalFrames) frames from \(url.lastPathComponent)"
//                        self.appState.sourceFileName = url.lastPathComponent
//                        self.appState.sourceURL = url
//                        self.appState.isProcessing = false
//                        
//                        // ✅ CHECK FOR KEYPOINTS IN LIDAR FOLDER TOO
//                        if !keypointFiles.isEmpty {
//                            let keypointURL = keypointFiles.first!
//                            print("📁 Found keypoint file in LiDAR folder: \(keypointURL.lastPathComponent)")
//                            
//                            DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
//                                self.loadKeypointFile(keypointURL)
//                            }
//                        }
//                    }
//                } else if hasDepthData {
//                    // Direct LiDAR data files
//                    print("Loading as LiDAR depth data")
//                    
//                    if let device = MTLCreateSystemDefaultDevice() {
//                        self.cameraManager.loadCapturedData(from: url, device: device)
//                        
//                        DispatchQueue.main.async {
//                            self.appState.processingStatus = "Loaded depth data from \(url.lastPathComponent)"
//                            self.appState.sourceFileName = url.lastPathComponent
//                            self.appState.sourceURL = url
//                            self.appState.isProcessing = false
//                        }
//                    } else {
//                        DispatchQueue.main.async {
//                            self.appState.errorMessage = "Metal is not available on this device"
//                            self.appState.isProcessing = false
//                        }
//                    }
//                } else {
//                    // Unknown folder structure
//                    DispatchQueue.main.async {
//                        self.appState.errorMessage = "Could not identify folder content type"
//                        self.appState.isProcessing = false
//                        print("Error: Folder does not contain recognized data: \(url.path)")
//                    }
//                }
//            } catch {
//                DispatchQueue.main.async {
//                    self.appState.errorMessage = "Failed to load data: \(error.localizedDescription)"
//                    self.appState.isProcessing = false
//                    print("Error loading folder: \(error)")
//                }
//            }
//        }
//    }

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
    
//    private func loadKeypointFile(_ url: URL) {
//        appState.isProcessing = true
//        appState.processingStatus = "Loading keypoints..."
//        
//        // Load keypoints into pose processor
//        appState.poseProcessor.loadKeypoints(from: url) { success, frameCount, error in
//            DispatchQueue.main.async {
//                appState.isProcessing = false
//                
//                if success {
//                    // Set flags to indicate we have keypoints
//                    appState.hasImportedKeypoints = true
//                    appState.showKeypoints = true  // Automatically show keypoints
//                    appState.processingStatus = "Loaded keypoints for \(frameCount) frames"
//                    appState.originalKeypointFileURL = url
//                    
//                    // Update sourceFileName for proper display in UI
//                    appState.sourceFileName = url.lastPathComponent
//                    
//                    // Validate the loaded keypoints
//                    if !appState.poseProcessor.validateLoadedKeypoints() {
//                        appState.processingStatus = "Warning: Keypoint data may be invalid"
//                    }
//                    
//                    // Update UI to show first frame with keypoints
//                    if frameCount > 0 {
//                        cameraManager.currentFrameIndex = 0
//                        DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
//                            self.updateDisplayWithKeypoints(for: 0)
//                        }
//                    }
//                } else if let error = error {
//                    appState.errorMessage = "Failed to load keypoints: \(error)"
//                }
//            }
//        }
//    }
//    
//    
    private func autoLoadDefaultData() {
        // Implementation for auto-loading default data
        // This would depend on your specific requirements
    }
    
//    private func processData() {
//        DispatchQueue.main.async {
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
//            self.appState.isProcessing = true
//            
//            // Update status based on ROI
//            if self.appState.hasROI {
//                self.appState.processingStatus = "Preparing ROI-based pose detection for all frames..."
//            } else {
//                self.appState.processingStatus = "Preparing pose detection for all frames..."
//            }
//            
//            print("Beginning pose detection on \(self.cameraManager.totalFrames) frames")
//            if self.appState.hasROI {
//                print("Using ROI: \(self.appState.roiImageCoordinates!)")
//            }
//            
//            DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
//                let statusText = self.appState.hasROI ?
//                    "Detecting poses in ROI across \(self.cameraManager.totalFrames) frames..." :
//                    "Detecting poses across \(self.cameraManager.totalFrames) frames..."
//                
//                self.appState.processingStatus = statusText
//                
//                // Pass ROI information to the pose processor
//                if let roiImageCoordinates = self.appState.roiImageCoordinates {
//                    self.appState.poseProcessor.setROI(roiImageCoordinates)
//                } else {
//                    self.appState.poseProcessor.clearROI()
//                }
//                
//                self.appState.poseProcessor.processFrames(from: self.cameraManager) { progressValue in
//                    let percentage = Int(progressValue * 100)
//                    let statusText = self.appState.hasROI ?
//                        "Processing ROI frames: \(percentage)%" :
//                        "Processing frames: \(percentage)%"
//                    self.appState.processingStatus = statusText
//                } completion: { success, error in
//                    self.appState.isProcessing = false
//                    
//                    if success {
//                        self.finishPoseDetection()
//                    } else if let processingError = error {
//                        self.appState.errorMessage = "Processing failed: \(processingError.localizedDescription)"
//                        print("Pose detection error: \(processingError)")
//                    }
//                }
//            }
//        }
//    }

    
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
//    private func switchToAnalysisMode() {
//        if appState.isRecordMode {
//            appState.isRecordMode = false
//            if cameraManager.isRecording {
//                cameraManager.stopRecording { _ in }
//            }
//            
//            // Stop camera stream on background thread
//            DispatchQueue.global(qos: .userInitiated).async {
//                self.cameraManager.pauseStream()
//            }
//            
//            // Reset states before loading new file
//            appState.resetFileAndKeypointState()
//            appState.resetStatusState()
//        }
//    }
    
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
    
    private func loadData(from url: URL) {
        // Clean up any previous folder access
        cleanupPreviousFolderAccess()
        
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

    // Helper method to clean up previous folder access when switching
    private func cleanupPreviousFolderAccess() {
        if let previousURL = appState.sourceURL {
            SecurityScopedResourceManager.shared.stopAccessing(previousURL)
        }
    }

    // Enhanced loadVideo method
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
            // Load as a direct video file
            cameraManager.loadVideoFile(url) { success, totalFrames, error in
                DispatchQueue.main.async {
                    self.appState.isProcessing = false
                    
                    if success {
                        self.appState.processingStatus = "Video loaded with \(totalFrames) frames"
                        self.appState.sourceFileName = url.lastPathComponent
                        self.appState.sourceURL = url
                        
                        // Check for associated keypoint files
                        DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
                            self.checkForAssociatedKeypointFile(videoURL: url)
                        }
                    } else if let error = error {
                        self.appState.errorMessage = "Failed to load video: \(error)"
                    }
                }
            }
        }
    }

    // Enhanced loadKeypointFile method
    private func loadKeypointFile(_ url: URL) {
        appState.isProcessing = true
        appState.processingStatus = "Loading keypoints..."
        
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
                    self.appState.processingStatus = "Loaded keypoints for \(frameCount) frames"
                    self.appState.originalKeypointFileURL = url
                    
                    // Only update sourceFileName if we don't have a video source
                    if self.appState.sourceFileName.isEmpty {
                        self.appState.sourceFileName = url.lastPathComponent
                    }
                    
                    // Validate the loaded keypoints
                    if !self.appState.poseProcessor.validateLoadedKeypoints() {
                        self.appState.processingStatus = "Warning: Keypoint data may be invalid"
                    }
                    
                    // Update UI to show first frame with keypoints
                    if frameCount > 0 {
                        self.cameraManager.currentFrameIndex = 0
                        DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
                            self.updateDisplayWithKeypoints(for: 0)
                        }
                    }
                } else if let error = error {
                    self.appState.errorMessage = "Failed to load keypoints: \(error)"
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
                
                print("Found \(contents.count) items in folder \(folderURL.lastPathComponent)")
                
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
                    print("Loading video from folder: \(videoURL.path)")
                    
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
                                        print("📁 Found keypoint file in folder: \(keypointURL.lastPathComponent)")
                                        
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
                                    self.appState.errorMessage = "Failed to load video: \(error)"
                                    self.appState.isProcessing = false
                                }
                            }
                        }
                    }
                } else if !frameDirectories.isEmpty {
                    // LiDAR recording with frame folders
                    print("Loading as LiDAR frame folder with \(frameDirectories.count) frames")
                    
                    self.cameraManager.loadVideoFolder(from: folderURL)
                    
                    DispatchQueue.main.async {
                        self.appState.processingStatus = "Loaded \(self.cameraManager.totalFrames) frames from \(folderURL.lastPathComponent)"
                        self.appState.sourceFileName = folderURL.lastPathComponent
                        self.appState.sourceURL = folderURL
                        self.appState.isProcessing = false
                        
                        // Check for keypoints in LiDAR folder
                        if !keypointFiles.isEmpty {
                            let keypointURL = keypointFiles.first!
                            print("📁 Found keypoint file in LiDAR folder: \(keypointURL.lastPathComponent)")
                            
                            DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
                                self.loadKeypointFile(keypointURL)
                            }
                        }
                    }
                } else if hasDepthData {
                    // Direct LiDAR data files
                    print("Loading as LiDAR depth data")
                    
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
                        print("Error: Folder does not contain recognized data: \(folderURL.path)")
                    }
                }
                
                // Don't stop folder access here - let it stay alive for continued use
                // It will be cleaned up when switching to a different folder or app lifecycle events
                
            } catch {
                DispatchQueue.main.async {
                    self.appState.errorMessage = "Failed to load data: \(error.localizedDescription)"
                    self.appState.isProcessing = false
                    print("Error loading folder: \(error)")
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
            cleanupPreviousFolderAccess()
            
            // Reset states before loading new file
            appState.resetFileAndKeypointState()
            appState.resetStatusState()
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
                .onChange(of: appState.isRecordMode) { newValue in
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
struct SettingsView: View {
    @ObservedObject var appState: AppState
    @Environment(\.presentationMode) var presentationMode
    
    var body: some View {
        NavigationView {
            Form {
                Section(header: Text("Analysis Options")) {
                    Toggle("Auto-detect keypoints when loading video", isOn: $appState.autoDetectKeypoints)
                        .onChange(of: appState.autoDetectKeypoints) { _ in
                            appState.saveUserPreferences()
                        }
                }
                
                Section(header: Text("Media Settings")) {
                    Toggle("Auto-load default data on startup", isOn: .constant(UserDefaults.standard.bool(forKey: "AutoLoadEnabled")))
                        .onChange(of: UserDefaults.standard.bool(forKey: "AutoLoadEnabled")) { newValue in
                            UserDefaults.standard.set(newValue, forKey: "AutoLoadEnabled")
                        }
                    // Add more settings as needed
                }
            }
            .navigationTitle("Settings")
            .navigationBarItems(trailing: Button("Done") {
                presentationMode.wrappedValue.dismiss()
            })
        }
    }
}
struct VideoFormat {
    let width: Int
    let height: Int
    let fps: Int
}

struct VideoSettings {
    var selectedFormat: VideoFormat
    
    static let defaultSettings = VideoSettings(
        selectedFormat: VideoFormat(width: 1920, height: 1080, fps: 30)
    )
}

//MARK: - Main Content View
import SwiftUI

struct MainContentView: View {
    @ObservedObject var appState: AppState
    @ObservedObject var cameraManager: CameraLiDARManager
    
    var body: some View {
        VStack(spacing: 0) {
            // Main display area
            ZStack {
                // Background Color for the ZStack
                Color.black
                    .edgesIgnoringSafeArea(.bottom)
                
                // --- Content Views based on mode ---
                if appState.isRecordMode {
                    // RECORD MODE: Camera Preview with Capture Button
                    recordModeContent
                } else {
                    // ANALYSIS MODE: Frame viewer or placeholder
                    analysisModeContent
                }
            }
            .cornerRadius(appState.isRecordMode ? 0 : 8)
            .padding(.horizontal, appState.isRecordMode ? 0 : 16)
            
            // Playback controls (hide in record mode)
            if !appState.isRecordMode {
                if cameraManager.totalFrames > 0 && !appState.isProcessing && !cameraManager.isRecording {
                    PlaybackControlView(
                        cameraManager: cameraManager,
                        totalFrames: cameraManager.totalFrames
                    )
                    .padding()
                }
                
                // Analysis button
                if cameraManager.totalFrames > 0 && appState.poseProcessor.hasKeypoints(for: cameraManager.currentFrameIndex) {
                    Button(action: {
                        appState.showAnalysisView = true
                    }) {
                        Text("Show Analysis")
                            .font(.headline)
                            .padding(.horizontal, 16)
                            .padding(.vertical, 12)
                            .background(Color.blue)
                            .foregroundColor(.white)
                            .cornerRadius(8)
                    }
                    .padding(.bottom)
                }
            }
        }
    }
    
    // MARK: - Mode-Specific Content
    
    private var recordModeContent: some View {
        ZStack {
            // Live camera view
            CameraPreviewView(cameraManager: cameraManager)
                .edgesIgnoringSafeArea(.all)
                .overlay(alignment: .topTrailing) {
                // LiDAR Toggle
                HStack {
                    Text("LiDAR")
                        .foregroundColor(.white)
                        .font(.caption)
                    Toggle("", isOn: $appState.useLiDAR)
                        .labelsHidden()
                        .toggleStyle(SwitchToggleStyle(tint: .blue))
                }
                .padding(.horizontal, 8)
                .padding(.vertical, 4)
                .background(Color.black.opacity(0.5))
                .cornerRadius(8)
                .padding(.top, 10)
                .padding(.trailing, 10)
                }
               .onAppear {
                   // Start center depth detection when view appears
                   cameraManager.startCenterDepthDetection()
               }
               .onDisappear {
                   // Stop depth detection when view disappears
                   cameraManager.stopCenterDepthDetection()
               }
                
                    // Depth center overlay - new code
                       if let depthValue = cameraManager.centerDepthValue {
                           VStack {
                               Spacer()
                               
                               // Centered depth indicator with crosshair
                               VStack(spacing: 4) {
                                   // Crosshair
                                   ZStack {
                                       Circle()
                                           .stroke(Color.white, lineWidth: 1)
                                           .frame(width: 30, height: 30)
                                       
                                       // Crosshair lines
                                       Group {
                                           Rectangle()
                                               .fill(Color.white)
                                               .frame(width: 20, height: 1)
                                           
                                           Rectangle()
                                               .fill(Color.white)
                                               .frame(width: 1, height: 20)
                                       }
                                   }
                                   
                                   // Depth value display
                                   Text("\(String(format: "%.2f", depthValue))m")
                                       .font(.system(size: 14, weight: .bold, design: .monospaced))
                                       .foregroundColor(.white)
                                       .padding(.horizontal, 8)
                                       .padding(.vertical, 4)
                                       .background(Color.black.opacity(0.6))
                                       .cornerRadius(4)
                               }
                               .padding(.bottom, 80) // Position above record button
                               
                               Spacer()
                           }
                       }
            
        
            // Capture button overlay
            VStack {
                Spacer()
                captureButton()
                    .padding(.bottom, 30)
            }
        }
    }
    
//    private var analysisModeContent: some View {
//        ZStack {
//            if appState.showKeypoints,
//               let keypoints = appState.poseProcessor.getKeypoints(for: cameraManager.currentFrameIndex),
//               !keypoints.isEmpty {
//                
//                GeometryReader { geometry in
//                    ZStack {
//                        ForEach(keypoints) { keypoint in
//                            Circle()
//                                .fill(Color.red)
//                                .frame(width: 20, height: 20)
//                                .position(
//                                    x: keypoint.x * (geometry.size.width / 1920),
//                                    y: keypoint.y * (geometry.size.height / 1440)
//                                )
//                        }
//                    }
//                }
//            }
//           
//            if cameraManager.totalFrames > 0 {
//                // Display loaded frame with optional keypoint overlay
//                FrameView(
//                    image: cameraManager.currentFrameImage,
//                    keypoints: appState.showKeypoints ? appState.poseProcessor.getKeypoints(for: cameraManager.currentFrameIndex) : nil,
//                    isAnnotationMode: appState.isAnnotationMode,
//                    rotation: appState.imageRotation,
//                    selectedKeypointIndex: $appState.selectedKeypointIndex
//                )
//                .overlay(
//                    // Add rotation controls overlay
//                    VStack {
//                        Spacer()
//                        HStack {
//                            // Counter-clockwise rotation
//                            Button(action: {
//                                appState.rotateImageCounterClockwise()
//                            }) {
//                                Image(systemName: "rotate.left")
//                                    .font(.title)
//                                    .foregroundColor(.white)
//                                    .padding(12)
//                                    .background(Color.black.opacity(0.6))
//                                    .clipShape(Circle())
//                            }
//                            .padding()
//                            
//                            Spacer()
//                            
//                            // Clockwise rotation
//                            Button(action: {
//                                appState.rotateImageClockwise()
//                            }) {
//                                Image(systemName: "rotate.right")
//                                    .font(.title)
//                                    .foregroundColor(.white)
//                                    .padding(12)
//                                    .background(Color.black.opacity(0.6))
//                                    .clipShape(Circle())
//                            }
//                            .padding()
//                        }
//                        .padding(.bottom, 20)
//                    }
//                )
//            } else {
//                // No content placeholder
//                VStack(spacing: 20) {
//                    Text("No File Selected")
//                        .font(.title2)
//                        .multilineTextAlignment(.center)
//                        .foregroundColor(.secondary)
//                    
//                    Image(systemName: "folder.fill")
//                        .font(.system(size: 50))
//                        .foregroundColor(.secondary)
//                    
//                    Text("Open a file or video to analyze")
//                        .font(.body)
//                        .foregroundColor(.secondary)
//                        .padding(.top, 10)
//                        
//                    Button(action: {
//                        // Show file picker
//                        appState.isFilePickerPresented = true
//                    }) {
//                        Text("Select File")
//                            .font(.headline)
//                            .padding()
//                            .background(Color.blue)
//                            .foregroundColor(.white)
//                            .cornerRadius(8)
//                    }
//                    .padding(.top, 20)
//                }
//                .frame(maxWidth: .infinity, maxHeight: .infinity)
//                .background(Color(.systemGray6))
//            }
//        }
//    }
    private var analysisModeContent: some View {
        ZStack {
            if cameraManager.totalFrames > 0 {
                // Display loaded frame with keypoint overlay and ROI support
                FrameView(
                    image: cameraManager.currentFrameImage,
                    keypoints: appState.showKeypoints ? appState.poseProcessor.getKeypoints(for: cameraManager.currentFrameIndex) : nil,
                    isAnnotationMode: appState.isAnnotationMode,
                    rotation: appState.imageRotation,
                    appState: appState,
                    selectedKeypointIndex: $appState.selectedKeypointIndex
                )
                .overlay(
                    // Debug info overlay
                    VStack {
                        HStack {
                            Text("Frame: \(cameraManager.currentFrameIndex + 1)/\(cameraManager.totalFrames)")
                                .padding(6)
                                .background(Color.black.opacity(0.7))
                                .foregroundColor(.white)
                                .cornerRadius(4)
                            
                            if appState.hasROI {
                                Text("ROI Applied to All Frames")
                                    .padding(6)
                                    .background(Color.orange.opacity(0.8))
                                    .foregroundColor(.white)
                                    .cornerRadius(4)
                            }
                            
                            Spacer()
                            
                            if let keypoints = appState.poseProcessor.getKeypoints(for: cameraManager.currentFrameIndex) {
                                Text("Keypoints: \(keypoints.count)")
                                    .padding(6)
                                    .background(appState.showKeypoints ? Color.green : Color.red)
                                    .foregroundColor(.white)
                                    .cornerRadius(4)
                            }
                        }
                        .padding(.horizontal)
                        .padding(.top, 8)
                        
                        Spacer()
                    }
                )
            } else {
                // No content placeholder
                VStack(spacing: 20) {
                    Text("No File Selected")
                        .font(.title2)
                        .multilineTextAlignment(.center)
                        .foregroundColor(.secondary)
                    
                    Image(systemName: "folder.fill")
                        .font(.system(size: 50))
                        .foregroundColor(.secondary)
                    
                    Text("Open a file or video to analyze")
                        .font(.body)
                        .foregroundColor(.secondary)
                        .padding(.top, 10)
                        
                    Button(action: {
                        appState.isFilePickerPresented = true
                    }) {
                        Text("Select File")
                            .font(.headline)
                            .padding()
                            .background(Color.blue)
                            .foregroundColor(.white)
                            .cornerRadius(8)
                    }
                    .padding(.top, 20)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .background(Color(.systemGray6))
            }
        }
    }

    
    @ViewBuilder
    private func captureButton() -> some View {
        Button(action: toggleRecording) {
            ZStack {
                // Outer ring
                Circle()
                    .strokeBorder(Color.white, lineWidth: 4)
                    .frame(width: 70, height: 70)
                
                // Inner circle (changes color/shape when recording)
                Circle()
                    .fill(cameraManager.isRecording ? Color.red : Color.white)
                    .frame(width: cameraManager.isRecording ? 35 : 58, height: cameraManager.isRecording ? 35 : 58)
                    .animation(.spring(response: 0.3, dampingFraction: 0.6), value: cameraManager.isRecording)
            }
        }
        .disabled(appState.isProcessing)
    }
    
    private func toggleRecording() {
        if cameraManager.isRecording {
            // Stop Recording
            print("Stopping recording...")
            if appState.useLiDAR {
                cameraManager.stopVideoRecording { url in
                    if let url = url {
                        print("LiDAR recording saved to: \(url.path)")
                        
                        // Post notification with the URL for the main app to handle
                        NotificationCenter.default.post(
                            name: Notification.Name("RecordingFinished"),
                            object: url
                        )
                    } else {
                        appState.errorMessage = "Failed to save LiDAR recording."
                    }
                }
            } else {
                cameraManager.stopRecording { url in
                    if let url = url {
                        print("Standard recording saved to: \(url.path)")
                        
                        // Post notification with the URL for the main app to handle
                        NotificationCenter.default.post(
                            name: Notification.Name("RecordingFinished"),
                            object: url
                        )
                    } else {
                        appState.errorMessage = "Failed to save recording."
                    }
                }
            }
        } else {
            // Start Recording - do focus locking on background thread
            DispatchQueue.global(qos: .userInitiated).async {
                // Set fixed focus before starting recording
                self.cameraManager.setFixedFocus()
                
                DispatchQueue.main.async {
                    print("Starting recording...")
                    // Start Recording based on LiDAR toggle
                    if self.appState.useLiDAR {
                        // Start LiDAR video recording with athlete info and distance
                        self.cameraManager.startVideoRecording(
                            personName: self.appState.athleteName.isEmpty ? "Test" : self.appState.athleteName,
                            action: self.appState.actionType.isEmpty ? "Test" : self.appState.actionType,
                            distance: self.appState.distanceValue ?? "Test"
                        )
                    } else {
                        // Start standard video recording with the same athlete info (no distance)
                        self.cameraManager.startRecording(
                            personName: self.appState.athleteName.isEmpty ? "Test" : self.appState.athleteName,
                            action: self.appState.actionType.isEmpty ? "Test" : self.appState.actionType
                        )
                    }
                }
            }
        }
    }
}

// MARK: - Playback Control View
struct PlaybackControlView: View {
    @ObservedObject var cameraManager: CameraLiDARManager
    let totalFrames: Int
    @State private var isPlaying = false
    
    var body: some View {
        VStack(spacing: 8) {
            // Frame counter
            Text("Frame \(cameraManager.currentFrameIndex + 1)/\(totalFrames)")
                .font(.caption)
                .foregroundColor(.secondary)
            
            // Playback controls
            HStack {
                // Reset button
                Button(action: {
                    resetPlayback()
                }) {
                    Image(systemName: "arrow.counterclockwise")
                        .font(.title2)
                }
                
                // Back to start button
                Button(action: {
                    moveToFirstFrame()
                }) {
                    Image(systemName: "backward.end.fill")
                        .font(.title2)
                }
                
                // Previous frame button
                Button(action: {
                    moveToPreviousFrame()
                }) {
                    Image(systemName: "backward.fill")
                        .font(.title2)
                }
                
                // Play/pause button
                Button(action: {
                    togglePlayback()
                }) {
                    Image(systemName: isPlaying ? "pause.fill" : "play.fill")
                        .font(.title)
                        .foregroundColor(isPlaying ? .red : .blue)
                }
                .frame(width: 50, height: 50)
                
                // Next frame button
                Button(action: {
                    moveToNextFrame()
                }) {
                    Image(systemName: "forward.fill")
                        .font(.title2)
                }
                
                // Forward to end button
                Button(action: {
                    moveToLastFrame()
                }) {
                    Image(systemName: "forward.end.fill")
                        .font(.title2)
                }
            }
            
            // Frame slider
            // Frame slider
            Slider(
                value: Binding(
                    get: { Double(cameraManager.currentFrameIndex) },
                    set: {
                        let newIndex = Int($0)
                        // First set the frame directly - this is the key fix
                        cameraManager.setFrame(to: newIndex)
                        // Then notify about the change
                        notifyFrameChanged(newIndex)
                    }
                ),
                in: 0...Double(totalFrames - 1),
                step: 1
            )
            .padding(.horizontal)
        }
    }
    
    private func togglePlayback() {
        isPlaying.toggle()
        
        if isPlaying {
            cameraManager.startPlayback()
        } else {
            cameraManager.stopPlayback()
        }
    }
    
    private func resetPlayback() {
        isPlaying = false
        cameraManager.stopPlayback()
        cameraManager.currentFrameIndex = 0
        notifyFrameChanged(0)
    }
    
    // IMPROVED FRAME NAVIGATION WITH NOTIFICATION
    private func moveToFirstFrame() {
        print("⏮️ Moving to first frame")
        cameraManager.setFrame(to: 0)
        notifyFrameChanged(0)
    }

    private func moveToPreviousFrame() {
        if cameraManager.currentFrameIndex > 0 {
            let newIndex = cameraManager.currentFrameIndex - 1
            print("◀️ Moving to previous frame: \(newIndex)")
            cameraManager.setFrame(to: newIndex)
            notifyFrameChanged(newIndex)
        }
    }

    private func moveToNextFrame() {
        if cameraManager.currentFrameIndex < totalFrames - 1 {
            let newIndex = cameraManager.currentFrameIndex + 1
            print("▶️ Moving to next frame: \(newIndex)")
            cameraManager.setFrame(to: newIndex)
            notifyFrameChanged(newIndex)
        }
    }

    private func moveToLastFrame() {
        let lastIndex = totalFrames - 1
        print("⏭️ Moving to last frame: \(lastIndex)")
        cameraManager.setFrame(to: lastIndex)
        notifyFrameChanged(lastIndex)
    }
    
    // Function to send notification about frame change
    private func notifyFrameChanged(_ frameIndex: Int) {
        // Post notification for frame change
        NotificationCenter.default.post(
            name: NSNotification.Name("FrameChanged"),
            object: nil,
            userInfo: ["frameIndex": frameIndex]
        )
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
// MARK: - Fixed Frame View (Simplified)
struct FrameView: View {
    let image: UIImage?
    let keypoints: [KeypointData]?
    let isAnnotationMode: Bool
    let rotation: Int
    let appState: AppState
    @Binding var selectedKeypointIndex: Int?
    
    var body: some View {
        GeometryReader { geometry in
            ZStack {
                // Background image
                if let image = image {
                    Image(uiImage: image)
                        .resizable()
                        .aspectRatio(contentMode: .fit)
                        .rotationEffect(.degrees(Double(rotation) * 90))
                        .clipped()
                } else {
                    Rectangle()
                        .fill(Color.black)
                }
                
                // ROI Selection Overlay
                if appState.isROIMode {
                    ROISelectionOverlay(
                        appState: appState,
                        containerSize: geometry.size,
                        imageSize: image?.size ?? CGSize(width: 1920, height: 1440),
                        rotation: rotation
                    )
                }
                
                // Keypoint Overlay - only show when not selecting ROI
                if let keypoints = keypoints,
                   !keypoints.isEmpty,
                   appState.showKeypoints,
                   !appState.isSelectingROI {
                    
                    FixedKeypointOverlay(
                        keypoints: keypoints,
                        containerSize: geometry.size,
                        imageSize: image?.size ?? CGSize(width: 1920, height: 1440),
                        rotation: rotation,
                        isAnnotationMode: isAnnotationMode,
                        selectedKeypointIndex: $selectedKeypointIndex
                    )
                }
            }
        }
    }
}


// MARK: - Fixed Keypoint Overlay (Simplified)
struct FixedKeypointOverlay: View {
    let keypoints: [KeypointData]
    let containerSize: CGSize
    let imageSize: CGSize
    let rotation: Int
    let isAnnotationMode: Bool
    @Binding var selectedKeypointIndex: Int?
    
    // Simplified connections
    private let connections: [(String, String)] = [
        // Torso
        ("left_shoulder", "right_shoulder"),
        ("left_shoulder", "left_hip"),
        ("right_shoulder", "right_hip"),
        ("left_hip", "right_hip"),
        
        // Arms
        ("left_shoulder", "left_elbow"),
        ("left_elbow", "left_wrist"),
        ("right_shoulder", "right_elbow"),
        ("right_elbow", "right_wrist"),
        
        // Legs
        ("left_hip", "left_knee"),
        ("left_knee", "left_ankle"),
        ("right_hip", "right_knee"),
        ("right_knee", "right_ankle"),
        
        // Face
        ("nose", "left_eye"),
        ("nose", "right_eye")
    ]
    
    var body: some View {
        ZStack {
            // Draw connections first
            ForEach(connections.indices, id: \.self) { index in
                FixedConnectionLine(
                    from: connections[index].0,
                    to: connections[index].1,
                    keypoints: keypoints,
                    containerSize: containerSize,
                    imageSize: imageSize,
                    rotation: rotation
                )
            }
            
            // Draw keypoints on top
            ForEach(keypoints.indices, id: \.self) { index in
                let keypoint = keypoints[index]
                
                if keypoint.confidence > 0.3 {
                    FixedKeypointDot(
                        keypoint: keypoint,
                        index: index,
                        containerSize: containerSize,
                        imageSize: imageSize,
                        rotation: rotation,
                        isSelected: selectedKeypointIndex == index,
                        isAnnotationMode: isAnnotationMode
                    )
                    .onTapGesture {
                        if isAnnotationMode {
                            selectedKeypointIndex = index
                        }
                    }
                }
            }
        }
    }
}

// MARK: - Fixed Connection Line
struct FixedConnectionLine: View {
    let from: String
    let to: String
    let keypoints: [KeypointData]
    let containerSize: CGSize
    let imageSize: CGSize
    let rotation: Int
    
    var body: some View {
        Path { path in
            guard let fromKeypoint = keypoints.first(where: { $0.name == from }),
                  let toKeypoint = keypoints.first(where: { $0.name == to }),
                  fromKeypoint.confidence > 0.3 && toKeypoint.confidence > 0.3 else {
                return
            }
            
            let fromPoint = transformPoint(
                x: fromKeypoint.x,
                y: fromKeypoint.y,
                containerSize: containerSize,
                imageSize: imageSize,
                rotation: rotation
            )
            
            let toPoint = transformPoint(
                x: toKeypoint.x,
                y: toKeypoint.y,
                containerSize: containerSize,
                imageSize: imageSize,
                rotation: rotation
            )
            
            path.move(to: fromPoint)
            path.addLine(to: toPoint)
        }
        .stroke(connectionColor(from: from, to: to), lineWidth: 2)
    }
    
    private func connectionColor(from: String, to: String) -> Color {
        if from.contains("left") || to.contains("left") {
            return .blue
        } else if from.contains("right") || to.contains("right") {
            return .red
        } else {
            return .green
        }
    }
}

// MARK: - Fixed Keypoint Dot
struct FixedKeypointDot: View {
    let keypoint: KeypointData
    let index: Int
    let containerSize: CGSize
    let imageSize: CGSize
    let rotation: Int
    let isSelected: Bool
    let isAnnotationMode: Bool
    
    var body: some View {
        let position = transformPoint(
            x: keypoint.x,
            y: keypoint.y,
            containerSize: containerSize,
            imageSize: imageSize,
            rotation: rotation
        )
        
        let color = keypointColor(name: keypoint.name)
        // Fix: Convert Float to CGFloat explicitly
        let size = 8.0 + (CGFloat(keypoint.confidence) * 6.0)
        
        ZStack {
            // Main keypoint circle
            Circle()
                .fill(color)
                .frame(width: size, height: size)
            
            // White border
            Circle()
                .stroke(Color.white, lineWidth: isSelected ? 3 : 1)
                .frame(width: size, height: size)
            
            // Selection indicator
            if isSelected {
                Circle()
                    .stroke(Color.yellow, lineWidth: 2)
                    .frame(width: size + 8, height: size + 8)
            }
        }
        .position(position)
    }
    
    private func keypointColor(name: String) -> Color {
        if name.contains("left") {
            return .blue
        } else if name.contains("right") {
            return .red
        } else {
            return .green
        }
    }
}


private func transformPoint(x: CGFloat, y: CGFloat, containerSize: CGSize, imageSize: CGSize, rotation: Int) -> CGPoint {
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

// MARK: - Simplified updateDisplayWithKeypoints method for BESTGYMPoseApp



// MARK: - Helper Types
struct Keypoint {
    let position: CGPoint
    let confidence: Float
    let name: String
}

enum BodySide {
    case left
    case right
    case center
}

struct KeypointConnection {
    let from: Int?
    let to: Int?
    let side: BodySide
}

struct ErrorWrapper: Identifiable {
    let id = UUID()
    let error: String
}


extension UIImage {
    func rotated(to orientation: UIImage.Orientation) -> UIImage? {
        guard let cgImage = self.cgImage else { return nil }
        return UIImage(cgImage: cgImage, scale: 1.0, orientation: orientation)
    }
}


// MARK: - Keypoint Analysis View
struct KeypointAnalysisView: View {
    let poseProcessor: VitPoseProcessor
    let currentFrameIndex: Int
    @Binding var showAnalysisView: Bool
    
    @State private var selectedAnalysisType = AnalysisType.jointAngles
    @State private var selectedJoints: [String] = []
    @State private var timeRange: ClosedRange<Double> = 0...1
    
    enum AnalysisType: String, CaseIterable, Identifiable {
        case jointAngles = "Joint Angles"
        case trajectories = "Joint Trajectories"
        case velocities = "Velocities"
        case accelerations = "Accelerations"
        case comparison = "Compare to Reference"
        
        var id: String { self.rawValue }
    }
    
    var body: some View {
        NavigationView {
            VStack {
                // Analysis type picker
                Picker("Analysis Type", selection: $selectedAnalysisType) {
                    ForEach(AnalysisType.allCases) { type in
                        Text(type.rawValue).tag(type)
                    }
                }
                .pickerStyle(SegmentedPickerStyle())
                .padding()
                
                // Joint selection for analysis
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 10) {
                        ForEach(availableJoints, id: \.self) { joint in
                            JointSelectionButton(
                                jointName: joint,
                                isSelected: selectedJoints.contains(joint),
                                onToggle: {
                                    toggleJointSelection(joint)
                                }
                            )
                        }
                    }
                    .padding(.horizontal)
                }
                
                // Time range slider
                VStack(alignment: .leading) {
                    Text("Frame Range")
                        .font(.headline)
                        .padding(.horizontal)
                    
                    HStack {
                        Text("Frame \(Int(timeRange.lowerBound * Double(totalFrames)))")
                            .font(.caption)
                        
                        Spacer()
                        
                        Text("Frame \(Int(timeRange.upperBound * Double(totalFrames)))")
                            .font(.caption)
                    }
                    .padding(.horizontal)
                    
                    RangeSlider(value: $timeRange, in: 0...1)
                        .padding(.horizontal)
                }
                .padding(.vertical)
                
                // Analysis graph based on selection
                AnalysisGraphView(
                    analysisType: selectedAnalysisType,
                    selectedJoints: selectedJoints,
                    timeRange: timeRange,
                    poseProcessor: poseProcessor,
                    currentFrameIndex: currentFrameIndex
                )
                .padding()
                .background(Color(.secondarySystemBackground))
                .cornerRadius(12)
                .padding()
                
                // Analysis metrics
                if !selectedJoints.isEmpty {
                    AnalysisMetricsView(
                        analysisType: selectedAnalysisType,
                        selectedJoints: selectedJoints,
                        poseProcessor: poseProcessor,
                        currentFrameIndex: currentFrameIndex
                    )
                    .padding()
                }
                
                Spacer()
            }
            .navigationTitle("Pose Analysis")
            .navigationBarItems(
                trailing: Button("Done") {
                    showAnalysisView = false
                }
            )
        }
    }
    
    // Helper properties and methods
    private var totalFrames: Int {
        return poseProcessor.getTotalFrames()
    }
    
    private var availableJoints: [String] {
        return [
            "Left Shoulder", "Right Shoulder",
            "Left Elbow", "Right Elbow",
            "Left Wrist", "Right Wrist",
            "Left Hip", "Right Hip",
            "Left Knee", "Right Knee",
            "Left Ankle", "Right Ankle"
        ]
    }
    
    private func toggleJointSelection(_ joint: String) {
        if selectedJoints.contains(joint) {
            selectedJoints.removeAll { $0 == joint }
        } else {
            selectedJoints.append(joint)
        }
    }
}

// MARK: - Joint Selection Button
struct JointSelectionButton: View {
    let jointName: String
    let isSelected: Bool
    let onToggle: () -> Void
    
    var body: some View {
        Button(action: onToggle) {
            Text(jointName)
                .font(.caption)
                .padding(.horizontal, 12)
                .padding(.vertical, 8)
                .background(isSelected ? Color.blue : Color(.systemGray5))
                .foregroundColor(isSelected ? .white : .primary)
                .cornerRadius(16)
        }
    }
}

// MARK: - Range Slider
struct RangeSlider: View {
    @Binding var value: ClosedRange<Double>
    let bounds: ClosedRange<Double>
    
    init(value: Binding<ClosedRange<Double>>, in bounds: ClosedRange<Double>) {
        self._value = value
        self.bounds = bounds
    }
    
    var body: some View {
        GeometryReader { geometry in
            ZStack(alignment: .leading) {
                // Track
                Rectangle()
                    .fill(Color.gray.opacity(0.2))
                    .frame(height: 6)
                    .cornerRadius(3)
                
                // Selected range
                Rectangle()
                    .fill(Color.blue)
                    .frame(width: CGFloat((value.upperBound - value.lowerBound) / (bounds.upperBound - bounds.lowerBound)) * geometry.size.width,
                           height: 6)
                    .offset(x: CGFloat((value.lowerBound - bounds.lowerBound) / (bounds.upperBound - bounds.lowerBound)) * geometry.size.width)
                    .cornerRadius(3)
                
                // Lower handle
                Circle()
                    .fill(Color.white)
                    .frame(width: 24, height: 24)
                    .shadow(radius: 2)
                    .offset(x: CGFloat((value.lowerBound - bounds.lowerBound) / (bounds.upperBound - bounds.lowerBound)) * geometry.size.width - 12)
                    .gesture(
                        DragGesture()
                            .onChanged { gesture in
                                let newValue = bounds.lowerBound + Double(gesture.location.x / geometry.size.width) * (bounds.upperBound - bounds.lowerBound)
                                
                                // Ensure lower bound doesn't exceed upper bound
                                if newValue < value.upperBound {
                                    value = newValue...value.upperBound
                                }
                            }
                    )
                
                // Upper handle
                Circle()
                    .fill(Color.white)
                    .frame(width: 24, height: 24)
                    .shadow(radius: 2)
                    .offset(x: CGFloat((value.upperBound - bounds.lowerBound) / (bounds.upperBound - bounds.lowerBound)) * geometry.size.width - 12)
                    .gesture(
                        DragGesture()
                            .onChanged { gesture in
                                let newValue = bounds.lowerBound + Double(gesture.location.x / geometry.size.width) * (bounds.upperBound - bounds.lowerBound)
                                
                                // Ensure upper bound doesn't fall below lower bound
                                if newValue > value.lowerBound {
                                    value = value.lowerBound...newValue
                                }
                            }
                    )
            }
            .frame(height: 24)
        }
        .frame(height: 24)
    }
}



// MARK: - Processing Overlay
struct ProcessingOverlay: View {
    let status: String
    
    var body: some View {
        ZStack {
            Color.black.opacity(0.7)
                .edgesIgnoringSafeArea(.all)
            
            VStack(spacing: 20) {
                ProgressView()
                    .scaleEffect(1.5)
                    .progressViewStyle(CircularProgressViewStyle(tint: .white))
                
                Text(status)
                    .font(.headline)
                    .foregroundColor(.white)
            }
            .padding(30)
            .background(Color(.systemGray5))
            .cornerRadius(15)
        }
    }
}

// MARK: - Error Overlay
struct ErrorOverlay: View {
    let message: String
    let onDismiss: () -> Void
    
    var body: some View {
        VStack {
            Spacer()
            
            HStack {
                Image(systemName: "exclamationmark.triangle.fill")
                    .foregroundColor(.white)
                
                Text(message)
                    .foregroundColor(.white)
                
                Spacer()
                
                Button(action: onDismiss) {
                    Image(systemName: "xmark.circle.fill")
                        .foregroundColor(.white)
                }
            }
            .padding()
            .background(Color.red)
            .cornerRadius(8)
            .padding()
        }
    }
}


//
// MARK: - Document Pickers

// File Picker for opening regular files
//struct DocumentPicker: UIViewControllerRepresentable {
//    let onPick: ([URL]) -> Void
//    
//    func makeUIViewController(context: Context) -> UIDocumentPickerViewController {
//        let picker = UIDocumentPickerViewController(forOpeningContentTypes: [.folder, .json, .item])
//        picker.allowsMultipleSelection = false
//        picker.delegate = context.coordinator
//        return picker
//    }
//    
//    func updateUIViewController(_ uiViewController: UIDocumentPickerViewController, context: Context) {}
//    
//    func makeCoordinator() -> Coordinator {
//        Coordinator(onPick: onPick)
//    }
//    
//    class Coordinator: NSObject, UIDocumentPickerDelegate {
//        let onPick: ([URL]) -> Void
//        
//        init(onPick: @escaping ([URL]) -> Void) {
//            self.onPick = onPick
//        }
//        
//        func documentPicker(_ controller: UIDocumentPickerViewController, didPickDocumentsAt urls: [URL]) {
//            onPick(urls)
//        }
//    }
//}


struct KeypointDocumentPicker: UIViewControllerRepresentable {
    let onPick: (URL) -> Void
    
    func makeUIViewController(context: Context) -> UIDocumentPickerViewController {
        let picker = UIDocumentPickerViewController(forOpeningContentTypes: [.json])
        picker.allowsMultipleSelection = false
        picker.delegate = context.coordinator
        return picker
    }
    
    func updateUIViewController(_ uiViewController: UIDocumentPickerViewController, context: Context) {}
    
    func makeCoordinator() -> Coordinator {
        Coordinator(onPick: onPick)
    }
    
    class Coordinator: NSObject, UIDocumentPickerDelegate {
        let onPick: (URL) -> Void
        
        init(onPick: @escaping (URL) -> Void) {
            self.onPick = onPick
        }
        
        func documentPicker(_ controller: UIDocumentPickerViewController, didPickDocumentsAt urls: [URL]) {
            if let url = urls.first {
                onPick(url)
            }
        }
    }
}

// Video file picker
struct VideoFilePicker: UIViewControllerRepresentable {
    let onPick: (URL) -> Void
    
    func makeUIViewController(context: Context) -> UIDocumentPickerViewController {
        let picker = UIDocumentPickerViewController(forOpeningContentTypes: [.movie, .video, .mpeg4Movie])
        picker.allowsMultipleSelection = false
        picker.delegate = context.coordinator
        return picker
    }
    
    func updateUIViewController(_ uiViewController: UIDocumentPickerViewController, context: Context) {}
    
    func makeCoordinator() -> Coordinator {
        Coordinator(onPick: onPick)
    }
    
    class Coordinator: NSObject, UIDocumentPickerDelegate {
        let onPick: (URL) -> Void
        
        init(onPick: @escaping (URL) -> Void) {
            self.onPick = onPick
        }
        
        func documentPicker(_ controller: UIDocumentPickerViewController, didPickDocumentsAt urls: [URL]) {
            if let url = urls.first {
                onPick(url)
            }
        }
    }
}

//// Photo library video picker
struct PhotoLibraryVideoPicker: UIViewControllerRepresentable {
    @Binding var isPresented: Bool
    let onPick: (URL?) -> Void
    
    func makeUIViewController(context: Context) -> PHPickerViewController {
        var config = PHPickerConfiguration()
        config.filter = .videos
        config.selectionLimit = 1
        
        let picker = PHPickerViewController(configuration: config)
        picker.delegate = context.coordinator
        return picker
    }
    
    func updateUIViewController(_ uiViewController: PHPickerViewController, context: Context) {}
    
    func makeCoordinator() -> Coordinator {
        Coordinator(parent: self)
    }
    
    class Coordinator: NSObject, PHPickerViewControllerDelegate {
        let parent: PhotoLibraryVideoPicker
        
        init(parent: PhotoLibraryVideoPicker) {
            self.parent = parent
        }
        
        func picker(_ picker: PHPickerViewController, didFinishPicking results: [PHPickerResult]) {
            parent.isPresented = false
            
            guard let result = results.first else {
                parent.onPick(nil)
                return
            }
            
            result.itemProvider.loadFileRepresentation(forTypeIdentifier: UTType.movie.identifier) { url, error in
                if let error = error {
                    print("Error loading video: \(error.localizedDescription)")
                    DispatchQueue.main.async {
                        self.parent.onPick(nil)
                    }
                    return
                }
                
                guard let url = url else {
                    DispatchQueue.main.async {
                        self.parent.onPick(nil)
                    }
                    return
                }
                
                // Create a copy of the file in the app's document directory
                let fileManager = FileManager.default
                let documentsDirectory = fileManager.urls(for: .documentDirectory, in: .userDomainMask).first!
                let destinationURL = documentsDirectory.appendingPathComponent(url.lastPathComponent)
                
                do {
                    // Remove existing file if it exists
                    if fileManager.fileExists(atPath: destinationURL.path) {
                        try fileManager.removeItem(at: destinationURL)
                    }
                    
                    try fileManager.copyItem(at: url, to: destinationURL)
                    
                    DispatchQueue.main.async {
                        self.parent.onPick(destinationURL)
                    }
                } catch {
                    print("Error copying video file: \(error.localizedDescription)")
                    DispatchQueue.main.async {
                        self.parent.onPick(nil)
                    }
                }
            }
        }
    }
}

// MARK: - Analysis Graph View
struct AnalysisGraphView: View {
    let analysisType: KeypointAnalysisView.AnalysisType
    let selectedJoints: [String]
    let timeRange: ClosedRange<Double>
    let poseProcessor: VitPoseProcessor
    let currentFrameIndex: Int
    
    var body: some View {
        VStack {
            if selectedJoints.isEmpty {
                Text("Select joints to analyze")
                    .foregroundColor(.secondary)
                    .frame(maxWidth: .infinity, maxHeight: 300)
            } else {
                // Different visualizations based on analysis type
                switch analysisType {
                case .jointAngles:
                    JointAngleGraphView(
                        selectedJoints: selectedJoints,
                        timeRange: timeRange,
                        poseProcessor: poseProcessor,
                        currentFrameIndex: currentFrameIndex
                    )
                    
                case .trajectories:
                    TrajectoryGraphView(
                        selectedJoints: selectedJoints,
                        timeRange: timeRange,
                        poseProcessor: poseProcessor
                    )
                    
                case .velocities:
                    VelocityGraphView(
                        selectedJoints: selectedJoints,
                        timeRange: timeRange,
                        poseProcessor: poseProcessor
                    )
                    
                case .accelerations:
                    AccelerationGraphView(
                        selectedJoints: selectedJoints,
                        timeRange: timeRange,
                        poseProcessor: poseProcessor
                    )
                    
                case .comparison:
                    ComparisonGraphView(
                        selectedJoints: selectedJoints,
                        timeRange: timeRange,
                        poseProcessor: poseProcessor
                    )
                }
            }
        }
        .frame(height: 300)
    }
}

// Example implementation of joint angle graph
struct JointAngleGraphView: View {
    let selectedJoints: [String]
    let timeRange: ClosedRange<Double>
    let poseProcessor: VitPoseProcessor
    let currentFrameIndex: Int
    
    // Joint colors for the graph
    private let jointColors: [String: Color] = [
        "Left Shoulder": .blue,
        "Right Shoulder": .red,
        "Left Elbow": .blue,
        "Right Elbow": .red,
        "Left Hip": .blue,
        "Right Hip": .red,
        "Left Knee": .blue,
        "Right Knee": .red,
        "Left Ankle": .blue,
        "Right Ankle": .red
    ]
    
    var body: some View {
        VStack {
            // This would be implemented with a charting library like SwiftUI Charts or a custom drawing
            // For this example, we'll create a placeholder with sample data
            Canvas { context, size in
                // Background grid
                drawGrid(context: context, size: size)
                
                // X and Y axes
                drawAxes(context: context, size: size)
                
                // Data lines for each selected joint
                for joint in selectedJoints {
                    drawJointAngleLine(
                        joint: joint,
                        context: context,
                        size: size,
                        color: jointColors[joint] ?? .gray
                    )
                }
                
                // Current frame indicator
                drawCurrentFrameIndicator(context: context, size: size)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            
            // Legend
            HStack {
                ForEach(selectedJoints, id: \.self) { joint in
                    HStack {
                        Circle()
                            .fill(jointColors[joint] ?? .gray)
                            .frame(width: 10, height: 10)
                        Text(joint)
                            .font(.caption)
                    }
                    .padding(.horizontal, 5)
                }
            }
            .padding(.top, 5)
        }
    }
    
    // Helper drawing methods
    private func drawGrid(context: GraphicsContext, size: CGSize) {
        let horizontalLines = 5
        let verticalLines = 10
        
        let path = Path { p in
            // Horizontal grid lines
            for i in 0...horizontalLines {
                let y = size.height / CGFloat(horizontalLines) * CGFloat(i)
                p.move(to: CGPoint(x: 0, y: y))
                p.addLine(to: CGPoint(x: size.width, y: y))
            }
            
            // Vertical grid lines
            for i in 0...verticalLines {
                let x = size.width / CGFloat(verticalLines) * CGFloat(i)
                p.move(to: CGPoint(x: x, y: 0))
                p.addLine(to: CGPoint(x: x, y: size.height))
            }
        }
        
        context.stroke(path, with: .color(.gray.opacity(0.2)), lineWidth: 1)
    }
    
    private func drawAxes(context: GraphicsContext, size: CGSize) {
        let path = Path { p in
            // X-axis
            p.move(to: CGPoint(x: 0, y: size.height))
            p.addLine(to: CGPoint(x: size.width, y: size.height))
            
            // Y-axis
            p.move(to: CGPoint(x: 0, y: 0))
            p.addLine(to: CGPoint(x: 0, y: size.height))
        }
        
        context.stroke(path, with: .color(.gray), lineWidth: 2)
    }
    
    private func drawJointAngleLine(joint: String, context: GraphicsContext, size: CGSize, color: Color) {
        // In a real implementation, you would get angle data from your pose processor
        // Here we're creating sample data for visualization
        let data = getSampleDataForJoint(joint, frames: 100)
        
        // Calculate visible range based on timeRange
        let startFrame = Int(timeRange.lowerBound * Double(data.count))
        let endFrame = Int(timeRange.upperBound * Double(data.count))
        let visibleData = Array(data[startFrame...endFrame])
        
        // Create path for the line
        let path = Path { p in
            guard !visibleData.isEmpty else { return }
            
            let xScale = size.width / CGFloat(visibleData.count - 1)
            let yScale = size.height / 180.0 // Assuming angles are in degrees (0-180)
            
            // Start at the first point
            p.move(to: CGPoint(
                x: 0,
                y: size.height - (CGFloat(visibleData[0]) * yScale)
            ))
            
            // Add lines to all subsequent points
            for i in 1..<visibleData.count {
                let point = CGPoint(
                    x: CGFloat(i) * xScale,
                    y: size.height - (CGFloat(visibleData[i]) * yScale)
                )
                p.addLine(to: point)
            }
        }
        
        // Draw the path
        context.stroke(path, with: .color(color), style: StrokeStyle(lineWidth: 2, lineCap: .round, lineJoin: .round))
    }
    
    private func drawCurrentFrameIndicator(context: GraphicsContext, size: CGSize) {
        // Calculate position based on current frame and visible range
        let totalFrames = poseProcessor.getTotalFrames()
        guard totalFrames > 0 else { return }
        
        let currentFrameNormalized = Double(currentFrameIndex) / Double(totalFrames - 1)
        
        // Only draw if current frame is within the visible range
        if currentFrameNormalized >= timeRange.lowerBound && currentFrameNormalized <= timeRange.upperBound {
            let rangeWidth = timeRange.upperBound - timeRange.lowerBound
            let positionInRange = (currentFrameNormalized - timeRange.lowerBound) / rangeWidth
            let xPosition = CGFloat(positionInRange) * size.width
            
            let path = Path { p in
                p.move(to: CGPoint(x: xPosition, y: 0))
                p.addLine(to: CGPoint(x: xPosition, y: size.height))
            }
            
            context.stroke(path, with: .color(.red), style: StrokeStyle(lineWidth: 2, dash: [4, 4]))
        }
    }
    
    // Generate sample data for visualization
    private func getSampleDataForJoint(_ joint: String, frames: Int) -> [Double] {
        var result: [Double] = []
        
        // Different patterns for different joints
        switch joint {
        case "Left Shoulder", "Right Shoulder":
            // Shoulder angles - moderate movement
            for i in 0..<frames {
                let angle = 90.0 + 30.0 * sin(Double(i) / Double(frames) * 2.0 * .pi)
                result.append(angle)
            }
        case "Left Elbow", "Right Elbow":
            // Elbow angles - more dramatic movement
            for i in 0..<frames {
                let angle = 100.0 + 70.0 * sin(Double(i) / Double(frames) * 3.0 * .pi)
                result.append(angle)
            }
        case "Left Knee", "Right Knee":
            // Knee angles - different pattern
            for i in 0..<frames {
                let base = Double(i) / Double(frames)
                let angle = 20.0 + 160.0 * (base < 0.5 ? 2.0 * base : 2.0 - 2.0 * base)
                result.append(angle)
            }
        default:
            // Other joints - gentle wave
            for i in 0..<frames {
                let angle = 60.0 + 20.0 * sin(Double(i) / Double(frames) * 1.5 * .pi)
                result.append(angle)
            }
        }
        
        return result
    }
}

// Placeholder implementations for other graph types
struct TrajectoryGraphView: View {
    let selectedJoints: [String]
    let timeRange: ClosedRange<Double>
    let poseProcessor: VitPoseProcessor
    
    var body: some View {
        Text("Joint Trajectory Visualization")
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(Color(.systemGray6))
            .cornerRadius(8)
    }
}

struct VelocityGraphView: View {
    let selectedJoints: [String]
    let timeRange: ClosedRange<Double>
    let poseProcessor: VitPoseProcessor
    
    var body: some View {
        Text("Joint Velocity Analysis")
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(Color(.systemGray6))
            .cornerRadius(8)
    }
}

struct AccelerationGraphView: View {
    let selectedJoints: [String]
    let timeRange: ClosedRange<Double>
    let poseProcessor: VitPoseProcessor
    
    var body: some View {
        Text("Joint Acceleration Analysis")
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(Color(.systemGray6))
            .cornerRadius(8)
    }
}

struct ComparisonGraphView: View {
    let selectedJoints: [String]
    let timeRange: ClosedRange<Double>
    let poseProcessor: VitPoseProcessor
    
    var body: some View {
        Text("Comparison with Reference Motion")
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(Color(.systemGray6))
            .cornerRadius(8)
    }
}

// MARK: - Analysis Metrics View
struct AnalysisMetricsView: View {
    let analysisType: KeypointAnalysisView.AnalysisType
    let selectedJoints: [String]
    let poseProcessor: VitPoseProcessor
    let currentFrameIndex: Int
    
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Metrics")
                .font(.headline)
            
            ForEach(selectedJoints, id: \.self) { joint in
                HStack {
                    Text(joint)
                        .font(.subheadline)
                        .frame(width: 120, alignment: .leading)
                    
                    Spacer()
                    
                    switch analysisType {
                    case .jointAngles:
                        Text("\(Int.random(in: 30...150))°")
                            .font(.system(.body, design: .monospaced))
                    case .trajectories:
                        Text("X: \(String(format: "%.1f", Double.random(in: -10...10))), Y: \(String(format: "%.1f", Double.random(in: -10...10)))")
                            .font(.system(.body, design: .monospaced))
                    case .velocities:
                        Text("\(String(format: "%.2f", Double.random(in: -2...2))) m/s")
                            .font(.system(.body, design: .monospaced))
                    case .accelerations:
                        Text("\(String(format: "%.2f", Double.random(in: -5...5))) m/s²")
                            .font(.system(.body, design: .monospaced))
                    case .comparison:
                        Text("Diff: \(String(format: "%.1f", Double.random(in: 0...15)))%")
                            .font(.system(.body, design: .monospaced))
                    }
                }
                .padding(.vertical, 4)
                .padding(.horizontal, 8)
                .background(Color(.systemGray6))
                .cornerRadius(8)
            }
        }
    }
}


struct DocumentPicker: UIViewControllerRepresentable {
    let onPick: ([URL]) -> Void
    
    func makeUIViewController(context: Context) -> UIDocumentPickerViewController {
        let picker = UIDocumentPickerViewController(forOpeningContentTypes: [.folder, .json, .item])
        picker.allowsMultipleSelection = false
        picker.delegate = context.coordinator
        
        // Enable iCloud Drive access
        picker.shouldShowFileExtensions = true
        picker.allowsMultipleSelection = false
        
        return picker
    }
    
    func updateUIViewController(_ uiViewController: UIDocumentPickerViewController, context: Context) {}
    
    func makeCoordinator() -> Coordinator {
        Coordinator(onPick: onPick)
    }
    
    class Coordinator: NSObject, UIDocumentPickerDelegate {
        let onPick: ([URL]) -> Void
        
        init(onPick: @escaping ([URL]) -> Void) {
            self.onPick = onPick
        }
        
        func documentPicker(_ controller: UIDocumentPickerViewController, didPickDocumentsAt urls: [URL]) {
            // Immediately start accessing security-scoped resources
            for url in urls {
                _ = SecurityScopedResourceManager.shared.startAccessing(url)
            }
            onPick(urls)
        }
        
        func documentPickerWasCancelled(_ controller: UIDocumentPickerViewController) {
            // Handle cancellation if needed
        }
    }
}
class SecurityScopedResourceManager {
    static let shared = SecurityScopedResourceManager()
    private var accessingURLs: [URL: Int] = [:] // URL -> reference count
    private let queue = DispatchQueue(label: "security-scoped-resource-queue", attributes: .concurrent)
    
    private init() {}
    
    func startAccessing(_ url: URL) -> Bool {
        return queue.sync(flags: .barrier) {
            // Check if we're already accessing this URL
            if let count = accessingURLs[url] {
                accessingURLs[url] = count + 1
                print("🔄 Incremented access count for: \(url.lastPathComponent) (count: \(count + 1))")
                return true
            }
            
            let success = url.startAccessingSecurityScopedResource()
            if success {
                accessingURLs[url] = 1
                print("✅ Started accessing security-scoped resource: \(url.lastPathComponent)")
            } else {
                print("❌ Failed to start accessing security-scoped resource: \(url.lastPathComponent)")
            }
            return success
        }
    }
    
    func stopAccessing(_ url: URL) {
        queue.sync(flags: .barrier) {
            guard let count = accessingURLs[url] else { return }
            
            if count > 1 {
                accessingURLs[url] = count - 1
                print("🔄 Decremented access count for: \(url.lastPathComponent) (count: \(count - 1))")
            } else {
                url.stopAccessingSecurityScopedResource()
                accessingURLs.removeValue(forKey: url)
                print("🛑 Stopped accessing security-scoped resource: \(url.lastPathComponent)")
            }
        }
    }
    
    func stopAccessingAll() {
        queue.sync(flags: .barrier) {
            for (url, _) in accessingURLs {
                url.stopAccessingSecurityScopedResource()
                print("🛑 Stopped accessing: \(url.lastPathComponent)")
            }
            accessingURLs.removeAll()
        }
    }
    
    func isAccessing(_ url: URL) -> Bool {
        return queue.sync {
            return accessingURLs[url] != nil
        }
    }
    
    // Perform operations with automatic resource management
    func withSecurityScopedResource<T>(_ url: URL, operation: () throws -> T) throws -> T {
        let wasAlreadyAccessing = isAccessing(url)
        
        if !wasAlreadyAccessing {
            guard startAccessing(url) else {
                throw FileAccessError.accessDenied
            }
        }
        
        defer {
            if !wasAlreadyAccessing {
                stopAccessing(url)
            }
        }
        
        return try operation()
    }
    
    // Special method for folder operations - keeps parent access alive
    func withFolderAccess<T>(_ folderURL: URL, operation: (_ folderURL: URL) throws -> T) throws -> T {
        guard startAccessing(folderURL) else {
            throw FileAccessError.accessDenied
        }
        
        // Don't stop accessing in defer - let caller manage it
        return try operation(folderURL)
    }
}
