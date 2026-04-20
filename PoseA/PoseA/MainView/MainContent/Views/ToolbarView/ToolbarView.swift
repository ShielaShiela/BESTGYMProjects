//
//  ToolbarView.swift
//  PoseA
//
//  Created by Ardhika Maulidani on 8/14/25.
//

import SwiftUI

extension BESTGYMPoseApp {
    struct ToolbarLeft: View {
        @ObservedObject var appState: MainAppState
        let toggleMode: () -> Void
        
        var body: some View {
            Button(action: toggleMode) {
                HStack(spacing: 6) {
                    Image(systemName: "record.circle")
                    Text("Record Mode")
                }
            }
            .frame(height: 22)
            .toolbarCapsuleStyle()
        }
    }

    struct ToolbarActiveMode: View {
        @ObservedObject var appState: MainAppState
        @State var toolbarVM: ToolbarButtonVM
        @State var mediaManager: MediaManagerVM
        @State var ROIModel: ROIViewModel
        @State var barPointVM: BarPointVM
        
        var body: some View {
            Group {
                switch toolbarVM.activeMode {
                case .roi:
                    ModeControlView(
                        actions: [
                            .clear { ROIModel.clearROI() },
                            .exit {
                                ROIModel.setROIMode(false)
                                toolbarVM.deactivateMode()
                            }
                        ],
                        label: "ROI"
                    )
                case .box:
                    ModeControlView(
                        actions: [
                            .custom(icon: "arrowshape.right", style: barPointVM.isFirstPointAvailable ? .blue : .gray) {
                                if barPointVM.isFirstPointAvailable { barPointVM.nextPoint() }
                                else { appState.informationMsg = InformationMessage(text: "Pick top bar point first.", type: .warning) }
                            },
                            .clear { barPointVM.clear() },
                            .exit {
                                barPointVM.syncBarPointsToMediaManager(mediaManagerVM: mediaManager)
                                barPointVM.setSelectMode(false)
                                toolbarVM.deactivateMode()
                            }
                        ],
                        label: "BarPoint"
                    )
                case .zoom:
                    ModeControlView(
                        actions: [
                            .exit {
                                appState.isZoomMode = false
                                toolbarVM.deactivateMode()
                            }
                        ],
                        label: "Zoom"
                    )
                default:
                    EmptyView()
                }
            }
        }
    }

    struct ToolbarMainActions: View {
        @ObservedObject var appState: MainAppState
        @State var toolbarVM: ToolbarButtonVM
        @State var mediaManager: MediaManagerVM
        @State var ROIModel: ROIViewModel
        @State var barPointVM: BarPointVM

        var body: some View {
            if mediaManager.isMediaAvailable {
                HStack(spacing: 6) {
                    ToolbarButtonView(mode: .roi, icon: "crop", title: "ROI", viewModel: toolbarVM) {
                        ROIModel.setROIMode(true)
                    }
                    ToolbarButtonView(mode: .box, icon: "square.dashed", title: "Box", viewModel: toolbarVM) {
                        barPointVM.setSelectMode(true)
                    }
                    ToolbarButtonView(mode: .zoom, icon: "plus.magnifyingglass", title: "Zoom", viewModel: toolbarVM) {
                        appState.isZoomMode = true
                    }
                }
                .toolbarCapsuleStyle()
            } else {
                EmptyView()
            }
        }
    }
    
    struct ToolbarRight: View {
        @ObservedObject var appState: MainAppState
        let selectFileOrFolder: () -> Void
        let selectVideoFromLibrary: () -> Void
        let selectKeypointFile: () -> Void
        
        var body: some View {
            HStack(spacing: 6) {
                Button(action: selectFileOrFolder) {
                    Image(systemName: "folder")
                }
                
                Button(action: selectVideoFromLibrary) {
                    Image(systemName: "photo.on.rectangle")
                }
                
                Menu {
                    Button(action: selectFileOrFolder) {
                        Label("Open File/Folder", systemImage: "folder")
                    }
                    Button(action: selectVideoFromLibrary) {
                        Label("Video from Library", systemImage: "photo.on.rectangle")
                    }
                    Divider()
                    Button(action: selectKeypointFile) {
                        Label("Import Keypoints (.json)", systemImage: "square.and.arrow.down")
                    }
                    Divider()
                    Button { appState.showSettingsView = true } label: {
                        Label("Settings", systemImage: "gear")
                    }
                } label: {
                    Label("Actions", systemImage: "ellipsis.circle")
                }
            }
            .frame(height: 22)
            .toolbarCapsuleStyle()
        }
    }

    private struct ModeControlView: View {
        let actions: [ModeAction]
        let label: String
        
        var body: some View {
            HStack(spacing: 6) {
                ForEach(actions, id: \.id) { action in
                    Button(action: action.handler) {
                        Label(label, systemImage: action.icon)
                            .foregroundStyle(action.style)
                    }
                }
            }
            .toolbarCapsuleStyle()
        }
    }
    
    struct ModeAction {
        let id = UUID()
        let icon: String
        let style: Color
        let handler: () -> Void
        
        static func clear(action: @escaping () -> Void) -> ModeAction {
            ModeAction(icon: "trash", style: .red, handler: action)
        }
        
        static func exit(action: @escaping () -> Void) -> ModeAction {
            ModeAction(icon: "xmark", style: .gray, handler: action)
        }
        
        static func custom(icon: String, style: Color = .primary, action: @escaping () -> Void) -> ModeAction {
            ModeAction(icon: icon, style: style, handler: action)
        }
    }
}
