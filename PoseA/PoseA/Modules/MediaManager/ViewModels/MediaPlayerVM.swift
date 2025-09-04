//
//  MediaPlayerVM.swift
//  PoseA
//
//  Created by Ardhika Maulidani on 7/3/25.
//

import SwiftUI

// Use Frame Cache - Preloading is Faster than Switching Methods
class FrameCache {
    private var cache = NSCache<NSNumber, UIImage>()
    private let preloadCount = 3

    init() {
        // Rough budget: 100 MB for cached frames
        cache.totalCostLimit = 100 * 1024 * 1024
    }

    func image(for index: Int) -> UIImage? {
        cache.object(forKey: NSNumber(value: index))
    }

    func setImage(_ image: UIImage, for index: Int) {
        let cost = Int(image.size.width * image.size.height * 4) // 4 bytes per pixel
        cache.setObject(image, forKey: NSNumber(value: index), cost: cost)
    }

    func preload(from index: Int, using loader: @escaping (Int) -> UIImage?) {
        DispatchQueue.global(qos: .utility).async {
            for i in index..<(index + self.preloadCount) {
                if self.cache.object(forKey: NSNumber(value: i)) == nil,
                   let img = loader(i) {
                    let cost = Int(img.size.width * img.size.height * 4)
                    self.cache.setObject(img, forKey: NSNumber(value: i), cost: cost)
                }
            }
        }
    }

    func clear() {
        cache.removeAllObjects()
    }
}


@Observable
class MediaPlayerVM {
    // Get Media Data
    private var frameCache = FrameCache()
    private var FrameImageURLs:[URL] = []
    
    private var displayLink: CADisplayLink?
    private var lastTimestamp: CFTimeInterval = 0
    private let frameInterval: Double = 1.0 / 60.0
    
    // Image Variables
    var totalFrames: Int = 0
    var currentFrameIndex: Int = 0
    var currentFrameImage: UIImage? = nil

    // MARK: - Update Media Data
    func updateMedia(imageURLs: [URL]) {
        // Update Media Variables
        self.FrameImageURLs = imageURLs
        self.totalFrames = imageURLs.count
        
        self.firstFrame()
        log("New Media Updated.", level: .info)
    }
    
    
    // MARK: - Fast Forward Frame Functions
    
    func nextFrame() {
        if self.currentFrameIndex < totalFrames - 1 {
            let newIndex = self.currentFrameIndex + 1
            self.setFrame(to: newIndex)
        }
    }
    
    func previousFrame() {
        if currentFrameIndex > 0 {
            let newIndex = self.currentFrameIndex - 1
            self.setFrame(to: newIndex)
        }
    }
    
    func firstFrame() {
        self.setFrame(to: 0)
    }
    
    func lastFrame() {
        self.setFrame(to: totalFrames - 1)
    }
    
    func moveToFrame(_ index: Int) {
        self.setFrame(to: index)
    }

    func moveToFrameAsync(_ index: Int) async -> UIImage? {
        await withCheckedContinuation { continuation in
            self.setFrameAsync(to: index) {
                continuation.resume(returning: self.currentFrameImage)
            }
        }
    }
    
    // MARK: - Play Pause Frame Functions
    
    func stopPlayback() {
        // Ensure Running in Main Thread
        guard Thread.isMainThread else {
            DispatchQueue.main.async { [weak self] in self?.stopPlayback() }
            return
        }
        
        // Invalidate timer
        displayLink?.invalidate()
        displayLink = nil
    }
    
    func startPlayback() {
        stopPlayback()

        guard totalFrames > 0 else {
            print("❌ Cannot start playback: no frames available")
            return
        }

        log("Starting playback from frame \(currentFrameIndex)", level: .debug)

        lastTimestamp = 0
        displayLink = CADisplayLink(target: self, selector: #selector(updateFrame))
        displayLink?.add(to: .main, forMode: .common)
    }

    @objc private func updateFrame(displayLink: CADisplayLink) {
        // Time-based playback control
        if lastTimestamp == 0 {
            lastTimestamp = displayLink.timestamp
            return
        }

        let elapsed = displayLink.timestamp - lastTimestamp
        if elapsed >= frameInterval {
            let nextIndex = currentFrameIndex + 1
            if nextIndex >= totalFrames {
                stopPlayback()
            } else {
                currentFrameIndex = nextIndex
                self.setFrame(to: nextIndex)
            }
            lastTimestamp = displayLink.timestamp
        }
    }

    // MARK: - Cleaner Function
    func resetAll() {
        stopPlayback()
        currentFrameImage = nil
        currentFrameIndex = 0
        
        log("Reset Media Player.", level: .info)
    }
    
    // MARK: - Helper Function
    
    // Sets the current frame for playback, loads its image, applies orientation, and updates the UI.
    private func setFrameAsync(to index: Int, completion: (() -> Void)? = nil) {
        guard index >= 0 && index < totalFrames else {
            completion?()
            return
        }

        currentFrameIndex = index

        if let cached = frameCache.image(for: index) {
            currentFrameImage = cached
            completion?()  // Image is ready immediately
        } else {
            DispatchQueue.global(qos: .userInitiated).async {
                let img = self.loadImage(at: index)
                if let img = img {
                    self.frameCache.setImage(img, for: index)
                    DispatchQueue.main.async {
                        self.currentFrameImage = img
                        completion?()  // Image loaded and set
                    }
                } else {
                    DispatchQueue.main.async {
                        self.currentFrameImage = nil
                        completion?()  // Failed to load but still call completion
                    }
                }
            }
        }

        // Preload next few frames (optional)
        frameCache.preload(from: index + 1) { self.loadImage(at: $0) }
    }

    private func setFrame(to index: Int) {
        guard index >= 0 && index < totalFrames else { return }

        currentFrameIndex = index

        if let cached = frameCache.image(for: index) {
            currentFrameImage = cached
        } else {
            DispatchQueue.global(qos: .userInitiated).async {
                let img = self.loadImage(at: index)
                if let img = img {
                    self.frameCache.setImage(img, for: index)
                    DispatchQueue.main.async {
                        self.currentFrameImage = img
                    }
                } else {
                    self.currentFrameImage = nil
                }
            }
        }

        // Preload next few frames
        frameCache.preload(from: index + 1) { self.loadImage(at: $0) }
    }

    private func loadImage(at index: Int) -> UIImage? {
        guard index < self.FrameImageURLs.count else { return nil }
        
        // Get the frame directory
        let imageURL = self.FrameImageURLs[index]
        return loadLiDARFrame(from: imageURL)
    }
    
    private func loadLiDARFrame(from imageURL: URL) -> UIImage? {
        do {
            // Read the file data
            let imageData = try Data(contentsOf: imageURL)
            
            if let image = UIImage(data: imageData) {
                // Apply orientation correction
                return applyDefaultOrientation(to: image)
            } else {
                log("Failed to create UIImage from image data.", level: .error)
                return nil
            }
        } catch {
            log("Error loading frame.", level: .error)
            return nil
        }
    }
    
    private func applyDefaultOrientation(to image: UIImage) -> UIImage {
        // First check if this is a valid image
        guard let cgImage = image.cgImage else { return image }
        
        // Use image dimensions as hint
        let isLandscapeImage = image.size.width > image.size.height
        
        // Default orientations
        let defaultLandscapeOrientation: UIImage.Orientation = .up
        let defaultPortraitOrientation: UIImage.Orientation = .right
        
        // Apply default orientation based on image dimensions
        if isLandscapeImage && image.imageOrientation != defaultLandscapeOrientation {
            return UIImage(cgImage: cgImage, scale: image.scale, orientation: defaultLandscapeOrientation)
        } else if !isLandscapeImage && image.imageOrientation != defaultPortraitOrientation {
            return UIImage(cgImage: cgImage, scale: image.scale, orientation: defaultPortraitOrientation)
        }
        
        // No change needed
        return image
    }
}
    

