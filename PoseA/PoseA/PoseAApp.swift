//
//  PoseAApp.swift
//  PoseA
//
//  Created by Shiela Cabahug on 2025/3/3.
//

import SwiftUI
import SwiftData

@main
struct PoseAApp: App {
    var sharedModelContainer: ModelContainer = {
        let schema = Schema([
            Item.self,
        ])
        let modelConfiguration = ModelConfiguration(schema: schema, isStoredInMemoryOnly: false)

        do {
            return try ModelContainer(for: schema, configurations: [modelConfiguration])
        } catch {
            fatalError("Could not create ModelContainer: \(error)")
        }
    }()

    var body: some Scene {
        WindowGroup {
//            let manager = CameraLiDARManager()
                    
            // Pass the manager to the view
            BESTGYMPoseApp()        }
        .modelContainer(sharedModelContainer)
    }
}
//@main
//struct PoseAApp: App {
//    // Create the manager as a StateObject at the app level
//    @StateObject private var manager = CameraLiDARManager()
//    
//    var body: some Scene {
//        WindowGroup {
//            // Pass the manager to the view
//            PoseDepthProcessorView(manager: manager)
//        }
//    }
//}
