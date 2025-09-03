//
//  RealtimePoseJointVM.swift
//  PoseA
//
//  Created by Ardhika Maulidani on 8/28/25.
//

import Foundation

@Observable
class RTPoseJointVM {
    // MARK: - Properties
    var angleCompleteData: [JointData] = []
    var positionCompleteData: [JointData] = []
    var velocityCompleteData: [JointData] = []
    var accelerationCompleteData: [JointData] = []
        
    var barPosition: [PointData] = []
    var swingData: [JointData] = []
    
    private let fps: Float = 30.0
    private let processingQueue = DispatchQueue(label: "com.posea.processing", qos: .userInitiated)
    
    // MARK: - Init
    init() {
        
    }
    
    // MARK: - Public Function
    
    
}
