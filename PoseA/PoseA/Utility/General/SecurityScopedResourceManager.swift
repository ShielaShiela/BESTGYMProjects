//
//  SecurityScopedResourceManager.swift
//  PoseA
//
//  Created by Ardhika Maulidani on 6/2/25.
//  Refactor from Shiela Cabahug's codebase

import SwiftUI

class SecurityScopedResourceManager {
    static let shared = SecurityScopedResourceManager()
    private var accessingURLs: [URL: Int] = [:] // URL -> reference count
    private let queue = DispatchQueue(label: "security-scoped-resource-queue", attributes: .concurrent)
    
    private init() {}
    
    func startAccessing(_ url: URL) -> Bool {
        return queue.sync(flags: .barrier) {
            // Check if we're already accessing this URL
            if let count = accessingURLs[url] {
                accessingURLs[url] = count + 1
                log("Incremented access count for: \(url.lastPathComponent) (Counter: \(count + 1))", level: .info)
                return true
            }
            
            let success = url.startAccessingSecurityScopedResource()
            if success {
                accessingURLs[url] = 1
                log("Success accessing security-scoped resource: \(url.lastPathComponent)", level: .info)
            } else {
                log("Failed to start accessing security-scoped resource: \(url.lastPathComponent)", level: .error)
            }
            return success
        }
    }
    
    func stopAccessing(_ url: URL) {
        queue.sync(flags: .barrier) {
            guard let count = accessingURLs[url] else { return }
            
            if count > 1 {
                accessingURLs[url] = count - 1
                print("🔄 Decremented access count for: \(url.lastPathComponent) (count: \(count - 1))")
            } else {
                url.stopAccessingSecurityScopedResource()
                accessingURLs.removeValue(forKey: url)
                print("🛑 Stopped accessing security-scoped resource: \(url.lastPathComponent)")
            }
        }
    }
    
    func stopAccessingAll() {
        queue.sync(flags: .barrier) {
            for (url, _) in accessingURLs {
                url.stopAccessingSecurityScopedResource()
                print("🛑 Stopped accessing: \(url.lastPathComponent)")
            }
            accessingURLs.removeAll()
        }
    }
    
    func isAccessing(_ url: URL) -> Bool {
        return queue.sync {
            return accessingURLs[url] != nil
        }
    }
    
    // Perform operations with automatic resource management
    func withSecurityScopedResource<T>(_ url: URL, operation: () throws -> T) throws -> T {
        let wasAlreadyAccessing = isAccessing(url)
        
        if !wasAlreadyAccessing {
            guard startAccessing(url) else {
                throw FileAccessError.accessDenied
            }
        }
        
        defer {
            if !wasAlreadyAccessing {
                stopAccessing(url)
            }
        }
        
        return try operation()
    }
    
    // Special method for folder operations - keeps parent access alive
    func withFolderAccess<T>(_ folderURL: URL, operation: (_ folderURL: URL) throws -> T) throws -> T {
        guard startAccessing(folderURL) else {
            throw FileAccessError.accessDenied
        }
        
        // Don't stop accessing in defer - let caller manage it
        return try operation(folderURL)
    }
}
