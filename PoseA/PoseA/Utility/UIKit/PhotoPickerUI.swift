//
//  PhotoPickerView.swift
//  PoseA
//
//  Created by Ardhika Maulidani on 5/27/25.
//  Refactor from Shiela's codebase

import SwiftUI
import PhotosUI

// Photo library video picker
struct PhotoLibraryVideoPicker: UIViewControllerRepresentable {
    @Binding var isPresented: Bool
    let onPick: (URL?) -> Void
    
    func makeUIViewController(context: Context) -> PHPickerViewController {
        var config = PHPickerConfiguration()
        config.filter = .videos
        config.selectionLimit = 1
        
        let picker = PHPickerViewController(configuration: config)
        picker.delegate = context.coordinator
        return picker
    }
    
    func updateUIViewController(_ uiViewController: PHPickerViewController, context: Context) {}
    
    func makeCoordinator() -> Coordinator {
        Coordinator(parent: self)
    }
    
    class Coordinator: NSObject, PHPickerViewControllerDelegate {
        let parent: PhotoLibraryVideoPicker
        
        init(parent: PhotoLibraryVideoPicker) {
            self.parent = parent
        }
        
        func picker(_ picker: PHPickerViewController, didFinishPicking results: [PHPickerResult]) {
            parent.isPresented = false
            
            guard let result = results.first else {
                parent.onPick(nil)
                return
            }
            
            result.itemProvider.loadFileRepresentation(forTypeIdentifier: UTType.movie.identifier) { url, error in
                if let error = error {
                    print("Error loading video: \(error.localizedDescription)")
                    DispatchQueue.main.async {
                        self.parent.onPick(nil)
                    }
                    return
                }
                
                guard let url = url else {
                    DispatchQueue.main.async {
                        self.parent.onPick(nil)
                    }
                    return
                }
                
                // Create a copy of the file in the app's document directory
                let fileManager = FileManager.default
                let documentsDirectory = fileManager.urls(for: .documentDirectory, in: .userDomainMask).first!
                let destinationURL = documentsDirectory.appendingPathComponent(url.lastPathComponent)
                
                do {
                    // Remove existing file if it exists
                    if fileManager.fileExists(atPath: destinationURL.path) {
                        try fileManager.removeItem(at: destinationURL)
                    }
                    
                    try fileManager.copyItem(at: url, to: destinationURL)
                    
                    DispatchQueue.main.async {
                        self.parent.onPick(destinationURL)
                    }
                } catch {
                    print("Error copying video file: \(error.localizedDescription)")
                    DispatchQueue.main.async {
                        self.parent.onPick(nil)
                    }
                }
            }
        }
    }
}
