//
//  SettingModel.swift
//  PoseA
//
//  Created by Ardhika Maulidani on 9/4/25.
//

import Foundation

enum AngleUnit: String, CaseIterable, Identifiable {
    case deg, rad
    var id: String { rawValue }
}

enum DistanceUnit: String, CaseIterable, Identifiable {
    case px, cm, m
    var id: String { rawValue }
}

enum TimeUnit: String, CaseIterable, Identifiable {
    case n, s
    var id: String { rawValue }
}
