//
//  3DChartAnimationView.swift
//  PoseA
//
//  Created by Ardhika Maulidani on 12/12/25.
//

import Spatial
import SwiftUI
import Charts

fileprivate let cocoConnections: [(Int, Int)] = [ (0, 1), (0, 2),
                                                  (1, 3), (2, 4),
                                                  (5, 6), (5, 7),
                                                  (7, 9), (6, 8),
                                                  (8, 10),
                                                  (5, 11), (6, 12),
                                                  (11, 12), (11, 13),
                                                  (13, 15), (12, 14),
                                                  (14, 16) ]

fileprivate struct Chart3DScale {
    var maxX: Double
    var maxY: Double
    var maxZ: Double
    var minX: Double
    var minY: Double
    var minZ: Double
    
    init(maxX: Double = 641, maxY: Double = -300, maxZ: Double = 0, minX: Double = 640, minY: Double = -321, minZ: Double = 0) {
        self.maxX = maxX
        self.maxY = maxY
        self.maxZ = maxZ
        self.minX = minX
        self.minY = minY
        self.minZ = minZ
    }
    
    func update(with other: Chart3DScale) -> Chart3DScale {
        return Chart3DScale(
            maxX: max(self.maxX, other.maxX),
            maxY: max(self.maxY, other.maxY),
            maxZ: max(self.maxZ, other.maxZ),
            minX: min(self.minX, other.minX),
            minY: min(self.minY, other.minY),
            minZ: min(self.minZ, other.minZ)
        )
    }
    
    func update(x: Double, y: Double, z: Double) -> Chart3DScale {
        // This function can be used to update the scale with individual values if needed
        return Chart3DScale(
            maxX: max(self.maxX, x),
            maxY: max(self.maxY, y),
            maxZ: max(self.maxZ, z),
            minX: min(self.minX, x),
            minY: min(self.minY, y),
            minZ: min(self.minZ, z)
        )
    }
}

struct Chart3DAnimationView: View {
    // MARK: - Properties
    let keypoints: PoseBox?
    
    @State private var chartScaleData = Chart3DScale()
    
    // MARK: - Body
    var body: some View {
        GeometryReader { geo in
            ZStack(alignment: .center) {
                Color.white // Force background
                if #available(iOS 26, *) {
                    if let keypoints = keypoints,
                       !keypoints.keypoints.isEmpty {
                        let (chartData, chartScale) = parsePoseBox(_poseBox: keypoints)
                        
                        Chart3D {
                            ForEach(chartData) { point in
                                PointMark(
                                    x: .value("X", point.x),
                                    y: .value("Y", point.y),
                                    z: .value("Z", point.z)
                                )
                            }
                        }
                        .chartXAxisLabel("X")
                        .chartYAxisLabel("Y")
                        .chartZAxisLabel("Z")
                        .chartXScale(domain: chartScaleData.minX...chartScaleData.maxX)
                        .chartYScale(domain: chartScaleData.minY...chartScaleData.maxY)
                        .chartZScale(domain: chartScaleData.minZ...chartScaleData.maxZ)
                        .frame(width: geo.size.width * 1.25,
                               height: geo.size.height * 1.25)
                        .background(Color.green)
                        .padding(0)
                        
                        .onAppear {
                            chartScaleData = chartScaleData.update(with: chartScale)
                        }
                        .onChange(of: chartData) {
                            chartScaleData = chartScaleData.update(with: chartScale)
                        }
                    }
                } else {
                    Text("3D Charts are available on iOS 26 and later.")
                }
            }
        }
    }
    
    
    private func parsePoseBox(_poseBox: PoseBox, steps: Int = 10) -> ([ChartPoint3D], Chart3DScale){
        let kp = _poseBox.keypoints
        var dataPoints: [ChartPoint3D] = []
        
        var scaleChart = Chart3DScale()
        
        // Add original joint points
        for keypoint in kp {
            dataPoints.append(ChartPoint3D(Point3D(x: keypoint.x,
                                                   y: -keypoint.y,
                                                   z: CGFloat(keypoint.depth))))
            
            scaleChart = scaleChart.update(x: Double(keypoint.x),
                                           y: Double(-keypoint.y),
                                           z: Double(keypoint.depth))
        }
            
        // Add interpolated points for skeleton lines
        for (s, e) in cocoConnections {
            guard s < kp.count, e < kp.count else { continue }
            
            let p1 = kp[s]
            let p2 = kp[e]
            
            let x1 = p1.x, y1 = -p1.y, z1 = CGFloat(p1.depth)
            let x2 = p2.x, y2 = -p2.y, z2 = CGFloat(p2.depth)
            
            // interpolate steps between points
            for i in 1..<steps {
                let t = CGFloat(i) / CGFloat(steps)
                let xi = x1 + (x2 - x1) * t
                let yi = y1 + (y2 - y1) * t
                let zi = z1 + (z2 - z1) * t
                
                dataPoints.append(
                    ChartPoint3D(Point3D(x: xi, y: yi, z: zi))
                )
            }
        }
        
        return (dataPoints, scaleChart)
    }
}
