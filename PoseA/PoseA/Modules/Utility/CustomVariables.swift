//
//  CustomVariables.swift
//  PoseA
//
//  Created by Ardhika Maulidani on 5/27/25.
//  Refactor from Shiela Cabahug's codebase

import SwiftUI

enum PipelineError: Error, LocalizedError {
    case mediaUnavailable
    case insufficientData(reason: String)
    case processingFailed(underlying: Error)

    var errorDescription: String? {
        switch self {
        case .mediaUnavailable:                return "Media is not available."
        case .insufficientData(let reason):    return "Insufficient data: \(reason)."
        case .processingFailed(let error):     return "Processing failed: \(error.localizedDescription)"
        }
    }
}

// MARK: Error Enumeration
enum FileAccessError: LocalizedError {
    case fileNotFound
    case accessDenied
    case unsupportedFormat(String)
    
    var errorDescription: String? {
        switch self {
        case .fileNotFound:
            return "The selected file or folder could not be found."
        case .accessDenied:
            return "Access to the selected file or folder was denied."
        case .unsupportedFormat(let format):
            return "Unsupported file format: \(format)"
        }
    }
}
