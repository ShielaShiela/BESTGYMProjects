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
    @Published var informationMsg: InformationMessage? = nil
    
    @Published var isProcessing = false
    @Published var isVideoSource = false
    @Published var isRecordMode = false
    @Published var showKeypoints = true
        
    // Toolbox Status
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
        showKeypoints = false
    }
    
    func loadUserPreferences() {
        autoDetectKeypoints = true
    }
    
    // Save preferences to UserDefaults
    func saveUserPreferences() {
        UserDefaults.standard.set(autoDetectKeypoints, forKey: "AutoDetectKeypoints")
     
    }
    
    // MARK: - Instruction Message Methods
    func showInstruction(_ text: String, duration: TimeInterval = 3.0) {
        informationMsg = InformationMessage(text: text, type: .info, duration: duration)
    }
    
    func showWarning(_ text: String, duration: TimeInterval = 4.0) {
        informationMsg = InformationMessage(text: text, type: .warning, duration: duration)
    }
    
    func showError(_ text: String, autoDismiss: Bool = false, duration: TimeInterval = 5.0) {
        informationMsg = InformationMessage(text: text, type: .error, autoDismiss: autoDismiss, duration: duration)
    }
    
    func dismissInstruction() {
        informationMsg = nil
    }
}
