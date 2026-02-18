//
//  YoloInference.swift
//  PoseA
//
//  Created by Shiela Cabahug on 2026/2/18.
//

import Vision
import CoreML
import CoreVideo
import CoreMedia

// MARK: - Pixel Buffer Pool
// Reuses CVPixelBuffer allocations instead of malloc/free per frame
final class PixelBufferPool {
    private var pool: CVPixelBufferPool?
    private let width: Int
    private let height: Int

    init(width: Int, height: Int) {
        self.width = width
        self.height = height

        let poolAttrs: [CFString: Any] = [
            kCVPixelBufferPoolMinimumBufferCountKey: 8  // Pre-warm 8 slots
        ]
        let bufferAttrs: [CFString: Any] = [
            kCVPixelBufferWidthKey:                  width,
            kCVPixelBufferHeightKey:                 height,
            kCVPixelBufferPixelFormatTypeKey:        kCVPixelFormatType_32BGRA,
            kCVPixelBufferCGImageCompatibilityKey:   true,
            kCVPixelBufferBytesPerRowAlignmentKey:   64  // Avoid Vision copy
        ]
        CVPixelBufferPoolCreate(kCFAllocatorDefault,
                                poolAttrs as CFDictionary,
                                bufferAttrs as CFDictionary,
                                &pool)
    }

    func dequeue() -> CVPixelBuffer? {
        guard let pool else { return nil }
        var buffer: CVPixelBuffer?
        CVPixelBufferPoolCreatePixelBuffer(kCFAllocatorDefault, pool, &buffer)
        return buffer
    }

    // Buffers auto-return to pool when their last retain drops
}

// MARK: - Frame Task
private struct FrameTask {
    let frameIndex: Int
    let url: URL
}

// MARK: - Inference Result
private struct FrameResult {
    let frameIndex: Int
    let keypoints: [KeypointData]
}

// MARK: - Efficient YOLO Pipeline
final class YOLOInferencePipeline {

    // MARK: - Tunables
    // Parallel inference workers — on A-series chips, 3-4 is the sweet spot.
    // More than 4 saturates the Neural Engine and degrades throughput.
    private let workerCount: Int
    // Frames loaded ahead of the current worker window
    private let prefetchDepth: Int
    private let inferenceTimeout: DispatchTimeInterval = .seconds(5)

    private let yolo: YOLOPoseProcessor

    init(yolo: YOLOPoseProcessor,
         workerCount: Int = 4,
         prefetchDepth: Int = 8) {
        self.yolo = yolo
        self.workerCount = workerCount
        self.prefetchDepth = prefetchDepth
    }

    // MARK: - Main Entry Point
    // Returns [frameIndex: keypoints], skipped frames are absent from the dict
    func run(
        frameURLs: [URL],
        onProgress: @escaping (Int, Int) -> Void,   // (completed, total)
        onComplete: @escaping ([Int: [KeypointData]], Int) -> Void  // (results, failCount)
    ) {
        let total = frameURLs.count
        guard total > 0 else {
            onComplete([:], 0)
            return
        }

        DispatchQueue.global(qos: .userInitiated).async {
            // Build task list
            let tasks = frameURLs.enumerated().map {
                FrameTask(frameIndex: $0.offset, url: $0.element)
            }

            // Peek at first frame to size the pixel buffer pool
            // (all video frames from the same source share dimensions)
            let firstFrameSize = self.peekImageSize(url: frameURLs[0]) ?? CGSize(width: 1920, height: 1080)
            let bufferPool = PixelBufferPool(
                width: Int(firstFrameSize.width),
                height: Int(firstFrameSize.height)
            )

            // Thread-safe result storage
            var results: [Int: [KeypointData]] = [:]
            results.reserveCapacity(total)
            let resultsLock = DispatchQueue(label: "pipeline.results", attributes: .concurrent)

            // Bounded concurrency: at most `workerCount` frames in-flight
            let throttle = DispatchSemaphore(value: self.workerCount)
            let group = DispatchGroup()

            var completedCount = 0
            var failCount = 0
            let counterLock = DispatchQueue(label: "pipeline.counters")

            for task in tasks {
                // Block until a worker slot opens — prevents unbounded prefetch
                throttle.wait()

                group.enter()
                DispatchQueue.global(qos: .userInitiated).async {
                    defer {
                        throttle.signal()   // Release slot for next frame
                        group.leave()
                    }

                    // Isolated autoreleasepool per frame — CGImage/buffer freed immediately
                    let result: FrameResult? = autoreleasepool {
                        self.processOne(task: task, pool: bufferPool)
                    }

                    counterLock.sync {
                        completedCount += 1
                        if result == nil { failCount += 1 }
                    }

                    if let result {
                        resultsLock.async(flags: .barrier) {
                            results[result.frameIndex] = result.keypoints
                        }
                    }

                    // Throttle UI updates — every 5 frames is enough
                    let completed = counterLock.sync { completedCount }
                    if completed % 5 == 0 || completed == total {
                        DispatchQueue.main.async { onProgress(completed, total) }
                    }
                }
            }

            // Wait for all workers to finish
            group.wait()

            let finalResults = resultsLock.sync { results }
            let finalFail = counterLock.sync { failCount }

            DispatchQueue.main.async {
                onComplete(finalResults, finalFail)
            }
        }
    }

    // MARK: - Single Frame
    private func processOne(task: FrameTask, pool: PixelBufferPool) -> FrameResult? {
        // 1. Decode with CGImageSource — no UIImage overhead, no extra copy
        guard
            let source = CGImageSourceCreateWithURL(task.url as CFURL, [
                kCGImageSourceShouldCache: false    // Don't cache decoded bitmap
            ] as CFDictionary),
            let cgImage = CGImageSourceCreateImageAtIndex(source, 0, [
                kCGImageSourceShouldCacheImmediately: false
            ] as CFDictionary)
        else {
//            log("Frame \(task.frameIndex): image load failed", level: .warning)
            print("Frame \(task.frameIndex): image load failed: warning")
            return nil
        }

        // 2. Blit into pooled buffer — reuses existing allocation
        guard let buffer = pool.dequeue(),
              blit(cgImage, into: buffer) else {
//            log("Frame \(task.frameIndex): pixel buffer unavailable", level: .warning)
            print("Frame \(task.frameIndex): image load failed: warning")
            return nil
        }

        // 3. Synchronous inference with timeout
        let pts = CMTime(value: CMTimeValue(task.frameIndex), timescale: 30)
        var frameResult: FrameResult? = nil
        let semaphore = DispatchSemaphore(value: 0)

        yolo.process(pixelBuffer: buffer, pts: pts) { [weak self] poses, _, _ in
            defer { semaphore.signal() }
            guard self != nil else { return }

            // Best pose = highest confidence detection
            guard let best = poses.max(by: { $0.confidence < $1.confidence }),
                  !best.keypoints.isEmpty else { return }

            let keypoints = best.keypoints.map {
                KeypointData(name: $0.name,
                             x: $0.x,
                             y: $0.y,
                             confidence: $0.confidence,
                             depth: $0.depth,
                             frameIndex: task.frameIndex)
            }
            frameResult = FrameResult(frameIndex: task.frameIndex, keypoints: keypoints)
        }

        // Hang-guard: if Neural Engine stalls, skip frame rather than deadlock
        if semaphore.wait(timeout: .now() + inferenceTimeout) == .timedOut {
            log("Frame \(task.frameIndex): inference timeout", level: .error)
            return nil
        }

        return frameResult
    }

    // MARK: - Blit (zero-copy where possible)
    // Draws CGImage directly into the pixel buffer's existing allocation
    private func blit(_ cgImage: CGImage, into buffer: CVPixelBuffer) -> Bool {
        CVPixelBufferLockBaseAddress(buffer, [])
        defer { CVPixelBufferUnlockBaseAddress(buffer, []) }

        guard let ctx = CGContext(
            data: CVPixelBufferGetBaseAddress(buffer),
            width: cvWidth(buffer),
            height: cvHeight(buffer),
            bitsPerComponent: 8,
            bytesPerRow: CVPixelBufferGetBytesPerRow(buffer),
            space: CGColorSpaceCreateDeviceRGB(),
            bitmapInfo: CGImageAlphaInfo.noneSkipFirst.rawValue
                      | CGBitmapInfo.byteOrder32Little.rawValue
        ) else { return false }

        ctx.draw(cgImage, in: CGRect(x: 0, y: 0,
                                     width: cvWidth(buffer),
                                     height: cvHeight(buffer)))
        return true
    }

    // MARK: - Helpers
    private func peekImageSize(url: URL) -> CGSize? {
        guard let source = CGImageSourceCreateWithURL(url as CFURL, nil),
              let props = CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [CFString: Any],
              let w = props[kCGImagePropertyPixelWidth] as? Int,
              let h = props[kCGImagePropertyPixelHeight] as? Int
        else { return nil }
        return CGSize(width: w, height: h)
    }

    private func cvWidth(_ b: CVPixelBuffer) -> Int { CVPixelBufferGetWidth(b) }
    private func cvHeight(_ b: CVPixelBuffer) -> Int { CVPixelBufferGetHeight(b) }
}



