//
//  ProjectModel.swift
//  PoseA
//
//  Created by Shiela Cabahug on 2026/2/23.
//
// ProjectModel.swift
import Foundation
import CoreGraphics

// MARK: - Action Type

enum ActionTypePreset: String, Codable, CaseIterable, Hashable {
    case giantSwing = "Giant Swing"
    case kip        = "Kip"
    case release    = "Release & Regrasp"
    case dismount   = "Dismount"
    case tkatchev   = "Tkatchev"
    case kovacs     = "Kovacs"
    case yamawaki   = "Yamawaki"
    case custom     = "Custom..."

    var icon: String {
        switch self {
        case .giantSwing: return "arrow.circlepath"
        case .kip:        return "figure.gymnastics"
        case .release:    return "hands.sparkles"
        case .dismount:   return "figure.fall"
        case .tkatchev:   return "arrow.up.and.down.circle"
        case .kovacs:     return "circle.arrows"
        case .yamawaki:   return "rotate.3d"
        case .custom:     return "pencil.circle"
        }
    }
}

struct ActionType: Codable, Equatable, Hashable {
    var preset: ActionTypePreset
    var customName: String

    var displayName: String {
        preset == .custom ? customName : preset.rawValue
    }

    var icon: String {
        preset.icon
    }

    // MARK: Convenience factories
    static func preset(_ p: ActionTypePreset) -> ActionType {
        ActionType(preset: p, customName: "")
    }
    static func custom(_ name: String) -> ActionType {
        ActionType(preset: .custom, customName: name)
    }

    // MARK: Common defaults
    static let giantSwing = ActionType.preset(.giantSwing)
    static let tkatchev   = ActionType.preset(.tkatchev)
    static let kovacs     = ActionType.preset(.kovacs)
    static let yamawaki   = ActionType.preset(.yamawaki)

    // MARK: Explicit Codable (belt-and-suspenders — struct is already auto-Codable
    //       but being explicit avoids any ambiguity with the nested enum)
    enum CodingKeys: String, CodingKey {
        case preset
        case customName
    }

    init(preset: ActionTypePreset, customName: String = "") {
        self.preset = preset
        self.customName = customName
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        preset     = try container.decode(ActionTypePreset.self, forKey: .preset)
        customName = try container.decodeIfPresent(String.self, forKey: .customName) ?? ""
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(preset,     forKey: .preset)
        try container.encode(customName, forKey: .customName)
    }
}

// MARK: - Athlete Profile

struct AthleteProfile: Codable, Equatable {
    var name: String      = ""
    var age: Int?         = nil
    var heightCm: Double? = nil
    var weightKg: Double? = nil

    var heightDisplay: String {
        guard let h = heightCm else { return "—" }
        return String(format: "%.1f cm", h)
    }
    var weightDisplay: String {
        guard let w = weightKg else { return "—" }
        return String(format: "%.1f kg", w)
    }

    enum CodingKeys: String, CodingKey {
        case name, age, heightCm, weightKg
    }

    init(name: String = "",
         age: Int? = nil,
         heightCm: Double? = nil,
         weightKg: Double? = nil) {
        self.name     = name
        self.age      = age
        self.heightCm = heightCm
        self.weightKg = weightKg
    }

    init(from decoder: Decoder) throws {
        let c    = try decoder.container(keyedBy: CodingKeys.self)
        name     = try c.decodeIfPresent(String.self, forKey: .name)     ?? ""
        age      = try c.decodeIfPresent(Int.self,    forKey: .age)
        heightCm = try c.decodeIfPresent(Double.self, forKey: .heightCm)
        weightKg = try c.decodeIfPresent(Double.self, forKey: .weightKg)
    }

    func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encode(name,     forKey: .name)
        try c.encodeIfPresent(age,      forKey: .age)
        try c.encodeIfPresent(heightCm, forKey: .heightCm)
        try c.encodeIfPresent(weightKg, forKey: .weightKg)
    }
}

// MARK: - CGPoint Codable Wrapper

struct CGPointCodable: Codable, Equatable {
    var x: Double
    var y: Double

    init(_ point: CGPoint) {
        self.x = point.x
        self.y = point.y
    }

    var cgPoint: CGPoint { CGPoint(x: x, y: y) }
}


// MARK: - GymProject

struct GymProject: Codable, Identifiable, Equatable {
    var id: UUID
    var projectName: String
    var athlete: AthleteProfile
    var actionType: ActionType
    var recordedDate: Date
    var createdDate: Date
    var lastModifiedDate: Date
    var notes: String
    var sourceFileName: String
    var sourceRelativePath: String?
    var calibrationData: SavedCalibration?
    var isAnalysisAvailable: Bool

    enum CodingKeys: String, CodingKey {
        case id, projectName, athlete, actionType,
             recordedDate, createdDate, lastModifiedDate,
             notes, sourceFileName, sourceRelativePath,
             calibrationData, isAnalysisAvailable
    }

    // MARK: Memberwise init
    init(projectName: String,
         athlete: AthleteProfile           = AthleteProfile(),
         actionType: ActionType            = .giantSwing,
         recordedDate: Date                = Date(),
         sourceFileName: String            = "",
         notes: String                     = "",
         calibrationData: SavedCalibration? = nil,
         isAnalysisAvailable: Bool         = false) {
        self.id                  = UUID()
        self.projectName         = projectName
        self.athlete             = athlete
        self.actionType          = actionType
        self.recordedDate        = recordedDate
        self.createdDate         = Date()
        self.lastModifiedDate    = Date()
        self.notes               = notes
        self.sourceFileName      = sourceFileName
        self.sourceRelativePath  = nil
        self.calibrationData     = calibrationData
        self.isAnalysisAvailable = isAnalysisAvailable
    }

    // MARK: Decodable
    init(from decoder: Decoder) throws {
        let c                = try decoder.container(keyedBy: CodingKeys.self)
        id                   = try c.decode(UUID.self,          forKey: .id)
        projectName          = try c.decode(String.self,        forKey: .projectName)
        athlete              = try c.decodeIfPresent(AthleteProfile.self,    forKey: .athlete)    ?? AthleteProfile()
        actionType           = try c.decodeIfPresent(ActionType.self,        forKey: .actionType) ?? .giantSwing
        recordedDate         = try c.decode(Date.self,          forKey: .recordedDate)
        createdDate          = try c.decodeIfPresent(Date.self, forKey: .createdDate)          ?? Date()
        lastModifiedDate     = try c.decodeIfPresent(Date.self, forKey: .lastModifiedDate)     ?? Date()
        notes                = try c.decodeIfPresent(String.self, forKey: .notes)              ?? ""
        sourceFileName       = try c.decodeIfPresent(String.self, forKey: .sourceFileName)     ?? ""
        sourceRelativePath   = try c.decodeIfPresent(String.self, forKey: .sourceRelativePath)
        calibrationData      = try c.decodeIfPresent(SavedCalibration.self, forKey: .calibrationData)
        isAnalysisAvailable  = try c.decodeIfPresent(Bool.self, forKey: .isAnalysisAvailable)  ?? false
    }

    // MARK: Encodable
    func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encode(id,                  forKey: .id)
        try c.encode(projectName,         forKey: .projectName)
        try c.encode(athlete,             forKey: .athlete)
        try c.encode(actionType,          forKey: .actionType)
        try c.encode(recordedDate,        forKey: .recordedDate)
        try c.encode(createdDate,         forKey: .createdDate)
        try c.encode(lastModifiedDate,    forKey: .lastModifiedDate)
        try c.encode(notes,               forKey: .notes)
        try c.encode(sourceFileName,      forKey: .sourceFileName)
        try c.encodeIfPresent(sourceRelativePath, forKey: .sourceRelativePath)
        try c.encodeIfPresent(calibrationData,    forKey: .calibrationData)
        try c.encode(isAnalysisAvailable, forKey: .isAnalysisAvailable)
    }
}

// MARK: - Saved Calibration
struct SavedCalibration: Codable, Equatable {
    var isCalibrated: Bool
    var barTopPoint: CGPointCodable?
    var barBottomPoint: CGPointCodable?
    var realBarHeightCm: Double

    enum CodingKeys: String, CodingKey {
        case isCalibrated, barTopPoint, barBottomPoint, realBarHeightCm
    }

    init(isCalibrated: Bool,
         barTopPoint: CGPointCodable?    = nil,
         barBottomPoint: CGPointCodable? = nil,
         realBarHeightCm: Double         = 260) {
        self.isCalibrated    = isCalibrated
        self.barTopPoint     = barTopPoint
        self.barBottomPoint  = barBottomPoint
        self.realBarHeightCm = realBarHeightCm
    }

    init(from decoder: Decoder) throws {
        let c            = try decoder.container(keyedBy: CodingKeys.self)
        isCalibrated     = try c.decode(Bool.self,                    forKey: .isCalibrated)
        barTopPoint      = try c.decodeIfPresent(CGPointCodable.self, forKey: .barTopPoint)
        barBottomPoint   = try c.decodeIfPresent(CGPointCodable.self, forKey: .barBottomPoint)
        realBarHeightCm  = try c.decodeIfPresent(Double.self,         forKey: .realBarHeightCm) ?? 260
    }

    func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encode(isCalibrated,                      forKey: .isCalibrated)
        try c.encodeIfPresent(barTopPoint,              forKey: .barTopPoint)
        try c.encodeIfPresent(barBottomPoint,           forKey: .barBottomPoint)
        try c.encode(realBarHeightCm,                   forKey: .realBarHeightCm)
    }
}
