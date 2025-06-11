//
//  CameraCapturedData.swift
//  PoseA
//
//  Created by Ardhika Maulidani on 6/9/25.
//  Refactor from Shiela Cabahug's codebase

import SwiftUI
import Metal
import AVFoundation

class CameraCapturedData {
    var depth: MTLTexture?
    var colorY: MTLTexture?
    var colorCbCr: MTLTexture?
    var cameraIntrinsics: matrix_float3x3
    var cameraReferenceDimensions: CGSize
    var depthCenter: Float16
    var originalDepth: AVDepthData?
    var colorImage: UIImage?
    var processedImage: UIImage?
//        let filterOn: Bool
//        let pointCloudManager = PointCloudManager()
    
    init(depth: MTLTexture? = nil,
         colorY: MTLTexture? = nil,
         colorCbCr: MTLTexture? = nil,
         cameraIntrinsics: matrix_float3x3 = matrix_float3x3(),
         cameraReferenceDimensions: CGSize = .zero,
         depthCenter: Float16 = 0,
         originalDepth: AVDepthData? = nil,
         colorImage: UIImage? = nil,
         processedImage: UIImage? = nil){
        
        self.depth = depth
        self.colorY = colorY
        self.colorCbCr = colorCbCr
        self.cameraIntrinsics = cameraIntrinsics
        self.cameraReferenceDimensions = cameraReferenceDimensions
        self.depthCenter = depthCenter
        self.originalDepth = originalDepth
        self.colorImage = colorImage
        self.processedImage = processedImage
        
        
    }
    
    private func createCaptureFolder(at url: URL) throws -> URL {
        let dateFormatter = DateFormatter()
        dateFormatter.dateFormat = "yyyy-MM-dd_HH-mm-ss"
        let timestamp = dateFormatter.string(from: Date())
        
        let folderName = "Capture_\(timestamp)"
        let folderURL = url.appendingPathComponent(folderName)
        
        try FileManager.default.createDirectory(at: folderURL, withIntermediateDirectories: true, attributes: nil)
        
        print("Created folder: \(folderURL.path)")
        
        return folderURL
    }
    
    
    func matrixToArray(_ matrix: matrix_float3x3) -> [[Float]] {
        return [
            [matrix.columns.0[0], matrix.columns.0[1], matrix.columns.0[2]],
            [matrix.columns.1[0], matrix.columns.1[1], matrix.columns.1[2]],
            [matrix.columns.2[0], matrix.columns.2[1], matrix.columns.2[2]]
        ]
    }
    
    private func cameraIntrinsicsToArray() -> [[Double]] {
        return [
            [Double(cameraIntrinsics.columns.0.x), Double(cameraIntrinsics.columns.0.y), Double(cameraIntrinsics.columns.0.z)],
            [Double(cameraIntrinsics.columns.1.x), Double(cameraIntrinsics.columns.1.y), Double(cameraIntrinsics.columns.1.z)],
            [Double(cameraIntrinsics.columns.2.x), Double(cameraIntrinsics.columns.2.y), Double(cameraIntrinsics.columns.2.z)]
        ]
    }
    func saveCaptureData(to url: URL, filter depthfilter:  Bool) throws {
        let folderURL = try createCaptureFolder(at: url)
        
        try saveDepthData(to: folderURL.appendingPathComponent("depthData.dat"))
        try saveColorData(to: folderURL)
        
        if let colorImage = self.colorImage {
            try saveUIImage(colorImage, to: folderURL.appendingPathComponent("colorImage.jpg"))
        } else {
            print("Warning: colorImage is nil, cannot save")
        }
        
        let metadata: [String: Any] = [
            "cameraIntrinsics": cameraIntrinsicsToArray(),
            "cameraReferenceDimensions": [
                "width": cameraReferenceDimensions.width,
                "height": cameraReferenceDimensions.height
            ],
            "depthCenter": Double(depthCenter), // Convert Float16 to Double
            "depthfilter": depthfilter

        ]
        
        let metadataURL = folderURL.appendingPathComponent("metadata.plist")
        
        // Use FileManager to write the dictionary directly
        (metadata as NSDictionary).write(to: metadataURL, atomically: true)
        
        print("Metadata saved successfully to: \(metadataURL.path)")
        
        // Save point cloud as PLY
       
        try savePointCloudAsPLY(to: folderURL.appendingPathComponent("pointcloud.ply"))
        print("Point cloud saved successfully.")
      
        print ("yooooo")
    }
    
    private func saveUIImage(_ image: UIImage, to url: URL) throws {
        guard let imageData = image.jpegData(compressionQuality: 1.0) else {
            throw NSError(domain: "CameraCapturedData", code: 9, userInfo: [NSLocalizedDescriptionKey: "Failed to create JPEG data from UIImage"])
        }
        try imageData.write(to: url)
        print("UIImage saved successfully to: \(url.path)")
    }
    
    
    private func saveDepthData(to url: URL) throws {
        guard let depth = self.depth else {
            throw NSError(domain: "CameraCapturedData", code: 1, userInfo: [NSLocalizedDescriptionKey: "No depth data available"])
        }
        
        let width = depth.width
        let height = depth.height
        let bytesPerPixel = 2 // For R16Float format
        let bytesPerRow = width * bytesPerPixel
        
        var depthData = [Float16](repeating: 0, count: width * height)
        let region = MTLRegionMake2D(0, 0, width, height)
        
        depth.getBytes(&depthData, bytesPerRow: bytesPerRow, from: region, mipmapLevel: 0)
        
        let data = Data(bytes: depthData, count: depthData.count * MemoryLayout<Float16>.size)
        try data.write(to: url)
        
        // Save depth dimensions
        let depthInfo: [String: Any] = [
            "width": width,
            "height": height
        ]
        let depthInfoURL = url.deletingLastPathComponent().appendingPathComponent("depthInfo.plist")
        (depthInfo as NSDictionary).write(to: depthInfoURL, atomically: true)
    }
    
    private func saveColorData(to url: URL) throws {
        guard let colorY = self.colorY, let colorCbCr = self.colorCbCr else {
            throw NSError(domain: "CameraCapturedData", code: 1, userInfo: [NSLocalizedDescriptionKey: "No color data available"])
        }
        
        // Save Y plane
        try saveTexture(colorY, to: url.appendingPathComponent("colorY.dat"))
        
        // Save CbCr plane
        try saveTexture(colorCbCr, to: url.appendingPathComponent("colorCbCr.dat"))
        
        // Save texture information
        let textureInfo: [String: Any] = [
            "yWidth": colorY.width,
            "yHeight": colorY.height,
            "yPixelFormat": colorY.pixelFormat.rawValue,
            "cbcrWidth": colorCbCr.width,
            "cbcrHeight": colorCbCr.height,
            "cbcrPixelFormat": colorCbCr.pixelFormat.rawValue
        ]
        let infoURL = url.appendingPathComponent("colorTextureInfo.plist")
        let infoData = try PropertyListSerialization.data(fromPropertyList: textureInfo, format: .xml, options: 0)
        try infoData.write(to: infoURL)
        
        
        print("yehaa")
    }
    
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
    
    
    private func arrayToMatrix(_ array: [Float]) -> matrix_float3x3 {
        return matrix_float3x3(columns: (
            SIMD3<Float>(array[0], array[1], array[2]),
            SIMD3<Float>(array[3], array[4], array[5]),
            SIMD3<Float>(array[6], array[7], array[8])
        ))
    }
    func load(from url: URL, device: MTLDevice) throws {
        let colorCbCrURL = url.appendingPathComponent("colorCbCr.dat")
        let colorYURL = url.appendingPathComponent("colorY.dat")
        let depthDataURL = url.appendingPathComponent("depthData.dat")
        let metadataURL = url.appendingPathComponent("metadata.plist")
        let textureInfoURL = url.appendingPathComponent("colorTextureInfo.plist")
        
        let colorImageURL = url.appendingPathComponent("colorImage.jpg")
        if let imageData = try? Data(contentsOf: colorImageURL),
           let image = UIImage(data: imageData) {
            self.colorImage = image
        }
        
        
        print("Starting to load data from \(url.path)")
        
        // Load metadata
        let metadataData = try Data(contentsOf: metadataURL)
        if let metadata = try PropertyListSerialization.propertyList(from: metadataData, format: nil) as? [String: Any] {
            // Camera Intrinsics
            if let intrinsicsArray = metadata["cameraIntrinsics"] as? [[Double]] {
                self.cameraIntrinsics = arrayToMatrix(intrinsicsArray)
                print("Camera Intrinsics loaded: \(self.cameraIntrinsics)")
            } else {
                print("Warning: Failed to load camera intrinsics")
            }
            
            // Camera Reference Dimensions
            if let referenceDimensions = metadata["cameraReferenceDimensions"] as? [String: CGFloat] {
                self.cameraReferenceDimensions = CGSize(width: referenceDimensions["width"] ?? 0, height: referenceDimensions["height"] ?? 0)
            } else if let referenceDimensions = metadata["cameraReferenceDimensions"] as? [String: Double] {
                self.cameraReferenceDimensions = CGSize(width: CGFloat(referenceDimensions["width"] ?? 0), height: CGFloat(referenceDimensions["height"] ?? 0))
            } else {
                print("Warning: Failed to load camera reference dimensions")
                self.cameraReferenceDimensions = CGSize(width: 1920, height: 1080) // Example default
            }
            print("Camera Reference Dimensions: \(self.cameraReferenceDimensions)")
            
            // Depth Center
            if let depthCenter = metadata["depthCenter"] as? Double {
                self.depthCenter = Float16(depthCenter)
            } else if let depthCenter = metadata["depthCenter"] as? Float {
                self.depthCenter = Float16(depthCenter)
            } else {
                print("Warning: Failed to load depth center")
                self.depthCenter = 0.0 // Default value
            }
            print("Depth Center: \(self.depthCenter)")
        } else {
            throw NSError(domain: "MetadataError", code: 1, userInfo: [NSLocalizedDescriptionKey: "Failed to parse metadata"])
        }
        
        // Load texture information
        let textureInfoData = try Data(contentsOf: textureInfoURL)
        guard let textureInfo = try PropertyListSerialization.propertyList(from: textureInfoData, format: nil) as? [String: Any] else {
            throw NSError(domain: "CameraCapturedData", code: 4, userInfo: [NSLocalizedDescriptionKey: "Failed to load color texture info"])
        }
        
        // Load textures
        let yWidth = textureInfo["yWidth"] as? Int ?? 0
        let yHeight = textureInfo["yHeight"] as? Int ?? 0
        let yPixelFormatRaw = textureInfo["yPixelFormat"] as? UInt ?? 0
        let yPixelFormat = MTLPixelFormat(rawValue: yPixelFormatRaw) ?? .r8Unorm
        
        let cbcrWidth = textureInfo["cbcrWidth"] as? Int ?? 0
        let cbcrHeight = textureInfo["cbcrHeight"] as? Int ?? 0
        let cbcrPixelFormatRaw = textureInfo["cbcrPixelFormat"] as? UInt ?? 0
        let cbcrPixelFormat = MTLPixelFormat(rawValue: cbcrPixelFormatRaw) ?? .r8Unorm
        
        print("Loading textures...")
        do {
            self.colorY = try loadTexture(from: colorYURL, width: yWidth, height: yHeight, pixelFormat: yPixelFormat, device: device)
            print("ColorY texture loaded: \(self.colorY != nil)")
            
            self.colorCbCr = try loadTexture(from: colorCbCrURL, width: cbcrWidth, height: cbcrHeight, pixelFormat: cbcrPixelFormat, device: device)
            print("ColorCbCr texture loaded: \(self.colorCbCr != nil)")
            
            self.depth = try loadDepthTexture(from: depthDataURL, device: device)
            print("Depth texture loaded: \(self.depth != nil)")
          
            if self.colorY == nil || self.colorCbCr == nil || self.depth == nil {
                print("Warning: One or more textures are nil after loading")
                if self.colorY == nil { print("ColorY is nil") }
                if self.colorCbCr == nil { print("ColorCbCr is nil") }
                if self.depth == nil { print("Depth is nil") }
            } else {
                print("All textures loaded successfully")
            }
        } catch {
            print("Error loading textures: \(error)")
            throw error
        }
        
        
    }
    
    private func loadTexture(from url: URL, width: Int, height: Int, pixelFormat: MTLPixelFormat, device: MTLDevice) throws -> MTLTexture {
        print("Loading texture from \(url.lastPathComponent)")
        print("Texture dimensions: \(width)x\(height), PixelFormat: \(pixelFormat)")
        
        do {
            let data = try Data(contentsOf: url)
            print("Loaded \(data.count) bytes for texture")
            
            let textureDescriptor = MTLTextureDescriptor.texture2DDescriptor(pixelFormat: pixelFormat, width: width, height: height, mipmapped: false)
            textureDescriptor.usage = [.shaderRead, .shaderWrite]
            
            guard let texture = device.makeTexture(descriptor: textureDescriptor) else {
                throw NSError(domain: "CameraCapturedData", code: 5, userInfo: [NSLocalizedDescriptionKey: "Failed to create texture"])
            }
            
            let bytesPerRow = width * pixelFormat.bytesPerPixel
            let region = MTLRegionMake2D(0, 0, width, height)
            
            texture.replace(region: region, mipmapLevel: 0, withBytes: [UInt8](data), bytesPerRow: bytesPerRow)
            
            print("Texture created successfully")
            return texture
        } catch {
            print("Error loading texture: \(error)")
            throw error
        }
    }
    
    private func loadDepthTexture(from url: URL, device: MTLDevice) throws -> MTLTexture {
        let depthData = try Data(contentsOf: url)
        
        let depthInfoURL = url.deletingLastPathComponent().appendingPathComponent("depthInfo.plist")
        guard let depthInfo = NSDictionary(contentsOf: depthInfoURL) as? [String: Any],
              let width = depthInfo["width"] as? Int,
              let height = depthInfo["height"] as? Int else {
            throw NSError(domain: "CameraCapturedData", code: 7, userInfo: [NSLocalizedDescriptionKey: "Failed to load depth info"])
        }
        
        let depthValues = depthData.withUnsafeBytes { Array(UnsafeBufferPointer<Float16>(start: $0.bindMemory(to: Float16.self).baseAddress!, count: depthData.count / MemoryLayout<Float16>.size)) }
        
        let textureDescriptor = MTLTextureDescriptor.texture2DDescriptor(pixelFormat: .r16Float,
                                                                         width: width,
                                                                         height: height,
                                                                         mipmapped: false)
        textureDescriptor.usage = [.shaderRead, .shaderWrite]
        
        guard let texture = device.makeTexture(descriptor: textureDescriptor) else {
            throw NSError(domain: "CameraCapturedData", code: 8, userInfo: [NSLocalizedDescriptionKey: "Failed to create depth texture"])
        }
        
        let region = MTLRegionMake2D(0, 0, width, height)
        texture.replace(region: region, mipmapLevel: 0, withBytes: depthValues, bytesPerRow: width * MemoryLayout<Float16>.size)
        
        return texture
    }
    
    private func arrayToMatrix(_ array: [[Double]]) -> matrix_float3x3 {
        return matrix_float3x3(columns: (
            SIMD3<Float>(Float(array[0][0]), Float(array[0][1]), Float(array[0][2])),
            SIMD3<Float>(Float(array[1][0]), Float(array[1][1]), Float(array[1][2])),
            SIMD3<Float>(Float(array[2][0]), Float(array[2][1]), Float(array[2][2]))
        ))
    }
}

extension CameraCapturedData {
    func saveCaptureData(to url: URL, isVideoFrame: Bool = false, completion: @escaping (Error?) -> Void) {
        DispatchQueue.global(qos: .userInitiated).async {
            do {
                let folderURL: URL
                if isVideoFrame {
                    folderURL = url  // For video frames, use the provided URL directly
                } else {
                    folderURL = try self.createCaptureFolder(at: url)  // For single captures, create a new folder
                }
                
                try self.saveDepthData(to: folderURL.appendingPathComponent("depthData.dat"))
                try self.saveColorData(to: folderURL)
                
                if let colorImage = self.colorImage {
                    try self.saveUIImage(colorImage, to: folderURL.appendingPathComponent("colorImage.jpg"))
                } else {
                    print("Warning: colorImage is nil, cannot save")
                }
                
                let metadata: [String: Any] = [
                    "cameraIntrinsics": self.cameraIntrinsicsToArray(),
                    "cameraReferenceDimensions": [
                        "width": self.cameraReferenceDimensions.width,
                        "height": self.cameraReferenceDimensions.height
                    ],
                    "depthCenter": Double(self.depthCenter),
                    "timestamp": Date().timeIntervalSinceReferenceDate
                ]
                
                let metadataURL = folderURL.appendingPathComponent("metadata.plist")
                
                // Use FileManager to write the dictionary directly
                (metadata as NSDictionary).write(to: metadataURL, atomically: true)
                
                DispatchQueue.main.async {
                    print("Data saved successfully to: \(folderURL.path)")
                    completion(nil)
                }
            } catch {
                DispatchQueue.main.async {
                    print("Error saving capture data: \(error)")
                    completion(error)
                }
            }
        }
    }

        func savePointCloudAsPLY(to url: URL, maxDepth: Float = 10000.0, minDepth: Float = 0.1) throws {
            guard let depthTexture = self.depth,
                  let colorYTexture = self.colorY,
                  let colorCbCrTexture = self.colorCbCr else {
                throw NSError(domain: "CameraCapturedData", code: 1, userInfo: [NSLocalizedDescriptionKey: "Missing texture data"])
            }

            let width = depthTexture.width
            let height = depthTexture.height

            let depthPixels = depthTexture.getPixelValues() as [Float16]
            let colorYPixels = colorYTexture.getPixelValues() as [UInt8]
            let colorCbCrPixels = colorCbCrTexture.getPixelValues() as [SIMD2<UInt8>]

            let depthResolution = simd_float2(x: Float(width), y: Float(height))
            let scaleRes = simd_float2(x: Float(cameraReferenceDimensions.width) / depthResolution.x,
                                       y: Float(cameraReferenceDimensions.height) / depthResolution.y)
            
            var scaledIntrinsics = cameraIntrinsics
            scaledIntrinsics[0][0] /= scaleRes.x
            scaledIntrinsics[1][1] /= scaleRes.y
            scaledIntrinsics[2][0] /= scaleRes.x
            scaledIntrinsics[2][1] /= scaleRes.y

            var points: [String] = []

            for y in 0..<height {
                for x in 0..<width {
                    let depth = Float(depthPixels[y * width + x])
                    if depth > minDepth && depth < maxDepth {
                        let position = calculatePosition(x: Float(x), y: Float(y), depth: depth, intrinsics: scaledIntrinsics)
                        let color = getColor(x: x, y: y, colorYPixels: colorYPixels, colorCbCrPixels: colorCbCrPixels, width: width)
                        points.append("\(position.x) \(position.y) \(position.z) \(color.x) \(color.y) \(color.z)")
                    }
                }
            }

            var fileContent = """
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

            fileContent += points.joined(separator: "\n")

            try fileContent.write(to: url, atomically: true, encoding: .utf8)
        }

        private func calculatePosition(x: Float, y: Float, depth: Float, intrinsics: simd_float3x3) -> SIMD3<Float> {
            let fx = intrinsics[0][0]
            let fy = intrinsics[1][1]
            let cx = intrinsics[2][0]
            let cy = intrinsics[2][1]

            let pointX = (x - cx) * depth / fx
            let pointY = -(y - cy) * depth / fy  // Flip Y-axis to match Metal rendering
            let pointZ = -depth  // Negate Z to match Metal rendering

            return SIMD3<Float>(pointX, pointY, pointZ)
        }

        private func getColor(x: Int, y: Int, colorYPixels: [UInt8], colorCbCrPixels: [SIMD2<UInt8>], width: Int) -> SIMD3<UInt8> {
            let yValue = Float(colorYPixels[y * width + x])
            let cbcrValue = colorCbCrPixels[(y/2) * (width/2) + (x/2)]
            let ycbcr = SIMD4<Float>(yValue, Float(cbcrValue.x), Float(cbcrValue.y), 1.0)
            
            let ycbcrToRGBTransform = simd_float4x4(
                SIMD4<Float>(+1.0000, +1.0000, +1.0000, +0.0000),
                SIMD4<Float>(+0.0000, -0.3441, +1.7720, +0.0000),
                SIMD4<Float>(+1.4020, -0.7141, +0.0000, +0.0000),
                SIMD4<Float>(-0.7010, +0.5291, -0.8860, +1.0000)
            )

            let rgbaColor = ycbcrToRGBTransform * ycbcr
            return SIMD3<UInt8>(UInt8(max(0, min(255, rgbaColor.x * 255))),
                                UInt8(max(0, min(255, rgbaColor.y * 255))),
                                UInt8(max(0, min(255, rgbaColor.z * 255))))
        }
    
}
