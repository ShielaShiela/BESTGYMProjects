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
        @State var ROIModel: ROIViewModel
        @State var BoxModel: BoxViewModel
        @State var calibrationModel: CalibrationModel
        
        var body: some View {
            Group {
                switch toolbarVM.activeMode {
                case .roi:
                    ModeControlView(
                        clearAction: { ROIModel.clearROI() },
                        exitAction: {
                            ROIModel.setROIMode(false)
                            toolbarVM.deactivateMode()
                        },
                        label: "ROI"
                    )
                case .box:
                    ModeControlView(
                        clearAction: { BoxModel.clearBox() },
                        exitAction: {
                            BoxModel.setBoxMode(false)
                            toolbarVM.deactivateMode()
                        },
                        label: "Box"
                    )
                case .annotate:
                    ModeControlView(
                        clearAction: { print("Return Annotate") },
                        exitAction: {
                            appState.isAnnotationMode = false
                            toolbarVM.deactivateMode()
                        },
                        label: "Annotate"
                    )
                case .zoom:
                    ModeControlView(
                        clearAction: { print("Return Zoom") },
                        exitAction: {
                            appState.isZoomMode = false
                            toolbarVM.deactivateMode()
                        },
                        label: "Zoom"
                    )
                case .calibrate:
                    CalibrationModeControlView(
                        calibrationModel: $calibrationModel,
                        exitAction: {
                            calibrationModel.isCalibrationMode = false
                            toolbarVM.deactivateMode()
                        }
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
        @State var BoxModel: BoxViewModel
        @State var calibrationModel: CalibrationModel

        var body: some View {
            if mediaManager.isMediaAvailable {
                HStack(spacing: 6) {
                    ToolbarButtonView(mode: .roi, icon: "crop", title: "ROI", viewModel: toolbarVM) {
                        ROIModel.setROIMode(true)
                    }
                    ToolbarButtonView(mode: .box, icon: "square.dashed", title: "Box", viewModel: toolbarVM) {
                        BoxModel.setBoxMode(true)
                    }
                    ToolbarButtonView(mode: .annotate, icon: "figure", title: "Annotate", viewModel: toolbarVM) {
                        appState.isAnnotationMode = true
                    }
                    ToolbarButtonView(mode: .zoom, icon: "plus.magnifyingglass", title: "Zoom", viewModel: toolbarVM) {
                        appState.isZoomMode = true
                    }
                    ToolbarButtonView(
                        mode: .calibrate,
                        icon: calibrationModel.isCalibrated ? "ruler.fill" : "ruler",
                        title: "Calibrate",
                        viewModel: toolbarVM
                    ) {
                        calibrationModel.startCalibration()
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
        let saveProject: () -> Void
        
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
                    Button(action: saveProject) {
                        Label("Save Projects", systemImage: "square.and.arrow.down")
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
        let clearAction: () -> Void
        let exitAction: () -> Void
        let label: String
        
        var body: some View {
            HStack(spacing: 6) {
                Button(action: clearAction) {
                    Label(label, systemImage: "trash").foregroundStyle(.red)
                }
                Button(action: exitAction) {
                    Label(label, systemImage: "xmark").foregroundStyle(.gray)
                }
            }
            .toolbarCapsuleStyle()
        }
    }
}
