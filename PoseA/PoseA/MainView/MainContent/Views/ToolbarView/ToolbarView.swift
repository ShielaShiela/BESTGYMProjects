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

    // MARK: - ToolbarActiveMode
    struct ToolbarActiveMode: View {
        @ObservedObject var appState: MainAppState
        @State var toolbarVM: ToolbarButtonVM
        @State var ROIModel: ROIViewModel
        @State var BoxModel: BoxViewModel
        @Bindable var calibrationModel: CalibrationModel
        @Bindable var quadCalibrationModel: QuadCalibrationModel
        

        var body: some View {
            modeContent
        }

        @ViewBuilder
        private var modeContent: some View {
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
            case .calibrateBar:
                CalibrationModeControlView(
                    calibrationModel: calibrationModel,
                    exitAction: {
                        calibrationModel.isCalibrationMode = false  // only touches its own flag
                        toolbarVM.deactivateMode()
                    }
                )

            case .calibrateQuad:
                QuadCalibrationModeControlView(
                    quadCalibrationModel: quadCalibrationModel,
                    exitAction: {
                        quadCalibrationModel.isQuadCalibrationMode = false  // only touches its own flag
                        if quadCalibrationModel.step == .placing {
                            quadCalibrationModel.step = .idle
                        }
                        toolbarVM.deactivateMode()
                    }
                )
            
            default:
                EmptyView()
            }
        }
    }

    // MARK: - ToolbarMainActions
    struct ToolbarMainActions: View {
        @ObservedObject var appState: MainAppState
        @State var toolbarVM: ToolbarButtonVM
        @State var mediaManager: MediaManagerVM
        @State var ROIModel: ROIViewModel
        @State var BoxModel: BoxViewModel
        @Bindable var calibrationModel: CalibrationModel
        @Bindable var quadCalibrationModel: QuadCalibrationModel
        @Binding var showKeypointOverlay: Bool
        @Binding var showBoxOverlay: Bool

        var body: some View {
            if mediaManager.isMediaAvailable {
                HStack(spacing: 6) {
                    overlayToggle(isOn: $showKeypointOverlay, icon: "figure.stand", help: "Toggle Keypoints")
                    overlayToggle(isOn: $showBoxOverlay, icon: "square.dashed", help: "Toggle Box Overlay")

                    Divider().frame(height: 14).opacity(0.4)

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
        
                    // Bar button
                    ToolbarButtonView(mode: .calibrateBar, icon: "ruler", title: "Bar", viewModel: toolbarVM) {
                        calibrationModel.isCalibrationMode = true   // only this
                        calibrationModel.startTwoPointCalibration()
                    }

                    // Quad button
                    ToolbarButtonView(mode: .calibrateQuad, icon: "square.on.square", title: "Quad", viewModel: toolbarVM) {
                        quadCalibrationModel.isQuadCalibrationMode = true  // only this
                        quadCalibrationModel.startPlacing()
                    }                }
                .toolbarCapsuleStyle()
            } else {
                EmptyView()
            }
        }

        private func overlayToggle(isOn: Binding<Bool>, icon: String, help: String) -> some View {
            Button {
                isOn.wrappedValue.toggle()
            } label: {
                ZStack {
                    Circle()
                        .fill(isOn.wrappedValue ? Color.blue : Color.clear)
                        .frame(height: 22)
                    Image(systemName: icon)
                        .foregroundStyle(isOn.wrappedValue ? Color.white : Color.blue)
                }
                .contentShape(Circle())
            }
            .buttonStyle(.plain)
            .help(help)
        }
    }

    // MARK: - ToolbarRight
    struct ToolbarRight: View {
        @ObservedObject var appState: MainAppState
        let selectFileOrFolder: () -> Void
        let selectVideoFromLibrary: () -> Void
        let selectKeypointFile: () -> Void
        let saveProject: () -> Void
        @Binding var showSaveProjectSheet: Bool
        @Binding var showProjectList: Bool

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
                    Button { saveProject() } label: {
                        Label("Save Project", systemImage: "folder.badge.plus")
                    }
                    Button(action: { showProjectList = true }) {
                        Label("Open Project", systemImage: "folder.badge.person.crop")
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

    // MARK: - ModeControlView
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
