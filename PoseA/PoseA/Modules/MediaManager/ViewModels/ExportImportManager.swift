//
//  ExportImportManager.swift
//  PoseA
//
//  Created by Ardhika Maulidani on 4/15/26.
//

import Foundation
import CoreGraphics

// MARK: - Export/Import Errors
enum ExportImportError: Error, LocalizedError {
    case invalidFormat
    case fileNotFound
    case corruptedData
    case unsupportedFileType
    case encodingError
    case decodingError
    
    var errorDescription: String? {
        switch self {
        case .invalidFormat:
            return "Invalid file format"
        case .fileNotFound:
            return "File not found"
        case .corruptedData:
            return "Corrupted data"
        case .unsupportedFileType:
            return "Unsupported file type"
        case .encodingError:
            return "Failed to encode data"
        case .decodingError:
            return "Failed to decode data"
        }
    }
}

// MARK: - Data Export Import Manager
class ExportImportManager {
    // MARK: - Events Export/Import
    static func exportEvents(
        eventsData: EventsModel,
        to fileURL: URL
    ) throws {
        let exportData = eventsData
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        let jsonData = try encoder.encode(exportData)
        try jsonData.write(to: fileURL)
    }
    
    static func importEvents(from fileURL: URL) throws -> EventsModel {
        guard FileManager.default.fileExists(atPath: fileURL.path) else {
            throw ExportImportError.fileNotFound
        }
        
        do {
            let jsonData = try Data(contentsOf: fileURL)
            let decoder = JSONDecoder()
            let importData = try decoder.decode(EventsModel.self, from: jsonData)
            return importData
        } catch is DecodingError {
            throw ExportImportError.decodingError
        } catch {
            throw ExportImportError.corruptedData
        }
    }
    
    // MARK: - Features Export/Import
    static func exportFeatures(
        featuresData: [Int: FeaturesModel],
        scalePxPerM: Double,
        to fileURL: URL
    ) throws {
        let sortedFrames = featuresData.keys.sorted()
        
        let features = sortedFrames.compactMap { frameIndex in
            featuresData[frameIndex]
        }
        
        let exportData = FeaturesExportModel(
            features: features,
            scalePxPerM: scalePxPerM
        )
        
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        let jsonData = try encoder.encode(exportData)
        try jsonData.write(to: fileURL)
    }
    
    static func importFeatures(from fileURL: URL) throws -> ([Int: FeaturesModel], Double) {
        let jsonData = try Data(contentsOf: fileURL)
        let decoder = JSONDecoder()
        let exportData = try decoder.decode(FeaturesExportModel.self, from: jsonData)
        
        var featuresData: [Int: FeaturesModel] = [:]
        
        for feature in exportData.features {
            featuresData[feature.frameIdx] = feature
        }
        
        return (featuresData, exportData.scalePxPerM)
    }
    
    // MARK: - CoM Export/Import
    static func exportCoM(
        comData: [Int: CGPoint],
        missingFrames: Set<Int>,
        to fileURL: URL
    ) throws {
        let sortedFrames = comData.keys.sorted()
        
        let frames = sortedFrames.map { frameIndex in
            CoMDataModel(
                frameNumber: frameIndex,
                com: comData[frameIndex] ?? .zero,
                poseMissing: missingFrames.contains(frameIndex)
            )
        }
        
        let exportData = CoMExportModel(
            frames: frames,
            frameCount: comData.count,
            exportTime: Date().timeIntervalSince1970
        )
        
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        let jsonData = try encoder.encode(exportData)
        try jsonData.write(to: fileURL)
    }
    
    static func importCoM(from fileURL: URL) throws -> ([Int: CGPoint], Set<Int>) {
        let jsonData = try Data(contentsOf: fileURL)
        let decoder = JSONDecoder()
        let exportData = try decoder.decode(CoMExportModel.self, from: jsonData)
        
        var comData: [Int: CGPoint] = [:]
        var missingFrames: Set<Int> = []
        
        for frame in exportData.frames {
            comData[frame.frameNumber] = frame.com
            if frame.poseMissing {
                missingFrames.insert(frame.frameNumber)
            }
        }
        
        return (comData, missingFrames)
    }
    // MARK: - Keypoint Export/Import
//    static func exportKeypointsCodable(
//        keypointData: [Int: PoseBox],
//        to fileURL: URL,
//        sourceInfo: [String: Any]?
//    ) throws {
//        // Implementation for Codable keypoint export
//        // This would require creating Codable structs for PoseBox and KeypointData
//        // For now, fall back to legacy format
//        try exportKeypointsLegacy(keypointData: keypointData, to: fileURL, sourceInfo: sourceInfo)
//    }
//    
//    static func importKeypoints(from fileURL: URL) throws -> [Int: PoseBox] {
//        guard fileURL.pathExtension.lowercased() == "json" else {
//            throw DataExportImportError.unsupportedFileType
//        }
//        
//        let data = try Data(contentsOf: fileURL)
//        guard let jsonObject = try JSONSerialization.jsonObject(with: data, options: []) as? [String: Any] else {
//            throw DataExportImportError.invalidFormat
//        }
//        
//        var keypointData: [Int: PoseBox] = [:]
//        
//        // Parse bbox data
//        if let bboxData = jsonObject["frames_bbox"] as? [String: [String: Any]] {
//            for (key, points) in bboxData {
//                if key.hasPrefix("framebbox_"),
//                   let frameIndexString = key.split(separator: "_").last,
//                   let frameIndex = Int(frameIndexString) {
//                    let poseBoxFrame = parseBboxFromDictionary(points, frameIndex: frameIndex)
//                    keypointData[frameIndex] = poseBoxFrame
//                }
//            }
//        }
//        
//        // Parse keypoint data
//        if let framesData = jsonObject["frames"] as? [String: [[String: Any]]] {
//            for (key, points) in framesData {
//                if key.hasPrefix("frame_"),
//                   let frameIndexString = key.split(separator: "_").last,
//                   let frameIndex = Int(frameIndexString) {
//                    let keypointsFrame = parseKeypointsFromDictionary(points, frameIndex: frameIndex)
//                    keypointData[frameIndex]?.keypoints = keypointsFrame
//                }
//            }
//        } else {
//            throw DataExportImportError.invalidFormat
//        }
//        
//        return keypointData
//    }
}
