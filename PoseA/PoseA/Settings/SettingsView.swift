//
//  SettingsView.swift
//  PoseA
//
//  Created by Ardhika Maulidani on 5/27/25.
//  Refactor from Shiela Cabahug's codebase

import SwiftUI

struct SettingsView: View {
    @ObservedObject var appState: AppState
    @Environment(\.presentationMode) var presentationMode
    
    var body: some View {
        NavigationView {
            Form {
                Section(header: Text("Analysis Options")) {
                    Toggle("Auto-detect keypoints when loading video", isOn: $appState.autoDetectKeypoints)
                        .onChange(of: appState.autoDetectKeypoints) {
                            appState.saveUserPreferences()
                        }
                }
                
                Section(header: Text("Media Settings")) {
                    Toggle("Auto-load default data on startup", isOn: .constant(UserDefaults.standard.bool(forKey: "AutoLoadEnabled")))
                        .onChange(of: UserDefaults.standard.bool(forKey: "AutoLoadEnabled")) { oldValue, newValue in
                            UserDefaults.standard.set(newValue, forKey: "AutoLoadEnabled")
                        }
                    // Add more settings as needed
                }
            }
            .navigationTitle("Settings")
            .navigationBarItems(trailing: Button("Done") {
                presentationMode.wrappedValue.dismiss()
            })
        }
    }
}
