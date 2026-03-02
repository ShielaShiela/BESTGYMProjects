//
// yolo11l_pose.swift
//
// This file was automatically generated and should not be edited.
//

import CoreML


/// Model Prediction Input Type
@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, visionOS 1.0, *)
class yolo11l_poseInput : MLFeatureProvider {

    /// image as color (kCVPixelFormatType_32BGRA) image buffer, 320 pixels wide by 320 pixels high
    var image: CVPixelBuffer

    var featureNames: Set<String> { ["image"] }

    func featureValue(for featureName: String) -> MLFeatureValue? {
        if featureName == "image" {
            return MLFeatureValue(pixelBuffer: image)
        }
        return nil
    }

    init(image: CVPixelBuffer) {
        self.image = image
    }

    convenience init(imageWith image: CGImage) throws {
        self.init(image: try MLFeatureValue(cgImage: image, pixelsWide: 320, pixelsHigh: 320, pixelFormatType: kCVPixelFormatType_32ARGB, options: nil).imageBufferValue!)
    }

    convenience init(imageAt image: URL) throws {
        self.init(image: try MLFeatureValue(imageAt: image, pixelsWide: 320, pixelsHigh: 320, pixelFormatType: kCVPixelFormatType_32ARGB, options: nil).imageBufferValue!)
    }

    func setImage(with image: CGImage) throws  {
        self.image = try MLFeatureValue(cgImage: image, pixelsWide: 320, pixelsHigh: 320, pixelFormatType: kCVPixelFormatType_32ARGB, options: nil).imageBufferValue!
    }

    func setImage(with image: URL) throws  {
        self.image = try MLFeatureValue(imageAt: image, pixelsWide: 320, pixelsHigh: 320, pixelFormatType: kCVPixelFormatType_32ARGB, options: nil).imageBufferValue!
    }

}


/// Model Prediction Output Type
@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, visionOS 1.0, *)
class yolo11l_poseOutput : MLFeatureProvider {

    /// Source provided by CoreML
    private let provider : MLFeatureProvider

    /// var_2340 as 1 × 56 × 2100 3-dimensional array of floats
    var var_2340: MLMultiArray {
        provider.featureValue(for: "var_2340")!.multiArrayValue!
    }

    /// var_2340 as 1 × 56 × 2100 3-dimensional array of floats
    var var_2340ShapedArray: MLShapedArray<Float> {
        MLShapedArray<Float>(var_2340)
    }

    var featureNames: Set<String> {
        provider.featureNames
    }

    func featureValue(for featureName: String) -> MLFeatureValue? {
        provider.featureValue(for: featureName)
    }

    init(var_2340: MLMultiArray) {
        self.provider = try! MLDictionaryFeatureProvider(dictionary: ["var_2340" : MLFeatureValue(multiArray: var_2340)])
    }

    init(features: MLFeatureProvider) {
        self.provider = features
    }
}


/// Class for model loading and prediction
@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, visionOS 1.0, *)
class yolo11l_pose {
    let model: MLModel

    /// URL of model assuming it was installed in the same bundle as this class
    class var urlOfModelInThisBundle : URL {
        let bundle = Bundle(for: self)
        return bundle.url(forResource: "yolo11l-pose", withExtension:"mlmodelc")!
    }

    /**
        Construct yolo11l_pose instance with an existing MLModel object.

        Usually the application does not use this initializer unless it makes a subclass of yolo11l_pose.
        Such application may want to use `MLModel(contentsOfURL:configuration:)` and `yolo11l_pose.urlOfModelInThisBundle` to create a MLModel object to pass-in.

        - parameters:
          - model: MLModel object
    */
    init(model: MLModel) {
        self.model = model
    }

    /**
        Construct a model with configuration

        - parameters:
           - configuration: the desired model configuration

        - throws: an NSError object that describes the problem
    */
    convenience init(configuration: MLModelConfiguration = MLModelConfiguration()) throws {
        try self.init(contentsOf: type(of:self).urlOfModelInThisBundle, configuration: configuration)
    }

    /**
        Construct yolo11l_pose instance with explicit path to mlmodelc file
        - parameters:
           - modelURL: the file url of the model

        - throws: an NSError object that describes the problem
    */
    convenience init(contentsOf modelURL: URL) throws {
        try self.init(model: MLModel(contentsOf: modelURL))
    }

    /**
        Construct a model with URL of the .mlmodelc directory and configuration

        - parameters:
           - modelURL: the file url of the model
           - configuration: the desired model configuration

        - throws: an NSError object that describes the problem
    */
    convenience init(contentsOf modelURL: URL, configuration: MLModelConfiguration) throws {
        try self.init(model: MLModel(contentsOf: modelURL, configuration: configuration))
    }

    /**
        Construct yolo11l_pose instance asynchronously with optional configuration.

        Model loading may take time when the model content is not immediately available (e.g. encrypted model). Use this factory method especially when the caller is on the main thread.

        - parameters:
          - configuration: the desired model configuration
          - handler: the completion handler to be called when the model loading completes successfully or unsuccessfully
    */
    class func load(configuration: MLModelConfiguration = MLModelConfiguration(), completionHandler handler: @escaping (Swift.Result<yolo11l_pose, Error>) -> Void) {
        load(contentsOf: self.urlOfModelInThisBundle, configuration: configuration, completionHandler: handler)
    }

    /**
        Construct yolo11l_pose instance asynchronously with optional configuration.

        Model loading may take time when the model content is not immediately available (e.g. encrypted model). Use this factory method especially when the caller is on the main thread.

        - parameters:
          - configuration: the desired model configuration
    */
    class func load(configuration: MLModelConfiguration = MLModelConfiguration()) async throws -> yolo11l_pose {
        try await load(contentsOf: self.urlOfModelInThisBundle, configuration: configuration)
    }

    /**
        Construct yolo11l_pose instance asynchronously with URL of the .mlmodelc directory with optional configuration.

        Model loading may take time when the model content is not immediately available (e.g. encrypted model). Use this factory method especially when the caller is on the main thread.

        - parameters:
          - modelURL: the URL to the model
          - configuration: the desired model configuration
          - handler: the completion handler to be called when the model loading completes successfully or unsuccessfully
    */
    class func load(contentsOf modelURL: URL, configuration: MLModelConfiguration = MLModelConfiguration(), completionHandler handler: @escaping (Swift.Result<yolo11l_pose, Error>) -> Void) {
        MLModel.load(contentsOf: modelURL, configuration: configuration) { result in
            switch result {
            case .failure(let error):
                handler(.failure(error))
            case .success(let model):
                handler(.success(yolo11l_pose(model: model)))
            }
        }
    }

    /**
        Construct yolo11l_pose instance asynchronously with URL of the .mlmodelc directory with optional configuration.

        Model loading may take time when the model content is not immediately available (e.g. encrypted model). Use this factory method especially when the caller is on the main thread.

        - parameters:
          - modelURL: the URL to the model
          - configuration: the desired model configuration
    */
    class func load(contentsOf modelURL: URL, configuration: MLModelConfiguration = MLModelConfiguration()) async throws -> yolo11l_pose {
        let model = try await MLModel.load(contentsOf: modelURL, configuration: configuration)
        return yolo11l_pose(model: model)
    }

    /**
        Make a prediction using the structured interface

        It uses the default function if the model has multiple functions.

        - parameters:
           - input: the input to the prediction as yolo11l_poseInput

        - throws: an NSError object that describes the problem

        - returns: the result of the prediction as yolo11l_poseOutput
    */
    func prediction(input: yolo11l_poseInput) throws -> yolo11l_poseOutput {
        try prediction(input: input, options: MLPredictionOptions())
    }

    /**
        Make a prediction using the structured interface

        It uses the default function if the model has multiple functions.

        - parameters:
           - input: the input to the prediction as yolo11l_poseInput
           - options: prediction options

        - throws: an NSError object that describes the problem

        - returns: the result of the prediction as yolo11l_poseOutput
    */
    func prediction(input: yolo11l_poseInput, options: MLPredictionOptions) throws -> yolo11l_poseOutput {
        let outFeatures = try model.prediction(from: input, options: options)
        return yolo11l_poseOutput(features: outFeatures)
    }

    /**
        Make an asynchronous prediction using the structured interface

        It uses the default function if the model has multiple functions.

        - parameters:
           - input: the input to the prediction as yolo11l_poseInput
           - options: prediction options

        - throws: an NSError object that describes the problem

        - returns: the result of the prediction as yolo11l_poseOutput
    */
    @available(macOS 14.0, iOS 17.0, tvOS 17.0, watchOS 10.0, visionOS 1.0, *)
    func prediction(input: yolo11l_poseInput, options: MLPredictionOptions = MLPredictionOptions()) async throws -> yolo11l_poseOutput {
        let outFeatures = try await model.prediction(from: input, options: options)
        return yolo11l_poseOutput(features: outFeatures)
    }

    /**
        Make a prediction using the convenience interface

        It uses the default function if the model has multiple functions.

        - parameters:
            - image: color (kCVPixelFormatType_32BGRA) image buffer, 320 pixels wide by 320 pixels high

        - throws: an NSError object that describes the problem

        - returns: the result of the prediction as yolo11l_poseOutput
    */
    func prediction(image: CVPixelBuffer) throws -> yolo11l_poseOutput {
        let input_ = yolo11l_poseInput(image: image)
        return try prediction(input: input_)
    }

    /**
        Make a batch prediction using the structured interface

        It uses the default function if the model has multiple functions.

        - parameters:
           - inputs: the inputs to the prediction as [yolo11l_poseInput]
           - options: prediction options

        - throws: an NSError object that describes the problem

        - returns: the result of the prediction as [yolo11l_poseOutput]
    */
    func predictions(inputs: [yolo11l_poseInput], options: MLPredictionOptions = MLPredictionOptions()) throws -> [yolo11l_poseOutput] {
        let batchIn = MLArrayBatchProvider(array: inputs)
        let batchOut = try model.predictions(from: batchIn, options: options)
        var results : [yolo11l_poseOutput] = []
        results.reserveCapacity(inputs.count)
        for i in 0..<batchOut.count {
            let outProvider = batchOut.features(at: i)
            let result =  yolo11l_poseOutput(features: outProvider)
            results.append(result)
        }
        return results
    }
}
