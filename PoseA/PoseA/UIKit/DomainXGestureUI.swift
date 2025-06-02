//
//  AxesXGestureUI.swift
//  PoseA
//
//  Created by Ardhika Maulidani on 6/1/25.
//

import SwiftUI

@available(iOS 18.0, *)
public struct DomainXGesture<Bound: ExpressibleByDouble>: UIGestureRecognizerRepresentable {
    @Binding var domain: ClosedRange<Bound>
    let simultaneous: Bool
    let onEnded: () -> Void
    
    @State private var leading: Double?
    @State private var leadingValue: Double?
    @State private var trailingValue: Double?
    
    public init(
        domain: Binding<ClosedRange<Bound>>,
        simultaneous: Bool = false,
        onEnded: @escaping () -> () = {}
    ) {
        self._domain = domain
        self.simultaneous = simultaneous
        self.onEnded = onEnded
    }
    
    public func makeUIGestureRecognizer(context: Context) -> GestureRecognizer {
        GestureRecognizer(simultaneous: simultaneous)
    }
    
    public func updateUIGestureRecognizer(_ recognizer: GestureRecognizer, context: Context) {
        recognizer.simultaneous = simultaneous
    }
    
    public func handleUIGestureRecognizerAction(_ recognizer: GestureRecognizer, context: Context) {
        let lowerBound = domain.lowerBound.double
        let upperBound = domain.upperBound.double
        switch recognizer.interaction {
        case .pan(let x, let isInitial):
            if isInitial { leading = x }
            if let leading {
                let offset = (upperBound - lowerBound) * (leading - x)
                domain = Bound(lowerBound + offset)...Bound(upperBound + offset)
                self.leading = x
            }
        case .pinch(let leadingX, let trailingX, let isInitial):
            if leadingX == trailingX { return }
            if isInitial {
                let m = upperBound - lowerBound
                leadingValue = (m * leadingX) + lowerBound
                trailingValue = (m * trailingX) + lowerBound
            }
            if let leadingValue, let trailingValue {
                let m = (trailingValue - leadingValue) / (trailingX - leadingX)
                let b = leadingValue - m * leadingX
                domain = Bound(b)...Bound(b + m)
            }
        case nil:
            onEnded()
        }
    }
}

public protocol ExpressibleByDouble: Comparable {
    var double: Double { get }
    init(_ double: Double)
}

extension TimeInterval: ExpressibleByDouble {
    public var double: Double { self }
    public init(_ double: Double) { self = double }
}

extension Date: ExpressibleByDouble {
    public var double: Double { timeIntervalSince1970 }
    public init(_ double: Double) { self = Date(timeIntervalSince1970: double) }
}
