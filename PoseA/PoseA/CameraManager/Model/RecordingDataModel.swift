//
//  RecordingModel.swift
//  PoseA
//
//  Created by Ardhika Maulidani on 6/25/25.
//

import Foundation

struct RecordingDataModel {
    var athleteName: String = "Test"
    var actionType: String = "Test"
    var distanceValue: String? = "Test"
    var videoSettings = VideoSettings.defaultSettings
}

struct VideoFormat {
    let width: Int
    let height: Int
    let fps: Int
}

struct VideoSettings {
    var selectedFormat: VideoFormat
    
    static let defaultSettings = VideoSettings(
        selectedFormat: VideoFormat(width: 1920, height: 1080, fps: 30)
    )
}

