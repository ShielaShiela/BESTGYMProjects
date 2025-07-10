//
//  MainAppViewModel.swift
//  PoseA
//
//  Created by Ardhika Maulidani on 6/24/25.
//

import SwiftUI

class MainAppViewModel: ObservableObject {
    @Published var isRecordMode: Bool = false
    @Published var showSettingsView = false
    @Published var showHelpView = false
    
    func toggleMode() {
        isRecordMode.toggle()
    }

    func selectFileOrFolder() { /* logic */ }
    func selectVideoFile() { /* logic */ }
    func selectKeypointFile() { /* logic */ }
    // etc...
}
