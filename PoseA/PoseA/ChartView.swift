//import SwiftUI
//import Charts
//
//// MARK: - Data Structures
//struct KeypointMetric: Identifiable {
//    let id = UUID()
//    let frameIndex: Int
//    let keypointName: String
//    let x: Double
//    let y: Double
//    let depth: Double
//}
//
//struct JointAngleMetric: Identifiable {
//    let id = UUID()
//    let frameIndex: Int
//    let jointName: String
//    let angle: Double
//}
//
//struct KeypointStats {
//    let keypointName: String
//    let minValue: Double
//    let maxValue: Double
//    let avgValue: Double
//    let currentValue: Double
//}
//
//struct JointAngleStats {
//    let jointName: String
//    let minAngle: Double
//    let maxAngle: Double
//    let avgAngle: Double
//    let currentAngle: Double
//}
//
//// MARK: - Main Analysis View
//struct KeypointAnalysisView: View {
//    var poseProcessor: VitPoseProcessor
//    var currentFrameIndex: Int = 0
//    @Binding var showAnalysisView: Bool
//    
//    // UI State
//    @State private var debugMessage: String = ""
//    @State private var selectedTab = 0
//    @State private var isLoading = true
//    @State private var showKeypointNames = true
//    
//    // Analysis data
//    @State private var keypointData: [String: [KeypointMetric]] = [:]
//    @State private var jointAngleData: [String: [JointAngleMetric]] = [:]
//    @State private var frameRange: ClosedRange<Int> = 0...100
//    
//    // Main body
//    var body: some View {
//        VStack(spacing: 0) {
//            // Fixed top control bar
//            topControlBar
//            
//            if isLoading {
//                // Loading indicator
//                VStack {
//                    ProgressView()
//                        .scaleEffect(1.5)
//                    Text("Loading analysis data...")
//                        .padding(.top)
//                }
//                .frame(maxWidth: .infinity, maxHeight: .infinity)
//            } else if debugMessage == "No frames with keypoint data found" {
//                // Error state
//                VStack(spacing: 16) {
//                    Image(systemName: "exclamationmark.triangle")
//                        .font(.system(size: 40))
//                        .foregroundColor(.orange)
//                    
//                    Text("No Keypoint Data Found")
//                        .font(.headline)
//                    
//                    Text("Please make sure you have processed the frames and generated keypoints before viewing analysis.")
//                        .multilineTextAlignment(.center)
//                        .foregroundColor(.secondary)
//                        .padding(.horizontal)
//                    
//                    Button("Try Manual Refresh") {
//                        isLoading = true
//                        DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
//                            loadAnalysisData(forceRefresh: true)
//                        }
//                    }
//                    .buttonStyle(.bordered)
//                    .padding(.top)
//                }
//                .padding()
//                .frame(maxWidth: .infinity, maxHeight: .infinity)
//            } else {
//                // Top tab selector
//                Picker("Analysis Type", selection: $selectedTab) {
//                    Text("Position").tag(0)
//                    Text("Joint Angles").tag(1)
//                    Text("3D Model").tag(2)
//                }
//                .pickerStyle(SegmentedPickerStyle())
//                .padding([.horizontal, .top])
//                
//                // Current frame info
//                HStack {
//                    Text("Frame: \(currentFrameIndex)")
//                        .font(.caption)
//                        .foregroundColor(.secondary)
//                    
//                    Spacer()
//                    
//                    Text("\(frameRange.lowerBound)...\(frameRange.upperBound)")
//                        .font(.caption)
//                        .foregroundColor(.secondary)
//                }
//                .padding(.horizontal)
//                
//                // Content based on selected tab
//                TabView(selection: $selectedTab) {
//                    PositionAnalysisView(
//                        poseProcessor: poseProcessor,
//                        keypointData: keypointData,
//                        currentFrameIndex: currentFrameIndex,
//                        frameRange: frameRange,
//                        showKeypointNames: showKeypointNames
//                    )
//                    .tag(0)
//                    
//                    JointAngleAnalysisView(
//                        poseProcessor: poseProcessor,
//                        jointAngleData: jointAngleData,
//                        currentFrameIndex: currentFrameIndex,
//                        frameRange: frameRange,
//                        showKeypointNames: showKeypointNames
//                    )
//                    .tag(1)
//                    
//                    Model3DPlaceholderView()
//                    .tag(2)
//                }
//                .tabViewStyle(.page(indexDisplayMode: .never))
//                .onChange(of: selectedTab) { _, _ in
//                    // When tab changes, feedback for user
//                    let generator = UIImpactFeedbackGenerator(style: .light)
//                    generator.impactOccurred()
//                }
//            }
//        }
//        .onAppear {
//            loadAnalysisData()
//        }
//        .onChange(of: currentFrameIndex) { _, _ in
//            updateCurrentFrameData()
//        }
//        .contentShape(Rectangle())
//      
//    }
//    
//    // Fixed top control bar
//    private var topControlBar: some View {
//        HStack {
//            Button {
//                showAnalysisView = false
//            } label: {
//                HStack {
//                    Image(systemName: "arrow.left")
//                    Text("Back to Video")
//                }
//            }
//            .buttonStyle(.bordered)
//            
//            Spacer()
//            
//            Toggle("Labels", isOn: $showKeypointNames)
//                .toggleStyle(.button)
//                .controlSize(.small)
//            
//            Button {
//                isLoading = true
//                DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
//                    loadAnalysisData(forceRefresh: true)
//                }
//            } label: {
//                Image(systemName: "arrow.clockwise")
//            }
//            .buttonStyle(.bordered)
//            .controlSize(.small)
//        }
//        .padding(.horizontal)
//        .padding(.vertical, 8)
//        .background(Color.secondary.opacity(0.1))
//    }
//    
//    // Load all data needed for analysis
//    private func loadAnalysisData(forceRefresh: Bool = false) {
//        // Reset loading state if needed
//        if forceRefresh {
//            keypointData = [:]
//            jointAngleData = [:]
//        }
//        
//        // Get all frames that have keypoint data
//        let allFrames = poseProcessor.getFrameIndicesWithKeypoints()
//        
//        print("Found \(allFrames.count) frames with keypoints")
//        
//        // If no frames or forcing refresh, try to manually find frames
//        if allFrames.isEmpty || forceRefresh {
//            // Try a manual search through a range of frames
//            var manualFrames: [Int] = []
//            let totalFrames = 500 // Try checking up to this many frames
//            
//            for frameIndex in 0..<totalFrames {
//                if let keypoints = poseProcessor.getKeypoints(for: frameIndex), !keypoints.isEmpty {
//                    manualFrames.append(frameIndex)
//                }
//            }
//            
//            print("Manual search found \(manualFrames.count) frames with keypoints")
//            
//            if !manualFrames.isEmpty {
//                // Successfully found frames - set frame range and continue
//                let minFrame = manualFrames.min() ?? 0
//                let maxFrame = manualFrames.max() ?? 0
//                frameRange = minFrame...maxFrame
//                
//                // Load keypoint position data
//                loadKeypointPositionData(frameIndices: manualFrames)
//                
//                // Load joint angle data
//                loadJointAngleData(frameIndices: manualFrames)
//                
//                isLoading = false
//                return
//            } else {
//                // No frames found even with manual search
//                debugMessage = "No frames with keypoint data found"
//                isLoading = false
//                return
//            }
//        }
//        
//        // We have frames - set the frame range
//        let frameIndices = allFrames.sorted()
//        let minFrame = frameIndices.first ?? 0
//        let maxFrame = frameIndices.last ?? 0
//        frameRange = minFrame...maxFrame
//        
//        // Load keypoint position data
//        loadKeypointPositionData(frameIndices: frameIndices)
//        
//        // Load joint angle data
//        loadJointAngleData(frameIndices: frameIndices)
//        
//        // Done loading
//        isLoading = false
//    }
//    
//    // Load keypoint position data for all frames
//    private func loadKeypointPositionData(frameIndices: [Int]) {
//        var allKeypointData: [String: [KeypointMetric]] = [:]
//        
//        // Process each frame
//        for frameIndex in frameIndices {
//            guard let keypoints = poseProcessor.getKeypoints(for: frameIndex) else { continue }
//            
//            // Add each keypoint to its respective array
//            for keypoint in keypoints {
//                let metric = KeypointMetric(
//                    frameIndex: frameIndex,
//                    keypointName: keypoint.name,
//                    x: Double(keypoint.x),
//                    y: Double(keypoint.y),
//                    depth: Double(keypoint.depth)
//                )
//                
//                if allKeypointData[keypoint.name] == nil {
//                    allKeypointData[keypoint.name] = []
//                }
//                
//                allKeypointData[keypoint.name]?.append(metric)
//            }
//        }
//        
//        self.keypointData = allKeypointData
//    }
//    
//    // Load joint angle data for all frames
//    private func loadJointAngleData(frameIndices: [Int]) {
//        var allJointData: [String: [JointAngleMetric]] = [:]
//        
//        // Joint definitions - using arrays instead of tuples
//        let jointDefinitions: [String: [String]] = [
//            "Right Elbow": ["right_shoulder", "right_elbow", "right_wrist"],
//            "Left Elbow": ["left_shoulder", "left_elbow", "left_wrist"],
//            "Right Knee": ["right_hip", "right_knee", "right_ankle"],
//            "Left Knee": ["left_hip", "left_knee", "left_ankle"],
//            "Right Shoulder": ["neck", "right_shoulder", "right_elbow"],
//            "Left Shoulder": ["neck", "left_shoulder", "left_elbow"],
//            "Right Hip": ["spine", "right_hip", "right_knee"],
//            "Left Hip": ["spine", "left_hip", "left_knee"]
//        ]
//        
//        // Process each frame
//        for frameIndex in frameIndices {
//            guard let keypoints = poseProcessor.getKeypoints(for: frameIndex) else { continue }
//            
//            // Create a dictionary for quick lookup
//            let keypointDict = Dictionary(uniqueKeysWithValues: keypoints.map { ($0.name, $0) })
//            
//            // Calculate angles for each joint
//            for (jointName, jointPoints) in jointDefinitions {
//                // Make sure we have exactly 3 points for the joint
//                guard jointPoints.count == 3 else { continue }
//                
//                // Get the three keypoints that define the joint angle
//                let point1Name = jointPoints[0]
//                let point2Name = jointPoints[1]
//                let point3Name = jointPoints[2]
//                
//                // Try alternatives for some points (e.g., use "nose" if "neck" not available)
//                let point1 = keypointDict[point1Name] ?? keypointDict[point1Name == "neck" ? "nose" : (point1Name == "spine" ? "neck" : point1Name)]
//                let point2 = keypointDict[point2Name]
//                let point3 = keypointDict[point3Name]
//                
//                // Calculate angle if all points are available
//                if let p1 = point1, let p2 = point2, let p3 = point3 {
//                    let angle = calculateAngle(a: p1, b: p2, c: p3)
//                    
//                    let metric = JointAngleMetric(
//                        frameIndex: frameIndex,
//                        jointName: jointName,
//                        angle: angle
//                    )
//                    
//                    if allJointData[jointName] == nil {
//                        allJointData[jointName] = []
//                    }
//                    
//                    allJointData[jointName]?.append(metric)
//                }
//            }
//        }
//        
//        self.jointAngleData = allJointData
//    }
//    
//    // Calculate angle between three points
//    private func calculateAngle(a: KeypointData, b: KeypointData, c: KeypointData) -> Double {
//        // Vectors from B (joint) to A and C
//        let BA_x = Double(a.x - b.x)
//        let BA_y = Double(a.y - b.y)
//        let BC_x = Double(c.x - b.x)
//        let BC_y = Double(c.y - b.y)
//        
//        // Compute the dot product
//        let dotProduct = BA_x * BC_x + BA_y * BC_y
//        
//        // Compute the magnitudes
//        let magnitudeBA = sqrt(BA_x * BA_x + BA_y * BA_y)
//        let magnitudeBC = sqrt(BC_x * BC_x + BC_y * BC_y)
//        
//        // Avoid division by zero
//        if magnitudeBA == 0 || magnitudeBC == 0 {
//            return 0
//        }
//        
//        // Compute the cosine of the angle
//        let cosine = dotProduct / (magnitudeBA * magnitudeBC)
//        
//        // Clamp the value to the range [-1, 1] to avoid acos errors
//        let clampedCosine = max(-1, min(1, cosine))
//        
//        // Return the angle in degrees
//        return acos(clampedCosine) * 180 / .pi
//    }
//    
//    // Update data for the current frame
//    private func updateCurrentFrameData() {
//        // This method can be used to update any stats or highlights
//        // for the current frame as the user navigates through frames
//    }
//}
//
//// MARK: - Position Analysis View - Social Media Style
//struct PositionAnalysisView: View {
//    let poseProcessor: VitPoseProcessor
//    let keypointData: [String: [KeypointMetric]]
//    let currentFrameIndex: Int
//    let frameRange: ClosedRange<Int>
//    let showKeypointNames: Bool
//    
//    // Group keypoints by body region
//    private var keypointGroups: [(String, [String])] {
//        let head = keypointData.keys.filter { $0.contains("nose") || $0.contains("eye") || $0.contains("ear") }
//        let arms = keypointData.keys.filter { $0.contains("shoulder") || $0.contains("elbow") || $0.contains("wrist") }
//        let legs = keypointData.keys.filter { $0.contains("hip") || $0.contains("knee") || $0.contains("ankle") }
//        let other = keypointData.keys.filter { !head.contains($0) && !arms.contains($0) && !legs.contains($0) }
//        
//        return [
//            ("Arms", arms.sorted()),
//            ("Legs", legs.sorted()),
//            ("Head", head.sorted()),
//            ("Other", other.sorted())
//        ]
//    }
//    
//    var body: some View {
//        // Social media style scroll view
//        ScrollView {
//            LazyVStack(spacing: 16) {
//                // Position graphs by body region
//                ForEach(keypointGroups, id: \.0) { group in
//                    if !group.1.isEmpty {
//                        // For social media style, show X, Y, and Depth in separate cards
//                        PositionCard(
//                            title: "\(group.0) - X Position",
//                            keypointNames: group.1,
//                            keypointData: keypointData,
//                            currentFrameIndex: currentFrameIndex,
//                            frameRange: frameRange,
//                            displayMode: 0,
//                            showKeypointNames: showKeypointNames
//                        )
//                        
//                        PositionCard(
//                            title: "\(group.0) - Y Position",
//                            keypointNames: group.1,
//                            keypointData: keypointData,
//                            currentFrameIndex: currentFrameIndex,
//                            frameRange: frameRange,
//                            displayMode: 1,
//                            showKeypointNames: showKeypointNames
//                        )
//                        
//                        PositionCard(
//                            title: "\(group.0) - Depth",
//                            keypointNames: group.1,
//                            keypointData: keypointData,
//                            currentFrameIndex: currentFrameIndex,
//                            frameRange: frameRange,
//                            displayMode: 2,
//                            showKeypointNames: showKeypointNames
//                        )
//                    }
//                }
//            }
//            .padding()
//        }
//    }
//}
//
//// MARK: - Position Card - Social Media Style
//struct PositionCard: View {
//    let title: String
//    let keypointNames: [String]
//    let keypointData: [String: [KeypointMetric]]
//    let currentFrameIndex: Int
//    let frameRange: ClosedRange<Int>
//    let displayMode: Int
//    let showKeypointNames: Bool
//    
//    @State private var isExpanded = false
//    
//    private var displayModeTitle: String {
//        switch displayMode {
//        case 0: return "X Position"
//        case 1: return "Y Position"
//        case 2: return "Depth"
//        default: return ""
//        }
//    }
//    
//    var body: some View {
//        VStack(alignment: .leading, spacing: 12) {
//            // Title with like/share buttons for social media feel
//            HStack {
//                Text(title)
//                    .font(.headline)
//                
//                Spacer()
//                
//                // Social-like buttons
//                HStack(spacing: 12) {
//                    Button(action: {
//                        // Like action
//                        let generator = UIImpactFeedbackGenerator(style: .medium)
//                        generator.impactOccurred()
//                    }) {
//                        Image(systemName: "hand.thumbsup")
//                            .foregroundColor(.blue)
//                    }
//                    
//                    Button(action: {
//                        // Share action
//                        let generator = UIImpactFeedbackGenerator(style: .medium)
//                        generator.impactOccurred()
//                    }) {
//                        Image(systemName: "square.and.arrow.up")
//                            .foregroundColor(.blue)
//                    }
//                }
//            }
//            
//            // Graph of position data
//            Chart {
//                ForEach(keypointNames, id: \.self) { keypointName in
//                    ForEach(keypointData[keypointName] ?? []) { dataPoint in
//                        LineMark(
//                            x: .value("Frame", dataPoint.frameIndex),
//                            y: .value("Position", valueForDisplayMode(dataPoint, mode: displayMode))
//                        )
//                        .interpolationMethod(.catmullRom)
//                        .foregroundStyle(by: .value("Keypoint", showKeypointNames ? keypointName : "Data"))
//                        .symbol(by: .value("Keypoint", showKeypointNames ? keypointName : "Data"))
//                    }
//                    
//                    // Add points at current frame
//                    if let currentFrameData = keypointData[keypointName]?.first(where: { $0.frameIndex == currentFrameIndex }) {
//                        PointMark(
//                            x: .value("Frame", currentFrameIndex),
//                            y: .value("Position", valueForDisplayMode(currentFrameData, mode: displayMode))
//                        )
//                        .foregroundStyle(by: .value("Keypoint", showKeypointNames ? keypointName : "Data"))
//                        .symbolSize(100)
//                    }
//                }
//                
//                // Current frame indicator
//                RuleMark(x: .value("Current Frame", currentFrameIndex))
//                    .foregroundStyle(.orange.opacity(0.5))
//                    .lineStyle(StrokeStyle(lineWidth: 2, dash: [5, 3]))
//            }
//            .frame(height: 200)
//            .chartLegend(showKeypointNames ? .visible : .hidden)
//            .chartXScale(domain: frameRange.lowerBound...frameRange.upperBound)
//            .chartYAxis {
//                AxisMarks(position: .leading)
//            }
//            
//            // Show keypoint details when expanded
//            if isExpanded {
//                Divider()
//                
//                ForEach(keypointNames, id: \.self) { keypointName in
//                    if let stats = calculateKeypointStats(keypointName: keypointName, mode: displayMode) {
//                        KeypointDetailRow(
//                            keypointName: keypointName,
//                            stats: stats,
//                            displayMode: displayMode
//                        )
//                        .padding(.vertical, 4)
//                    }
//                }
//            }
//            
//            // Expand/collapse button with social media style
//            Button(action: {
//                withAnimation {
//                    isExpanded.toggle()
//                }
//            }) {
//                HStack {
//                    Spacer()
//                    Text(isExpanded ? "Show Less" : "Show Details")
//                    Image(systemName: isExpanded ? "chevron.up" : "chevron.down")
//                    Spacer()
//                }
//                .padding(.vertical, 6)
//                .foregroundColor(.blue)
//                .background(Color.blue.opacity(0.1))
//                .cornerRadius(16)
//            }
//        }
//        .padding()
//        .background(Color.secondary.opacity(0.1))
//        .cornerRadius(12)
//        .shadow(color: Color.black.opacity(0.1), radius: 5, x: 0, y: 2)
//    }
//    
//    // Get the value based on display mode
//    private func valueForDisplayMode(_ dataPoint: KeypointMetric, mode: Int) -> Double {
//        switch mode {
//        case 0: return dataPoint.x
//        case 1: return dataPoint.y
//        case 2: return dataPoint.depth
//        default: return 0
//        }
//    }
//    
//    // Calculate stats for a keypoint
//    private func calculateKeypointStats(keypointName: String, mode: Int) -> KeypointStats? {
//        guard let data = keypointData[keypointName] else { return nil }
//        
//        let values = data.map { valueForDisplayMode($0, mode: mode) }
//        
//        if values.isEmpty { return nil }
//        
//        let minValue = values.min() ?? 0
//        let maxValue = values.max() ?? 0
//        let avgValue = values.reduce(0, +) / Double(values.count)
//        
//        let currentValue = data
//            .first(where: { $0.frameIndex == currentFrameIndex })
//            .map { valueForDisplayMode($0, mode: mode) } ?? 0
//        
//        return KeypointStats(
//            keypointName: keypointName,
//            minValue: minValue,
//            maxValue: maxValue,
//            avgValue: avgValue,
//            currentValue: currentValue
//        )
//    }
//}
//
//// MARK: - Joint Angle Analysis View - Social Media Style
//struct JointAngleAnalysisView: View {
//    let poseProcessor: VitPoseProcessor
//    let jointAngleData: [String: [JointAngleMetric]]
//    let currentFrameIndex: Int
//    let frameRange: ClosedRange<Int>
//    let showKeypointNames: Bool
//    
//    // Group joints by body region
//    private var jointGroups: [(String, [String])] {
//        let upperBody = jointAngleData.keys.filter { $0.contains("Elbow") || $0.contains("Shoulder") }
//        let lowerBody = jointAngleData.keys.filter { $0.contains("Knee") || $0.contains("Hip") }
//        let other = jointAngleData.keys.filter { !upperBody.contains($0) && !lowerBody.contains($0) }
//        
//        return [
//            ("Upper Body", upperBody.sorted()),
//            ("Lower Body", lowerBody.sorted()),
//            ("Other", other.sorted())
//        ]
//    }
//    
//    var body: some View {
//        // Social media style scroll view
//        ScrollView {
//            LazyVStack(spacing: 16) {
//                // Joint angle graphs by body region
//                ForEach(jointGroups, id: \.0) { group in
//                    if !group.1.isEmpty {
//                        JointAngleCard(
//                            title: "\(group.0) Joints",
//                            jointNames: group.1,
//                            jointAngleData: jointAngleData,
//                            currentFrameIndex: currentFrameIndex,
//                            frameRange: frameRange,
//                            showJointNames: showKeypointNames
//                        )
//                    }
//                }
//            }
//            .padding()
//        }
//    }
//}
//
//// MARK: - Joint Angle Card - Social Media Style
//struct JointAngleCard: View {
//    let title: String
//    let jointNames: [String]
//    let jointAngleData: [String: [JointAngleMetric]]
//    let currentFrameIndex: Int
//    let frameRange: ClosedRange<Int>
//    let showJointNames: Bool
//    
//    @State private var isExpanded = false
//    
//    var body: some View {
//        VStack(alignment: .leading, spacing: 12) {
//            // Title with like/share buttons for social media feel
//            HStack {
//                Text(title)
//                    .font(.headline)
//                
//                Spacer()
//                
//                // Social-like buttons
//                HStack(spacing: 12) {
//                    Button(action: {
//                        // Like action
//                        let generator = UIImpactFeedbackGenerator(style: .medium)
//                        generator.impactOccurred()
//                    }) {
//                        Image(systemName: "hand.thumbsup")
//                            .foregroundColor(.blue)
//                    }
//                    
//                    Button(action: {
//                        // Share action
//                        let generator = UIImpactFeedbackGenerator(style: .medium)
//                        generator.impactOccurred()
//                    }) {
//                        Image(systemName: "square.and.arrow.up")
//                            .foregroundColor(.blue)
//                    }
//                }
//            }
//            
//            // Graph of joint angle data
//            Chart {
//                ForEach(jointNames, id: \.self) { jointName in
//                    ForEach(jointAngleData[jointName] ?? []) { dataPoint in
//                        LineMark(
//                            x: .value("Frame", dataPoint.frameIndex),
//                            y: .value("Angle", dataPoint.angle)
//                        )
//                        .interpolationMethod(.catmullRom)
//                        .foregroundStyle(by: .value("Joint", showJointNames ? jointName : "Data"))
//                        .symbol(by: .value("Joint", showJointNames ? jointName : "Data"))
//                    }
//                    
//                    // Add points at current frame
//                    if let currentFrameData = jointAngleData[jointName]?.first(where: { $0.frameIndex == currentFrameIndex }) {
//                        PointMark(
//                            x: .value("Frame", currentFrameIndex),
//                            y: .value("Angle", currentFrameData.angle)
//                        )
//                        .foregroundStyle(by: .value("Joint", showJointNames ? jointName : "Data"))
//                        .symbolSize(100)
//                    }
//                }
//                
//                // Current frame indicator
//                RuleMark(x: .value("Current Frame", currentFrameIndex))
//                    .foregroundStyle(.orange.opacity(0.5))
//                    .lineStyle(StrokeStyle(lineWidth: 2, dash: [5, 3]))
//            }
//            .frame(height: 200)
//            .chartLegend(showJointNames ? .visible : .hidden)
//            .chartXScale(domain: frameRange.lowerBound...frameRange.upperBound)
//            .chartYAxis {
//                AxisMarks(position: .leading) { value in
//                    AxisValueLabel {
//                        if let angle = value.as(Double.self) {
//                            Text("\(Int(angle))°")
//                        }
//                    }
//                }
//            }
//            .chartYScale(domain: 0...180)
//            
//            // Show joint details when expanded
//            if isExpanded {
//                Divider()
//                
//                ForEach(jointNames, id: \.self) { jointName in
//                    if let stats = calculateJointStats(jointName: jointName) {
//                        JointDetailRow(
//                            jointName: jointName,
//                            stats: stats
//                        )
//                        .padding(.vertical, 4)
//                    }
//                }
//            }
//            
//            // Expand/collapse button with social media style
//            Button(action: {
//                withAnimation {
//                    isExpanded.toggle()
//                }
//            }) {
//                HStack {
//                    Spacer()
//                    Text(isExpanded ? "Show Less" : "Show Details")
//                    Image(systemName: isExpanded ? "chevron.up" : "chevron.down")
//                    Spacer()
//                }
//                .padding(.vertical, 6)
//                .foregroundColor(.blue)
//                .background(Color.blue.opacity(0.1))
//                .cornerRadius(16)
//            }
//        }
//        .padding()
//        .background(Color.secondary.opacity(0.1))
//        .cornerRadius(12)
//        .shadow(color: Color.black.opacity(0.1), radius: 5, x: 0, y: 2)
//    }
//    
//    // Calculate stats for a joint
//    private func calculateJointStats(jointName: String) -> JointAngleStats? {
//        guard let data = jointAngleData[jointName] else { return nil }
//        
//        let angles = data.map { $0.angle }
//        
//        if angles.isEmpty { return nil }
//        
//        let minAngle = angles.min() ?? 0
//        let maxAngle = angles.max() ?? 0
//        let avgAngle = angles.reduce(0, +) / Double(angles.count)
//        
//        let currentAngle = data
//            .first(where: { $0.frameIndex == currentFrameIndex })
//            .map { $0.angle } ?? 0
//        
//        return JointAngleStats(
//            jointName: jointName,
//            minAngle: minAngle,
//            maxAngle: maxAngle,
//            avgAngle: avgAngle,
//            currentAngle: currentAngle
//        )
//    }
//}
//
//// MARK: - Detail Rows
//struct KeypointDetailRow: View {
//    let keypointName: String
//    let stats: KeypointStats
//    let displayMode: Int
//    
//    private var unitLabel: String {
//        switch displayMode {
//        case 0, 1: return "px"
//        case 2: return "m"
//        default: return ""
//        }
//    }
//    
//    var body: some View {
//        VStack(alignment: .leading) {
//            Text(keypointName)
//                .fontWeight(.medium)
//            
//            HStack(spacing: 16) {
//                DetailStat(label: "Current", value: String(format: "%.1f\(unitLabel)", stats.currentValue))
//                    .foregroundColor(.orange)
//                
//                DetailStat(label: "Min", value: String(format: "%.1f\(unitLabel)", stats.minValue))
//                DetailStat(label: "Max", value: String(format: "%.1f\(unitLabel)", stats.maxValue))
//                DetailStat(label: "Avg", value: String(format: "%.1f\(unitLabel)", stats.avgValue))
//            }
//        }
//    }
//}
//
//struct JointDetailRow: View {
//    let jointName: String
//    let stats: JointAngleStats
//    
//    var body: some View {
//        VStack(alignment: .leading) {
//            Text(jointName)
//                .fontWeight(.medium)
//            
//            HStack(spacing: 16) {
//                DetailStat(label: "Current", value: "\(Int(stats.currentAngle))°")
//                    .foregroundColor(.orange)
//                
//                DetailStat(label: "Min", value: "\(Int(stats.minAngle))°")
//                DetailStat(label: "Max", value: "\(Int(stats.maxAngle))°")
//                DetailStat(label: "Avg", value: "\(Int(stats.avgAngle))°")
//            }
//        }
//    }
//}
//
//struct DetailStat: View {
//    let label: String
//    let value: String
//    
//    var body: some View {
//        VStack(alignment: .center) {
//            Text(value)
//                .font(.system(.subheadline, design: .monospaced))
//                .fontWeight(.semibold)
//            
//            Text(label)
//                .font(.caption2)
//                .foregroundColor(.secondary)
//        }
//    }
//}
//
//// MARK: - 3D Model Placeholder
//struct Model3DPlaceholderView: View {
//    var body: some View {
//        ScrollView {
//            VStack(spacing: 20) {
//                // Placeholder 3D model card
//                VStack(spacing: 20) {
//                    Image(systemName: "cube.transparent.fill")
//                        .font(.system(size: 60))
//                        .foregroundColor(.blue)
//                    
//                    Text("3D Model Visualization")
//                        .font(.headline)
//                    
//                    Text("Coming in a future update")
//                        .fontWeight(.medium)
//                    
//                    Text("This feature will allow you to visualize the 3D pose data with a skeletal model that can be rotated and examined from any angle.")
//                        .font(.caption)
//                        .foregroundColor(.secondary)
//                        .multilineTextAlignment(.center)
//                        .padding(.horizontal)
//                }
//                .padding()
//                .background(Color.secondary.opacity(0.1))
//                .cornerRadius(12)
//                .shadow(color: Color.black.opacity(0.1), radius: 5, x: 0, y: 2)
//                
//                // Additional placeholder for future visualization options
//                VStack(alignment: .leading, spacing: 12) {
//                    Text("3D Analysis Options")
//                        .font(.headline)
//                    
//                    HStack(spacing: 16) {
//                        Button {
//                            // Placeholder for future functionality
//                        } label: {
//                            VStack {
//                                Image(systemName: "person.fill")
//                                    .font(.system(size: 24))
//                                Text("Full Body")
//                                    .font(.caption)
//                            }
//                            .frame(width: 80, height: 80)
//                            .background(Color.blue.opacity(0.1))
//                            .cornerRadius(12)
//                        }
//                        
//                        Button {
//                            // Placeholder for future functionality
//                        } label: {
//                            VStack {
//                                Image(systemName: "hand.raised.fill")
//                                    .font(.system(size: 24))
//                                Text("Upper Body")
//                                    .font(.caption)
//                            }
//                            .frame(width: 80, height: 80)
//                            .background(Color.blue.opacity(0.1))
//                            .cornerRadius(12)
//                        }
//                        
//                        Button {
//                            // Placeholder for future functionality
//                        } label: {
//                            VStack {
//                                Image(systemName: "figure.walk")
//                                    .font(.system(size: 24))
//                                Text("Gait Analysis")
//                                    .font(.caption)
//                            }
//                            .frame(width: 80, height: 80)
//                            .background(Color.blue.opacity(0.1))
//                            .cornerRadius(12)
//                        }
//                    }
//                }
//                .padding()
//                .background(Color.secondary.opacity(0.1))
//                .cornerRadius(12)
//                .shadow(color: Color.black.opacity(0.1), radius: 5, x: 0, y: 2)
//            }
//            .padding()
//        }
//    }
//}
//
//// MARK: - Main Tab Integration
//struct AnalysisTabView: View {
//    @ObservedObject var manager: CameraLiDARManager
//    let poseProcessor: VitPoseProcessor
//    @State private var selectedTab = 0
//    @State private var showAnalysisView = false
//    
//    var body: some View {
//        TabView(selection: $selectedTab) {
//            // Video View Tab
//            PoseDepthProcessorView(manager: manager)
//                .tabItem {
//                    Image(systemName: "video")
//                    Text("Video")
//                }
//                .tag(0)
//            
//            // Analysis View Tab
//            VStack {
//                if showAnalysisView {
//                    KeypointAnalysisView(
//                        poseProcessor: poseProcessor,
//                        currentFrameIndex: manager.currentFrameIndex,
//                        showAnalysisView: $showAnalysisView
//                    )
//                } else {
//                    VStack(spacing: 20) {
//                        Spacer()
//                        
//                        Image(systemName: "chart.line.uptrend.xyaxis")
//                            .font(.system(size: 60))
//                            .foregroundColor(.blue)
//                        
//                        Text("Keypoint Analysis")
//                            .font(.title2)
//                        
//                        Text("View detailed graphs and statistics about keypoint positions and joint angles.")
//                            .multilineTextAlignment(.center)
//                            .foregroundColor(.secondary)
//                            .padding(.horizontal, 40)
//                        
//                        Button {
//                            withAnimation {
//                                showAnalysisView = true
//                            }
//                        } label: {
//                            Text("View Analysis")
//                                .fontWeight(.medium)
//                                .padding(.vertical, 12)
//                                .padding(.horizontal, 24)
//                                .background(Color.blue)
//                                .foregroundColor(.white)
//                                .cornerRadius(10)
//                        }
//                        .padding(.top, 20)
//                        
//                        Spacer()
//                    }
//                }
//            }
//            .tabItem {
//                Image(systemName: "chart.xyaxis.line")
//                Text("Analysis")
//            }
//            .tag(1)
//        }
//    }
//}
