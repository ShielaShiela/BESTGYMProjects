//
//  CustomVariables.swift
//  PoseA
//
//  Created by Ardhika Maulidani on 5/27/25.
//  Refactor from Shiela Cabahug's codebase

import SwiftUI

// MARK: Error Variables
struct ErrorWrapper: Identifiable {
    let id = UUID()
    let error: String
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
