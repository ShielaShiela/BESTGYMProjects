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
                            ToolbarLeft(appState: appState, toggleMode: toggleMode)
                        }
                        
                        // Principal Toolbar
                        ToolbarItemGroup(placement: .topBarTrailing) {
                            ToolbarActiveMode(appState: appState,
                                              toolbarVM: toolbarVM,
                                              ROIModel: ROIModel,
                                              BoxModel: BoxModel)
                        }
                        
                        // Principal Toolbar
                        ToolbarItemGroup(placement: .topBarTrailing) {
                            ToolbarMainActions(appState: appState,
                                               toolbarVM: toolbarVM,
                                               mediaManager: mediaManager,
                                               ROIModel: ROIModel,
                                               BoxModel: BoxModel)
                        }
                        
                        // Right Toolbar
                        ToolbarItemGroup(placement: .topBarTrailing) {
                            ToolbarRight(appState: appState,
                                         selectFileOrFolder: selectFileOrFolder,
                                         selectVideoFromLibrary: selectVideoFromLibrary,
                                         selectKeypointFile: selectKeypointFile,
                                         saveProject: saveProject)
                        }
                    }
                    
                    // File/Folder Picker
                    .fullScreenCover(isPresented: $appState.isFilePickerPresented) {
                        DocumentPickerUI { urls in
                            if let url = urls.first {
                                // Use loadData Function
                                appState.isProcessing = true
                                appState.processingStatus = "Loading data..."
                                
                                let errMsg = mediaManager.loadMedia(url: url, autoDetectKeypoints: appState.autoDetectKeypoints)
                                
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
                                
                                mediaManager.loadGalleryFile(url: url, autoDetectKeypoints: appState.autoDetectKeypoints) { errMsg in
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
                }
                
                .fullScreenCover(isPresented: $appState.showSettingsView) {
                    SettingsView(appState: appState)
                }
            }
            .navigationViewStyle(StackNavigationViewStyle())
            
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
        .onAppear {
            // Ensure initialization
            _ = OrientationCache.shared
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
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.01) {
                        self.appState.isRecordMode = true
                    }
                }
            }
        }
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
                
                let errMsg = mediaManager.loadMedia(url: url, autoDetectKeypoints: appState.autoDetectKeypoints)
                
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
