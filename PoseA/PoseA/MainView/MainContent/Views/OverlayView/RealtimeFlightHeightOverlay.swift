import SwiftUI

// MARK: - RealtimeFlightHeightOverlay.swift
//
// Integration — inside RecordLandscapeView's camera ZStack, after PoseOverlayView:
//
//   if appState.realtimeDetection {
//       RealtimeFlightHeightOverlay(
//           cameraManager: cameraManager,
//           calibrationModel: $calibrationModel
//       )
//   }

// MARK: - Live Flight Height State

final class RealtimeFlightHeightState: ObservableObject {
    @Published var currentCm: Double? = nil
    @Published var maxCm: Double? = nil
    @Published var isAboveBar: Bool = false

    func reset() {
        currentCm = nil
        maxCm = nil
        isAboveBar = false
    }

    /// Feed raw poseKeypoints from CameraManagerVM directly.
    /// Reads nose Y (COCO index 0) from the first detected person,
    /// matching exactly how PoseOverlayView reads keypoints[0].
    func update(poses: [PoseBox], calibration: CalibrationModel) {
        guard calibration.isCalibrated,
              let barTopNormalized = calibration.barTopPoint,
              let firstPerson = poses.first,
              firstPerson.keypoints.count > 0 else {
            currentCm = nil
            isAboveBar = false
            return
        }

        // COCO 0 = nose — same index PoseOverlayView draws first
        let noseY   = Double(firstPerson.keypoints[0].y)
        let barTopY = Double(barTopNormalized.y)

        // Positive → head is above the bar (smaller Y = higher in image space)
        let normalizedDiff = barTopY - noseY
        let cm = calibration.normalizedYDiffToCm(normalizedDiff)

        currentCm  = cm
        isAboveBar = (cm ?? 0) > 0

        // Running max — only count frames where gymnast is actually above the bar
        if let cm, cm > 0 {
            maxCm = max(maxCm ?? 0, cm)
        }
    }
}

// MARK: - Overlay View

struct RealtimeFlightHeightOverlay: View {
    @ObservedObject var cameraManager: CameraManagerVM
    @Binding var calibrationModel: CalibrationModel

    @StateObject private var flightState = RealtimeFlightHeightState()

    var body: some View {
        VStack {
            HStack {
                FlightHeightHUD(state: flightState, isCalibrated: calibrationModel.isCalibrated)
                    .padding(.leading, 70)   // clear the ~60pt left sidebar
                    .padding(.top, 14)       // same top offset as CalibrationBadge
                Spacer()
            }
            Spacer()
        }
        .onChange(of: cameraManager.poseKeypoints) { _, newPoses in
            flightState.update(poses: newPoses, calibration: calibrationModel)
        }
        .onChange(of: cameraManager.isRecording) { _, isRecording in
            if isRecording { flightState.reset() }
        }
        .onChange(of: calibrationModel.isCalibrated) { _, _ in
            flightState.reset()
        }
    }
}

// MARK: - HUD Widget

private struct FlightHeightHUD: View {
    @ObservedObject var state: RealtimeFlightHeightState
    let isCalibrated: Bool

    var body: some View {
        HStack(spacing: 0) {
            HeightPanel(
                label: "NOW",
                value: state.currentCm,
                color: state.isAboveBar ? .green : .orange,
                icon: state.isAboveBar ? "arrow.up" : "arrow.down",
                isLarge: true
            )

            Rectangle()
                .fill(Color.white.opacity(0.12))
                .frame(width: 1, height: 56)

            HeightPanel(
                label: "MAX",
                value: state.maxCm,
                color: .cyan,
                icon: "crown.fill",
                isLarge: false
            )
        }
        .background(
            RoundedRectangle(cornerRadius: 14)
                .fill(.ultraThinMaterial)
                .overlay(
                    RoundedRectangle(cornerRadius: 14)
                        .stroke(
                            isCalibrated ? Color.white.opacity(0.15) : Color.orange.opacity(0.6),
                            lineWidth: 1
                        )
                )
        )
        .overlay(alignment: .topLeading) {
            if !isCalibrated {
                Text("Calibrate bar")
                    .font(.system(size: 8, weight: .semibold))
                    .foregroundStyle(.orange)
                    .padding(.horizontal, 5)
                    .padding(.vertical, 2)
                    .background(Color.orange.opacity(0.2), in: Capsule())
                    .offset(x: 6, y: -10)
            }
        }
        .shadow(color: .black.opacity(0.4), radius: 8, x: 0, y: 4)
    }
}

// MARK: - Single Panel

private struct HeightPanel: View {
    let label: String
    let value: Double?
    let color: Color
    let icon: String
    let isLarge: Bool

    var body: some View {
        VStack(spacing: 3) {
            HStack(spacing: 3) {
                Image(systemName: icon)
                    .font(.system(size: 8, weight: .bold))
                    .foregroundStyle(color)
                Text(label)
                    .font(.system(size: 9, weight: .bold, design: .monospaced))
                    .foregroundStyle(color.opacity(0.8))
            }

            if let v = value {
                Text(String(format: "%+.1f", v))
                    .font(.system(size: isLarge ? 22 : 18, weight: .black, design: .monospaced))
                    .foregroundStyle(color)
                    .contentTransition(.numericText(value: v))
                    .animation(.easeOut(duration: 0.15), value: v)
                Text("cm")
                    .font(.system(size: 9, weight: .semibold))
                    .foregroundStyle(color.opacity(0.7))
            } else {
                Text("--")
                    .font(.system(size: isLarge ? 22 : 18, weight: .black, design: .monospaced))
                    .foregroundStyle(Color.white.opacity(0.3))
                Text("cm")
                    .font(.system(size: 9, weight: .semibold))
                    .foregroundStyle(Color.white.opacity(0.2))
            }
        }
        .frame(width: isLarge ? 80 : 70)
        .padding(.vertical, 10)
    }
}

// MARK: - Equatable conformance needed for .onChange(of: cameraManager.poseKeypoints)
// Add this here, or move it next to the PoseBox struct definition in your codebase.

extension PoseBox: Equatable {
    static func == (lhs: PoseBox, rhs: PoseBox) -> Bool {
        lhs.bbox == rhs.bbox &&
        lhs.confidence == rhs.confidence &&
        lhs.keypoints == rhs.keypoints &&
        lhs.hasDepthData == rhs.hasDepthData &&
        lhs.averageDepth == rhs.averageDepth
    }
}
