//
//  AppState.swift
//  PoseA
//
//  Created by Ardhika Maulidani on 6/2/25.
//  Refactor from Shiela Cabahug's codebase

import SwiftUI

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
        
        print("🔄 Resetting file and keypoint state...")
        print("  - Before: hasImportedKeypoints = \(hasImportedKeypoints), keypoint frames = \(poseProcessor.getTotalFrames())")
           
          
        // ✅ ADD THIS LINE - explicitly clear pose processor keypoints
        poseProcessor.clearAllKeypoints()
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
