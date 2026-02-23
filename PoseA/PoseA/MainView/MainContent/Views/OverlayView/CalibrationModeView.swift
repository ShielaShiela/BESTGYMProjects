//
//  CalibrationModeView.swift
//  PoseA
//
//  Created by Shiela Cabahug on 2026/2/19.
//
//import SwiftUI
//struct CalibrationModeControlView: View {
//    @Binding var calibrationModel: CalibrationModel
//    let exitAction: () -> Void
//
//    @State private var barHeightInput: String = ""
//    @State private var showHeightInput: Bool = false
//
//    var body: some View {
//        HStack(spacing: 8) {
//            // Step indicator
//            Text(stepLabel)
//                .font(.caption)
//                .foregroundColor(stepColor)
//
//            Divider().frame(height: 16)
//
//            // Bar height input toggle
//            Button(action: { showHeightInput.toggle() }) {
//                HStack(spacing: 4) {
//                    Image(systemName: "arrow.up.and.down")
//                        .font(.system(size: 11))
//                    Text(String(format: "%.0f cm", calibrationModel.realBarHeightCm))
//                        .font(.caption.monospacedDigit())
//                }
//                .foregroundColor(.yellow)
//            }
//            .popover(isPresented: $showHeightInput) {
//                VStack(spacing: 12) {
//                    Text("Bar Height (cm)")
//                        .font(.caption)
//                        .foregroundColor(.secondary)
//                    TextField("e.g. 260", text: $barHeightInput)
//                        .keyboardType(.decimalPad)
//                        .textFieldStyle(.roundedBorder)
//                        .frame(width: 120)
//                        .onAppear {
//                            barHeightInput = String(calibrationModel.realBarHeightCm)
//                        }
//                    HStack {
//                        Button("Cancel") { showHeightInput = false }
//                            .foregroundColor(.secondary)
//                        Button("Set") {
//                            if let val = Double(barHeightInput), val > 0 {
//                                calibrationModel.realBarHeightCm = val
//                            }
//                            showHeightInput = false
//                        }
//                        .buttonStyle(.borderedProminent)
//                    }
//                }
//                .padding()
//            }
//
//            Divider().frame(height: 16)
//
//            // Clear points
//            Button(action: { calibrationModel.reset() }) {
//                Image(systemName: "xmark.circle")
//                    .font(.system(size: 12))
//                    .foregroundColor(.secondary)
//            }
//
//            // Exit
//            Button(action: exitAction) {
//                Text("Done")
//                    .font(.caption.bold())
//                    .foregroundColor(.white)
//                    .padding(.horizontal, 8)
//                    .padding(.vertical, 3)
//                    .background(Color.blue.opacity(0.8))
//                    .cornerRadius(5)
//            }
//        }
//        .padding(.horizontal, 10)
//        .padding(.vertical, 5)
//        .background(Color(.systemGray5).opacity(0.9))
//        .cornerRadius(10)
//    }
//
//    private var stepLabel: String {
//        switch calibrationModel.calibrationStep {
//        case .selectingBarTop:    return "① Tap bar top"
//        case .selectingBarBottom: return "② Tap ground ref"
//        case .complete:           return "✓ Calibrated"
//        default:                  return "Tap to begin"
//        }
//    }
//
//    private var stepColor: Color {
//        switch calibrationModel.calibrationStep {
//        case .selectingBarTop:    return .yellow
//        case .selectingBarBottom: return .orange
//        case .complete:           return .green
//        default:                  return .secondary
//        }
//    }
//}

// MARK: // new crosshair

import SwiftUI

struct CalibrationModeControlView: View {
    @Binding var calibrationModel: CalibrationModel
    let exitAction: () -> Void

    @State private var barHeightInput: String = ""
    @State private var showHeightInput: Bool = false

    var body: some View {
        HStack(spacing: 8) {
            // Step indicator
            Text(stepLabel)
                .font(.caption)
                .foregroundColor(stepColor)

            Divider().frame(height: 16)

            // Bar height input toggle
            Button(action: { showHeightInput.toggle() }) {
                HStack(spacing: 4) {
                    Image(systemName: "arrow.up.and.down")
                        .font(.system(size: 11))
                    Text(String(format: "%.0f cm", calibrationModel.realBarHeightCm))
                        .font(.caption.monospacedDigit())
                }
                .foregroundColor(.yellow)
            }
            .popover(isPresented: $showHeightInput) {
                VStack(spacing: 12) {
                    Text("Bar Height (cm)")
                        .font(.caption)
                        .foregroundColor(.secondary)
                    TextField("e.g. 260", text: $barHeightInput)
                        .keyboardType(.decimalPad)
                        .textFieldStyle(.roundedBorder)
                        .frame(width: 120)
                        .onAppear { barHeightInput = String(calibrationModel.realBarHeightCm) }
                    HStack {
                        Button("Cancel") { showHeightInput = false }
                            .foregroundColor(.secondary)
                        Button("Set") {
                            if let val = Double(barHeightInput), val > 0 {
                                calibrationModel.realBarHeightCm = val
                            }
                            showHeightInput = false
                        }
                        .buttonStyle(.borderedProminent)
                    }
                }
                .padding()
            }

            Divider().frame(height: 16)

            // ── "Next" button: advance from bar-top to bar-bottom step ───
            if calibrationModel.calibrationStep == .selectingBarTop {
                Button(action: {
                    calibrationModel.calibrationStep = .selectingBarBottom
                }) {
                    HStack(spacing: 3) {
                        Text("Next")
                            .font(.caption.bold())
                        Image(systemName: "arrow.right")
                            .font(.system(size: 10, weight: .bold))
                    }
                    .foregroundColor(.white)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 3)
                    .background(Color.yellow.opacity(0.85))
                    .cornerRadius(5)
                }
            }

            // Clear points
            Button(action: { calibrationModel.reset() }) {
                Image(systemName: "xmark.circle")
                    .font(.system(size: 12))
                    .foregroundColor(.secondary)
            }

            // Exit / Done
            Button(action: exitAction) {
                Text("Done")
                    .font(.caption.bold())
                    .foregroundColor(.white)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 3)
                    .background(Color.blue.opacity(0.8))
                    .cornerRadius(5)
            }
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 5)
        .background(Color(.systemGray5).opacity(0.9))
        .cornerRadius(10)
    }

    private var stepLabel: String {
        switch calibrationModel.calibrationStep {
        case .selectingBarTop:    return "① Position bar top"
        case .selectingBarBottom: return "② Position ground ref"
        case .complete:           return "✓ Calibrated"
        default:                  return "Tap to begin"
        }
    }

    private var stepColor: Color {
        switch calibrationModel.calibrationStep {
        case .selectingBarTop:    return .yellow
        case .selectingBarBottom: return .orange
        case .complete:           return .green
        default:                  return .secondary
        }
    }
}
