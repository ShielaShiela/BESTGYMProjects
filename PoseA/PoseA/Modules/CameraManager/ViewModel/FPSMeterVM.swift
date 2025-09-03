//
//  FPSMeterVM.swift
//  PoseA
//
//  Created by Ardhika Maulidani on 8/22/25.
//

import Foundation

final class FPSMeter {
    private var lastTime: CFAbsoluteTime = CFAbsoluteTimeGetCurrent()
    private var frameCount: Int = 0
    private(set) var fps: Double = 0
    
    private let label: String
    private let autoPrint: Bool
    
    init(label: String, autoPrint: Bool = false) {
        self.label = label
        self.autoPrint = autoPrint
    }
    
    func tick() {
        frameCount += 1
        let now = CFAbsoluteTimeGetCurrent()
        if now - lastTime >= 1.0 {
            fps = Double(frameCount) / (now - lastTime)
            if autoPrint {
                print(" \(label) FPS: \(String(format: "%.1f", fps))")
            }
            frameCount = 0
            lastTime = now
        }
    }
}
