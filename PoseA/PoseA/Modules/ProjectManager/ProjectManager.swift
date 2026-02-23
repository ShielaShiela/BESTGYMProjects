//
//  ProjectManager.swift
//  PoseA
//
//  Created by Shiela Cabahug on 2026/2/23.
//

// ProjectManager.swift
import Foundation

@Observable
class ProjectManager {
    
    static let shared = ProjectManager()
    
    private let fileManager = FileManager.default
    private var projectsDirectory: URL {
        let docs = fileManager.urls(for: .documentDirectory, in: .userDomainMask).first!
        return docs.appendingPathComponent("Projects", isDirectory: true)
    }
    
    var savedProjects: [GymProject] = []
    var isSaving: Bool = false
    var isLoading: Bool = false
    var lastError: String? = nil
    
    init() {
        createProjectsDirectoryIfNeeded()
        loadProjectList()
    }
    
    // MARK: - Directory Setup
    
    private func createProjectsDirectoryIfNeeded() {
        if !fileManager.fileExists(atPath: projectsDirectory.path) {
            try? fileManager.createDirectory(at: projectsDirectory,
                                              withIntermediateDirectories: true)
        }
    }
    
    // MARK: - Save Project
    
    func saveProject(_ project: inout GymProject,
                     keypointsData: [Int: [KeypointData]]?,
                     sourceURL: URL?,
                     completion: @escaping (Result<URL, Error>) -> Void) {
        
        isSaving = true
        project.lastModifiedDate = Date()
        
        let projectSnapshot = project
        let projectDir = projectsDirectory.appendingPathComponent(projectSnapshot.id.uuidString)
        
        Task {
            do {
                try fileManager.createDirectory(at: projectDir, withIntermediateDirectories: true)
                
                // 1. Save project metadata
                let metaURL = projectDir.appendingPathComponent("project.json")
                let encoder = JSONEncoder()
                encoder.dateEncodingStrategy = .iso8601
                encoder.outputFormatting = .prettyPrinted
                let metaData = try encoder.encode(projectSnapshot)
                try metaData.write(to: metaURL)
                
                // 2. Copy source video/LiDAR folder into project directory
                if let srcURL = sourceURL {
                    let destURL = projectDir.appendingPathComponent(srcURL.lastPathComponent)
                    if !fileManager.fileExists(atPath: destURL.path) {
                        let accessing = srcURL.startAccessingSecurityScopedResource()
                        defer { if accessing { srcURL.stopAccessingSecurityScopedResource() } }
                        
                        // Check if it's a directory (LiDAR folder) or single file (video)
                        var isDir: ObjCBool = false
                        fileManager.fileExists(atPath: srcURL.path, isDirectory: &isDir)
                        
                        if isDir.boolValue {
                            try fileManager.copyItem(at: srcURL, to: destURL)
                        } else {
                            try fileManager.copyItem(at: srcURL, to: destURL)
                        }
                    }
                }
                
                // 3. Save keypoints if available
                if let keypoints = keypointsData {
                    let keypointsURL = projectDir.appendingPathComponent("keypoints.json")
                    let stringKeyed = keypoints.mapKeys { String($0) }
                    let kpData = try encoder.encode(stringKeyed)
                    try kpData.write(to: keypointsURL)
                }
                
                await MainActor.run {
                    self.isSaving = false
                    if let idx = self.savedProjects.firstIndex(where: { $0.id == projectSnapshot.id }) {
                        self.savedProjects[idx] = projectSnapshot
                    } else {
                        self.savedProjects.insert(projectSnapshot, at: 0)
                    }
                    completion(.success(projectDir))
                }
                
            } catch {
                await MainActor.run {
                    self.isSaving = false
                    self.lastError = error.localizedDescription
                    completion(.failure(error))
                }
            }
        }
    }

    // MARK: - Get copied source URL for a project
    func sourceFileURL(for project: GymProject) -> URL? {
        guard !project.sourceFileName.isEmpty else { return nil }
        let url = projectsDirectory
            .appendingPathComponent(project.id.uuidString)
            .appendingPathComponent(project.sourceFileName)
        
        var isDir: ObjCBool = false
        let exists = fileManager.fileExists(atPath: url.path, isDirectory: &isDir)
        return exists ? url : nil
    }

    // MARK: - Estimate project source size before saving
    func estimatedSourceSize(sourceURL: URL?) -> String {
        guard let url = sourceURL else { return "Unknown" }
        
        var isDir: ObjCBool = false
        fileManager.fileExists(atPath: url.path, isDirectory: &isDir)
        
        let bytes: Int64
        if isDir.boolValue {
            bytes = directorySize(url: url)
        } else {
            bytes = (try? url.resourceValues(forKeys: [.fileSizeKey]).fileSize)
                .map { Int64($0) } ?? 0
        }
        
        return ByteCountFormatter.string(fromByteCount: bytes, countStyle: .file)
    }

    private func directorySize(url: URL) -> Int64 {
        guard let enumerator = fileManager.enumerator(
            at: url,
            includingPropertiesForKeys: [.fileSizeKey],
            options: .skipsHiddenFiles
        ) else { return 0 }
        
        return enumerator
            .compactMap { $0 as? URL }
            .compactMap { try? $0.resourceValues(forKeys: [.fileSizeKey]).fileSize }
            .reduce(0) { $0 + Int64($1) }
    }
    
    // MARK: - Load Project Metadata
    
    func loadProject(id: UUID) -> GymProject? {
        let metaURL = projectsDirectory
            .appendingPathComponent(id.uuidString)
            .appendingPathComponent("project.json")
        
        guard let data = try? Data(contentsOf: metaURL) else {
            lastError = "Could not read project file for \(id)"
            return nil
        }
        
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        
        do {
            return try decoder.decode(GymProject.self, from: data)
        } catch {
            lastError = "Failed to decode project: \(error.localizedDescription)"
            return nil
        }
    }
    
    // MARK: - Load Keypoints
    
    func loadKeypointsForProject(id: UUID) -> [Int: [KeypointData]]? {
        let keypointsURL = projectsDirectory
            .appendingPathComponent(id.uuidString)
            .appendingPathComponent("keypoints.json")
        
        guard let data = try? Data(contentsOf: keypointsURL) else { return nil }
        
        let decoder = JSONDecoder()
        
        do {
            let stringKeyed = try decoder.decode([String: [KeypointData]].self, from: data)
            return Dictionary(uniqueKeysWithValues: stringKeyed.compactMap { key, value in
                guard let intKey = Int(key) else { return nil }
                return (intKey, value)
            })
        } catch {
            lastError = "Failed to decode keypoints: \(error.localizedDescription)"
            return nil
        }
    }
    
    // MARK: - List Projects
    
    func loadProjectList() {
        isLoading = true
        
        guard let contents = try? fileManager.contentsOfDirectory(
            at: projectsDirectory,
            includingPropertiesForKeys: [.contentModificationDateKey],
            options: .skipsHiddenFiles
        ) else {
            isLoading = false
            return
        }
        
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        
        savedProjects = contents.compactMap { dir in
            let metaURL = dir.appendingPathComponent("project.json")
            guard let data = try? Data(contentsOf: metaURL) else { return nil }
            return try? decoder.decode(GymProject.self, from: data)
        }
        .sorted { $0.lastModifiedDate > $1.lastModifiedDate }
        
        isLoading = false
    }
    
    // MARK: - Update Project (without re-saving keypoints)
    
    /// Use this when you only want to update metadata (e.g. after re-analysis)
    /// without touching the keypoints file.
    func updateProjectMetadata(_ project: inout GymProject,
                                completion: @escaping (Result<Void, Error>) -> Void) {
        project.lastModifiedDate = Date()
        let projectSnapshot = project
        let metaURL = projectsDirectory
            .appendingPathComponent(projectSnapshot.id.uuidString)
            .appendingPathComponent("project.json")
        
        Task {
            do {
                let encoder = JSONEncoder()
                encoder.dateEncodingStrategy = .iso8601
                encoder.outputFormatting = .prettyPrinted
                let data = try encoder.encode(projectSnapshot)
                try data.write(to: metaURL)
                
                await MainActor.run {
                    if let idx = self.savedProjects.firstIndex(where: { $0.id == projectSnapshot.id }) {
                        self.savedProjects[idx] = projectSnapshot
                    }
                    completion(.success(()))
                }
            } catch {
                await MainActor.run {
                    self.lastError = error.localizedDescription
                    completion(.failure(error))
                }
            }
        }
    }
    
    // MARK: - Delete Project
    
    func deleteProject(id: UUID) {
        let projectDir = projectsDirectory.appendingPathComponent(id.uuidString)
        do {
            try fileManager.removeItem(at: projectDir)
            savedProjects.removeAll { $0.id == id }
        } catch {
            lastError = "Failed to delete project: \(error.localizedDescription)"
        }
    }
    
    // MARK: - Check if Project Has Keypoints Saved
    
    func hasKeypointFile(id: UUID) -> Bool {
        let keypointsURL = projectsDirectory
            .appendingPathComponent(id.uuidString)
            .appendingPathComponent("keypoints.json")
        return fileManager.fileExists(atPath: keypointsURL.path)
    }
    
    // MARK: - Project Directory URL (for debugging or export)
    
    func projectDirectoryURL(id: UUID) -> URL {
        projectsDirectory.appendingPathComponent(id.uuidString)
    }
}

// MARK: - Dictionary helper

extension Dictionary {
    func mapKeys<T: Hashable>(_ transform: (Key) -> T) -> [T: Value] {
        Dictionary<T, Value>(uniqueKeysWithValues: map { (transform($0.key), $0.value) })
    }
}
