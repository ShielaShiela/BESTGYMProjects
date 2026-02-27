//
//  RecordLandscapeView.swift
//  PoseA
//
//  Created by Ardhika Maulidani on 7/21/25.
//

import SwiftUI

// MARK: - RecordLandscapeView.swift (Updated)

struct RecordLandscapeView: View {
    @ObservedObject var appState: MainAppState
    @ObservedObject var cameraManager: CameraManagerVM
    
    @State private var showInfoView: Bool = false
    @State private var showAthleteEditor: Bool = false
    @State private var recordingDuration: TimeInterval = 0
    @State private var recordingTimer: Timer? = nil
    
    var body: some View {
        ZStack {
            Color.black
            
            GeometryReader { geometry in
                let isLandscape = OrientationCache.shared.orientation == .landscapeLeft ||
                                  OrientationCache.shared.orientation == .landscapeRight
                
                // ── FULL-SCREEN CAMERA ──────────────────────────────────────
                if cameraManager.isCameraReady {
                    ZStack {
                        CameraPreviewView(cameraManager: self.cameraManager)
                            .frame(width: geometry.size.width, height: geometry.size.height)
                        
                        if appState.realtimeDetection {
                            PoseOverlayView(
                                poses: self.cameraManager.poseKeypoints,
                                videoSize: isLandscape
                                    ? CGSize(width: cameraManager.cameraConfiguration.resolution.width,
                                             height: cameraManager.cameraConfiguration.resolution.height)
                                    : CGSize(width: cameraManager.cameraConfiguration.resolution.height,
                                             height: cameraManager.cameraConfiguration.resolution.width)
                            )
                            PoseInformationView()
                            if appState.realtimeViewMode == "side-view" {
                                PointPickerView().allowsHitTesting(true)
                            }
                        }
                    }
                    .frame(width: geometry.size.width, height: geometry.size.height)
                    .onAppear  { cameraManager.startCenterDepthDetection() }
                    .onDisappear { cameraManager.stopCenterDepthDetection() }
                    .onChange(of: appState.realtimeDetection) { cameraManager.toogleRealtimeDetection() }
                    .onChange(of: appState.realtimeModel) { _, newValue in cameraManager.setRealtimeModelVersion(newValue) }
                    .transition(.opacity)
                }
                
                // ── LEFT SIDEBAR: Info + Gear only ──────────────────────────
                VStack(spacing: 0) {
                    // Info
                    Button { showInfoView = true } label: {
                        SidebarIcon(systemName: "info.circle")
                    }
                    .popover(isPresented: $showInfoView) { infoPopover }
                    
                    Spacer()
                    
                    // Gear → opens Settings (FPS + Resolution now live inside)
                    Button { appState.showSettingsView = true } label: {
                        SidebarIcon(systemName: "gear")
                    }
                }
                .padding(.vertical, 20)
                .padding(.leading, 10)
                .frame(width: 60, height: geometry.size.height)
                .position(x: 30, y: geometry.size.height * 0.5)
                
                // ── RIGHT SIDEBAR ───────────────────────────────────────────
                VStack(spacing: 0) {
                    
                    // Analysis Mode (top)
                    Button {
                        appState.isRecordMode = false
                        if cameraManager.isRecording { cameraManager.stopRecording { _ in } }
                        DispatchQueue.global(qos: .userInitiated).async {
                            self.cameraManager.pauseStream()
                            DispatchQueue.main.async {
                                self.cameraManager.isLiveCapture = false
                            }
                        }
                    } label: {
                        SidebarIcon(systemName: "waveform")
                    }
                    
                    Spacer()
                    
                    // ── Pose Detection Toggle ───────────────────────────────
                    TogglePill(
                        icon: "figure.walk",
                        label: "Pose",
                        isOn: $appState.realtimeDetection,
                        activeColor: .green
                    )
                    .onChange(of: appState.realtimeDetection) {
                        if appState.realtimeDetection {
                            // Auto-set to the fastest/most reliable model
                            appState.realtimeModel = "yolo11n-pose"
                        }
                        appState.saveUserPreferences()
                    }
                    
                    Spacer()
                    
                    // ── LiDAR Toggle ────────────────────────────────────────
                    TogglePill(
                        icon: "sensor.tag.radiowaves.forward",
                        label: "LiDAR",
                        isOn: $appState.useLiDAR,
                        activeColor: .yellow,
                        disabled: !cameraManager.isLiDARSupported
                    )
                    .onChange(of: appState.useLiDAR) {
                        cameraManager.toggleLiDAR()
                    }
                    
                    Spacer()
                    
                    // ── Athlete Info Preview ────────────────────────────────
                    Button { showAthleteEditor = true } label: {
                        VStack(spacing: 3) {
                            HStack(spacing: 4) {
                                Image(systemName: "person.fill")
                                    .font(.system(size: 9))
                                    .foregroundStyle(.white.opacity(0.5))
                                Text(appState.athleteName.isEmpty ? "Name?" : appState.athleteName)
                                    .font(.system(size: 11, weight: .semibold))
                                    .foregroundStyle(appState.athleteName.isEmpty ? .orange : .white)
                                    .lineLimit(1)
                                    .truncationMode(.middle)
                            }
                            HStack(spacing: 4) {
                                Image(systemName: "figure.gymnastics")
                                    .font(.system(size: 9))
                                    .foregroundStyle(.white.opacity(0.5))
                                Text(appState.actionType.isEmpty ? "Action?" : appState.actionType)
                                    .font(.system(size: 10))
                                    .foregroundStyle(appState.actionType.isEmpty ? .orange : .white.opacity(0.75))
                                    .lineLimit(1)
                                    .truncationMode(.middle)
                            }
                        }
                        .padding(.horizontal, 8)
                        .padding(.vertical, 6)
                        .frame(maxWidth: 90)
                        .background(
                            RoundedRectangle(cornerRadius: 10)
                                .fill(.ultraThinMaterial)
                                .overlay(
                                    RoundedRectangle(cornerRadius: 10)
                                        .stroke(
                                            (appState.athleteName.isEmpty || appState.actionType.isEmpty)
                                                ? Color.orange.opacity(0.6)
                                                : Color.white.opacity(0.15),
                                            lineWidth: 1
                                        )
                                )
                        )
                    }
                    .popover(isPresented: $showAthleteEditor) {
                        athleteEditorPopover
                    }
                    
                    Spacer()
                    
                    // ── Record Button ───────────────────────────────────────
                    VStack(spacing: 6) {
                        if cameraManager.isRecording {
                            // Live FPS during recording
                            Text("\(cameraManager.fpsStream, specifier: "%.0f") fps")
                                .font(.system(size: 10, weight: .bold, design: .monospaced))
                                .foregroundStyle(.white.opacity(0.8))
                                .padding(.horizontal, 6)
                                .padding(.vertical, 2)
                                .background(Color.red.opacity(0.6), in: Capsule())
                        }
                        
                        Button {
                            if cameraManager.isRecording { stopRecording() }
                            else { startRecording() }
                        } label: {
                            ZStack {
                                Circle()
                                    .fill(cameraManager.isRecording ? Color.white : Color.red)
                                    .frame(width: 64, height: 64)
                                    .overlay(Circle().stroke(Color.white, lineWidth: 4))
                                    .shadow(color: .black.opacity(0.4), radius: 6)
                                
                                if cameraManager.isRecording {
                                    RoundedRectangle(cornerRadius: 4)
                                        .fill(Color.red)
                                        .frame(width: 20, height: 20)
                                } else if cameraManager.isPreparingRecording {
                                    ProgressView()
                                        .progressViewStyle(CircularProgressViewStyle(tint: .white))
                                        .scaleEffect(0.85)
                                }
                            }
                        }
                        .disabled(cameraManager.isPreparingRecording)
                        .scaleEffect(cameraManager.isRecording ? 1.08 : 1.0)
                        .animation(.easeInOut(duration: 0.2), value: cameraManager.isRecording)
                    }
                    
                    Spacer()
                }
                .padding(.vertical, 16)
                .padding(.trailing, 10)
                .frame(width: 100, height: geometry.size.height)
                .position(x: geometry.size.width - 50, y: geometry.size.height * 0.5)
            }
            
            // ── TOP REC INDICATOR ───────────────────────────────────────────
            if cameraManager.isRecording {
                VStack {
                    HStack(spacing: 6) {
                        Circle()
                            .fill(Color.red)
                            .frame(width: 8, height: 8)
                        Text("REC  \(formatDuration(recordingDuration))")
                            .font(.system(size: 12, weight: .bold, design: .monospaced))
                            .foregroundStyle(.white)
                    }
                    .padding(.horizontal, 12)
                    .padding(.vertical, 5)
                    .background(Color.black.opacity(0.5), in: Capsule())
                    .padding(.top, 14)
                    Spacer()
                }
            }
        }
        .edgesIgnoringSafeArea(.all)
        .onAppear { cameraManager.reconfigureCamera() }
    }
    
    // MARK: – Info Popover
    
    @ViewBuilder
    private var infoPopover: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Camera Info")
                .font(.body).fontWeight(.bold)
            
            InfoRow(color: .green,
                    label: "Resolution: \(cameraManager.cameraConfiguration.resolution.width) × \(cameraManager.cameraConfiguration.resolution.height)")
            Divider()
            InfoRow(color: .green,
                    label: "Frame Rate: \(cameraManager.cameraConfiguration.frameRate.rawValue) FPS")
            Divider()
            InfoRow(color: cameraManager.isLiDARSupported ? .green : .red,
                    label: "LiDAR Support: \(cameraManager.isLiDARSupported ? "Yes" : "No")")
            Divider()
            InfoRow(color: cameraManager.isLiDAREnabled ? .green : .red,
                    label: "LiDAR Enabled: \(cameraManager.isLiDAREnabled ? "Yes" : "No")")
            Divider()
            InfoRow(color: cameraManager.isFilteringDepth ? .green : .red,
                    label: "LiDAR Filtering: \(cameraManager.isFilteringDepth ? "Yes" : "No")")
            Divider()
            InfoRow(color: cameraManager.fpsStream > 20 ? .green : .red,
                    label: "FPS Model / Stream: \(String(format: "%.1f", cameraManager.fpsModel)) / \(String(format: "%.1f", cameraManager.fpsStream))")
        }
        .padding()
        .presentationCompactAdaptation(.popover)
    }
    
    // MARK: – Athlete Editor Popover
    
    @ViewBuilder
    private var athleteEditorPopover: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Athlete Info")
                .font(.headline)
            
            VStack(alignment: .leading, spacing: 6) {
                Label("Name", systemImage: "person")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                TextField("Athlete name", text: $appState.athleteName)
                    .textFieldStyle(.roundedBorder)
                    .autocorrectionDisabled()
                    .onChange(of: appState.athleteName) { appState.saveUserPreferences() }
            }
            
            VStack(alignment: .leading, spacing: 6) {
                Label("Action", systemImage: "figure.gymnastics")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                TextField("e.g. giant swing, release", text: $appState.actionType)
                    .textFieldStyle(.roundedBorder)
                    .autocorrectionDisabled()
                    .onChange(of: appState.actionType) { appState.saveUserPreferences() }
            }
            
            // View mode (only relevant when pose is on)
            if appState.realtimeDetection {
                Divider()
                VStack(alignment: .leading, spacing: 6) {
                    Label("View Mode", systemImage: "camera.viewfinder")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    Picker("", selection: $appState.realtimeViewMode) {
                        Text("General").tag("general")
                        Text("Side View").tag("side-view")
                        Text("Front View").tag("front-view")
                        Text("Corner View").tag("corner-view")
                    }
                    .pickerStyle(.segmented)
                }
            }
        }
        .padding(20)
        .frame(minWidth: 280)
        .presentationCompactAdaptation(.popover)
    }
    
    // MARK: – Helpers
    
    private func startRecording() {
        cameraManager.startRecording(personName: appState.athleteName, action: appState.actionType)
        recordingDuration = 0
        recordingTimer = Timer.scheduledTimer(withTimeInterval: 1, repeats: true) { _ in
            recordingDuration += 1
        }
    }
    
    private func stopRecording() {
        recordingTimer?.invalidate()
        recordingTimer = nil
        recordingDuration = 0
        cameraManager.stopRecording { url in
            if let url { print("Saved: \(url)") }
        }
    }
    
    private func formatDuration(_ t: TimeInterval) -> String {
        String(format: "%02d:%02d", Int(t) / 60, Int(t) % 60)
    }
}

// MARK: - TogglePill

struct TogglePill: View {
    let icon: String
    let label: String
    @Binding var isOn: Bool
    let activeColor: Color
    var disabled: Bool = false
    
    var body: some View {
        Button { if !disabled { isOn.toggle() } } label: {
            VStack(spacing: 4) {
                Image(systemName: icon)
                    .font(.system(size: 15, weight: .medium))
                Text(label)
                    .font(.system(size: 10, weight: .semibold))
            }
            .foregroundStyle(isOn ? .black : (disabled ? .white.opacity(0.2) : .white))
            .frame(width: 58, height: 52)
            .background(
                RoundedRectangle(cornerRadius: 12)
                    .fill(isOn ? activeColor : Color.white.opacity(disabled ? 0.05 : 0.12))
            )
            .overlay(
                RoundedRectangle(cornerRadius: 12)
                    .stroke(isOn ? activeColor.opacity(0.3) : .clear, lineWidth: 1)
            )
        }
        .disabled(disabled)
        .animation(.easeInOut(duration: 0.15), value: isOn)
    }
}

// MARK: - SidebarIcon

private struct SidebarIcon: View {
    let systemName: String
    var body: some View {
        Image(systemName: systemName)
            .font(.system(size: 18, weight: .medium))
            .foregroundStyle(.white)
            .frame(width: 44, height: 44)
            .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 10))
    }
}

// MARK: - InfoRow

private struct InfoRow: View {
    let color: Color
    let label: String
    var body: some View {
        HStack(spacing: 6) {
            Circle().fill(color).frame(width: 8, height: 8)
            Text(label)
                .font(.caption)
                .foregroundStyle(.secondary)
                .lineLimit(1)
                .truncationMode(.middle)
        }
    }
}
