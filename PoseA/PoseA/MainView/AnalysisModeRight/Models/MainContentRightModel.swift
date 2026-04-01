//
//  MainContentRightModel.swift
//  PoseA
//
//  Created by Ardhika Maulidani on 7/14/25.
//


import Foundation

enum RightViewModel {
    case info
    case angle
    case trajectoryAxes
    case velocity
    case acceleration
    case swing
    case dataMetrics
    case flightHeight
    case manualAnnotation   

    var isChartView: Bool {
        switch self {
        case .swing, .angle, .trajectoryAxes, .velocity, .acceleration, .dataMetrics, .flightHeight:
            return true
        case .info, .manualAnnotation:
            return false
        }
    }
}
