//
//  CalibrationOverlayView.swift
//  PoseA
//
//  Created by Shiela Cabahug on 2026/2/19.
//

// CalibrationOverlayView.swift
import SwiftUI

struct CalibrationOverlayView: View {
    @Binding var calibrationModel: CalibrationModel
    let containerSize: CGSize
    let imageSize: CGSize
    
    var body: some View {
        ZStack {
            // Tap capture layer
            Color.clear
                .contentShape(Rectangle())
                .onTapGesture { location in
                    handleTap(at: location)
                }
            
            // Draw bar top point
            if let barTop = calibrationModel.barTopPoint {
                let displayPt = normalizedToDisplay(barTop)
                CalibrationPointView(point: displayPt, label: "Bar Top", color: .yellow)
            }
            
            // Draw bar bottom point
            if let barBottom = calibrationModel.barBottomPoint {
                let displayPt = normalizedToDisplay(barBottom)
                CalibrationPointView(point: displayPt, label: "Ground Ref", color: .green)
            }
            
            // Draw line between points
            if let top = calibrationModel.barTopPoint,
               let bottom = calibrationModel.barBottomPoint {
                let topDisplay = normalizedToDisplay(top)
                let bottomDisplay = normalizedToDisplay(bottom)
                
                Path { path in
                    path.move(to: topDisplay)
                    path.addLine(to: bottomDisplay)
                }
                .stroke(Color.orange, style: StrokeStyle(lineWidth: 2, dash: [6, 4]))
            }
            
            // Instruction banner
            if calibrationModel.isCalibrationMode {
                VStack {
                    HStack {
                        Spacer()
                        Text(instructionText)
                            .font(.caption)
                            .padding(8)
                            .background(Color.black.opacity(0.75))
                            .foregroundColor(.yellow)
                            .cornerRadius(8)
                        Spacer()
                    }
                    .padding(.top, 8)
                    Spacer()
                }
            }
        }
    }
    
    private var instructionText: String {
        switch calibrationModel.calibrationStep {
        case .selectingBarTop:    return "Tap the TOP of the horizontal bar"
        case .selectingBarBottom: return "Tap the GROUND level (or bottom reference)"
        case .complete:           return "Calibrated ✓ — tap to re-select points"
        default:                  return ""
        }
    }
    
//    private func handleTap(at location: CGPoint) {
//        guard calibrationModel.isCalibrationMode else { return }
//        let normalized = displayToNormalized(location)
//        
//        switch calibrationModel.calibrationStep {
//        case .selectingBarTop:
//            calibrationModel.barTopPoint = normalized
//            calibrationModel.calibrationStep = .selectingBarBottom
//        case .selectingBarBottom:
//            calibrationModel.barBottomPoint = normalized
//            calibrationModel.calibrationStep = .complete
//            calibrationModel.isCalibrationMode = false
//        case .complete:
//            // Allow re-tapping to redo
//            calibrationModel.startCalibration()
//        default:
//            break
//        }
//    }
    // In CalibrationOverlayView handleTap()
    private func handleTap(at location: CGPoint) {
        guard calibrationModel.isCalibrationMode else {
            print("⚠️ Tap ignored — not in calibration mode")
            return
        }
        let normalized = displayToNormalized(location)
        print("📍 Tap at display: \(location) → normalized: \(normalized)")
        
        switch calibrationModel.calibrationStep {
        case .selectingBarTop:
            calibrationModel.barTopPoint = normalized
            calibrationModel.calibrationStep = .selectingBarBottom
            print("✅ Bar top set: \(normalized)")
        case .selectingBarBottom:
            calibrationModel.barBottomPoint = normalized
            calibrationModel.calibrationStep = .complete
            calibrationModel.isCalibrationMode = false
            print("✅ Bar bottom set: \(normalized)")
//            if let ppc = calibrationModel.pixelsPerCm {
//                print("📏 Pixels per cm: \(ppString(describing: c)")
//            }
        case .complete:
            calibrationModel.startCalibration()
        default:
            break
        }
    }
    
    // MARK: - Coordinate helpers (matches your existing pattern)
    
    private func fittedImageRect() -> CGRect {
        let imageAspect = imageSize.width / imageSize.height
        let containerAspect = containerSize.width / containerSize.height
        
        if imageAspect > containerAspect {
            let width = containerSize.width
            let height = width / imageAspect
            let yOffset = (containerSize.height - height) / 2
            return CGRect(x: 0, y: yOffset, width: width, height: height)
        } else {
            let height = containerSize.height
            let width = height * imageAspect
            let xOffset = (containerSize.width - width) / 2
            return CGRect(x: xOffset, y: 0, width: width, height: height)
        }
    }
    
    private func normalizedToDisplay(_ point: CGPoint) -> CGPoint {
        let rect = fittedImageRect()
        return CGPoint(
            x: rect.origin.x + point.x * rect.width,
            y: rect.origin.y + point.y * rect.height
        )
    }
    
    private func displayToNormalized(_ point: CGPoint) -> CGPoint {
        let rect = fittedImageRect()
        return CGPoint(
            x: (point.x - rect.origin.x) / rect.width,
            y: (point.y - rect.origin.y) / rect.height
        )
    }
}

// MARK: - Calibration Point Marker
struct CalibrationPointView: View {
    let point: CGPoint
    let label: String
    let color: Color
    
    var body: some View {
        ZStack {
            // Crosshair
            Group {
                Rectangle()
                    .frame(width: 20, height: 2)
                Rectangle()
                    .frame(width: 2, height: 20)
            }
            .foregroundColor(color)
            
            // Label
            Text(label)
                .font(.system(size: 10, weight: .bold))
                .foregroundColor(color)
                .padding(3)
                .background(Color.black.opacity(0.7))
                .cornerRadius(4)
                .offset(x: 30, y: -10)
        }
        .position(point)
    }
}
