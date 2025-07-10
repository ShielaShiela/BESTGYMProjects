//
//  InferenceTiming.swift
//  PoseA
//
//  Created by Shiela Cabahug on 2025/7/1.
//

import Foundation
import CoreML
import UIKit

// MARK: - Inference Timing Model
struct InferenceTiming {
    let frameIndex: Int
    let preprocessingTime: TimeInterval
    let modelInferenceTime: TimeInterval
    let postprocessingTime: TimeInterval
    let totalTime: TimeInterval
    let timestamp: Date
    
    var formattedTotalTime: String {
        return String(format: "%.1f ms", totalTime * 1000)
    }
    
    var formattedBreakdown: String {
        return """
        Preprocessing: \(String(format: "%.1f ms", preprocessingTime * 1000))
        Model Inference: \(String(format: "%.1f ms", modelInferenceTime * 1000))
        Postprocessing: \(String(format: "%.1f ms", postprocessingTime * 1000))
        Total: \(formattedTotalTime)
        """
    }
}

// MARK: - Timing Statistics
class InferenceTimingStats {
    private var timings: [InferenceTiming] = []
    private let maxStoredTimings = 100 // Limit memory usage
    
    func addTiming(_ timing: InferenceTiming) {
        timings.append(timing)
        
        // Keep only recent timings to prevent memory bloat
        if timings.count > maxStoredTimings {
            timings.removeFirst(timings.count - maxStoredTimings)
        }
    }
    
    var averageInferenceTime: TimeInterval {
        guard !timings.isEmpty else { return 0 }
        return timings.map { $0.totalTime }.reduce(0, +) / Double(timings.count)
    }
    
    var averageModelInferenceTime: TimeInterval {
        guard !timings.isEmpty else { return 0 }
        return timings.map { $0.modelInferenceTime }.reduce(0, +) / Double(timings.count)
    }
    
    var minInferenceTime: TimeInterval {
        return timings.map { $0.totalTime }.min() ?? 0
    }
    
    var maxInferenceTime: TimeInterval {
        return timings.map { $0.totalTime }.max() ?? 0
    }
    
    var recentTimings: [InferenceTiming] {
        return Array(timings.suffix(10)) // Last 10 timings
    }
    
    func getFormattedStats() -> String {
        guard !timings.isEmpty else { return "No inference timings recorded" }
        
        return """
        === Inference Timing Statistics ===
        Total Frames Processed: \(timings.count)
        Average Total Time: \(String(format: "%.1f ms", averageInferenceTime * 1000))
        Average Model Time: \(String(format: "%.1f ms", averageModelInferenceTime * 1000))
        Min Time: \(String(format: "%.1f ms", minInferenceTime * 1000))
        Max Time: \(String(format: "%.1f ms", maxInferenceTime * 1000))
        FPS Estimate: \(String(format: "%.1f", 1.0 / averageInferenceTime))
        """
    }
    
    func clearStats() {
        timings.removeAll()
    }
}

