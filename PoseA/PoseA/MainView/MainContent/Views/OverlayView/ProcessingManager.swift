//
//  ProcessingManager.swift
//  PoseA
//
//  Created by Ardhika Maulidani on 11/7/25.
//

import Foundation
import SwiftUI

@MainActor
@Observable
class ProcessingManagerVM {
    static let shared = ProcessingManagerVM()
    
    private var activeOperations: [String: ProcessingOperation] = [:]
    
    var isProcessing: Bool {
        !activeOperations.isEmpty
    }
    
    var currentStatus: String {
        if let primaryOperation = activeOperations.values.first(where: { $0.isPrimary }) {
            return primaryOperation.status
        } else if let anyOperation = activeOperations.values.first {
            return anyOperation.status
        }
        return ""
    }
    
    var progress: Double {
        if activeOperations.isEmpty { return 0.0 }
        let totalProgress = activeOperations.values.map { $0.progress }.reduce(0, +)
        return totalProgress / Double(activeOperations.count)
    }
    
    private init() {}
    
    func startOperation(
        id: String,
        status: String,
        isPrimary: Bool = false,
        progress: Double = 0.0
    ) {
        activeOperations[id] = ProcessingOperation(
            id: id,
            status: status,
            isPrimary: isPrimary,
            progress: progress
        )
    }
    
    func updateOperation(
        id: String,
        status: String? = nil,
        progress: Double? = nil
    ) {
        guard var operation = activeOperations[id] else { return }
        
        if let status = status {
            operation.status = status
        }
        if let progress = progress {
            operation.progress = progress
        }
        
        activeOperations[id] = operation
    }
    
    func completeOperation(id: String) {
        activeOperations.removeValue(forKey: id)
    }
    
    func cancelAllOperations() {
        activeOperations.removeAll()
    }
}

struct ProcessingOperation {
    let id: String
    var status: String
    var isPrimary: Bool
    var progress: Double
}
