//
//  Item.swift
//  PoseA
//
//  Created by Shiela Cabahug on 2025/3/3.
//

import Foundation
import SwiftData

@Model
final class Item {
    var timestamp: Date
    
    init(timestamp: Date) {
        self.timestamp = timestamp
    }
}
