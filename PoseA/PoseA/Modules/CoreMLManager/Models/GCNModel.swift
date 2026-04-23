//
//  GCNModel.swift
//  PoseA
//
//  Created by Ardhika Maulidani on 4/23/26.
//

import Foundation

// MARK: - Errors
enum GCNError: LocalizedError {
    case resourceNotFound(String)
    case invalidNormStats
    case inferenceOutputMissing
    case pipelineError(String)

    var errorDescription: String? {
        switch self {
        case .resourceNotFound(let name):  return "Bundle resource not found: \(name)"
        case .invalidNormStats:            return "gcn_norm_stats.json has wrong channel count"
        case .inferenceOutputMissing:      return "CoreML output 'probabilities' is missing"
        case .pipelineError(let reason):   return "GCN pipeline error: \(reason)"
        }
    }
}

// MARK: - Output
struct SkillPrediction {
    var probabilities: [String: Double]  // e.g. ["tkatchev": 0.91, "yamawaki": 0.09]
    var topLabel:      String            // highest probability skill name
    var confidence:    Double            // probability of topLabel
}


struct NormStats: Codable {
    var mean: [Double]   // length C
    var std:  [Double]   // length C
}
