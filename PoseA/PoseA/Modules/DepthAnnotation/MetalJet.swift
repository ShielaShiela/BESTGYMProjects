//
//  MetalJet.swift
//  PoseA
//
//  Created by Shiela Cabahug on 2026/3/9.
//

// MetalJETRenderer.swift
import Metal
import UIKit

/// Converts a Float32 depth map to a JET-colourmap UIImage on the GPU.
/// Thread-safe: render() can be called from any queue.
final class MetalJETRenderer {

    static let shared = MetalJETRenderer()   // one device, one queue, one pipeline

    private let device:        MTLDevice
    private let commandQueue:  MTLCommandQueue
    private let pipelineState: MTLComputePipelineState

    private init?() {
        guard let dev   = MTLCreateSystemDefaultDevice(),
              let queue = dev.makeCommandQueue() else { return nil }
        device       = dev
        commandQueue = queue

        let src = """
        #include <metal_stdlib>
        using namespace metal;

        float3 jet(float t) {
            return float3(
                clamp(1.5 - abs(4.0*t - 3.0), 0.0, 1.0),
                clamp(1.5 - abs(4.0*t - 2.0), 0.0, 1.0),
                clamp(1.5 - abs(4.0*t - 1.0), 0.0, 1.0)
            );
        }

        kernel void depthJET(
            texture2d<float, access::read>  src   [[texture(0)]],
            texture2d<float, access::write> dst   [[texture(1)]],
            constant float2&                range [[buffer(0)]],
            uint2 gid [[thread_position_in_grid]])
        {
            if (gid.x >= dst.get_width() || gid.y >= dst.get_height()) return;
            float d = src.read(gid).r;
            float4 c = (d > 0.1 && d < 50.0 && !isnan(d))
                ? float4(jet(clamp((d - range[0]) / (range[1] - range[0]), 0.0, 1.0)), 1.0)
                : float4(0.157, 0.157, 0.157, 1.0);   // invalid → dark grey
            dst.write(c, gid);
        }
        """
        guard let lib = try? dev.makeLibrary(source: src, options: nil),
              let fn  = lib.makeFunction(name: "depthJET"),
              let ps  = try? dev.makeComputePipelineState(function: fn)
        else { return nil }
        pipelineState = ps
    }

    // MARK: - Public API

    /// Returns nil only if Metal is unavailable or the frame is empty.
    func render(frame: DepthFrame) -> UIImage? {
        let w = frame.width, h = frame.height
        guard w > 0, h > 0 else { return nil }

        // Auto-range
        var lo: Float = .greatestFiniteMagnitude
        var hi: Float = -.greatestFiniteMagnitude
        for v in frame.data where v > 0.1 && v < 50.0 && !v.isNaN {
            if v < lo { lo = v }
            if v > hi { hi = v }
        }
        if lo >= hi { lo = 0.5; hi = 15.0 }

        // Textures
        guard let inTex  = makeTexture(w: w, h: h, fmt: .r32Float,   usage: .shaderRead),
              let outTex = makeTexture(w: w, h: h, fmt: .rgba8Unorm, usage: .shaderWrite)
        else { return nil }

        frame.data.withUnsafeBytes {
            inTex.replace(region: MTLRegionMake2D(0,0,w,h),
                          mipmapLevel: 0, withBytes: $0.baseAddress!, bytesPerRow: w*4)
        }

        // Encode
        guard let cmd     = commandQueue.makeCommandBuffer(),
              let encoder = cmd.makeComputeCommandEncoder() else { return nil }
        encoder.setComputePipelineState(pipelineState)
        encoder.setTexture(inTex,  index: 0)
        encoder.setTexture(outTex, index: 1)
        var range = SIMD2<Float>(lo, hi)
        encoder.setBytes(&range, length: MemoryLayout<SIMD2<Float>>.size, index: 0)
        let tg = MTLSize(width:16, height:16, depth:1)
        encoder.dispatchThreadgroups(
            MTLSize(width:(w+15)/16, height:(h+15)/16, depth:1),
            threadsPerThreadgroup: tg)
        encoder.endEncoding()
        cmd.commit()
        cmd.waitUntilCompleted()

        // Read back
        var rgba = [UInt8](repeating: 0, count: w*h*4)
        rgba.withUnsafeMutableBytes {
            outTex.getBytes($0.baseAddress!, bytesPerRow: w*4,
                            from: MTLRegionMake2D(0,0,w,h), mipmapLevel: 0)
        }
        let cs = CGColorSpaceCreateDeviceRGB()
        guard let ctx = CGContext(data: &rgba, width: w, height: h,
                                  bitsPerComponent: 8, bytesPerRow: w*4, space: cs,
                                  bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue),
              let cg = ctx.makeImage() else { return nil }
        return UIImage(cgImage: cg)
    }

    private func makeTexture(w: Int, h: Int,
                             fmt: MTLPixelFormat, usage: MTLTextureUsage) -> MTLTexture? {
        let d = MTLTextureDescriptor.texture2DDescriptor(pixelFormat: fmt,
                                                         width: w, height: h,
                                                         mipmapped: false)
        d.usage       = usage
        d.storageMode = .shared
        return device.makeTexture(descriptor: d)
    }
}
