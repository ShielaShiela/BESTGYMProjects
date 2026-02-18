//
//  YoloInferenceCoor.swift
//  PoseA
//
//  Created by Shiela Cabahug on 2026/2/18.
//

import Foundation
//import Logging
// MARK: - InferenceCoordinator
// Owns the pipeline lifetime and bridges results into your existing VMs.
// Keep one instance in AnalysisModeRightView (@State var coordinator = InferenceCoordinator())

final class InferenceCoordinator {

    // MARK: - Config — tweak these without touching the pipeline
    struct Config {
        var modelName:           String  = "yolo11l-pose" // ← only change needed
        var confidence:          Float   = 0.35
        var iou:                 Float   = 0.50
        // Auto-scales to 2 on older chips, 4 on M-series at runtime
        var workerCount:         Int     = ProcessInfo.processInfo.activeProcessorCount >= 6 ? 4 : 2
    }
    var config = Config()

    // Active pipeline — retained so caller can't accidentally deallocate mid-run
    private var activePipeline: YOLOInferencePipeline?

    // MARK: - Run
    // Mirrors the existing `updateData` contract:
    //   appState.isProcessing → true while running
    //   appState.isAnalysisAvailable → true on success
    func run(
        mediaManager: MediaManagerVM,
        appState:     MainAppState,
        poseJointVM:  PoseJointLandscapeVM
    ) {
        // Guard — same checks your original code had
        guard !appState.isProcessing else {
            log("InferenceCoordinator: already processing", level: .info)
            return
        }
        guard mediaManager.isMediaAvailable else {
            appState.errorMessage = "No media loaded. Please load a video or folder first."
            return
        }

        // --- Phase 1: Load model ---
        appState.isProcessing       = true
        appState.isAnalysisAvailable = false
        appState.processingStatus   = "Loading model…"

        let yolo = YOLOPoseProcessor()
        yolo.confidenceThreshold = config.confidence
        yolo.iouThreshold        = config.iou

        yolo.loadModel(named: config.modelName) { [weak self] success in
            guard let self else { return }

            guard success else {
                appState.errorMessage  = "Failed to load YOLO model '\(self.config.modelName)'."
                appState.isProcessing  = false
                return
            }

            // --- Phase 2: Run inference ---
            let frameURLs = mediaManager.fileLoaderViewModel.FrameImageURLs
            let total     = frameURLs.count

            let pipeline = YOLOInferencePipeline(yolo: yolo, workerCount: self.config.workerCount)
            self.activePipeline = pipeline   // retain

            appState.processingStatus = "Running inference on \(total) frames…"

            pipeline.run(frameURLs: frameURLs) { completed, total in
                // Progress — already on main thread (pipeline guarantees this)
                let pct = Int(Float(completed) / Float(total) * 100)
                appState.processingStatus = "Inference \(pct)%  (\(completed)/\(total))"

            } onComplete: { [weak self] keypointDict, failCount in
                guard let self else { return }
                self.activePipeline = nil    // release pipeline memory

                self.handleResults(
                    keypointDict: keypointDict,
                    failCount:    failCount,
                    total:        total,
                    mediaManager: mediaManager,
                    appState:     appState,
                    poseJointVM:  poseJointVM
                )
            }
        }
    }

    // MARK: - Result Handler
    // Separated so the closure chain above stays readable
    private func handleResults(
        keypointDict: [Int: [KeypointData]],
        failCount:    Int,
        total:        Int,
        mediaManager: MediaManagerVM,
        appState:     MainAppState,
        poseJointVM:  PoseJointLandscapeVM
    ) {
        guard !keypointDict.isEmpty else {
            appState.errorMessage = "No poses detected. Try lowering confidence (current: \(config.confidence))."
            appState.isProcessing = false
            return
        }

        if failCount > 0 {
//            log("InferenceCoordinator: \(failCount)/\(total) frames had no detection", level: .warning)
            print("InferenceCoordinator: \(failCount)/\(total) frames had no detection: warning")
        }

        // --- Phase 3: Load into your existing VMs (unchanged API) ---
        appState.processingStatus = "Loading keypoints…"
        mediaManager.fileLoaderViewModel.loadKeypoints(from: keypointDict)
        appState.showKeypoints = true

        // --- Phase 4: Build analysis (unchanged call) ---
        appState.processingStatus = "Building analysis…"

        poseJointVM.buildCompleteData { success in
            // Same state transitions your original code used
            appState.isAnalysisAvailable = success
            appState.isProcessing        = false
            appState.processingStatus    = success
                ? "Complete — \(keypointDict.count)/\(total) frames detected"
                : "Analysis failed. Check keypoint data quality."

            if !success {
                log("InferenceCoordinator: buildCompleteData failed with \(keypointDict.count) keypoint frames", level: .error)
            }
        }
    }
}
