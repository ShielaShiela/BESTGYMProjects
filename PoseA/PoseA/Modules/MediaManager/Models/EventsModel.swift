//
//  EventsModel.swift
//  PoseA
//
//  Created by Ardhika Maulidani on 4/20/26.
//

import Foundation

struct EventsModel: Codable {
    // Rotation Direction
    var rotationDir: String
    
    // Handstand Posture
    var handstandPoseIdx:  Int?
    
    // Release Phase
    var releaseStartPoseIdx: Int?
    var releaseEndPosePhase: Int?
    var release180PoseIdx: Int?
    
    // Flight Phase
    var flightStartPoseIdx: Int?
    var flightEndPoseIdx: Int?
    var ankleCrossIdx: Int?
    var peakFlightIdx: Int?
    
    init(
        rotationDir: String,
        handstandPoseIdx:  Int? = nil,
        releaseStartPoseIdx: Int? = nil,
        releaseEndPosePhase: Int? = nil,
        release180PoseIdx: Int? = nil,
        flightStartPoseIdx: Int? = nil,
        flightEndPoseIdx: Int? = nil,
        ankleCrossIdx: Int? = nil,
        peakFlightIdx: Int? = nil
    ) {
        self.rotationDir = rotationDir
        self.handstandPoseIdx = handstandPoseIdx
        self.releaseStartPoseIdx = releaseStartPoseIdx
        self.releaseEndPosePhase = releaseEndPosePhase
        self.release180PoseIdx = release180PoseIdx
        
        self.flightStartPoseIdx = flightStartPoseIdx
        self.flightEndPoseIdx = flightEndPoseIdx
        self.ankleCrossIdx = ankleCrossIdx
        self.peakFlightIdx = peakFlightIdx
    }
}
