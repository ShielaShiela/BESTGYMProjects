//
//  DeviceOrientationVM.swift
//  PoseA
//
//  Created by Ardhika Maulidani on 6/24/25.
//

import SwiftUI

struct DeviceOrientationVM: View {
    @Binding var orientation: DeviceOrientationModel

    var body: some View {
        GeometryReader { geometry in
            Color.clear
                .onAppear {
                    updateOrientation(from: geometry.size)
                }
                .onChange(of: geometry.size) { _, newSize in
                    updateOrientation(from: newSize)
                }
        }
    }

    private func updateOrientation(from size: CGSize) {
        let newOrientation: DeviceOrientationModel = size.width > size.height ? .landscape : .portrait
        if orientation != newOrientation {
            orientation = newOrientation
        }
    }
}
