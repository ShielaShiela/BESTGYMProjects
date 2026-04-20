
import AVFoundation
import Photos
import PhotosUI
import SwiftUI

struct BESTGYMPoseApp: View {
    // MARK: - Properties
    // Camera VM
    @StateObject private var cameraManager = CameraManagerVM()
    
    // Media Related VM
    @State private var mediaManager = MediaManagerVM()
    @State private var ROIModel = ROIViewModel()
    @State private var barPointVM = BarPointVM()
    
    // Processing Manager
    @State private var processingManager = ProcessingManagerVM.shared
    
    // UI/UX Related VM
    @StateObject private var appState = MainAppState()
    @State private var toolbarVM = ToolbarButtonVM()
    
    // ML Model Related VM
    @State private var MLModel = YOLOPoseProcessor.shared
    
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
                                                 barPointVM: $barPointVM,
                                                 mediaManager: self.mediaManager)
                            .frame(width: geometry.size.width / 2 - 10) // Half of screen minus spacing
                            
                            Spacer()
                            
                            
                            // Right half: MainContentRightView with padding inside its half
                            AnalysisModeRightView(appState: self.appState,
                                                  ROIModel: self.ROIModel,
                                                  barPointVM: self.barPointVM,
                                                  mediaManager: self.mediaManager)
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
                                              mediaManager: mediaManager,
                                              ROIModel: ROIModel,
                                              barPointVM: barPointVM)
                        }
                        
                        // Principal Toolbar
                        ToolbarItemGroup(placement: .topBarTrailing) {
                            ToolbarMainActions(appState: appState,
                                               toolbarVM: toolbarVM,
                                               mediaManager: mediaManager,
                                               ROIModel: ROIModel,
                                               barPointVM: barPointVM)
                        }
                        
                        // Right Toolbar
                        ToolbarItemGroup(placement: .topBarTrailing) {
                            ToolbarRight(appState: appState,
                                         selectFileOrFolder: selectFileOrFolder,
                                         selectVideoFromLibrary: selectVideoFromLibrary,
                                         selectKeypointFile: selectKeypointFile)
                        }
                    }
                    
                    // File/Folder Picker
                    .sheet(isPresented: $appState.isFilePickerPresented) {
                        DocumentPickerUI { urls in
                            if let url = urls.first {
                                Task {
                                    await loadMediaAsync(url: url)
                                }
                            }
                        }
                    }
                    
                    // Gallery Picker
                    .sheet(isPresented: $appState.isPhotoLibraryPresented) {
                        PhotoLibraryVideoPicker(isPresented: $appState.isPhotoLibraryPresented) { url in
                            if let url = url {
                                Task {
                                    await loadGalleryAsync(url: url)
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
            if processingManager.isProcessing {
                ProcessingOverlayView(
                    status: processingManager.currentStatus,
                    progress: processingManager.progress
                )
                    .zIndex(1)
            }
            
            // Instruction Message Overlay
            if let instruction = appState.informationMsg {
                VStack {
                    HStack {
                        InformationMsgView(message: instruction) {
                            appState.informationMsg = nil
                        }
                        .padding(.leading, 130)
                        .padding(.top, 30)
                        
                        Spacer()
                    }
                    Spacer()
                }
            }
        }
        .onAppear {
            // Ensure initialization
            _ = OrientationCache.shared
            appState.loadUserPreferences()
            Task {
                await self.setModelVersion(appState.realtimeModel)
            }
        }
        .onChange(of: appState.realtimeModel) { oldModel, newModel in
            if oldModel != newModel {
                Task {
                    await self.setModelVersion(newModel)
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
        // Small delay to ensure cleanup completes
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
            self.appState.isKeypointImportPresented = true
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
        
        appState.resetFileAndKeypointState()
        print("Reset app state")
        
        // Clear Media Manager
        mediaManager.clearAllData()
        
        print("Cleanup complete")
    }
    
    private func setModelVersion(_ version: String) async {
        let operationId = "loadMLModel_\(UUID().uuidString)"

        // Start the processing operation
        ProcessingManagerVM.shared.startOperation(
            id: operationId,
            status: "Loading ML Model...",
            isPrimary: true
        )
        let errMsg = await Task.detached {
            return YOLOPoseProcessor.shared.loadModel(named: version)
        }.value
        
        if let errMsg = errMsg {
            self.appState.informationMsg = InformationMessage(text: errMsg,
                                                              type: .error)
        } else {
            self.appState.informationMsg = InformationMessage(text: "Successfully loaded ML Model.",
                                                              type: .info)
        }
        
        // Complete the operation
        ProcessingManagerVM.shared.completeOperation(id: operationId)
    }
}

extension BESTGYMPoseApp {
    
    // Loader
    @MainActor
    private func loadMediaAsync(url: URL) async {
        let operationId = "loadMediaUI_\(UUID().uuidString)"

        ProcessingManagerVM.shared.startOperation(
            id: operationId,
            status: "Preparing to load data...",
            isPrimary: true
        )

        let errMsg = await mediaManager.loadMedia(
            url: url,
            opID: operationId,
            autoDetectKeypoints: appState.autoDetectKeypoints
        )

        if let errMsg = errMsg {
            appState.informationMsg = InformationMessage(text: errMsg, type: .error)
        } else {
            appState.sourceFileName = url.lastPathComponent
            appState.sourceURL = url
            appState.isVideoSource = !mediaManager.isDataLIDAR
            appState.isTempFiles = mediaManager.isDataTemp
            appState.isAnalysisAvailable = !mediaManager.FeaturesData.isEmpty
            mediaManager.syncBarPointVM(barPointVM: barPointVM)
            
            appState.informationMsg = InformationMessage(
                text: "Successfully loading media data.",
                type: .info
            )
        }
        // Complete Operation
        ProcessingManagerVM.shared.completeOperation(id: operationId)
    }
    
    @MainActor
    private func loadGalleryAsync(url: URL) async {
        let operationId = "loadGalleryUI_\(UUID().uuidString)"

        // Start the processing operation
        ProcessingManagerVM.shared.startOperation(
            id: operationId,
            status: "Preparing to load data...",
            isPrimary: true
        )
        
        // Perform the media loading operation
        let errMsg = await Task.detached { [mediaManager, appState] in
            return mediaManager.loadGalleryFile(url: url, opID: operationId, autoDetectKeypoints: appState.autoDetectKeypoints)
        }.value
        
        // Update UI on main thread
        if let errMsg = errMsg {
            self.appState.informationMsg = InformationMessage(text: errMsg, type: .error)
        } else {
            self.appState.sourceFileName = url.lastPathComponent
            self.appState.sourceURL = url
            self.appState.showKeypoints = false
            self.appState.isVideoSource = !mediaManager.isDataLIDAR
            self.appState.isTempFiles = mediaManager.isDataTemp
        }
        
        // Complete the operation
        ProcessingManagerVM.shared.completeOperation(id: operationId)
    }
}
