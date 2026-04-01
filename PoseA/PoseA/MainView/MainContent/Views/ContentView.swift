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
    @State private var calibrationModel = CalibrationModel()
    @State var quadCalibrationModel: QuadCalibrationModel = QuadCalibrationModel()
    
    // ML Model Related VM
//    @State private var MLModel = VitPoseProcessor()
    
    // Project
    @State private var showSaveProjectSheet = false
    @State private var showProjectList = false
    @State private var currentProject: GymProject? = nil
    @State private var analysisResetToken: UUID = UUID()
    
    @State private var sharedAnnotationVM = ManualAnnotationVM()
    @State private var selectedRightView: RightViewModel = .info  // lift this up
    
    @State private var showKeypointOverlay: Bool = true
    @State private var showBoxOverlay: Bool = true
    
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
                                                 mediaManager: self.mediaManager,
                                                 calibrationModel: self.calibrationModel,
                                                 annotationVM: $sharedAnnotationVM,          // ← NEW
                                                 selectedRightView: $selectedRightView ,
                                                 showKeypointOverlay: $showKeypointOverlay,   // ← NEW
                                                 showBoxOverlay: $showBoxOverlay,
                                                 quadCalibrationModel: quadCalibrationModel  // ← NEW
                            )
                            .frame(width: geometry.size.width / 2 - 10) // Half of screen minus spacing
                            
                            Spacer()
                            
                            
                            // Right half: MainContentRightView with padding inside its half
                            AnalysisModeRightView(appState: self.appState,
                                                  ROIModel: self.ROIModel,
                                                  BoxModel: self.BoxModel,
                                                  mediaManager: self.mediaManager,
                                                  calibrationModel: self.calibrationModel,
                                                  resetToken: analysisResetToken,
                                                  annotationVM: $sharedAnnotationVM,          // ← NEW
                                                  selectedRightView: $selectedRightView,
                                                  quadCalibrationModel: quadCalibrationModel 
                            )
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
                        
                        
                        ToolbarItemGroup(placement: .topBarTrailing) {
                            ToolbarActiveMode(
                                appState: appState,
                                toolbarVM: toolbarVM,
                                ROIModel: ROIModel,
                                BoxModel: BoxModel,
                                calibrationModel: calibrationModel,
                                quadCalibrationModel: quadCalibrationModel                            )
                        }
                         
                        ToolbarItemGroup(placement: .topBarTrailing) {
                            ToolbarMainActions(
                                appState: appState,
                                toolbarVM: toolbarVM,
                                mediaManager: mediaManager,
                                ROIModel: ROIModel,
                                BoxModel: BoxModel,
                                calibrationModel: calibrationModel,
                                quadCalibrationModel: quadCalibrationModel,
                                showKeypointOverlay: $showKeypointOverlay,
                                showBoxOverlay: $showBoxOverlay
                            )
                        }

                        // Right Toolbar
                        ToolbarItemGroup(placement: .topBarTrailing) {
                            ToolbarRight(appState: appState,
                                         selectFileOrFolder: selectFileOrFolder,
                                         selectVideoFromLibrary: selectVideoFromLibrary,
                                         selectKeypointFile: selectKeypointFile,
                                         saveProject: saveProject,
                                         showSaveProjectSheet: $showSaveProjectSheet,
                                         showProjectList: $showProjectList   )
                        }
                    }
                    
                    .fullScreenCover(isPresented: $appState.isFilePickerPresented) {
                        DocumentPickerUI { urls in
                            guard let url = urls.first else { return }
                            
                            appState.isProcessing = true
                            appState.processingStatus = "Loading data..."
                            
                            mediaManager.loadMedia(url: url, autoDetectKeypoints: appState.autoDetectKeypoints) { errMsg in
                                DispatchQueue.main.async {
                                    if let errMsg = errMsg {
                                        self.appState.errorMessage = errMsg
                                    } else {
                                        self.appState.processingStatus = "Loaded frames from \(url.lastPathComponent)"
                                        self.appState.sourceFileName = url.lastPathComponent
                                        self.appState.sourceURL = url
                                        self.appState.showKeypoints = false
                                        self.appState.isVideoSource = !self.mediaManager.isDataLIDAR
                                        self.appState.isTempFiles = self.mediaManager.isDataTemp
                                    }
                                    self.appState.isProcessing = false
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
                .sheet(isPresented: $showSaveProjectSheet) {
                    SaveProjectSheet(
                        isPresented: $showSaveProjectSheet,
                        appState: appState,
                        mediaManager: mediaManager,
                        calibrationModel: calibrationModel,
                        existingProject: currentProject      // ← passes existing so UUID is reused
                    ) { savedProject in
                        currentProject = savedProject        // ← captures it back so next save reuses same UUID
                    }
                }
                .sheet(isPresented: $showProjectList) {
                    ProjectListView(isPresented: $showProjectList) { project, keypoints in
                        loadProjectData(project, keypoints: keypoints)
                    }
                }
                .fullScreenCover(isPresented: $appState.showSettingsView) {
                    SettingsView(appState: appState, cameraManager: cameraManager)
                }
            }
            .navigationViewStyle(StackNavigationViewStyle())
            
            if appState.isRecordMode {
                RecordLandscapeView(appState: self.appState,
                                    cameraManager: self.cameraManager,
                                    calibrationModel: $calibrationModel)
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
            appState.loadUserPreferences()
            calibrationModel.loadFromUserDefaults()
            quadCalibrationModel.loadFromUserDefaults()
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
        // Watch for keypoint detection completion
        .onChange(of: mediaManager.isKeypointAvailable) { _, newValue in
            if newValue && !appState.isRecordMode {   // ✅ skip during recording
                autoSaveIfNeeded()
            }
        }
        // Watch for calibration completion
        .onChange(of: calibrationModel.calibrationStep) { _, newStep in
            if newStep == .complete && !appState.isRecordMode {   // ✅ skip during recording
                autoSaveIfNeeded()
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
        showSaveProjectSheet = true
    }
    
    private func loadProjectData(_ project: GymProject, keypoints: [Int: [KeypointData]]?) {
        cleanupPreviousData()
        
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.15) {
            currentProject = project
            appState.sourceFileName = project.sourceFileName

            // Restore calibration
            if let cal = project.calibrationData, cal.isCalibrated {
                calibrationModel.barTopPoint     = cal.barTopPoint?.cgPoint
                calibrationModel.barBottomPoint  = cal.barBottomPoint?.cgPoint
                calibrationModel.realBarHeightCm = cal.realBarHeightCm
                calibrationModel.calibrationStep = .complete
            }

            // Load copied source file from project folder
            if let sourceURL = ProjectManager.shared.sourceFileURL(for: project) {
                appState.isProcessing = true
                appState.processingStatus = "Loading media..."
                appState.sourceURL = sourceURL
                appState.isVideoSource = !mediaManager.isDataLIDAR

                mediaManager.loadMedia(url: sourceURL,
                                       autoDetectKeypoints: false) { errMsg in
                    DispatchQueue.main.async {
                        appState.isProcessing = false
                        if let errMsg = errMsg {
                            appState.errorMessage = "Media load failed: \(errMsg)"
                            
                        }
                        else if !self.calibrationModel.isCalibrated {
                            // No project calibration yet — try the recording's own metadata.json
                            MediaManagerVM.applyCalibrationIfPresent(
                                folderURL: sourceURL,
                                to: &self.calibrationModel
                            )
                        }
                        // Restore keypoints regardless of media success
                        self.restoreKeypoints(keypoints, project: project)
                    }
                }
            } else {
                // No copied media found (old project saved before this feature)
                restoreKeypoints(keypoints, project: project)
                appState.errorMessage = "Media not found in project folder. Please re-open '\(project.sourceFileName)' manually."
            }
        }
    }

    private func restoreKeypoints(_ keypoints: [Int: [KeypointData]]?, project: GymProject) {
        if let keypoints = keypoints {
            mediaManager.fileLoaderViewModel.keypointsByFrame = keypoints
            mediaManager.fileLoaderViewModel.isKeyLoaded = true
            mediaManager.isKeypointAvailable = true
        }
        appState.isAnalysisAvailable = project.isAnalysisAvailable
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
        
        currentProject = nil
        
        analysisResetToken = UUID()
        
        sharedAnnotationVM = ManualAnnotationVM()
        
        print("Cleanup complete")
    }
    
    private func autoSaveIfNeeded() {
        // ❌ Don't auto-save while in recording/camera mode
        guard !appState.isRecordMode else { return }
        
        // ❌ Don't auto-save unless media is actually loaded in this session
        guard !appState.sourceFileName.isEmpty else { return }
        
        // ❌ Only proceed if something meaningful is ready
        guard mediaManager.isKeypointAvailable || calibrationModel.isCalibrated else { return }

        if currentProject == nil {
            showSaveProjectSheet = true   // first time — prompt for name
        } else {
            // ✅ Only silently update if the project belongs to the currently loaded file
            guard currentProject?.sourceFileName == appState.sourceFileName else {
                // Source changed but currentProject wasn't cleared — skip silent update
                return
            }

            var updated = currentProject!
            updated.calibrationData = SavedCalibration(
                isCalibrated: calibrationModel.isCalibrated,
                barTopPoint: calibrationModel.barTopPoint.map { CGPointCodable($0) },
                barBottomPoint: calibrationModel.barBottomPoint.map { CGPointCodable($0) },
                realBarHeightCm: calibrationModel.realBarHeightCm
            )
            updated.isAnalysisAvailable = appState.isAnalysisAvailable
            ProjectManager.shared.updateProjectMetadata(&updated) { _ in }
            currentProject = updated
        }
    }
}
