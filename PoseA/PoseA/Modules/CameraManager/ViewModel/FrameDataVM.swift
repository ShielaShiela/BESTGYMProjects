//
//  FrameDataVM.swift
//  PoseA
//
//  Created by Ardhika Maulidani on 6/26/25.
//

import SwiftUI
import Metal

final class FrameDataVM: ObservableObject {
    @Published var database = FrameDataModel()
    @Published var saveStatusMessage: String?
    
    private let ioService = FrameDataIOService()
    
    func saveData(to directory: URL, filter: Bool) {
        do {
            try ioService.save(database, to: directory, filter: filter)
        } catch {
            self.saveStatusMessage = "Save failed: \(error.localizedDescription)"
        }
    }
    
    func loadMetadata(from directory: URL) {
        do {
            let metadata = try ioService.loadMetadata(from: directory)
            database = FrameDataModel( cameraIntrinsics: metadata.intrinsics,
                                       cameraReferenceDimensions: metadata.referenceSize,
                                       depthCenter: metadata.depthCenter
                                     )
            
        } catch {
            print("Load metadata failed: \(error.localizedDescription)")
        }
    }
}
