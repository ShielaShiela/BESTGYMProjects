//
//  YoloVM.swift
//  PoseA
//
//  Created by Ardhika Maulidani on 8/11/25.
//

import CoreML
import Vision
import os.log

final class YOLOPoseProcessor {
    // MARK: - Public knobs
    var confidenceThreshold: Float = 0.35
    var iouThreshold: Float = 0.50

    // MARK: - Private
    private var mlModel: MLModel!
    private var vnModel: VNCoreMLModel!
    private var visionRequest: VNCoreMLRequest!

    private let queue = DispatchQueue(label: "yolo.pose.queue")

    private(set) var camInputSize: CGSize = .zero
    private(set) var modelInputSize: CGSize = .zero

    private var boxCount: Int = 0
    private var featureLength: Int = 0
    
    // MARK: - Double buffer
    private let frameQueue = DispatchQueue(label: "yolo.pose.frameQueue", attributes: .concurrent)
    private var pixelBufferQueue: [(CVPixelBuffer, CMTime)] = []
    private var isProcessing: Bool = false

    private let modelFPS = FPSMeter(label: "Model", autoPrint: false)

    // MARK: - Utilities
    private func tick(_ label: String, block: () -> Void) {
        let start = CFAbsoluteTimeGetCurrent()
        block()
        let diff = (CFAbsoluteTimeGetCurrent() - start) * 1000
        print("⏱ \(label): \(String(format: "%.2f", diff)) ms")
    }

    // MARK: - Model Loading
    func loadModel(named name: String, completion: @escaping ((Bool) -> Void)) {
        DispatchQueue.global(qos: .userInitiated).async {
            self.tick("LoadModel") {
                do {
                    guard let url = Bundle.main.url(forResource: name, withExtension: "mlmodelc") else {
                        assertionFailure("Model not found in bundle")
                        return
                    }
                    let config = MLModelConfiguration()
                    config.computeUnits = .cpuAndNeuralEngine
                    
                    self.mlModel = try MLModel(contentsOf: url, configuration: config)
                    self.vnModel = try VNCoreMLModel(for: self.mlModel)
                    
                    if let input = self.mlModel?.modelDescription.inputDescriptionsByName.values.first,
                       input.type == .image,
                       let ic = input.imageConstraint {
                        self.modelInputSize = CGSize(width: ic.pixelsWide, height: ic.pixelsHigh)
                    }

                    if let output = self.mlModel?.modelDescription.outputDescriptionsByName.values.first,
                       output.type == .multiArray,
                       let shape = output.multiArrayConstraint?.shape,
                       shape.count == 3 {
                        self.featureLength = Int(truncating: shape[1])
                        self.boxCount = Int(truncating: shape[2])
                    }
                    
                    DispatchQueue.main.async {
                        self.setUpVision()
                        completion(true)
                    }
                    
                } catch {
                    assertionFailure("Failed to load model: \(error)")
                    DispatchQueue.main.async {
                        completion(false)
                    }
                }
            }
        }
    }

    private func setUpVision() {
        visionRequest = VNCoreMLRequest(model: vnModel) { _, _ in }
        visionRequest.imageCropAndScaleOption = .scaleFill
    }

    // MARK: - Public API
    func process(pixelBuffer: CVPixelBuffer, pts: CMTime, completion: @escaping ([PoseBox], Double, CMTime) -> Void) {
        // Add frame to queue
        frameQueue.async(flags: .barrier) {
            // Keep max 2 frames, drop older
            if self.pixelBufferQueue.count >= 2 {
                self.pixelBufferQueue.removeFirst()
            }
            self.pixelBufferQueue.append((pixelBuffer, pts))
        }

        tryProcessNextFrame(completion: completion)
    }

    private func tryProcessNextFrame(completion: @escaping ([PoseBox], Double, CMTime) -> Void) {
        let start = CFAbsoluteTimeGetCurrent()

        // Only one frame at a time
        guard !isProcessing else { return }
        isProcessing = true

        // Get the latest frame
        var bufferToProcess: (CVPixelBuffer, CMTime)?
        frameQueue.sync {
            bufferToProcess = self.pixelBufferQueue.popLast()!
            self.pixelBufferQueue.removeAll() // discard older frames
        }

        guard let (buffer, pts) = bufferToProcess else {
            isProcessing = false
            return
        }

        camInputSize = CGSize(width: CVPixelBufferGetWidth(buffer),
                              height: CVPixelBufferGetHeight(buffer))

        let handler = VNImageRequestHandler(cvPixelBuffer: buffer, orientation: .up, options: [:])
        let request = VNCoreMLRequest(model: vnModel) { [weak self] request, _ in
            guard let self = self else { return }
            defer { self.isProcessing = false }

            guard let results = request.results as? [VNCoreMLFeatureValueObservation],
                  let multiArray = results.first?.featureValue.multiArrayValue else {
                DispatchQueue.main.async { completion([], self.modelFPS.fps, pts) }
                // Try next frame if available
                self.tryProcessNextFrame(completion: completion)
                return
            }
            
            let diff = (CFAbsoluteTimeGetCurrent() - start) * 1000
            print("⏱ inference time: \(String(format: "%.2f", diff)) ms")

            let poses = self.decodeOutputFast(multiArray)
            self.modelFPS.tick()

            DispatchQueue.main.async {
                completion(poses, self.modelFPS.fps, pts)
            }

            // Try next frame if there are queued frames
            self.tryProcessNextFrame(completion: completion)
        }
        request.imageCropAndScaleOption = .scaleFill

        DispatchQueue.global(qos: .userInitiated).async {
            do {
                try handler.perform([request])
            } catch {
                self.isProcessing = false
                DispatchQueue.main.async { completion([], self.modelFPS.fps, pts) }
            }
        }
    }

    // MARK: - Fast decode
    private func decodeOutputFast(_ multiArray: MLMultiArray) -> [PoseBox] {
        let start = CFAbsoluteTimeGetCurrent()

        // Access MLMultiArray as a raw pointer
        let ptr = UnsafeMutablePointer<Float>(OpaquePointer(multiArray.dataPointer))
        let shape = multiArray.shape.map { Int(truncating: $0) }      // e.g. [1, 56, 2100]
        let strides = multiArray.strides.map { Int(truncating: $0) }
        
        let C = shape[1]   // featureLength (56)
        let N = shape[2]   // boxCount (2100)

        var candidates: [PoseBox] = []

        // Concurrent decode using thread-local arrays to avoid locks
        let lock = DispatchQueue(label: "com.YOLOVM.lock")

        DispatchQueue.concurrentPerform(iterations: N) { boxIdx in
            let confIndex = 4 * strides[1] + boxIdx * strides[2]
            let conf = ptr[confIndex]
            if conf > confidenceThreshold {
                // Decode box coords
                let cx = ptr[0 * strides[1] + boxIdx * strides[2]]
                let cy = ptr[1 * strides[1] + boxIdx * strides[2]]
                let w  = ptr[2 * strides[1] + boxIdx * strides[2]]
                let h  = ptr[3 * strides[1] + boxIdx * strides[2]]
                
                let tl = modelToCameraCoords(x: CGFloat(cx - w * 0.5),
                                             y: CGFloat(cy - h * 0.5),
                                             origSize: camInputSize,
                                             modelSize: modelInputSize)
                let br = modelToCameraCoords(x: CGFloat(cx + w * 0.5),
                                             y: CGFloat(cy + h * 0.5),
                                             origSize: camInputSize,
                                             modelSize: modelInputSize)
                let rect = CGRect(x: tl.x, y: tl.y, width: br.x - tl.x, height: br.y - tl.y)

                var keypoints: [KeypointData] = []
                
                // Decode all keypoints
                for k in 0..<((C - 5) / 3) {
                    let kx = ptr[(5 + k * 3) * strides[1] + boxIdx * strides[2]]
                    let ky = ptr[(6 + k * 3) * strides[1] + boxIdx * strides[2]]
                    let kc = ptr[(7 + k * 3) * strides[1] + boxIdx * strides[2]]
                    
                    let mapped = modelToCameraCoords(x: CGFloat(kx),
                                                     y: CGFloat(ky),
                                                     origSize: camInputSize,
                                                     modelSize: modelInputSize)
                    
                    keypoints.append(KeypointData(name: keypointNames[k],
                                                  x: mapped.x,
                                                  y: mapped.y,
                                                  confidence: kc,
                                                  depth: 0.0,
                                                  frameIndex: 0))
                }

                let localBox = PoseBox(bbox: rect,
                                       confidence: conf,
                                       keypoints: keypoints)

                // Merge into main array once
                lock.sync {
                    candidates.append(localBox)
                }
            }
        }
        
        let diff = (CFAbsoluteTimeGetCurrent() - start) * 1000
        print("⏱ decode time: \(String(format: "%.2f", diff)) ms")
        
        // Optional: run NMS
        var filtered: [PoseBox] = []
        filtered = filterPoses(candidates, minConfidence: confidenceThreshold, iouThreshold: iouThreshold)

        return filtered
    }

    // MARK: - Reuse your existing helpers (unchanged)
    private func modelToCameraCoords(
        x: CGFloat, y: CGFloat,
        origSize: CGSize, modelSize: CGSize) -> CGPoint {
        // Scale
        let scaledX = (x / modelSize.width)
        let scaledY = (y / modelSize.height)
            
        // Rotate coordinates back to camera orientation
        return CGPoint(x: scaledX, y: scaledY)
    }

    func filterPoses(_ poses: [PoseBox], minConfidence: Float = 0.5, iouThreshold: Float = 0.5) -> [PoseBox] {
        let start = CFAbsoluteTimeGetCurrent()

        let boxes = poses.enumerated()
            .filter { $0.element.confidence > minConfidence }
            .sorted { $0.element.confidence > $1.element.confidence }

        var suppressed = Array(repeating: false, count: boxes.count)
        var results: [PoseBox] = []

        for i in 0..<boxes.count {
            if suppressed[i] { continue }
            let current = boxes[i].element
            results.append(current)

            for j in (i+1)..<boxes.count {
                if suppressed[j] { continue }
                let other = boxes[j].element
                let iou = calculateIoU(current.bbox, other.bbox)
                if iou >= iouThreshold {
                    suppressed[j] = true
                }
            }
        }
        let diff = (CFAbsoluteTimeGetCurrent() - start) * 1000
        print("⏱ decode time: \(String(format: "%.2f", diff)) ms")
        
        return results
    }

    func calculateIoU(_ a: CGRect, _ b: CGRect) -> Float {
        let inter = a.intersection(b)
        if inter.isNull { return 0 }
        let interArea = inter.width * inter.height
        let unionArea = a.width * a.height + b.width * b.height - interArea
        return Float(interArea / unionArea)
    }
}
