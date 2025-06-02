////
////  RangeSlider.swift
////  PoseA
////
////  Created by Ardhika Maulidani on 5/27/25.
////  Refactor from Shiela Cabahug's codebase
//
//import SwiftUI
//struct RangeSlider: View {
//    @Binding var value: ClosedRange<Double>
//    let bounds: ClosedRange<Double>
//
//    init(value: Binding<ClosedRange<Double>>, in bounds: ClosedRange<Double>) {
//        self._value = value
//        self.bounds = bounds
//    }
//
//    var body: some View {
//        GeometryReader { geometry in
//            ZStack(alignment: .leading) {
//                // Track
//                Rectangle()
//                    .fill(Color.gray.opacity(0.2))
//                    .frame(height: 6)
//                    .cornerRadius(3)
//
//                // Selected range
//                Rectangle()
//                    .fill(Color.blue)
//                    .frame(
//                        width: CGFloat((value.upperBound - value.lowerBound) / (bounds.upperBound - bounds.lowerBound)) * geometry.size.width,
//                        height: 6
//                    )
//                    .offset(
//                        x: CGFloat((value.lowerBound - bounds.lowerBound) / (bounds.upperBound - bounds.lowerBound)) * geometry.size.width
//                    )
//                    .cornerRadius(3)
//
//                // Lower handle
//                Circle()
//                    .fill(Color.white)
//                    .frame(width: 24, height: 24)
//                    .shadow(radius: 2)
//                    .offset(
//                        x: CGFloat((value.lowerBound - bounds.lowerBound) / (bounds.upperBound - bounds.lowerBound)) * geometry.size.width - 12
//                    )
//                    .gesture(
//                        DragGesture()
//                            .onChanged { gesture in
//                                let rawValue = Double(gesture.location.x / geometry.size.width)
//                                let unclampedValue = bounds.lowerBound + rawValue * (bounds.upperBound - bounds.lowerBound)
//                                let clampedValue = min(max(unclampedValue, bounds.lowerBound), value.upperBound)
//
//                                value = clampedValue...value.upperBound
//                            }
//                    )
//
//                // Upper handle
//                Circle()
//                    .fill(Color.white)
//                    .frame(width: 24, height: 24)
//                    .shadow(radius: 2)
//                    .offset(
//                        x: CGFloat((value.upperBound - bounds.lowerBound) / (bounds.upperBound - bounds.lowerBound)) * geometry.size.width - 12
//                    )
//                    .gesture(
//                        DragGesture()
//                            .onChanged { gesture in
//                                let rawValue = Double(gesture.location.x / geometry.size.width)
//                                let unclampedValue = bounds.lowerBound + rawValue * (bounds.upperBound - bounds.lowerBound)
//                                let clampedValue = max(min(unclampedValue, bounds.upperBound), value.lowerBound)
//
//                                value = value.lowerBound...clampedValue
//                            }
//                    )
//            }
//            .frame(height: 24)
//        }
//        .frame(height: 24)
//    }
//}
