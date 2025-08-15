//
//  FrameDataIOService.swift
//  PoseA
//
//  Created by Ardhika Maulidani on 6/26/25.
//

import Foundation
import Metal
import UIKit
import simd

final class FrameDataIOService {

    // MARK: - Save Methods
    
    func save(_ data: FrameDataModel, to url: URL, filter depthfilter:  Bool) throws {
        // Create the Folder
        let folderURL = try createCaptureFolder(at: url)
        
        // Try to Save All Information
        try self.saveDepth(data.depth, to: folderURL)
        try self.saveColor(y: data.colorY, cbcr: data.colorCbCr, to: folderURL)
        try self.saveImage(data.colorImage, to: folderURL)
        try self.saveMetadata(data, to: folderURL, filter: depthfilter)
    }
    
    // Helper: - Create Folder
    private func createCaptureFolder(at url: URL) throws -> URL {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd_HH-mm-ss"
        let timestamp = formatter.string(from: Date())
        let folderURL = url.appendingPathComponent("Capture_\(timestamp)")
        try FileManager.default.createDirectory(at: folderURL, withIntermediateDirectories: true)
        return folderURL
    }
    
    // Helper: - File Save for Texture (Color)
    private func saveTexture(_ texture: MTLTexture, to url: URL) throws {
        let width = texture.width
        let height = texture.height
        let bytesPerPixel = texture.pixelFormat.bytesPerPixel
        let bytesPerRow = width * bytesPerPixel
        let dataSize = height * bytesPerRow
        
        var data = [UInt8](repeating: 0, count: dataSize)
        let region = MTLRegionMake2D(0, 0, width, height)
        texture.getBytes(&data, bytesPerRow: bytesPerRow, from: region, mipmapLevel: 0)
        
        try Data(data).write(to: url)
    }
    
    // Helper: - File Save for Depth
    private func saveDepth(_ depth: MTLTexture?, to folderURL: URL) throws {
        // Check for Depth Data Availability
        guard let _depth = depth else {
            throw NSError(domain: "FrameDataIOService", code: 1, userInfo: [NSLocalizedDescriptionKey: "No depth data available"])
        }
        
        // Get Depth Properties
        let width = _depth.width
        let height = _depth.height
        
        // Convert tot Float16 Format for Memory Saving
        let bytesPerPixel = 2
        let bytesPerRow = width * bytesPerPixel
        
        var depthData = [Float16](repeating: 0, count: width * height)
        let region = MTLRegionMake2D(0, 0, width, height)
        
        _depth.getBytes(&depthData, bytesPerRow: bytesPerRow, from: region, mipmapLevel: 0)
        
        // Save Depth Data
        let data = Data(bytes: depthData, count: depthData.count * MemoryLayout<Float16>.size)
        try data.write(to: folderURL.appendingPathComponent("depthData.dat"))
        
        // Save Depth Info
        let depthInfo: [String: Any] = [
            "width": width,
            "height": height
        ]
        let depthInfoURL = folderURL.appendingPathComponent("depthInfo.plist")
        (depthInfo as NSDictionary).write(to: depthInfoURL, atomically: true)
        
        log("Depth data saved successfully to \(folderURL.path)", level: .debug)
    }

    // Helper: - File Save for Color Y and CbCr
    private func saveColor(y: MTLTexture?, cbcr: MTLTexture?, to folderURL: URL) throws {
        // Check for Color Data Availability
        guard let colorY = y, let colorCbCr = cbcr else {
            throw NSError(domain: "FrameDataIOService", code: 1, userInfo: [NSLocalizedDescriptionKey: "No color data available"])
        }
        
        // Save Y Plane
        try saveTexture(colorY, to: folderURL.appendingPathComponent("colorY.dat"))
        
        // Save CbCr Plane
        try saveTexture(colorCbCr, to: folderURL.appendingPathComponent("colorCbCr.dat"))
        
        // Save Texture Info
        let textureInfo: [String: Any] = [
            "yWidth": colorY.width,
            "yHeight": colorY.height,
            "yPixelFormat": colorY.pixelFormat.rawValue,
            "cbcrWidth": colorCbCr.width,
            "cbcrHeight": colorCbCr.height,
            "cbcrPixelFormat": colorCbCr.pixelFormat.rawValue
        ]
        let infoURL = folderURL.appendingPathComponent("colorTextureInfo.plist")
        let infoData = try PropertyListSerialization.data(fromPropertyList: textureInfo, format: .xml, options: 0)
        try infoData.write(to: infoURL)
        
        log("color textures (Y and CbCr) saved successfully to \(folderURL.path)", level: .debug)
    }

    private func saveImage(_ image: UIImage?, to folderURL: URL) throws {
        // Check for UIImage Data Availability
        guard let image = image,
              let data = image.jpegData(compressionQuality: 1.0) else {
            throw NSError(domain: "FrameDataIOService", code: 9, userInfo: [NSLocalizedDescriptionKey: "Failed to create JPEG data from UIImage"])
        }
        
        // Save UIImage to JPG
        let url = folderURL.appendingPathComponent("colorImage.jpg")
        try data.write(to: url)
        
        log("colorImage.jpg saved successfully to \(folderURL.path)", level: .debug)
    }

    private func saveMetadata(_ data: FrameDataModel, to folderURL: URL, filter depthfilter:  Bool) throws {
        let intrinsics = matrixToArray(data.cameraIntrinsics)

        let metadata: [String: Any] = [
            "cameraIntrinsics": intrinsics,
            "cameraReferenceDimensions": [
                "width": data.cameraReferenceDimensions.width,
                "height": data.cameraReferenceDimensions.height
            ],
            "depthCenter": Double(data.depthCenter),
            "depthfilter": depthfilter
        ]

        let metadataURL = folderURL.appendingPathComponent("metadata.plist")
        (metadata as NSDictionary).write(to: metadataURL, atomically: true)
        
        log("Metadata.plist saved successfully to \(folderURL.path)", level: .debug)
    }
    
    // MARK: - Load Methods
    func load(from url: URL, device: MTLDevice) throws -> FrameDataModel {
        // Load Metadata
        let metadata = try loadMetadata(from: url.appendingPathComponent("metadata.plist"))
        
        // Load Texture
        let textureInfo = try loadTextureInfo(from: url)
        
        let depthTexture = try loadDepthTexture(from: url.appendingPathComponent("depthData.dat"),
                                                width: textureInfo.depthWidth,
                                                height: textureInfo.depthHeight,
                                                device: device)
        
        let colorYTexture = try loadTexture(from: url.appendingPathComponent("colorY.dat"),
                                            width: textureInfo.yWidth,
                                            height: textureInfo.yHeight,
                                            pixelFormat: textureInfo.yPixelFormat,
                                            device: device)

        let colorCbCrTexture = try loadTexture(from: url.appendingPathComponent("colorCbCr.dat"),
                                               width: textureInfo.cbcrWidth,
                                               height: textureInfo.cbcrHeight,
                                               pixelFormat: textureInfo.cbcrPixelFormat,
                                               device: device)
        
        // Load Image
        let colorImage = loadUIImage(from: url.appendingPathComponent("colorImage.jpg"))

        return FrameDataModel(
            depth: depthTexture,
            colorY: colorYTexture,
            colorCbCr: colorCbCrTexture,
            cameraIntrinsics: metadata.intrinsics,
            cameraReferenceDimensions: metadata.referenceSize,
            depthCenter: metadata.depthCenter,
            colorImage: colorImage
        )
    }
        
    func loadMetadata(from url: URL) throws -> MetadataInfo {
        // Parse File
        let data = try Data(contentsOf: url)
        guard let dict = try PropertyListSerialization.propertyList(from: data, format: nil) as? [String: Any] else {
            throw NSError(domain: "FrameDataIOService", code: 1, userInfo: [NSLocalizedDescriptionKey: "Invalid metadata"])
        }
        
        // Fetch Camera Intrinsics
        let intrinsicsArray = dict["cameraIntrinsics"] as? [[Double]] ?? Array(repeating: [0.0, 0.0, 0.0], count: 3)
        let intrinsics = arrayToMatrix(intrinsicsArray)!
        
        // Fetch Camera Reference Dimensions
        let refDict = dict["cameraReferenceDimensions"] as? [String: Double] ?? [:]
        let referenceSize = CGSize(width: refDict["width"] ?? 0.0, height: refDict["height"] ?? 0.0)
        
        // Fetch Depth Center
        let depthCenter = Float16(dict["depthCenter"] as? Double ?? 0.0)

        return MetadataInfo(intrinsics: intrinsics, referenceSize: referenceSize, depthCenter: depthCenter)
    }
    
    private func loadTextureInfo(from url: URL) throws -> TextureInfo {
        // Parse File
        let colorInfoURL = url.appendingPathComponent("colorTextureInfo.plist")
        let depthInfoURL = url.appendingPathComponent("depthInfo.plist")
        
        let dataColor = try Data(contentsOf: colorInfoURL)
        guard let dictColor = try PropertyListSerialization.propertyList(from: dataColor, format: nil) as? [String: Any] else {
            throw NSError(domain: "FrameDataIOService", code: 2, userInfo: [NSLocalizedDescriptionKey: "Invalid color texture info"])
        }

        let datadepth = try Data(contentsOf: depthInfoURL)
        guard let dictDepth = try PropertyListSerialization.propertyList(from: datadepth, format: nil) as? [String: Any] else {
            throw NSError(domain: "FrameDataIOService", code: 2, userInfo: [NSLocalizedDescriptionKey: "Invalid depth texture info"])
        }
        
        return TextureInfo(
            yWidth: dictColor["yWidth"] as? Int ?? 0,
            yHeight: dictColor["yHeight"] as? Int ?? 0,
            yPixelFormat: MTLPixelFormat(rawValue: dictColor["yPixelFormat"] as? UInt ?? 0) ?? .r8Unorm,
            cbcrWidth: dictColor["cbcrWidth"] as? Int ?? 0,
            cbcrHeight: dictColor["cbcrHeight"] as? Int ?? 0,
            cbcrPixelFormat: MTLPixelFormat(rawValue: dictColor["cbcrPixelFormat"] as? UInt ?? 0) ?? .r8Unorm,
            depthWidth: dictDepth["width"] as? Int ?? 0,
            depthHeight: dictDepth["height"] as? Int ?? 0
        )
    }

    private func loadUIImage(from url: URL) -> UIImage? {
        // Parse File
        guard let data = try? Data(contentsOf: url) else { return nil }
        return UIImage(data: data)
    }
    
    private func loadTexture(from url: URL, width: Int, height: Int, pixelFormat: MTLPixelFormat, device: MTLDevice) throws -> MTLTexture {
        // Parse File
        let data = try Data(contentsOf: url)
        
        let textureDescriptor = MTLTextureDescriptor.texture2DDescriptor(pixelFormat: pixelFormat, width: width, height: height, mipmapped: false)
        textureDescriptor.usage = [.shaderRead, .shaderWrite]
        
        guard let texture = device.makeTexture(descriptor: textureDescriptor) else {
            throw NSError(domain: "FrameDataIOService", code: 5, userInfo: [NSLocalizedDescriptionKey: "Failed to create texture"])
        }
        
        let bytesPerRow = width * pixelFormat.bytesPerPixel
        let region = MTLRegionMake2D(0, 0, width, height)
        
        texture.replace(region: region, mipmapLevel: 0, withBytes: [UInt8](data), bytesPerRow: bytesPerRow)
        return texture
    }
    
    private func loadDepthTexture(from url: URL, width: Int, height: Int, device: MTLDevice) throws -> MTLTexture {
        // Parse File
        let depthData = try Data(contentsOf: url)
        
        let depthValues = depthData.withUnsafeBytes { Array(UnsafeBufferPointer<Float16>(start: $0.bindMemory(to: Float16.self).baseAddress!, count: depthData.count / MemoryLayout<Float16>.size)) }
        
        let textureDescriptor = MTLTextureDescriptor.texture2DDescriptor(pixelFormat: .r16Float,
                                                                         width: width,
                                                                         height: height,
                                                                         mipmapped: false)
        textureDescriptor.usage = [.shaderRead, .shaderWrite]
        
        guard let texture = device.makeTexture(descriptor: textureDescriptor) else {
            throw NSError(domain: "FrameDataIOService", code: 8, userInfo: [NSLocalizedDescriptionKey: "Failed to create depth texture"])
        }
        
        let region = MTLRegionMake2D(0, 0, width, height)
        texture.replace(region: region, mipmapLevel: 0, withBytes: depthValues, bytesPerRow: width * MemoryLayout<Float16>.size)
        
        return texture
    }
}


// Point Cloud 3D Extension
extension FrameDataIOService {
    func exportPointCloud(_ data: FrameDataModel, to url: URL, maxDepth: Float = 10000.0, minDepth: Float = 0.1) throws {
        guard let depthTexture = data.depth,
              let colorYTexture = data.colorY,
              let colorCbCrTexture = data.colorCbCr else {
            throw NSError(domain: "FrameDataIOService", code: 1, userInfo: [NSLocalizedDescriptionKey: "Missing texture data"])
        }

        let width = depthTexture.width
        let height = depthTexture.height

        let depthPixels = depthTexture.getPixelValues() as [Float16]
        let colorYPixels = colorYTexture.getPixelValues() as [UInt8]
        let colorCbCrPixels = colorCbCrTexture.getPixelValues() as [SIMD2<UInt8>]

        let scale = simd_float2(Float(data.cameraReferenceDimensions.width) / Float(width),
                                Float(data.cameraReferenceDimensions.height) / Float(height))

        var scaledIntrinsics = data.cameraIntrinsics
        scaledIntrinsics[0][0] /= scale.x
        scaledIntrinsics[1][1] /= scale.y
        scaledIntrinsics[2][0] /= scale.x
        scaledIntrinsics[2][1] /= scale.y

        var points: [String] = []

        for y in 0..<height {
            for x in 0..<width {
                let index = y * width + x
                let depth = Float(depthPixels[index])
                guard depth > minDepth, depth < maxDepth else { continue }

                let position = compute3DPosition(x: Float(x), y: Float(y), depth: depth, intrinsics: scaledIntrinsics)
                let color = decodeColor(atX: x, y: y, yData: colorYPixels, cbcrData: colorCbCrPixels, width: width)
                points.append("\(position.x) \(position.y) \(position.z) \(color.x) \(color.y) \(color.z)")
            }
        }

        let header = """
        ply
        format ascii 1.0
        element vertex \(points.count)
        property float x
        property float y
        property float z
        property uchar red
        property uchar green
        property uchar blue
        end_header

        """

        let fileContent = header + points.joined(separator: "\n")
        try fileContent.write(to: url, atomically: true, encoding: .utf8)
    }

    private func compute3DPosition(x: Float, y: Float, depth: Float, intrinsics: simd_float3x3) -> SIMD3<Float> {
        let fx = intrinsics[0][0]
        let fy = intrinsics[1][1]
        let cx = intrinsics[2][0]
        let cy = intrinsics[2][1]

        let pointX = (x - cx) * depth / fx
        let pointY = -(y - cy) * depth / fy  // Y-flip for Metal convention
        let pointZ = -depth                  // Negative Z to match Metal convention

        return SIMD3<Float>(pointX, pointY, pointZ)
    }

    private func decodeColor(atX x: Int, y: Int, yData: [UInt8], cbcrData: [SIMD2<UInt8>], width: Int) -> SIMD3<UInt8> {
        let yValue = Float(yData[y * width + x])
        let cbcr = cbcrData[(y / 2) * (width / 2) + (x / 2)]
        let ycbcr = SIMD4<Float>(yValue, Float(cbcr.x), Float(cbcr.y), 1.0)

        let ycbcrToRGB = simd_float4x4(
            SIMD4<Float>(+1.0000, +1.0000, +1.0000, +0.0000),
            SIMD4<Float>(+0.0000, -0.3441, +1.7720, +0.0000),
            SIMD4<Float>(+1.4020, -0.7141, +0.0000, +0.0000),
            SIMD4<Float>(-0.7010, +0.5291, -0.8860, +1.0000)
        )

        let rgb = ycbcrToRGB * ycbcr

        return SIMD3<UInt8>(
            UInt8(clamping: Int(rgb.x * 255)),
            UInt8(clamping: Int(rgb.y * 255)),
            UInt8(clamping: Int(rgb.z * 255))
        )
    }
}
