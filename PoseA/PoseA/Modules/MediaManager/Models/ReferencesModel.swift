//
//  ReferencesModel.swift
//  PoseA
//
//  Created by Ardhika Maulidani on 4/21/26.
//

import Foundation

// MARK: - Reference curve data (one dense grid of mean ± std)
struct RefCurve: Codable {
    var mean: [Double]
    var std:  [Double]
    var n:    [Double]
}

// MARK: - One phase's full reference data
struct ReferencePhase: Codable {
    var tGrid:         [Double]
    var shoulderAngle: RefCurve
    var hipAngle:      RefCurve
    var kneeAngle:     RefCurve

    enum CodingKeys: String, CodingKey {
        case tGrid         = "t_grid"
        case shoulderAngle = "shoulder_angle"
        case hipAngle      = "hip_angle"
        case kneeAngle     = "knee_angle"
    }

    // Convenience subscript so comparison code can iterate joints generically.
    subscript(feature: CompareList) -> RefCurve {
        switch feature {
        case .shoulder: return shoulderAngle
        case .hip:      return hipAngle
        case .knee:     return kneeAngle
        }
    }
}

// MARK: - Top-level reference file

struct ReferencesModel: Codable {
    var skill:      String
    var nSuccess:   Int
    var fileIds:    [String]
    var gridPoints: Int
    var release:    ReferencePhase
    var flight:     ReferencePhase

    enum CodingKeys: String, CodingKey {
        case skill
        case nSuccess   = "n_success"
        case fileIds    = "file_ids"
        case gridPoints = "grid_points"
        case release
        case flight
    }

    // MARK: - Load from bundle or file URL

    // Load and decode a *_reference.json file.
    static func load(from url: URL) throws -> ReferencesModel {
        let data = try Data(contentsOf: url)
        return try JSONDecoder().decode(ReferencesModel.self, from: data)
    }
    
    static func loadFromBundle(named fileName: String) async throws -> ReferencesModel {
        guard let url = Bundle.main.url(forResource: fileName, withExtension: "json") else {
            throw ReferenceLoadError.fileNotFound(fileName)
        }
        return try load(from: url)
    }
}

enum ReferenceLoadError: LocalizedError {
    case fileNotFound(String)
    var errorDescription: String? {
        switch self {
        case .fileNotFound(let name): return "Reference file '\(name).json' not found in bundle."
        }
    }
}

// MARK: - Joint enum shared between Reference and Comparison layers
enum CompareList: CaseIterable {
    case shoulder, hip, knee

    var label: String {
        switch self {
        case .shoulder: return "Shoulder"
        case .hip:      return "Hip"
        case .knee:     return "Knee"
        }
    }
}
