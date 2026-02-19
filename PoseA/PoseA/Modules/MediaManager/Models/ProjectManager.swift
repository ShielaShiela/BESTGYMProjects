//
//  ProjectManager.swift
//  PoseA
//
//  Created by Shiela Cabahug on 2026/2/19.
//

// ProjectManager.swift
import Foundation
import UIKit

struct GymProject: Codable {
    var version: Int = 1
    var projectName: String
    var sourceVideoName: String
    var createdAt: Date
    var frameCount: Int
    var fps: Double
    var calibration: CalibrationData?
    
    struct CalibrationData: Codable {
        var barTopX: Double
        var barTopY: Double
        var barBottomX: Double
        var barBottomY: Double
        var realBarHeightCm: Double
    }
}

class ProjectManager {
    static let shared = ProjectManager()
    
    private let fileManager = FileManager.default
    
    // Base directory: Documents/GymProjects/
    var projectsBaseURL: URL {
        let docs = fileManager.urls(for: .documentDirectory, in: .userDomainMask)[0]
        return docs.appendingPathComponent("GymProjects", isDirectory: true)
    }
    
    func ensureBaseDirectoryExists() throws {
        if !fileManager.fileExists(atPath: projectsBaseURL.path) {
            try fileManager.createDirectory(at: projectsBaseURL, withIntermediateDirectories: true)
        }
    }
    
    // MARK: - Save Project
    
    func saveProject(
        name: String,
        videoURL: URL,
        keypoints: [[KeypointData]],       // your existing type
        calibration: CalibrationModel,
        frameCount: Int,
        fps: Double,
        completion: @escaping (Result<URL, Error>) -> Void
    ) {
        DispatchQueue.global(qos: .userInitiated).async {
            do {
                try self.ensureBaseDirectoryExists()
                
                // Create project folder: Documents/GymProjects/<name>/
                let safeProjectName = name.replacingOccurrences(of: "/", with: "-")
                let projectURL = self.projectsBaseURL.appendingPathComponent(safeProjectName, isDirectory: true)
                
                if !self.fileManager.fileExists(atPath: projectURL.path) {
                    try self.fileManager.createDirectory(at: projectURL, withIntermediateDirectories: true)
                }
                
                // 1. Copy video
                let videoDestURL = projectURL.appendingPathComponent(videoURL.lastPathComponent)
                if !self.fileManager.fileExists(atPath: videoDestURL.path) {
                    try self.fileManager.copyItem(at: videoURL, to: videoDestURL)
                }
                
                // 2. Save keypoints as JSON
                let keypointsURL = projectURL.appendingPathComponent("keypoints.json")
                let keypointsData = try JSONEncoder().encode(keypoints)
                try keypointsData.write(to: keypointsURL)
                
                // 3. Save project metadata
                var calData: GymProject.CalibrationData? = nil
                if calibration.isCalibrated,
                   let top = calibration.barTopPoint,
                   let bottom = calibration.barBottomPoint {
                    calData = GymProject.CalibrationData(
                        barTopX: top.x,
                        barTopY: top.y,
                        barBottomX: bottom.x,
                        barBottomY: bottom.y,
                        realBarHeightCm: calibration.realBarHeightCm
                    )
                }
                
                let project = GymProject(
                    projectName: safeProjectName,
                    sourceVideoName: videoURL.lastPathComponent,
                    createdAt: Date(),
                    frameCount: frameCount,
                    fps: fps,
                    calibration: calData
                )
                
                let projectMetaURL = projectURL.appendingPathComponent("project.json")
                let metaData = try JSONEncoder().encode(project)
                try metaData.write(to: projectMetaURL)
                
                // 4. Save thumbnail (first frame)
                // You can generate this from mediaManager.currentFrameImage
                
                DispatchQueue.main.async {
                    completion(.success(projectURL))
                }
                
            } catch {
                DispatchQueue.main.async {
                    completion(.failure(error))
                }
            }
        }
    }
    
    // MARK: - Load Project
    
    func loadProject(
        from projectURL: URL,
        completion: @escaping (Result<LoadedProject, Error>) -> Void
    ) {
        DispatchQueue.global(qos: .userInitiated).async {
            do {
                // Load project.json
                let metaURL = projectURL.appendingPathComponent("project.json")
                let metaData = try Data(contentsOf: metaURL)
                let project = try JSONDecoder().decode(GymProject.self, from: metaData)
                
                // Load keypoints.json
                let keypointsURL = projectURL.appendingPathComponent("keypoints.json")
                let keypointsData = try Data(contentsOf: keypointsURL)
                let keypoints = try JSONDecoder().decode([[KeypointData]].self, from: keypointsData)
                
                // Video URL
                let videoURL = projectURL.appendingPathComponent(project.sourceVideoName)
                
                DispatchQueue.main.async {
                    completion(.success(LoadedProject(
                        metadata: project,
                        keypoints: keypoints,
                        videoURL: videoURL
                    )))
                }
            } catch {
                DispatchQueue.main.async {
                    completion(.failure(error))
                }
            }
        }
    }
    
    // MARK: - List Projects
    
    func listProjects() -> [URL] {
        guard let contents = try? fileManager.contentsOfDirectory(
            at: projectsBaseURL,
            includingPropertiesForKeys: [.isDirectoryKey],
            options: .skipsHiddenFiles
        ) else { return [] }
        
        return contents.filter { url in
            var isDir: ObjCBool = false
            fileManager.fileExists(atPath: url.path, isDirectory: &isDir)
            return isDir.boolValue
        }.sorted { a, b in
            // Sort by modification date, newest first
            let aDate = (try? a.resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate) ?? Date.distantPast
            let bDate = (try? b.resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate) ?? Date.distantPast
            return aDate > bDate
        }
    }
}

// MARK: - Loaded Project Result
struct LoadedProject {
    let metadata: GymProject
    let keypoints: [[KeypointData]]
    let videoURL: URL
}
