import Foundation
import Vision
import AppKit
import Combine
import CoreImage
import CoreML
import CoreVideo

// Matches exactly what your custom grid layout reads.
// The UI still only needs fileURL and faceCount, so the view can stay simple.
struct MatchResult: Identifiable {
    let id = UUID()
    let fileURL: URL
    let faceCount: Int
}

private enum FaceMatcherError: LocalizedError {
    case modelNotFound([String])
    case modelHasNoInputs
    case modelHasNoOutputs
    case unsupportedInputType(MLFeatureType)
    case pixelBufferCreationFailed
    case pixelBufferContextFailed
    case missingModelOutput(String)
    case unsupportedModelOutput
    case noFaceDetected

    var errorDescription: String? {
        switch self {
        case .modelNotFound(let names):
            return "FaceNet CoreML model not found. Add one of these to the app target: \(names.map { $0 + ".mlmodel" }.joined(separator: ", "))"
        case .modelHasNoInputs:
            return "The CoreML model has no input description."
        case .modelHasNoOutputs:
            return "The CoreML model has no output description."
        case .unsupportedInputType(let type):
            return "Unsupported FaceNet model input type: \(type). Expected image or MLMultiArray."
        case .pixelBufferCreationFailed:
            return "Could not create the normalized face pixel buffer."
        case .pixelBufferContextFailed:
            return "Could not create CGContext for face preprocessing."
        case .missingModelOutput(let name):
            return "The FaceNet model did not return output named \(name)."
        case .unsupportedModelOutput:
            return "The FaceNet model output is not an MLMultiArray embedding."
        case .noFaceDetected:
            return "No usable face detected."
        }
    }
}

/// Runtime wrapper around a FaceNet-style CoreML embedding model.
///
/// This intentionally avoids relying on the generated Swift model class name because
/// different conversions of the daduz11/davidsandberg FaceNet model may be named
/// `FaceNet`, `facenet`, `model`, etc. The wrapper reads the model's first input and
/// first output dynamically.
final class FaceEmbeddingModel {
    static let defaultModelNames = [
        "FaceNet",
        "facenet",
        "Facenet",
        "InceptionResnetV1",
        "facenet512",
        "model"
    ]

    private let model: MLModel
    private let inputName: String
    private let outputName: String
    private let inputDescription: MLFeatureDescription
    private let imageSize: Int
    private let ciContext = CIContext(options: [.useSoftwareRenderer: false])

    init(modelNames: [String] = FaceEmbeddingModel.defaultModelNames, fallbackImageSize: Int = 160) throws {
        let modelURL = try Self.findCompiledModelURL(modelNames: modelNames)
        let configuration = MLModelConfiguration()
        configuration.computeUnits = .all

        self.model = try MLModel(contentsOf: modelURL, configuration: configuration)

        guard let firstInput = self.model.modelDescription.inputDescriptionsByName.first(where: {
            $0.value.type == .image || $0.value.type == .multiArray
        }) ?? self.model.modelDescription.inputDescriptionsByName.first else {
            throw FaceMatcherError.modelHasNoInputs
        }
        guard let firstOutput = self.model.modelDescription.outputDescriptionsByName.first(where: {
            $0.value.type == .multiArray
        }) ?? self.model.modelDescription.outputDescriptionsByName.first else {
            throw FaceMatcherError.modelHasNoOutputs
        }

        self.inputName = firstInput.key
        self.inputDescription = firstInput.value
        self.outputName = firstOutput.key
        self.imageSize = Self.inferImageSize(from: firstInput.value) ?? fallbackImageSize

        #if DEBUG
        print("Loaded FaceNet model: \(modelURL.lastPathComponent), input: \(inputName), output: \(outputName), size: \(imageSize)x\(imageSize)")
        #endif
    }

    private static func findCompiledModelURL(modelNames: [String]) throws -> URL {
        for name in modelNames {
            if let compiled = Bundle.main.url(forResource: name, withExtension: "mlmodelc") {
                return compiled
            }
            if let raw = Bundle.main.url(forResource: name, withExtension: "mlmodel") {
                return try MLModel.compileModel(at: raw)
            }
        }

        // Last-resort fallback: if the app bundle has exactly one compiled model,
        // use it. This helps when the converted model has an unexpected name.
        let bundledCompiledModels = Bundle.main.urls(forResourcesWithExtension: "mlmodelc", subdirectory: nil) ?? []
        if bundledCompiledModels.count == 1, let onlyModel = bundledCompiledModels.first {
            return onlyModel
        }

        throw FaceMatcherError.modelNotFound(modelNames)
    }

    private static func inferImageSize(from description: MLFeatureDescription) -> Int? {
        if description.type == .image, let imageConstraint = description.imageConstraint {
            return imageConstraint.pixelsWide > 0 ? imageConstraint.pixelsWide : nil
        }

        guard description.type == .multiArray,
              let shape = description.multiArrayConstraint?.shape.map({ $0.intValue }) else {
            return nil
        }

        // Common FaceNet shapes: [1, 160, 160, 3], [1, 3, 160, 160], [160, 160, 3].
        if shape.contains(160) { return 160 }
        if shape.contains(112) { return 112 }
        if shape.contains(128) { return 128 }

        let spatialCandidates = shape.filter { $0 > 16 && $0 != 3 }
        return spatialCandidates.first
    }

    func embedding(from faceCGImage: CGImage) throws -> [Float] {
        let pixelBuffer = try makeResizedPixelBuffer(from: faceCGImage, size: imageSize)
        let inputFeature: MLFeatureValue

        switch inputDescription.type {
        case .image:
            inputFeature = MLFeatureValue(pixelBuffer: pixelBuffer)

        case .multiArray:
            let shape = inputDescription.multiArrayConstraint?.shape.map { $0.intValue } ?? [1, imageSize, imageSize, 3]
            let inputArray = try makeStandardizedRGBMultiArray(from: pixelBuffer, shape: shape)
            inputFeature = MLFeatureValue(multiArray: inputArray)

        default:
            throw FaceMatcherError.unsupportedInputType(inputDescription.type)
        }

        let provider = try MLDictionaryFeatureProvider(dictionary: [inputName: inputFeature])
        let prediction = try model.prediction(from: provider)

        guard let outputFeature = prediction.featureValue(for: outputName) else {
            throw FaceMatcherError.missingModelOutput(outputName)
        }
        guard let outputArray = outputFeature.multiArrayValue else {
            throw FaceMatcherError.unsupportedModelOutput
        }

        var vector = [Float]()
        vector.reserveCapacity(outputArray.count)
        for index in 0..<outputArray.count {
            vector.append(outputArray[index].floatValue)
        }

        return l2Normalized(vector)
    }

    private func makeResizedPixelBuffer(from cgImage: CGImage, size: Int) throws -> CVPixelBuffer {
        var pixelBuffer: CVPixelBuffer?
        let attributes: [CFString: Any] = [
            kCVPixelBufferCGImageCompatibilityKey: true,
            kCVPixelBufferCGBitmapContextCompatibilityKey: true,
            kCVPixelBufferIOSurfacePropertiesKey: [:]
        ]

        let status = CVPixelBufferCreate(
            kCFAllocatorDefault,
            size,
            size,
            kCVPixelFormatType_32BGRA,
            attributes as CFDictionary,
            &pixelBuffer
        )

        guard status == kCVReturnSuccess, let buffer = pixelBuffer else {
            throw FaceMatcherError.pixelBufferCreationFailed
        }

        CVPixelBufferLockBaseAddress(buffer, [])
        defer { CVPixelBufferUnlockBaseAddress(buffer, []) }

        guard let baseAddress = CVPixelBufferGetBaseAddress(buffer) else {
            throw FaceMatcherError.pixelBufferCreationFailed
        }

        let colorSpace = CGColorSpaceCreateDeviceRGB()
        let bitmapInfo = CGBitmapInfo.byteOrder32Little.rawValue | CGImageAlphaInfo.premultipliedFirst.rawValue

        guard let context = CGContext(
            data: baseAddress,
            width: size,
            height: size,
            bitsPerComponent: 8,
            bytesPerRow: CVPixelBufferGetBytesPerRow(buffer),
            space: colorSpace,
            bitmapInfo: bitmapInfo
        ) else {
            throw FaceMatcherError.pixelBufferContextFailed
        }

        context.interpolationQuality = .high
        context.clear(CGRect(x: 0, y: 0, width: size, height: size))
        context.draw(cgImage, in: CGRect(x: 0, y: 0, width: size, height: size))

        return buffer
    }

    /// Converts BGRA pixels to standardized RGB values.
    /// For FaceNet/davidsandberg models this is normally fixed image standardization:
    /// (pixel - 127.5) / 128.0.
    private func makeStandardizedRGBMultiArray(from buffer: CVPixelBuffer, shape: [Int]) throws -> MLMultiArray {
        let normalizedShape = shape.isEmpty ? [1, imageSize, imageSize, 3] : shape
        let array = try MLMultiArray(shape: normalizedShape.map { NSNumber(value: $0) }, dataType: .float32)

        CVPixelBufferLockBaseAddress(buffer, .readOnly)
        defer { CVPixelBufferUnlockBaseAddress(buffer, .readOnly) }

        guard let baseAddress = CVPixelBufferGetBaseAddress(buffer) else {
            throw FaceMatcherError.pixelBufferCreationFailed
        }

        let bytesPerRow = CVPixelBufferGetBytesPerRow(buffer)
        let pointer = baseAddress.assumingMemoryBound(to: UInt8.self)

        for y in 0..<imageSize {
            let row = pointer.advanced(by: y * bytesPerRow)
            for x in 0..<imageSize {
                let pixel = row.advanced(by: x * 4)

                // kCVPixelFormatType_32BGRA gives B, G, R, A in memory.
                let b = Float(pixel[0])
                let g = Float(pixel[1])
                let r = Float(pixel[2])

                setStandardizedChannelValue((r - 127.5) / 128.0, in: array, shape: normalizedShape, y: y, x: x, channel: 0)
                setStandardizedChannelValue((g - 127.5) / 128.0, in: array, shape: normalizedShape, y: y, x: x, channel: 1)
                setStandardizedChannelValue((b - 127.5) / 128.0, in: array, shape: normalizedShape, y: y, x: x, channel: 2)
            }
        }

        return array
    }

    private func setStandardizedChannelValue(_ value: Float, in array: MLMultiArray, shape: [Int], y: Int, x: Int, channel: Int) {
        let number = NSNumber(value: value)

        func set(_ indices: [Int]) {
            array[indices.map { NSNumber(value: $0) }] = number
        }

        switch shape.count {
        case 4:
            if shape[0] == 1 && shape[3] == 3 {
                // NHWC: [1, H, W, C]
                set([0, y, x, channel])
            } else if shape[0] == 1 && shape[1] == 3 {
                // NCHW: [1, C, H, W]
                set([0, channel, y, x])
            } else if shape[3] == 1 && shape[2] == 3 {
                // HWC batch-last: [H, W, C, 1]
                set([y, x, channel, 0])
            } else {
                let flatIndex = ((y * imageSize + x) * 3) + channel
                if flatIndex < array.count { array[flatIndex] = number }
            }

        case 3:
            if shape[2] == 3 {
                // HWC: [H, W, C]
                set([y, x, channel])
            } else if shape[0] == 3 {
                // CHW: [C, H, W]
                set([channel, y, x])
            } else {
                let flatIndex = ((y * imageSize + x) * 3) + channel
                if flatIndex < array.count { array[flatIndex] = number }
            }

        default:
            let flatIndex = ((y * imageSize + x) * 3) + channel
            if flatIndex < array.count { array[flatIndex] = number }
        }
    }

    private func l2Normalized(_ vector: [Float]) -> [Float] {
        let squaredSum = vector.reduce(Float(0)) { $0 + ($1 * $1) }
        let norm = sqrt(max(squaredSum, 1e-12))
        return vector.map { $0 / norm }
    }
}

class FaceMatcher: ObservableObject {
    // UI Binding State hooks matching your custom view layers exactly
    @Published var isScanning = false
    @Published var progress: Double = 0.0
    @Published var statusText = "STANDBY"
    @Published var matchedResults: [MatchResult] = []

    private var currentTask: Task<Void, Never>? = nil
    private let ciContext = CIContext(options: [.useSoftwareRenderer: false])
    private let embeddingModel: FaceEmbeddingModel?
    private let modelLoadError: Error?

    init(modelNames: [String] = FaceEmbeddingModel.defaultModelNames) {
        do {
            self.embeddingModel = try FaceEmbeddingModel(modelNames: modelNames)
            self.modelLoadError = nil
        } catch {
            self.embeddingModel = nil
            self.modelLoadError = error
            #if DEBUG
            print("FaceNet model load failed: \(error.localizedDescription)")
            #endif
        }
    }

    /// Halts ongoing looping routines safely upon explicit UI trigger requests
    func cancel() {
        currentTask?.cancel()
        cleanupScanningState(finalStatus: "SCAN CANCELED BY USER")
    }

    func clearResults() {
        currentTask?.cancel()
        DispatchQueue.main.async {
            self.isScanning = false
            self.progress = 0.0
            self.statusText = "STANDBY"
            self.matchedResults.removeAll()
        }
    }

    private func cleanupScanningState(finalStatus: String) {
        DispatchQueue.main.async {
            self.isScanning = false
            self.progress = 0.0
            self.statusText = finalStatus
        }
    }

    /// Extracts the FaceNet embedding for the most prominent face in the identity selfie.
    private func extractTargetFaceEmbedding(from nsImage: NSImage, using model: FaceEmbeddingModel) throws -> [Float] {
        guard let cgImage = nsImage.cgImage(forProposedRect: nil, context: nil, hints: nil) else {
            throw FaceMatcherError.noFaceDetected
        }

        let faces = try detectFaces(in: cgImage).filter { isUsableFace($0, in: cgImage) }
        guard let largestFace = faces.max(by: {
            ($0.boundingBox.width * $0.boundingBox.height) < ($1.boundingBox.width * $1.boundingBox.height)
        }) else {
            throw FaceMatcherError.noFaceDetected
        }

        guard let croppedFace = cropFace(from: cgImage, boundingBox: largestFace.boundingBox) else {
            throw FaceMatcherError.noFaceDetected
        }

        return try model.embedding(from: croppedFace)
    }

    /// Iterates through target local folder items and matches using FaceNet embeddings.
    func scanPartyFolder(selfieImage: NSImage, folderURL: URL, strictness: Double) async {
        currentTask?.cancel()

        let minimumSimilarity = minimumCosineSimilarity(for: strictness)
        let scanTask = Task {
            await MainActor.run {
                self.isScanning = true
                self.progress = 0.0
                self.statusText = "LOADING FACENET RECOGNITION CORE..."
                self.matchedResults.removeAll()
            }

            guard let embeddingModel = self.embeddingModel else {
                await MainActor.run {
                    self.isScanning = false
                    self.statusText = "ERROR: \(self.modelLoadError?.localizedDescription ?? "FACENET MODEL MISSING")"
                }
                return
            }

            let targetEmbedding: [Float]
            do {
                targetEmbedding = try self.extractTargetFaceEmbedding(from: selfieImage, using: embeddingModel)
            } catch {
                await MainActor.run {
                    self.isScanning = false
                    self.statusText = "ERROR: CAPTURE CLEAR FRONT SELFIE FACE"
                }
                return
            }

            let fileManager = FileManager.default
            let keys: [URLResourceKey] = [.isRegularFileKey]

            guard let fileURLs = try? fileManager.contentsOfDirectory(at: folderURL, includingPropertiesForKeys: keys, options: .skipsHiddenFiles) else {
                await MainActor.run {
                    self.isScanning = false
                    self.statusText = "ERROR: INVALID REPOSITORY TARGET LOCATION"
                }
                return
            }

            let allowedExtensions = ["jpg", "jpeg", "png", "heic"]
            let imageFiles = fileURLs.filter { allowedExtensions.contains($0.pathExtension.lowercased()) }
            let totalCount = imageFiles.count

            if totalCount == 0 {
                await MainActor.run {
                    self.isScanning = false
                    self.statusText = "EMPTY TARGET DIRECTORY COMPLETED"
                }
                return
            }

            var localMatches: [MatchResult] = []

            for (index, fileURL) in imageFiles.enumerated() {
                if Task.isCancelled { return }

                let currentProgress = Double(index + 1) / Double(totalCount)
                let currentFileName = fileURL.lastPathComponent

                await MainActor.run {
                    self.progress = currentProgress
                    self.statusText = "RECOGNIZING: \(currentFileName.uppERCased())"
                }

                guard let partyImage = NSImage(contentsOf: fileURL),
                      let cgImage = partyImage.cgImage(forProposedRect: nil, context: nil, hints: nil) else {
                    continue
                }

                do {
                    let detectedFaces = try self.detectFaces(in: cgImage)
                    let usableFaces = detectedFaces.filter { self.isUsableFace($0, in: cgImage) }
                    let totalPeopleInPhoto = detectedFaces.count

                    var bestSimilarity: Float = -1.0

                    for face in usableFaces {
                        guard let croppedFace = self.cropFace(from: cgImage, boundingBox: face.boundingBox) else {
                            continue
                        }

                        let candidateEmbedding = try embeddingModel.embedding(from: croppedFace)
                        let similarity = self.cosineSimilarity(candidateEmbedding, targetEmbedding)
                        bestSimilarity = max(bestSimilarity, similarity)
                    }

                    if bestSimilarity >= minimumSimilarity {
                        localMatches.append(MatchResult(fileURL: fileURL, faceCount: totalPeopleInPhoto))

                        await MainActor.run {
                            self.matchedResults = localMatches
                        }
                    }
                } catch {
                    #if DEBUG
                    print("FaceNet recognition skipped one selected file: \(error.localizedDescription)")
                    #endif
                }
            }

            await MainActor.run {
                self.isScanning = false
                self.statusText = localMatches.isEmpty ? "FACENET SCAN FINISHED: NO LOCAL RESULTS" : "FACENET SCAN COMPLETE: \(localMatches.count) TARGETS FOUND"
            }
        }

        currentTask = scanTask
        await scanTask.value
    }

    private func detectFaces(in cgImage: CGImage) throws -> [VNFaceObservation] {
        let requestHandler = VNImageRequestHandler(cgImage: cgImage, options: [:])
        let request = VNDetectFaceLandmarksRequest()
        try requestHandler.perform([request])
        return request.results ?? []
    }

    private func isUsableFace(_ face: VNFaceObservation, in cgImage: CGImage) -> Bool {
        guard face.confidence >= 0.70 else { return false }

        let rect = VNImageRectForNormalizedRect(face.boundingBox, cgImage.width, cgImage.height)
        guard rect.width >= 55, rect.height >= 55 else { return false }

        return true
    }

    private func cropFace(from cgImage: CGImage, boundingBox: CGRect) -> CGImage? {
        let imageRect = CGRect(x: 0, y: 0, width: cgImage.width, height: cgImage.height)
        var cropRect = VNImageRectForNormalizedRect(boundingBox, cgImage.width, cgImage.height)

        // FaceNet benefits from a consistent face crop with a little context around chin/forehead.
        let horizontalPadding = cropRect.width * 0.30
        let verticalPadding = cropRect.height * 0.35
        cropRect = cropRect.insetBy(dx: -horizontalPadding, dy: -verticalPadding)
        cropRect = cropRect.intersection(imageRect).integral

        guard cropRect.width >= 55, cropRect.height >= 55 else { return nil }

        let ciImage = CIImage(cgImage: cgImage)
        let croppedImage = ciImage.cropped(to: cropRect)
        return ciContext.createCGImage(croppedImage, from: cropRect)
    }

    private func cosineSimilarity(_ lhs: [Float], _ rhs: [Float]) -> Float {
        let count = min(lhs.count, rhs.count)
        guard count > 0 else { return -1.0 }

        var dot: Float = 0
        var lhsNorm: Float = 0
        var rhsNorm: Float = 0

        for index in 0..<count {
            dot += lhs[index] * rhs[index]
            lhsNorm += lhs[index] * lhs[index]
            rhsNorm += rhs[index] * rhs[index]
        }

        let denominator = sqrt(max(lhsNorm, 1e-12)) * sqrt(max(rhsNorm, 1e-12))
        return dot / denominator
    }

    private func minimumCosineSimilarity(for strictness: Double) -> Float {
        let clampedStrictness = min(max(strictness, 0.0), 1.0)

        // Tune these with your own photos. If false positives remain, raise both values.
        let lenientSimilarity: Float = 0.55
        let strictSimilarity: Float = 0.78

        return lenientSimilarity + (Float(clampedStrictness) * (strictSimilarity - lenientSimilarity))
    }
}

// Extension to cleanly transform file names in status updates
private extension String {
    func uppERCased() -> String {
        return self.uppercased()
    }
}
