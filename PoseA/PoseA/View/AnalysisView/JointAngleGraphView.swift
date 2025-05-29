//
//  JointAngleGraphView.swift
//  PoseA
//
//  Created by Ardhika Maulidani on 5/27/25.
//

import SwiftUI
import Charts

//struct JointAngleGraphView: View {
//    // Define Variable
//    let selectedJoints: [String]
//    let timeRange: ClosedRange<Double>
//    let poseProcessor: VitPoseProcessor
//    let currentFrameIndex: Int
//    
//    // Joint colors for the graph
//    private let jointColors: [String: Color] = [
//        "L Shoulder": .blue,
//        "R Shoulder": .red,
//        "L Elbow": .orange,
//        "R Elbow": .yellow,
//        "L Hip": .purple,
//        "R Hip": .pink,
//        "L Knee": .black,
//        "R Knee": .gray,
//        "L Ankle": .green,
//        "R Ankle": .mint
//    ]
//    
//    @State private var zoomScale: CGFloat = 1.0
//    @State private var offset: CGSize = .zero
//    
//    private func createLine(dataPoints: [(Int, Double)]) {
//        ForEach(dataPoints, id: \.time) { point in
//            LineMark(
//                x: .value("Time", point.time),
//                y: .value("Angle", point.angle)
//            )
//            .foregroundStyle(Color("lightCyan"))
//        }
//    }
//    
//    var body: some View {
//        VStack {
//            Chart {
//                // Loop over selected joints and plot each joint's data
//                ForEach(selectedJoints, id: \.self) { joint in
//                    let dataPoints = getJointData(joint)
//
//                }
//            }
//            .chartYAxis {
//                AxisMarks(position: .leading) { value in
//                    AxisGridLine()
//                        .foregroundStyle(.white)
//                    AxisTick()
//                        .foregroundStyle(.white)
//                    AxisValueLabel()
//                        .foregroundStyle(.white)
//                }
//            }
//            .chartXAxis {
//                AxisMarks(position: .bottom) { value in
//                    AxisGridLine()
//                        .foregroundStyle(.white)
//                    AxisTick()
//                        .foregroundStyle(.white)
//                    AxisValueLabel()
//                        .foregroundStyle(.white)
//                }
//            }
//            .padding()
//        }
//    }
//    
//    private func getJointData(_ joint: String) -> [(Int, Double)] {
//        // Simple Double Array Data -> Create and Destroy Methods -> Save Memory
//        // Define Array Container
//        var dataPoints: [(time: Int, result: Double)] = []
//        
//        // Get Total Frame
//        let totalFrame = poseProcessor.getTotalFrames()
//
//        // Get Keypoints
//        for i in 0..<totalFrame {
//            var angle: Double = 0
//            guard let keypoints = poseProcessor.getKeypoints(for: i) else { return [] }
//            
//            // Check Availability of Keypoint
//            if keypoints.count != 17 { continue }
//            
//            // Get Joint Data
//            switch joint {
//            case "L Elbow": // Points: Shoulder → Elbow → Wrist
//                angle = angleBetween(keypoints[5], keypoints[7], keypoints[9])
//            case "R Elbow":
//                angle = angleBetween(keypoints[6], keypoints[8], keypoints[10])
//            case "L Shoulder": // Points: Hip → Shoulder → Elbow
//                angle = angleBetween(keypoints[11], keypoints[5], keypoints[7])
//            case "R Shoulder":
//                angle = angleBetween(keypoints[12], keypoints[6], keypoints[8])
//            case "L Hip": // Points: Shoulder → Hip → Knee
//                angle = angleBetween(keypoints[5], keypoints[11], keypoints[13])
//            case "R Hip":
//                angle = angleBetween(keypoints[6], keypoints[12], keypoints[14])
//            case "L Knee": // Points: Hip → Knee → Ankle
//                angle = angleBetween(keypoints[11], keypoints[13], keypoints[15])
//            case "R Knee":
//                angle = angleBetween(keypoints[12], keypoints[14], keypoints[16])
//            case "L Ankle": // Points: Knee → Ankle → Ground?
//                angle = angleBetween(keypoints[11], keypoints[13], keypoints[15])
//            case "R Ankle":
//                angle = angleBetween(keypoints[12], keypoints[14], keypoints[16])
//            default:
//                angle = 0
//            }
//            // Append to Array
//            dataPoints.append((i,angle))
//        }
//        return dataPoints
//    }
//}

// Joint Angle Graph
struct JointAngleGraphView: View {
    // Define Variable
    let selectedJoints: [String]
    let timeRange: ClosedRange<Double>
    let poseProcessor: VitPoseProcessor
    let currentFrameIndex: Int
    
    // Joint colors for the graph
    private let jointColors: [String: Color] = [
        "L Shoulder": .blue,
        "R Shoulder": .red,
        "L Elbow": .orange,
        "R Elbow": .yellow,
        "L Hip": .purple,
        "R Hip": .pink,
        "L Knee": .black,
        "R Knee": .gray,
        "L Ankle": .green,
        "R Ankle": .mint
    ]
    
    var body: some View {
        VStack {
            // This would be implemented with a charting library like SwiftUI Charts or a custom drawing
            // For this example, we'll create a placeholder with sample data
            Canvas { context, size in
                // Background grid
                drawGrid(context: context, size: size)
                
                // X and Y axes
                drawAxes(context: context, size: size)
                
                // Data lines for each selected joint
                for joint in selectedJoints {
                    drawJointAngleLine(
                        joint: joint,
                        context: context,
                        size: size,
                        color: jointColors[joint] ?? .gray
                    )
                }
                
                // Current frame indicator
                drawCurrentFrameIndicator(context: context, size: size)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            
            // Legend
            HStack {
                ForEach(selectedJoints, id: \.self) { joint in
                    HStack {
                        Circle()
                            .fill(jointColors[joint] ?? .gray)
                            .frame(width: 10, height: 10)
                        Text(joint)
                            .font(.caption)
                    }
                    .padding(.horizontal, 5)
                }
            }
            .padding(.top, 5)
        }
    }
    
    // Helper drawing methods
    private func drawGrid(context: GraphicsContext, size: CGSize) {
        let horizontalLines = 5
        let verticalLines = 10
        
        let path = Path { p in
            // Horizontal grid lines
            for i in 0...horizontalLines {
                let y = size.height / CGFloat(horizontalLines) * CGFloat(i)
                p.move(to: CGPoint(x: 0, y: y))
                p.addLine(to: CGPoint(x: size.width, y: y))
            }
            
            // Vertical grid lines
            for i in 0...verticalLines {
                let x = size.width / CGFloat(verticalLines) * CGFloat(i)
                p.move(to: CGPoint(x: x, y: 0))
                p.addLine(to: CGPoint(x: x, y: size.height))
            }
        }
        
        context.stroke(path, with: .color(.gray.opacity(0.2)), lineWidth: 1)
    }
    
    private func drawAxes(context: GraphicsContext, size: CGSize) {
        let path = Path { p in
            // X-axis
            p.move(to: CGPoint(x: 0, y: size.height))
            p.addLine(to: CGPoint(x: size.width, y: size.height))
            
            // Y-axis
            p.move(to: CGPoint(x: 0, y: 0))
            p.addLine(to: CGPoint(x: 0, y: size.height))
        }
        
        context.stroke(path, with: .color(.gray), lineWidth: 2)
        
        // Draw Y-axis labels (angles)
        let yLabelSpacing = size.height / 5.0
        for i in 0...5 {
            let yValue = 180.0 - (Double(i) * 36.0)  // Assuming Y axis represents joint angles (0-180 degrees)
            let yLabelPosition = CGPoint(x: -40, y: size.height - CGFloat(i) * yLabelSpacing)
            
            context.draw(
                Text("\(Int(yValue))°")
                    .font(.system(size: 12))
                    .foregroundColor(.black),
                at: yLabelPosition
            )
        }
        
        // Draw X-axis labels (time range)
        let xLabelSpacing = size.width / 10.0
        for i in 0...10 {
            let xValue = timeRange.lowerBound + (timeRange.upperBound - timeRange.lowerBound) * Double(i) / 10.0
            let xLabelPosition = CGPoint(x: CGFloat(i) * xLabelSpacing, y: size.height + 10)
            
            context.draw(
                Text(String(format: "%.1f", xValue))
                    .font(.system(size: 12))
                    .foregroundColor(.black),
                at: xLabelPosition
            )
        }
    }
    
    private func drawJointAngleLine(joint: String, context: GraphicsContext, size: CGSize, color: Color) {
        // Get Data From poseProcessor
        let data = getJointData(joint)
        
        // Calculate visible range based on timeRange
        let startFrame = Int(timeRange.lowerBound * Double(data.count))
        let endFrame = Int(timeRange.upperBound * Double(data.count-1))
        
        let visibleData = Array(data[startFrame...endFrame])
        
        // Create path for the line
        let path = Path { p in
            guard !visibleData.isEmpty else { return }
            
            let xScale = size.width / CGFloat(visibleData.count - 1)
            let yScale = size.height / 180.0 // Assuming angles are in degrees (0-180)
            
            // Start at the first point
            p.move(to: CGPoint(
                x: 0,
                y: size.height - (CGFloat(visibleData[0]) * yScale)
            ))
            
            // Add lines to all subsequent points
            for i in 1..<visibleData.count {
                let point = CGPoint(
                    x: CGFloat(i) * xScale,
                    y: size.height - (CGFloat(visibleData[i]) * yScale)
                )
                p.addLine(to: point)
            }
        }
        
        // Draw the path
        context.stroke(path, with: .color(color), style: StrokeStyle(lineWidth: 2, lineCap: .round, lineJoin: .round))
    }
    
    private func drawCurrentFrameIndicator(context: GraphicsContext, size: CGSize) {
        // Calculate position based on current frame and visible range
        let totalFrames = poseProcessor.getTotalFrames()
        guard totalFrames > 0 else { return }
        
        let currentFrameNormalized = Double(currentFrameIndex) / Double(totalFrames - 1)
        
        // Only draw if current frame is within the visible range
        if currentFrameNormalized >= timeRange.lowerBound && currentFrameNormalized <= timeRange.upperBound {
            let rangeWidth = timeRange.upperBound - timeRange.lowerBound
            let positionInRange = (currentFrameNormalized - timeRange.lowerBound) / rangeWidth
            let xPosition = CGFloat(positionInRange) * size.width
            
            let path = Path { p in
                p.move(to: CGPoint(x: xPosition, y: 0))
                p.addLine(to: CGPoint(x: xPosition, y: size.height))
            }
            
            context.stroke(path, with: .color(.red), style: StrokeStyle(lineWidth: 2, dash: [4, 4]))
        }
    }

    
    private func getJointData(_ joint: String) -> [Double] {
        // Simple Double Array Data -> Create and Destroy Methods -> Save Memory
        // Define Array Container
        var dataPoints: [Double] = []
//        var dataPoints: [(time: Int, result: Double)] = []
        
        // Get Total Frame
        let totalFrame = poseProcessor.getTotalFrames()

        // Get Keypoints
        for i in 0..<totalFrame {
            var angle: Double = 0
            guard let keypoints = poseProcessor.getKeypoints(for: i) else { return [] }
            
            // Check Availability of Keypoint
            if keypoints.count != 17 { continue }
            
            // Get Joint Data
            switch joint {
            case "L Elbow": // Points: Shoulder → Elbow → Wrist
                angle = angleBetween(keypoints[5], keypoints[7], keypoints[9])
            case "R Elbow":
                angle = angleBetween(keypoints[6], keypoints[8], keypoints[10])
            case "L Shoulder": // Points: Hip → Shoulder → Elbow
                angle = angleBetween(keypoints[11], keypoints[5], keypoints[7])
            case "R Shoulder":
                angle = angleBetween(keypoints[12], keypoints[6], keypoints[8])
            case "L Hip": // Points: Shoulder → Hip → Knee
                angle = angleBetween(keypoints[5], keypoints[11], keypoints[13])
            case "R Hip":
                angle = angleBetween(keypoints[6], keypoints[12], keypoints[14])
            case "L Knee": // Points: Hip → Knee → Ankle
                angle = angleBetween(keypoints[11], keypoints[13], keypoints[15])
            case "R Knee":
                angle = angleBetween(keypoints[12], keypoints[14], keypoints[16])
            case "L Ankle": // Points: Knee → Ankle → Ground?
                angle = angleBetween(keypoints[11], keypoints[13], keypoints[15])
            case "R Ankle":
                angle = angleBetween(keypoints[12], keypoints[14], keypoints[16])
            default:
                angle = 0
            }
            // Append to Array
//            dataPoints.append((i,angle))
            dataPoints.append(angle)
        }
        return dataPoints
    }
    
    // MARK: ONLY USED FOR DEBUGGING. DO NOT USE FOR PRODUCTION APPS
    // Generate sample data for visualization
    private func getSampleDataForJoint(_ joint: String, frames: Int) -> [Double] {
        var result: [Double] = []
        
        // Different patterns for different joints
        switch joint {
        case "L Shoulder", "R Shoulder":
            // Shoulder angles - moderate movement
            for i in 0..<frames {
                let angle = 90.0 + 30.0 * sin(Double(i) / Double(frames) * 2.0 * .pi)
                result.append(angle)
            }
        case "L Elbow", "R Elbow":
            // Elbow angles - more dramatic movement
            for i in 0..<frames {
                let angle = 100.0 + 70.0 * sin(Double(i) / Double(frames) * 3.0 * .pi)
                result.append(angle)
            }
        case "L Knee", "R Knee":
            // Knee angles - different pattern
            for i in 0..<frames {
                let base = Double(i) / Double(frames)
                let angle = 20.0 + 160.0 * (base < 0.5 ? 2.0 * base : 2.0 - 2.0 * base)
                result.append(angle)
            }
        default:
            // Other joints - gentle wave
            for i in 0..<frames {
                let angle = 60.0 + 20.0 * sin(Double(i) / Double(frames) * 1.5 * .pi)
                result.append(angle)
            }
        }
        
        return result
    }
}

