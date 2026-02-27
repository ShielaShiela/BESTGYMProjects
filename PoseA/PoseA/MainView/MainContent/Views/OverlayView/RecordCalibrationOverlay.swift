//
//  RecordCalibrationOverlay.swift
//  PoseA
//
//  Created by Shiela Cabahug on 2026/2/28.
//

import SwiftUI

// MARK: - Control panel

struct RecordCalibrationOverlay: View {
    @Binding var calibrationModel: CalibrationModel
    /// Called when the panel should close (Confirm tapped or Done tapped).
    let onClose: () -> Void

    var body: some View {
        VStack {
            Spacer()

            VStack(spacing: 10) {

                // ── Step buttons ──────────────────────────────────────────
                HStack(spacing: 10) {
                    
                    HStack(spacing: 12) {
                        Text("Bar ht (cm):")
                            .font(.system(size: 11))
                            .foregroundStyle(.white.opacity(0.65))
                        
                        TextField("260", value: $calibrationModel.realBarHeightCm, format: .number)
                            .keyboardType(.decimalPad)
                            .multilineTextAlignment(.center)
                            .frame(width: 64)
                            .padding(.vertical, 5)
                            .padding(.horizontal, 8)
                            .background(Color.white.opacity(0.12),
                                        in: RoundedRectangle(cornerRadius: 7))
                            .foregroundStyle(.white)
                            .font(.system(size: 12))
                    }
                    
                    Spacer()
                    
                    CalStepButton(
                        title: "Bar Top",
                        color: .yellow,
                        isActive: calibrationModel.calibrationStep == .selectingBarTop
                    ) {
                        calibrationModel.isCalibrationMode = true
                        calibrationModel.calibrationStep   = .selectingBarTop
                    }

                    CalStepButton(
                        title: "Ground Ref",
                        color: .green,
                        isActive: calibrationModel.calibrationStep == .selectingBarBottom
                    ) {
                        calibrationModel.isCalibrationMode = true
                        calibrationModel.calibrationStep   = .selectingBarBottom
                    }

                    // Confirm – auto-dismisses on tap when both points are set
                    CalStepButton(
                        title: "Confirm ✓",
                        color: .orange,
                        isActive: calibrationModel.calibrationStep == .complete
                    ) {
                        guard calibrationModel.barTopPoint != nil,
                              calibrationModel.barBottomPoint != nil else { return }
                        calibrationModel.calibrationStep = .complete
                        // Auto-dismiss after a brief moment so the user sees the state flip
                        DispatchQueue.main.asyncAfter(deadline: .now() + 0.25) {
                            onClose()
                        }
                    }
                    .opacity(calibrationModel.calibrationStep == .selectingBarBottom
                             || calibrationModel.calibrationStep == .complete ? 1 : 0.35)
                    .disabled(calibrationModel.calibrationStep == .selectingBarTop)
                    
                    Spacer()
                    
                    HStack(spacing: 12){
                        // Reset – clears points and restarts from step 1
                        Button {
                            let height = calibrationModel.realBarHeightCm
                            calibrationModel.reset()
                            calibrationModel.realBarHeightCm = height
                            calibrationModel.isCalibrationMode = true
                            calibrationModel.calibrationStep   = .selectingBarTop
                        } label: {
                            Image(systemName: "arrow.counterclockwise")
                                .font(.system(size: 13, weight: .medium))
                                .foregroundStyle(.orange)
                                .frame(width: 32, height: 32)
                                .background(Color.white.opacity(0.1),
                                            in: RoundedRectangle(cornerRadius: 8))
                        }
                        
                        // Close without confirming (keeps current state)
                        Button {
                            onClose()
                        } label: {
                            Text("Close")
                                .font(.system(size: 13, weight: .semibold))
                                .foregroundStyle(.white.opacity(0.7))
                                .padding(.horizontal, 16)
                                .frame(height: 32)
                                .background(Color.white.opacity(0.1),
                                            in: RoundedRectangle(cornerRadius: 8))
                        }
                    }
                }
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 12)
            .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 14))
            .overlay(
                RoundedRectangle(cornerRadius: 14)
                    .stroke(Color.white.opacity(0.12), lineWidth: 1)
            )
            .padding(.horizontal, 80)   // keep clear of sidebars (~60-100 pt each side)
            .padding(.top, 20)
            Spacer()
            Spacer()
            Spacer()
            Spacer()
            Spacer()
            Spacer()
        }
        .allowsHitTesting(true)
        .transition(.move(edge: .top).combined(with: .opacity))
        .animation(.spring(response: 0.3), value: calibrationModel.isCalibrationMode)
    }
}

// MARK: - Persistent calibration badge (shown when calibrated + panel closed)

/// Small indicator anchored to the top-leading corner of the camera preview.
/// Lets the user know calibration is active without cluttering the feed.
struct CalibrationBadge: View {
    let heightCm: Double

    var body: some View {
        VStack(alignment: .leading) {
            HStack(spacing: 5) {
                Image(systemName: "checkmark.circle.fill")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(.green)
                Text("Calibrated · \(Int(heightCm)) cm")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(.white)
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 5)
            .background(.ultraThinMaterial, in: Capsule())
            .overlay(Capsule().stroke(Color.green.opacity(0.4), lineWidth: 1))
            .padding(.top, 12)
            .padding(.leading, 70)   // clear of left sidebar

            Spacer()
        }
        .allowsHitTesting(false)
        .transition(.opacity.animation(.easeInOut(duration: 0.3)))
    }
}

// MARK: - Step button (private)

private struct CalStepButton: View {
    let title: String
    let color: Color
    let isActive: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Text(title)
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(isActive ? .black : .white)
                .padding(.horizontal, 10)
                .padding(.vertical, 8)
                .background(
                    RoundedRectangle(cornerRadius: 8)
                        .fill(isActive ? color : color.opacity(0.2))
                )
                .overlay(
                    RoundedRectangle(cornerRadius: 8)
                        .stroke(color.opacity(isActive ? 0 : 0.5), lineWidth: 1)
                )
        }
    }
}


// ── Calibration status pill used in the recording sidebar ────────────────────

struct CalibrationStatusPill: View {
    let isCalibrated: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            VStack(spacing: 3) {
                Image(systemName: isCalibrated
                      ? "checkmark.circle.fill"
                      : "ruler")
                    .font(.system(size: 15, weight: .medium))
                Text(isCalibrated ? "Cal ✓" : "Cal")
                    .font(.system(size: 10, weight: .semibold))
            }
            .foregroundStyle(isCalibrated ? .black : .white)
            .frame(width: 58, height: 52)
            .background(
                RoundedRectangle(cornerRadius: 12)
                    .fill(isCalibrated
                          ? Color.yellow
                          : Color.white.opacity(0.12))
            )
            .overlay(
                RoundedRectangle(cornerRadius: 12)
                    .stroke(isCalibrated ? Color.yellow.opacity(0.4) : .clear,
                            lineWidth: 1)
            )
        }
        .animation(.easeInOut(duration: 0.15), value: isCalibrated)
    }
}
