//
//  AppState.swift
//  PoseA
//
//  Created by Ardhika Maulidani on 6/2/25.
//  Refactor from Shiela Cabahug's codebase

import SwiftUI

// MARK: - Main App State
class MainAppState: ObservableObject {
    // UI state
    @Published var isProcessing = false
    @Published var isVideoSource = false
    @Published var isRecordMode = false
    @Published var hasImportedKeypoints = false
    @Published var processingStatus = ""
    @Published var errorMessage: String? = nil
    @Published var showKeypoints = false
    
    // Toolbox Status
    @Published var isAnnotationMode = false
    @Published var isROIMode = false
    @Published var isZoomMode = false
    @Published var analysisFilterMode = true
    
    // Pickers Status
    @Published var isTempFiles = false
    @Published var isFilePickerPresented = false
    @Published var isPhotoLibraryPresented = false
    @Published var isKeypointImportPresented = false
    
    // View Status
    @Published var showSettingsView = false
    @Published var isAnalysisAvailable: Bool = false

    // Device Orientation
    @Published var orientation: DeviceOrientationModel = .portrait
    
    // File metadata
    @Published var sourceFileName = ""
    @Published var sourceURL: URL? = nil
    @Published var originalKeypointFileURL: URL? = nil
    @Published var recordingDate: Date? = nil
    
    // Editing state
    @Published var RecordingData: RecordingDataModel = RecordingDataModel(athleteName: "Test",
                                                                          actionType: "Test",
                                                                          distanceValue: "Test",
                                                                          videoSettings: VideoSettings.defaultSettings)
    
    // LiDAR toggle state
    @Published var useLiDAR: Bool = false
    @Published var imageRotation: Int = 0
    
    @Published var autoDetectKeypoints: Bool = false
}

extension MainAppState {
    func resetFileAndKeypointState() {
        
        print("🔄 Resetting file and keypoint state...")
        
        sourceFileName = ""
        sourceURL = nil
        originalKeypointFileURL = nil
        hasImportedKeypoints = false
        showKeypoints = false
        
        // Keep default values for athlete info
        if RecordingData.athleteName.isEmpty {
            RecordingData.athleteName = "Test"
        }
        if RecordingData.actionType.isEmpty {
            RecordingData.actionType = "Test"
        }
        if RecordingData.distanceValue == nil {
            RecordingData.distanceValue = "Test"
        }
    }
    
    // Helper to reset processing/error state
    func resetStatusState() {
        isProcessing = false
        processingStatus = ""
        errorMessage = nil
    }
    
    func loadUserPreferences() {
        autoDetectKeypoints = UserDefaults.standard.bool(forKey: "AutoDetectKeypoints")
    }
    
    // Save preferences to UserDefaults
    func saveUserPreferences() {
        UserDefaults.standard.set(autoDetectKeypoints, forKey: "AutoDetectKeypoints")
    }
}
