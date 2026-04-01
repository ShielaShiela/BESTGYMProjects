
// MARK: // new crosshair
import SwiftUI

struct CalibrationModeControlView: View {
    // Both are @Observable classes — pass directly, use @Bindable for $ inside
    @Bindable var calibrationModel: CalibrationModel
    let exitAction: () -> Void
    
    @State private var barHeightInput: String = ""
    @State private var showHeightInput: Bool = false
    
    var body: some View {
        HStack(spacing: 8) {
            twoPointControls
            
            Divider().frame(height: 16)
            
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


    // MARK: - Two-point controls (original)
    // MARK: - Two-point controls (with required height confirmation
    private var twoPointControls: some View {
        HStack(spacing: 8) {
            Text(stepLabel)
                .font(.caption)
                .foregroundColor(stepColor)

            Divider().frame(height: 16)

            // Height picker — now required, styled to stand out when unset
            Button(action: { showHeightInput.toggle() }) {
                HStack(spacing: 4) {
                    Image(systemName: "arrow.up.and.down")
                        .font(.system(size: 11))
                    Text(String(format: "%.0f cm", calibrationModel.realBarHeightCm))
                        .font(.caption.monospacedDigit())
                }
                .foregroundColor(calibrationModel.realBarHeightCm > 0 ? .yellow : .orange)
                .padding(.horizontal, 6)
                .padding(.vertical, 3)
                .overlay(
                    RoundedRectangle(cornerRadius: 4)
                        .stroke(calibrationModel.realBarHeightCm > 0 ? Color.yellow.opacity(0.4) : Color.orange, lineWidth: 1)
                )
            }
            .popover(isPresented: $showHeightInput) {
                VStack(spacing: 12) {
                    Text("Reference Height (cm)")
                        .font(.caption.bold())
                    Text("Enter the real-world vertical distance\nbetween the two crosshair positions.")
                        .font(.caption)
                        .foregroundColor(.secondary)
                        .multilineTextAlignment(.center)
                    TextField("e.g. 260", text: $barHeightInput)
                        .keyboardType(.decimalPad)
                        .textFieldStyle(.roundedBorder)
                        .frame(width: 120)
                        .onAppear { barHeightInput = String(format: "%.0f", calibrationModel.realBarHeightCm) }
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
                        .disabled(Double(barHeightInput) == nil || (Double(barHeightInput) ?? 0) <= 0)
                    }
                }
                .padding()
                .frame(minWidth: 220)
            }

            Divider().frame(height: 16)

            if calibrationModel.calibrationStep == .selectingBarTop {
                Button(action: { calibrationModel.calibrationStep = .selectingBarBottom }) {
                    HStack(spacing: 3) {
                        Text("Next").font(.caption.bold())
                        Image(systemName: "arrow.right").font(.system(size: 10, weight: .bold))
                    }
                    .foregroundColor(.white)
                    .padding(.horizontal, 8).padding(.vertical, 3)
                    .background(Color.yellow.opacity(0.85))
                    .cornerRadius(5)
                }
            }

            Button(action: { calibrationModel.reset() }) {
                Image(systemName: "xmark.circle")
                    .font(.system(size: 12))
                    .foregroundColor(.secondary)
            }
        }
    }


    // MARK: - Helpers
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
