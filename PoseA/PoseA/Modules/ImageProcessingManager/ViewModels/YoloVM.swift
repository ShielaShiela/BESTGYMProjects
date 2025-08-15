//
//  YoloVM.swift
//  PoseA
//
//  Created by Ardhika Maulidani on 8/11/25.
//

import CoreML
import UIKit
import CoreImage

final class YOLOPoseProcessor {
    private var mlModel: MLModel?
    private let queue = DispatchQueue(label: "yolo.pose.queue")
    
    private var camInputSize: CGSize = .zero // Camera input size
    private var modelInputSize: CGSize = .zero // Model input size
    private var boxCount: Int = 0
    private var featureLength: Int = 0
    private var keypointCount: Int = 0
    
    init(modelName: String) {
        loadModel(named: modelName)
        configureModelParameters()
    }
    
    private func loadModel(named name: String) {
        guard let modelURL = Bundle.main.url(forResource: name, withExtension: "mlmodelc") else {
            log("Model not found", level: .error)
            return
        }
        do {
            let config = MLModelConfiguration()
            config.computeUnits = .all
            mlModel = try MLModel(contentsOf: modelURL, configuration: config)
            log("Model loaded successfully", level: .info)
        } catch {
            log("Failed to load model - \(error)", level: .error)
        }
    }
    
    private func configureModelParameters() {
        guard let model = mlModel else { return }
        
        // Get the model's output description
        if let outputDescription = model.modelDescription.outputDescriptionsByName.keys.first {
            // Assuming the output is a MultiArray
            let output = model.modelDescription.outputDescriptionsByName[outputDescription]
            if output!.type == .multiArray {
                // Extract dimensions
                let shape = output?.multiArrayConstraint?.shape ?? []
                if shape.count == 3 {
                    boxCount = Int(truncating: shape[2])
                    featureLength = Int(truncating: shape[1])
                    keypointCount = 17
                }
            }
        }
        
        // Get the model's output description
        if let inputDescription = model.modelDescription.inputDescriptionsByName.keys.first {
            let input = model.modelDescription.inputDescriptionsByName[inputDescription]
            if input!.type == .image {
                modelInputSize = CGSize(width: input?.imageConstraint?.pixelsWide ?? 640,
                                        height: input?.imageConstraint?.pixelsHigh ?? 640)
            }
        }
    }
    
    func process(pixelBuffer: CVPixelBuffer, completion: @escaping ([PoseBox]) -> Void) {
        queue.async { [weak self] in
            guard let self = self, let model = self.mlModel else {
                DispatchQueue.main.async { completion([]) }
                return
            }
            
            // Get Camera Size
            self.camInputSize = CGSize(width: CGFloat(CVPixelBufferGetWidth(pixelBuffer)),
                                       height: CGFloat(CVPixelBufferGetHeight(pixelBuffer)))
            
            // Convert YCbCr -> BGRA + resize to 640x640
            guard let inputBuffer = self.convertToBGRA(pixelBuffer, targetSize: self.modelInputSize) else {
                DispatchQueue.main.async { completion([]) }
                return
            }
            
            let inputName = model.modelDescription.inputDescriptionsByName.keys.first!
            
            guard let inputProvider = try? MLDictionaryFeatureProvider(dictionary: [inputName: inputBuffer]) else {
                DispatchQueue.main.async { completion([]) }
                return
            }
            
            do {
                let prediction = try model.prediction(from: inputProvider)
                guard let outputMultiArray = prediction.featureValue(for: prediction.featureNames.first!)?.multiArrayValue else {
                    DispatchQueue.main.async { completion([]) }
                    return
                }
                
                let poses = self.decodeOutput(outputMultiArray)
                
                DispatchQueue.main.async {
                    completion(poses)
                }
                
            } catch {
                log("Model prediction error: \(error)", level: .error)
                DispatchQueue.main.async { completion([]) }
            }
        }
    }
    
    private func decodeOutput(_ multiArray: MLMultiArray) -> [PoseBox] {
        func index(_ channel: Int, _ box: Int) -> Int {
            return channel * boxCount + box
        }
        
        var results: [PoseBox] = []
        
        for boxIdx in 0..<boxCount {
            let conf = multiArray[index(4, boxIdx)].floatValue
            if conf < 0.3 { continue }
            
            let x = multiArray[index(0, boxIdx)].floatValue
            let y = multiArray[index(1, boxIdx)].floatValue
            let w = multiArray[index(2, boxIdx)].floatValue
            let h = multiArray[index(3, boxIdx)].floatValue
            
            let topLeft = self.modelToCameraCoords(x: CGFloat(x - w/2), y: CGFloat(y - h/2),
                                                   origW: self.camInputSize.width, origH: self.camInputSize.height,
                                                   modelW: self.modelInputSize.width, modelH: self.modelInputSize.width)
            
            let bottomRight = self.modelToCameraCoords(x: CGFloat(x + w/2), y: CGFloat(y + h/2),
                                                       origW: self.camInputSize.width, origH: self.camInputSize.height,
                                                       modelW: self.modelInputSize.width, modelH: self.modelInputSize.width)
            let rect = CGRect(
                x: topLeft.x,
                y: topLeft.y,
                width: bottomRight.x - topLeft.x,
                height: bottomRight.y - topLeft.y
            )
            
            var keypoints: [CGPoint] = []
            var visibility: [Float] = []
            
            for k in 0..<keypointCount {
                let px = multiArray[index(5 + k * 3, boxIdx)].floatValue
                let py = multiArray[index(6 + k * 3, boxIdx)].floatValue
                let v = multiArray[index(7 + k * 3, boxIdx)].floatValue
                
                let kp = self.modelToCameraCoords(x: CGFloat(px), y: CGFloat(py),
                                                  origW: self.camInputSize.width, origH: self.camInputSize.height,
                                                  modelW: self.modelInputSize.width, modelH: self.modelInputSize.width)
                                             
                keypoints.append(CGPoint(x: kp.x, y: kp.y))
                visibility.append(v)
            }
            
            results.append(PoseBox(bbox: rect, confidence: conf, keypoints: keypoints, visibility: visibility))
        }
        
        return results
    }
    
    private func convertToBGRA(_ pixelBuffer: CVPixelBuffer, targetSize: CGSize) -> CVPixelBuffer? {
        let ciImage = CIImage(cvPixelBuffer: pixelBuffer)

        // Maintain aspect ratio
        let scale = min(targetSize.width / self.camInputSize.width, targetSize.height / self.camInputSize.height)
        let scaledWidth = self.camInputSize.width * scale
        let scaledHeight = self.camInputSize.height * scale
        
        let dx = (targetSize.width - scaledWidth) / 2.0
        let dy = (targetSize.height - scaledHeight) / 2.0
        
        // First scale
        let scaledImage = ciImage.transformed(by: CGAffineTransform(scaleX: scale, y: scale))
            .transformed(by: CGAffineTransform(translationX: dx, y: dy))
        
        let attrs = [
            kCVPixelBufferCGImageCompatibilityKey: true,
            kCVPixelBufferCGBitmapContextCompatibilityKey: true,
            kCVPixelBufferPixelFormatTypeKey: kCVPixelFormatType_32BGRA
        ] as CFDictionary
        
        var outputBuffer: CVPixelBuffer?
        let status = CVPixelBufferCreate(
            kCFAllocatorDefault,
            Int(targetSize.width),
            Int(targetSize.height),
            kCVPixelFormatType_32BGRA,
            attrs,
            &outputBuffer
        )
        
        guard status == kCVReturnSuccess, let outBuffer = outputBuffer else {
            return nil
        }
        
        let context = CIContext()
        context.render(scaledImage, to: outBuffer)
        return outBuffer
    }
    
    private func modelToCameraCoords(x: CGFloat, y: CGFloat,
                                     origW: CGFloat, origH: CGFloat,
                                     modelW: CGFloat, modelH: CGFloat) -> CGPoint {
        let scale = min(modelW / origW, modelH / origH)
        let padX = (modelW - origW * scale) / 2
        let padY = (modelH - origH * scale) / 2
        
        let unpadX = (x - padX) / scale
        let unpadY = (y - padY) / scale
        return CGPoint(x: unpadX, y: unpadY)
    }

    
    func filterPoses(_ poses: [PoseBox], minConfidence: Float = 0.5, iouThreshold: Float = 0.5) -> [PoseBox] {
        // Step 1: Filter by confidence
        var filtered = poses.filter { $0.confidence > minConfidence }
        
        // Step 2: Sort by confidence descending
        filtered.sort { $0.confidence > $1.confidence }
        
        var result: [PoseBox] = []
        
        while !filtered.isEmpty {
            let current = filtered.removeFirst()
            result.append(current)
            
            filtered = filtered.filter { other in
                let iou = calculateIoU(current.bbox, other.bbox)
                return iou < iouThreshold
            }
        }
        
        return result
    }

    func calculateIoU(_ rectA: CGRect, _ rectB: CGRect) -> Float {
        let intersection = rectA.intersection(rectB)
        if intersection.isNull {
            return 0
        }
        
        let intersectionArea = intersection.width * intersection.height
        let unionArea = rectA.width * rectA.height + rectB.width * rectB.height - intersectionArea
        
        return Float(intersectionArea / unionArea)
    }

}
