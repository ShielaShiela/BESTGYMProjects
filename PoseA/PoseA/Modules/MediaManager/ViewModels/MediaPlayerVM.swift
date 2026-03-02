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

//class FrameCache {
//    private var cache = NSCache<NSNumber, UIImage>()
//    private let preloadCount = 3
//    private var isCancelled = false  // ADD THIS
//
//    init() {
//        cache.totalCostLimit = 100 * 1024 * 1024
//    }
//
//    func image(for index: Int) -> UIImage? {
//        cache.object(forKey: NSNumber(value: index))
//    }
//
//    func setImage(_ image: UIImage, for index: Int) {
//        guard !isCancelled else { return }  // ADD THIS guard
//        let cost = Int(image.size.width * image.size.height * 4)
//        cache.setObject(image, forKey: NSNumber(value: index), cost: cost)
//    }
//
//    func preload(from index: Int, using loader: @escaping (Int) -> UIImage?) {
//        DispatchQueue.global(qos: .utility).async {
//            for i in index..<(index + self.preloadCount) {
//                guard !self.isCancelled else { return }  // ADD THIS guard
//                if self.cache.object(forKey: NSNumber(value: i)) == nil,
//                   let img = loader(i) {
//                    guard !self.isCancelled else { return }  // ADD THIS guard
//                    let cost = Int(img.size.width * img.size.height * 4)
//                    self.cache.setObject(img, forKey: NSNumber(value: i), cost: cost)
//                }
//            }
//        }
//    }
//
//    func clear() {
//        isCancelled = true           // Stop any in-flight preloads first
//        cache.removeAllObjects()
//        isCancelled = false          // Re-arm for next use
//    }
//}


@Observable
class MediaPlayerVM {
    // Get Media Data
    private var frameCache = FrameCache()
    private var FrameImageURLs:[URL] = []
    
    private var displayLink: CADisplayLink?
    private var lastTimestamp: CFTimeInterval = 0
//    private let frameInterval: Double = 1.0 / 60.0
    var fps: Double = 30.0
    private var frameInterval: Double { 1.0 / fps }
    
    // Image Variables
    var totalFrames: Int = 0
    var currentFrameIndex: Int = 0
    var currentFrameImage: UIImage? = nil

    // MARK: - Update Media Data
//    func updateMedia(imageURLs: [URL]) {
//        // Update Media Variables
//        self.FrameImageURLs = imageURLs
//        self.totalFrames = imageURLs.count
//        
//        self.firstFrame()
//        log("New Media Updated.", level: .info)
//    }
    func updateMedia(imageURLs: [URL], fps: Double = 30.0) {
        self.fps = fps
        self.FrameImageURLs = imageURLs
        self.totalFrames = imageURLs.count
        self.currentFrameIndex = 0
        
        // Force load first frame immediately
        if let firstURL = imageURLs.first {
            self.currentFrameImage = UIImage(contentsOfFile: firstURL.path)
        } else {
            self.currentFrameImage = nil
        }
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
    
    func resetAll() {
        // Invalidate and nil immediately so any stray tick is blocked by the guard above
        displayLink?.invalidate()
        displayLink = nil
        totalFrames = 0
        currentFrameImage = nil
        currentFrameIndex = 0
        FrameImageURLs = []
        frameCache.clear()
        lastTimestamp = 0  // ADD THIS — prevents stale timestamp on next load
        
        log("Reset Media Player.", level: .info)
    }
    // MARK: - Play Pause Frame Functions
    
//    func stopPlayback() {
//        // Ensure Running in Main Thread
//        guard Thread.isMainThread else {
//            DispatchQueue.main.async { [weak self] in self?.stopPlayback() }
//            return
//        }
//        
//        // Invalidate timer
//        displayLink?.invalidate()
//        displayLink = nil
//    }
    
    func stopPlayback() {
        guard Thread.isMainThread else {
            DispatchQueue.main.async { [weak self] in self?.stopPlayback() }
            return
        }
        displayLink?.invalidate()
        displayLink = nil  // ADD THIS — was missing before
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

//    @objc private func updateFrame(displayLink: CADisplayLink) {
//        // Time-based playback control
//        if lastTimestamp == 0 {
//            lastTimestamp = displayLink.timestamp
//            return
//        }
//
//        let elapsed = displayLink.timestamp - lastTimestamp
//        if elapsed >= frameInterval {
//            let nextIndex = currentFrameIndex + 1
//            if nextIndex >= totalFrames {
//                stopPlayback()
//            } else {
//                currentFrameIndex = nextIndex
//                self.setFrame(to: nextIndex)
//            }
//            lastTimestamp = displayLink.timestamp
//        }
//    }
    @objc private func updateFrame(displayLink: CADisplayLink) {
        guard totalFrames > 0, !FrameImageURLs.isEmpty else {  // ADD THIS guard
            stopPlayback()
            return
        }
        
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
//    func resetAll() {
//        stopPlayback()
//        currentFrameImage = nil
//        currentFrameIndex = 0
//        
//        log("Reset Media Player.", level: .info)
//    }
    
    
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

//    private func setFrame(to index: Int) {
//        guard index >= 0 && index < totalFrames else { return }
//
//        currentFrameIndex = index
//
//        if let cached = frameCache.image(for: index) {
//            currentFrameImage = cached
//        } else {
//            DispatchQueue.global(qos: .userInitiated).async {
//                let img = self.loadImage(at: index)
//                if let img = img {
//                    self.frameCache.setImage(img, for: index)
//                    DispatchQueue.main.async {
//                        self.currentFrameImage = img
//                    }
//                } else {
//                    self.currentFrameImage = nil
//                }
//            }
//        }
//
//        // Preload next few frames
//        frameCache.preload(from: index + 1) { self.loadImage(at: $0) }
//    }
    
    private func setFrame(to index: Int) {
        guard index >= 0 && index < totalFrames else { return }

        currentFrameIndex = index

        if let cached = frameCache.image(for: index) {
            currentFrameImage = cached
        } else {
            let capturedURLs = self.FrameImageURLs  // capture before async
            DispatchQueue.global(qos: .userInitiated).async {
                guard !capturedURLs.isEmpty, index < capturedURLs.count else { return }  // ADD THIS
                let img = self.loadImage(at: index)
                if let img = img {
                    self.frameCache.setImage(img, for: index)
                    DispatchQueue.main.async {
                        guard self.currentFrameIndex == index else { return }  // ADD THIS — stale update guard
                        self.currentFrameImage = img
                    }
                } else {
                    self.currentFrameImage = nil
                }
            }
        }

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
    

