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
    
    @Published var is3DAnimationView = false
    
    // Toolbox Status
    @Published var isAnnotationMode = false
    @Published var isROIMode = false
    @Published var isZoomMode = false
    
    // Analysis Settings
    @Published var analysisFilterMode = true
    @Published var angleUnit: AngleUnit = .deg
    @Published var distanceUnit: DistanceUnit = .px
    @Published var timeUnit: TimeUnit = .n
    @Published var autoDetectKeypoints: Bool = true

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
    
    // Recording Value
    @Published var actionType: String = "General"
    @Published var athleteName: String = "Unknown"
    
    // Camera Settings
    @Published var useLiDAR: Bool = false
    @Published var isLidarDepthView:Bool = false
    @Published var realtimeDetection: Bool = false
    @Published var realtimeModel: String = "yolo11n-pose"
    @Published var realtimeViewMode: String = "general"
}

extension MainAppState {
    func resetFileAndKeypointState() {
        
        print("🔄 Resetting file and keypoint state...")
        
        sourceFileName = ""
        sourceURL = nil
        originalKeypointFileURL = nil
        hasImportedKeypoints = false
        showKeypoints = false
    }
    
    // Helper to reset processing/error state
    func resetStatusState() {
        isProcessing = false
        processingStatus = ""
        errorMessage = nil
    }
    
    func loadUserPreferences() {
        autoDetectKeypoints = true
    }
    
    // Save preferences to UserDefaults
    func saveUserPreferences() {
        UserDefaults.standard.set(autoDetectKeypoints, forKey: "AutoDetectKeypoints")
     
    }
}
