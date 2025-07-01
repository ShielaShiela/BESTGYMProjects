//
//  LandscapeToolbarView.swift
//  PoseA
//
//  Created by Ardhika Maulidani on 6/24/25.
//

import SwiftUI

//struct LeftToolbarView: View {
//    @ObservedObject var appState: MainAppState
//
//    var body: some View {
//        // Left Toolbar: File Related Toolbar
//        HStack {
//            if !appState.isRecordMode {
//                // Open File/Video Button
//                Button {
//                    selectFileOrFolder()
//                } label: {
//                    Image(systemName: "folder")
//                }
//            }
//            
//            Menu {
//                // Analysis Mode actions
//                Button { selectFileOrFolder() } label: {
//                    Label("Open File/Folder", systemImage: "folder")
//                }
//                Button { selectVideoFile() } label: {
//                    Label("Open Video File", systemImage: "film")
//                }
//                Button { selectVideoFromLibrary() } label: {
//                    Label("Video from Library", systemImage: "photo.on.rectangle")
//                }
//                
//                Divider()
//                
//                Button { selectKeypointFile() } label: {
//                    Label("Import Keypoints (.json)", systemImage: "square.and.arrow.down")
//                }
//            }label: {
//                Label("Actions", systemImage: "ellipsis.circle")
//            }
//        }
//        .padding(.horizontal, 6)
//        .padding(.vertical, 4)
//        .background(Color(.systemGray5))
//        .clipShape(Capsule())
//    }
//}
