// DepthFrameLoader.swift
// Loads depth_NNNN.bin files from the depth_frames/ subfolder of a LiDAR recording.
// Each .bin file is a row-major Float32 array of depth values in metres.

import Foundation
import UIKit
import simd

// MARK: - Loaded depth frame

struct DepthFrame {
    let width: Int
    let height: Int
    /// Row-major Float32 array, metres, length == width * height
    let data: [Float32]

    subscript(x: Int, y: Int) -> Float32 {
        guard x >= 0, y >= 0, x < width, y < height else { return 0 }
        return data[y * width + x]
    }

    /// Sample depth at a normalised (0–1) position, bilinear
    func depthAt(normalizedX nx: Double, normalizedY ny: Double) -> Float32 {
        let px = nx * Double(width  - 1)
        let py = ny * Double(height - 1)
        let x0 = Int(floor(px)), y0 = Int(floor(py))
        let x1 = min(x0 + 1, width  - 1)
        let y1 = min(y0 + 1, height - 1)
        let fx = Float(px - floor(px)), fy = Float(py - floor(py))

        let v00 = self[x0, y0], v10 = self[x1, y0]
        let v01 = self[x0, y1], v11 = self[x1, y1]
        return v00 * (1 - fx) * (1 - fy)
             + v10 *      fx  * (1 - fy)
             + v01 * (1 - fx) *      fy
             + v11 *      fx  *      fy
    }
}

// MARK: - Loader

final class DepthFrameLoader {

    // Cache to avoid re-reading the same file repeatedly
    private var cache: [Int: DepthFrame] = [:]
    private var depthFramesURL: URL?

    // Resolved width/height once the first frame is loaded
    private(set) var frameWidth: Int = 0
    private(set) var frameHeight: Int = 0

    // MARK: - Setup

    /// Call this when a new LiDAR recording folder is opened.
    /// `recordingFolderURL` is the root folder that contains `depth_frames/`.
    func configure(recordingFolderURL: URL) {
        cache.removeAll()
        frameWidth  = 0
        frameHeight = 0

        print("📡 DepthFrameLoader: searching from \(recordingFolderURL.path)")

        if let found = findDepthFramesFolder(startingAt: recordingFolderURL) {
            depthFramesURL = found
            // Sniff the padding width and index base from whatever files exist
            sniffFileFormat(in: found)
            print("📡 DepthFrameLoader: configured with \(found.path)")
            print("📡 DepthFrameLoader: format → padding=\(paddingWidth) digits, startIndex=\(frameStartIndex)")
        } else {
            depthFramesURL = nil
            print("⚠️ DepthFrameLoader: depth_frames/ NOT found anywhere under \(recordingFolderURL.lastPathComponent)")
        }
    }

    /// Searches `start` and one level of parent for a `depth_frames` directory.
    private func findDepthFramesFolder(startingAt start: URL) -> URL? {
        let fm = FileManager.default

        // Candidates to check, in priority order:
        // 1. start/depth_frames          (start is already the recording folder)
        // 2. start/../depth_frames       (start is a file inside the recording folder)
        // 3. start (itself)              (start IS depth_frames)
        let candidates: [URL] = [
            start.appendingPathComponent("depth_frames"),
            start.deletingLastPathComponent().appendingPathComponent("depth_frames"),
            start   // in case the caller already passed the depth_frames folder directly
        ]

        for url in candidates {
            var isDir: ObjCBool = false
            if fm.fileExists(atPath: url.path, isDirectory: &isDir), isDir.boolValue {
                // Confirm it actually contains .bin files
                if let items = try? fm.contentsOfDirectory(atPath: url.path),
                   items.contains(where: { isValidDepthFile($0) }) {
                    return url
                }
            }
        }
        return nil
    }

    // MARK: - Format sniffing

    /// Detected zero-pad width (e.g. 6 for depth_000001.bin)
    private(set) var paddingWidth: Int = 6
    /// Whether files are 1-based (depth_000001) or 0-based (depth_000000)
    private(set) var frameStartIndex: Int = 1

    private func sniffFileFormat(in folderURL: URL) {
        guard let items = try? FileManager.default.contentsOfDirectory(atPath: folderURL.path) else { return }
        let binFiles = items
            .filter { isValidDepthFile($0) }
            .sorted()
        guard let first = binFiles.first else { return }

        // Strip prefix "depth_" and suffix ".bin" to get the numeric part
        let stem = first
            .replacingOccurrences(of: "depth_", with: "")
            .replacingOccurrences(of: ".bin", with: "")
        paddingWidth  = stem.count   // e.g. "000001" → 6
        frameStartIndex = Int(stem) ?? 1   // e.g. 1 for 1-based, 0 for 0-based

        print("📡 DepthFrameLoader: sniffed first file='\(first)' → padding=\(paddingWidth), startIndex=\(frameStartIndex)")
    }

    var isAvailable: Bool { depthFramesURL != nil }

    // MARK: - Load

    /// Returns the depth frame for `frameIndex` (0-based, matching video array index).
    /// Tries `depth_NNNN.bin` naming convention where NNNN is zero-padded 4 digits.
    /// Async so it doesn't block the main thread.
    func loadFrame(_ frameIndex: Int,
                   width: Int, height: Int) async -> DepthFrame? {
        // Return cached
        if let cached = cache[frameIndex] { return cached }
        guard let baseURL = depthFramesURL else { return nil }

        // Single deterministic filename — sniffed format is now trustworthy
        let fileNumber = frameIndex + frameStartIndex
        let name = String(format: "depth_%0\(paddingWidth)d.bin", fileNumber)
        let url  = baseURL.appendingPathComponent(name)

        guard FileManager.default.fileExists(atPath: url.path) else {
            print("⚠️ DepthFrameLoader[\(frameIndex)]: not found → \(name)")
            return nil
        }

        // Load on background thread
        return await withCheckedContinuation { continuation in
            DispatchQueue.global(qos: .userInitiated).async { [weak self] in
                guard let self else { continuation.resume(returning: nil); return }
                do {
                    let data = try Data(contentsOf: url)
                    guard data.count > 12 else {
                        print("⚠️ DepthFrameLoader: file too small (\(data.count) bytes): \(url.lastPathComponent)")
                        continuation.resume(returning: nil)
                        return
                    }

                    // ── Parse 12-byte header ──────────────────────────────────
                    let w: Int = data.withUnsafeBytes { Int($0.load(fromByteOffset: 0, as: Int32.self)) }
                    let h: Int = data.withUnsafeBytes { Int($0.load(fromByteOffset: 4, as: Int32.self)) }
                    let pixelFormat: UInt32 = data.withUnsafeBytes { $0.load(fromByteOffset: 8, as: UInt32.self) }

                    let headerSize    = 12
                    let pixelCount    = w * h
                    let remainingBytes = data.count - headerSize

                    // ── Detect Float16 vs Float32 by byte count (ground truth) ──
                    // pixelFormat tag can lie — byte count never does.
                    let isFloat32: Bool
                    if remainingBytes == pixelCount * 4 {
                        isFloat32 = true
                    } else if remainingBytes == pixelCount * 2 {
                        isFloat32 = false
                    } else {
                        // Ambiguous size — fall back to OSType hint
                        let float32OSTypes: Set<UInt32> = [
                            0x68646570,  // 'hdep' Apple standard
                            0x66646570,  // 'fdep' Python doc
                            1717855600,
                            1751410032
                        ]
                        isFloat32 = float32OSTypes.contains(pixelFormat)
                    }

                    if frameIndex < 2 {
                        print("📡 DepthFrame[\(frameIndex)]: w=\(w) h=\(h) fmt=\(pixelFormat) " +
                              "detectedAs=\(isFloat32 ? "Float32" : "Float16") " +
                              "bytes=\(remainingBytes) expected32=\(pixelCount*4) expected16=\(pixelCount*2)")
                    }

                    // ── Decode pixels ─────────────────────────────────────────
                    var floats = [Float32](repeating: 0, count: pixelCount)

                    if isFloat32 {
                        let expectedBytes = pixelCount * 4
                        guard data.count >= headerSize + expectedBytes else {
                            print("⚠️ DepthFrameLoader: Float32 underflow")
                            continuation.resume(returning: nil); return
                        }
                        floats.withUnsafeMutableBytes { dst in
                            data.copyBytes(to: dst, from: headerSize..<(headerSize + expectedBytes))
                        }
                    } else {
                        let expectedBytes = pixelCount * 2
                        guard data.count >= headerSize + expectedBytes else {
                            print("⚠️ DepthFrameLoader: Float16 underflow")
                            continuation.resume(returning: nil); return
                        }
                        data.withUnsafeBytes { rawPtr in
                            let f16Ptr = rawPtr.baseAddress!
                                .advanced(by: headerSize)
                                .assumingMemoryBound(to: UInt16.self)
                            for i in 0..<pixelCount {
                                floats[i] = self.float16ToFloat32(f16Ptr[i])
                            }
                        }
                    }

                    // ── Sanity check ──────────────────────────────────────────
                    if frameIndex < 2 {
                        let valid = floats.filter { $0 > 0.1 && $0 < 50.0 }
                        if !valid.isEmpty {
                            print("📡 DepthFrame[\(frameIndex)]: depth range " +
                                  "\(String(format:"%.2f", valid.min()!))m – " +
                                  "\(String(format:"%.2f", valid.max()!))m " +
                                  "(\(valid.count)/\(pixelCount) valid pixels)")
                        }
                    }

                    let frame = DepthFrame(width: w, height: h, data: floats)
                    DispatchQueue.main.async {
                        self.cache[frameIndex] = frame
                        if self.frameWidth == 0 { self.frameWidth = w; self.frameHeight = h }
                    }
                    continuation.resume(returning: frame)

                } catch {
                    print("⚠️ DepthFrameLoader: failed to load \(url.lastPathComponent): \(error)")
                    continuation.resume(returning: nil)
                }
            }
        }
    }

    // MARK: - DepthFrameLoader

    // Add this private helper once:
    private func isValidDepthFile(_ name: String) -> Bool {
        name.hasPrefix("depth_") && name.hasSuffix(".bin") && !name.hasPrefix("._")
    }
    // MARK: - Float16 → Float32 conversion (no Accelerate dependency)

    private func float16ToFloat32(_ h: UInt16) -> Float32 {
        let sign    = UInt32((h >> 15) & 0x0001)
        let exp     = UInt32((h >> 10) & 0x001F)
        let mantissa = UInt32(h & 0x03FF)
        var f: UInt32
        switch exp {
        case 0:
            if mantissa == 0 { f = sign << 31 }
            else {
                var e = UInt32(127 - 14)
                var m = mantissa
                while (m & 0x0400) == 0 { e -= 1; m <<= 1 }
                f = (sign << 31) | (e << 23) | ((m & 0x03FF) << 13)
            }
        case 31:
            f = (sign << 31) | 0x7F800000 | (mantissa << 13)
        default:
            f = (sign << 31) | ((exp + 127 - 15) << 23) | (mantissa << 13)
        }
        return Float32(bitPattern: f)
    }

    // MARK: - Depth at point (convenience, async)

    func depth(at normalisedPoint: CGPoint,
               frameIndex: Int,
               width: Int,
               height: Int) async -> Float32? {
        guard let frame = await loadFrame(frameIndex, width: width, height: height) else {
            return nil
        }
        return frame.depthAt(normalizedX: Double(normalisedPoint.x),
                             normalizedY: Double(normalisedPoint.y))
    }

    // MARK: - Colormap rendering (JET colourmap → UIImage)

    /// Renders the depth frame as a false-colour JET image.
    /// Uses auto-ranging across valid pixel values (0.1–50m) so the full
    /// colour spectrum is always used regardless of scene depth.
    func renderColormap(frame: DepthFrame) -> UIImage? {
        let w = frame.width, h = frame.height
        guard w > 0, h > 0 else { return nil }

        // ── Auto-range: find actual min/max from valid pixels ────────────────
        var minD: Float = .greatestFiniteMagnitude
        var maxD: Float = -.greatestFiniteMagnitude
        for v in frame.data {
            guard v > 0.1 && v < 50.0 && !v.isNaN && !v.isInfinite else { continue }
            if v < minD { minD = v }
            if v > maxD { maxD = v }
        }
        // Fallback if no valid pixels
        if minD >= maxD { minD = 0.5; maxD = 15.0 }
        let range = maxD - minD

        var rgba = [UInt8](repeating: 255, count: w * h * 4)
        for idx in 0..<(w * h) {
            let d = frame.data[idx]
            // Invalid / zero depth → dark grey
            guard d > 0.1 && d < 50.0 && !d.isNaN else {
                rgba[idx * 4 + 0] = 40
                rgba[idx * 4 + 1] = 40
                rgba[idx * 4 + 2] = 40
                rgba[idx * 4 + 3] = 255
                continue
            }
            let t = max(0, min(1, (d - minD) / range))
            let (r, g, b) = jetColormap(t)
            rgba[idx * 4 + 0] = r
            rgba[idx * 4 + 1] = g
            rgba[idx * 4 + 2] = b
            rgba[idx * 4 + 3] = 255
        }

        let colorSpace = CGColorSpaceCreateDeviceRGB()
        guard let ctx = CGContext(data: &rgba,
                                  width: w, height: h,
                                  bitsPerComponent: 8,
                                  bytesPerRow: w * 4,
                                  space: colorSpace,
                                  bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue),
              let cgImg = ctx.makeImage() else { return nil }
        return UIImage(cgImage: cgImg)
    }

    // MARK: - JET colormap (t ∈ [0,1])

    private func jetColormap(_ t: Float) -> (UInt8, UInt8, UInt8) {
        let r = clamp(1.5 - abs(4 * t - 3))
        let g = clamp(1.5 - abs(4 * t - 2))
        let b = clamp(1.5 - abs(4 * t - 1))
        return (UInt8(r * 255), UInt8(g * 255), UInt8(b * 255))
    }

    private func clamp(_ v: Float) -> Float { max(0, min(1, v)) }

    // MARK: - Clear cache

    func clearCache() { cache.removeAll() }
}
