//
//  PotraitContentView.swift
//  PoseA
//
//  Created by Ardhika Maulidani on 6/24/25.
//

import SwiftUI

struct LandscapeContentView: View {
    // MARK: - Properties
    @StateObject var cameraManager: CameraLiDARManager
    @StateObject var appState: MainAppState
    @StateObject var ROIModel: ROIViewModel
    
    @State var showSettingsView = false
    @State var showHelpView = false
    
    // MARK: - Body
    var body: some View {
        NavigationView {
            ZStack {
                // Main content
                HStack(spacing: 0) {
                    // Main content container
                    MainContentView(appState: appState,
                                    ROIModel: ROIModel,
                                    cameraManager: cameraManager)
                    
                    Text("PlaceHolder")
                        .font(.caption)
                        .fontWeight(.bold)
                }
                
                // Loading Overlay View
                if appState.isProcessing {
                    ProcessingOverlayView(status: appState.processingStatus)
                }
                
                // Error Overlay
                if let error = appState.errorMessage {
                    ErrorOverlayView(message: error) {
                        appState.errorMessage = nil
                    }
                }
            }
        }
    }
}
   
