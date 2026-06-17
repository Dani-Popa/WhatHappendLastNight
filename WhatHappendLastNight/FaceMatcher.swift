import Foundation
import Vision
import AppKit
import Combine
import CoreImage
import CoreML
import CoreVideo
import ImageIO
import Accelerate

// Matches exactly what your custom grid layout reads.
// The UI still only needs fileURL and faceCount, so the view can stay simple.
struct MatchResult: Identifiable {
    let id = UUID()
    let fileURL: URL
    let faceCount: Int
    /// Best face-embedding cosine similarity vs. the reference selfie, in 0…1.
    /// Defaults to 1.0 so older call sites keep working until they pass a value.
    let similarity: Double

    init(fileURL: URL, faceCount: Int, similarity: Double = 1.0) {
        self.fileURL = fileURL
        self.faceCount = faceCount
        self.similarity = similarity
    }
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
    ///
    /// This implementation writes directly into the MLMultiArray's backing buffer via
    /// the raw `Float` pointer instead of going through NSNumber subscripts. The
    /// previous subscript path called `MLMultiArray.subscript([NSNumber])` ~80,000
    /// times per face (160×160×3) which dominated per-image cost.
    private func makeStandardizedRGBMultiArray(from buffer: CVPixelBuffer, shape: [Int]) throws -> MLMultiArray {
        let normalizedShape = shape.isEmpty ? [1, imageSize, imageSize, 3] : shape
        let array = try MLMultiArray(shape: normalizedShape.map { NSNumber(value: $0) }, dataType: .float32)

        CVPixelBufferLockBaseAddress(buffer, .readOnly)
        defer { CVPixelBufferUnlockBaseAddress(buffer, .readOnly) }

        guard let baseAddress = CVPixelBufferGetBaseAddress(buffer) else {
            throw FaceMatcherError.pixelBufferCreationFailed
        }

        let bytesPerRow = CVPixelBufferGetBytesPerRow(buffer)
        let src = baseAddress.assumingMemoryBound(to: UInt8.self)
        let dst = array.dataPointer.assumingMemoryBound(to: Float.self)
        let strides = array.strides.map { $0.intValue }

        // Resolve which dims of the model input correspond to height/width/channel.
        // Works for NHWC, NCHW, HWC, CHW and HWC1 layouts.
        let (yStride, xStride, cStride) = Self.spatialStrides(shape: normalizedShape, strides: strides)

        // Fixed image standardization (FaceNet/davidsandberg): (px - 127.5) / 128.0
        let scale: Float = 1.0 / 128.0
        let bias: Float = -127.5 / 128.0

        for y in 0..<imageSize {
            let row = src.advanced(by: y * bytesPerRow)
            let yOffset = y * yStride
            for x in 0..<imageSize {
                let pixel = row.advanced(by: x * 4)
                // kCVPixelFormatType_32BGRA gives B, G, R, A in memory.
                let b = Float(pixel[0])
                let g = Float(pixel[1])
                let r = Float(pixel[2])
                let base = yOffset + x * xStride
                dst[base + 0 * cStride] = r * scale + bias
                dst[base + 1 * cStride] = g * scale + bias
                dst[base + 2 * cStride] = b * scale + bias
            }
        }

        return array
    }

    /// Picks the (y, x, channel) strides out of a model input's shape/stride pair so
    /// the standardization loop is layout-agnostic.
    private static func spatialStrides(shape: [Int], strides: [Int]) -> (Int, Int, Int) {
        guard shape.count == strides.count, shape.count >= 3 else {
            // Sensible row-major fallback for the typical NHWC FaceNet input.
            return (shape.count >= 2 ? shape[1] * 3 : 3, 3, 1)
        }

        // Channel axis = the dim that equals 3 (RGB). Fall back to the last axis.
        var channelAxis = shape.firstIndex(of: 3) ?? (shape.count - 1)
        // Guard against the (rare) ambiguous case where multiple dims equal 3.
        if shape.filter({ $0 == 3 }).count > 1, shape.last == 3 {
            channelAxis = shape.count - 1
        }

        // H and W are the two remaining non-batch axes; assume row-major ordering
        // (lower index = Y / height) which matches every common FaceNet conversion.
        var spatial: [Int] = []
        for i in 0..<shape.count where i != channelAxis && shape[i] != 1 {
            spatial.append(i)
        }
        if spatial.count < 2 {
            for i in 0..<shape.count where i != channelAxis && !spatial.contains(i) {
                spatial.append(i)
                if spatial.count >= 2 { break }
            }
        }
        spatial.sort()

        let yAxis = spatial[0]
        let xAxis = spatial[1]
        return (strides[yAxis], strides[xAxis], strides[channelAxis])
    }

    private func l2Normalized(_ vector: [Float]) -> [Float] {
        var result = vector
        let count = vDSP_Length(result.count)
        var sumOfSquares: Float = 0
        vDSP_svesq(result, 1, &sumOfSquares, count)
        var inverseNorm = 1.0 / sqrt(max(sumOfSquares, 1e-12))
        vDSP_vsmul(result, 1, &inverseNorm, &result, 1, count)
        return result
    }
}

class FaceMatcher: ObservableObject {
    // UI Binding State hooks matching your custom view layers exactly
    @Published var isScanning = false
    @Published var progress: Double = 0.0
    @Published var statusText = "STANDBY"
    @Published var matchedResults: [MatchResult] = []
    /// True once at least one scan has fully completed (even if no matches were found).
    @Published var hasScanned = false

    private var currentTask: Task<Void, Never>? = nil
    private let ciContext = CIContext(options: [.useSoftwareRenderer: false])
    private let embeddingModel: FaceEmbeddingModel?
    private let modelLoadError: Error?

    /// Max long-edge pixel size used when decoding a candidate photo for scanning.
    /// FaceNet ultimately resizes the face crop to 160×160, so resolutions much
    /// larger than this don't improve recognition quality but do massively slow
    /// disk decode and Vision face detection — and starve the UI thread.
    private let maxScanImageDimension: Int = 2400

    /// Minimum time between main-actor UI publishes during a scan.
    /// Smooth enough for the progress bar without flooding SwiftUI with re-renders.
    private let uiPublishInterval: TimeInterval = 0.12

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
            self.hasScanned = false
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
    ///
    /// Performance notes (vs. the original sequential implementation):
    /// - Files are processed in parallel via a bounded TaskGroup so disk decode,
    ///   Vision face detection and CoreML inference overlap.
    /// - Each candidate image is decoded at a capped long-edge resolution through
    ///   `ImageIO`. FaceNet only ever sees a 160×160 face crop, so the larger
    ///   originals were burning CPU and memory without improving recognition.
    /// - UI publishes (progress, status, matched results) are throttled to
    ///   `uiPublishInterval` so SwiftUI is not re-rendered on every file.
    func scanPartyFolder(selfieImage: NSImage, folderURL: URL, strictness: Double) async {
        currentTask?.cancel()

        let minimumSimilarity = minimumCosineSimilarity(for: strictness)
        let scanTask = Task { [weak self] in
            guard let self = self else { return }

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

            let allowedExtensions: Set<String> = ["jpg", "jpeg", "png", "heic"]
            let imageFiles = fileURLs.filter { allowedExtensions.contains($0.pathExtension.lowercased()) }
            let totalCount = imageFiles.count

            if totalCount == 0 {
                await MainActor.run {
                    self.isScanning = false
                    self.hasScanned = true
                    self.statusText = "EMPTY TARGET DIRECTORY COMPLETED"
                }
                return
            }

            await MainActor.run {
                self.statusText = "SCANNING 0/\(totalCount)"
            }

            // Leave one core for the UI; ANE/CoreML rarely benefits past ~4 in-flight
            // requests, so we cap accordingly to avoid memory spikes on large folders.
            let concurrency = max(2, min(6, ProcessInfo.processInfo.activeProcessorCount - 1))

            var publishedMatches: [MatchResult] = []
            var pendingMatches: [MatchResult] = []
            var processed = 0
            var lastPublish = Date(timeIntervalSince1970: 0)

            await withTaskGroup(of: MatchResult?.self) { group in
                var iterator = imageFiles.makeIterator()

                @discardableResult
                func enqueueNext() -> Bool {
                    guard !Task.isCancelled, let url = iterator.next() else { return false }
                    group.addTask { [weak self] in
                        guard let self = self else { return nil }
                        return await self.processFile(
                            fileURL: url,
                            targetEmbedding: targetEmbedding,
                            embeddingModel: embeddingModel,
                            minimumSimilarity: minimumSimilarity
                        )
                    }
                    return true
                }

                for _ in 0..<concurrency {
                    if !enqueueNext() { break }
                }

                while let result = await group.next() {
                    if Task.isCancelled {
                        group.cancelAll()
                        break
                    }

                    processed += 1
                    if let match = result {
                        pendingMatches.append(match)
                    }
                    enqueueNext()

                    let now = Date()
                    let elapsed = now.timeIntervalSince(lastPublish)
                    let isFinalTick = processed == totalCount
                    if elapsed >= self.uiPublishInterval || isFinalTick {
                        lastPublish = now

                        var matchesSnapshot: [MatchResult]? = nil
                        if !pendingMatches.isEmpty {
                            publishedMatches.append(contentsOf: pendingMatches)
                            pendingMatches.removeAll(keepingCapacity: true)
                            publishedMatches.sort { $0.similarity > $1.similarity }
                            matchesSnapshot = publishedMatches
                        }

                        let progressValue = Double(processed) / Double(totalCount)
                        let statusSnapshot = "SCANNING \(processed)/\(totalCount)"
                        await MainActor.run {
                            self.progress = progressValue
                            self.statusText = statusSnapshot
                            if let snapshot = matchesSnapshot {
                                self.matchedResults = snapshot
                            }
                        }
                    }
                }
            }

            let wasCancelled = Task.isCancelled
            if !pendingMatches.isEmpty {
                publishedMatches.append(contentsOf: pendingMatches)
                publishedMatches.sort { $0.similarity > $1.similarity }
            }
            let finalMatches = publishedMatches
            let totalFound = finalMatches.count

            await MainActor.run {
                if wasCancelled {
                    self.isScanning = false
                    self.progress = 0.0
                    self.matchedResults = finalMatches
                    self.statusText = "SCAN CANCELED BY USER"
                } else {
                    self.matchedResults = finalMatches
                    self.isScanning = false
                    self.hasScanned = true
                    self.statusText = totalFound == 0
                        ? "FACENET SCAN FINISHED: NO LOCAL RESULTS"
                        : "FACENET SCAN COMPLETE: \(totalFound) TARGETS FOUND"
                }
            }
        }

        currentTask = scanTask
        await scanTask.value
    }

    /// Per-file recognition pipeline. Safe to invoke from multiple concurrent tasks:
    /// `CIContext`, `MLModel` and `VNImageRequestHandler` instances are all
    /// thread-safe for concurrent reads.
    private func processFile(
        fileURL: URL,
        targetEmbedding: [Float],
        embeddingModel: FaceEmbeddingModel,
        minimumSimilarity: Float
    ) async -> MatchResult? {
        if Task.isCancelled { return nil }

        guard let cgImage = loadDownscaledCGImage(from: fileURL, maxPixelSize: maxScanImageDimension) else {
            return nil
        }

        do {
            let detectedFaces = try detectFaces(in: cgImage)
            let totalPeopleInPhoto = detectedFaces.count
            let usableFaces = detectedFaces.filter { isUsableFace($0, in: cgImage) }
            if usableFaces.isEmpty { return nil }

            var bestSimilarity: Float = -1.0
            for face in usableFaces {
                if Task.isCancelled { return nil }
                guard let croppedFace = cropFace(from: cgImage, boundingBox: face.boundingBox) else {
                    continue
                }
                let candidateEmbedding = try embeddingModel.embedding(from: croppedFace)
                let similarity = cosineSimilarity(candidateEmbedding, targetEmbedding)
                if similarity > bestSimilarity {
                    bestSimilarity = similarity
                }
                // Already a near-perfect match — no value in embedding the rest of
                // the faces in the same photo.
                if bestSimilarity >= 0.985 { break }
            }

            if bestSimilarity >= minimumSimilarity {
                return MatchResult(
                    fileURL: fileURL,
                    faceCount: totalPeopleInPhoto,
                    similarity: Double(max(0, min(1, bestSimilarity)))
                )
            }
        } catch {
            #if DEBUG
            print("FaceNet recognition skipped one selected file: \(error.localizedDescription)")
            #endif
        }
        return nil
    }

    /// Decodes the file at `url` to a CGImage no larger than `maxPixelSize` on the
    /// long edge, honoring EXIF orientation. Uses ImageIO's hardware-backed
    /// thumbnail path so memory usage stays bounded even for DSLR-sized originals.
    private func loadDownscaledCGImage(from url: URL, maxPixelSize: Int) -> CGImage? {
        let sourceOptions: [CFString: Any] = [
            kCGImageSourceShouldCache: false
        ]
        guard let source = CGImageSourceCreateWithURL(url as CFURL, sourceOptions as CFDictionary) else {
            return nil
        }
        let thumbOptions: [CFString: Any] = [
            kCGImageSourceCreateThumbnailFromImageAlways: true,
            kCGImageSourceCreateThumbnailWithTransform: true,
            kCGImageSourceShouldCacheImmediately: true,
            kCGImageSourceThumbnailMaxPixelSize: maxPixelSize
        ]
        return CGImageSourceCreateThumbnailAtIndex(source, 0, thumbOptions as CFDictionary)
    }

    private func detectFaces(in cgImage: CGImage) throws -> [VNFaceObservation] {
        let requestHandler = VNImageRequestHandler(cgImage: cgImage, options: [:])
        // Rectangles-only is materially faster than landmarks and we never read
        // landmark points; we only use confidence + boundingBox downstream.
        let request = VNDetectFaceRectanglesRequest()
        if #available(macOS 11.0, *) {
            request.revision = VNDetectFaceRectanglesRequestRevision3
        }
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

        let length = vDSP_Length(count)
        var dot: Float = 0
        var lhsNorm: Float = 0
        var rhsNorm: Float = 0
        vDSP_dotpr(lhs, 1, rhs, 1, &dot, length)
        vDSP_svesq(lhs, 1, &lhsNorm, length)
        vDSP_svesq(rhs, 1, &rhsNorm, length)

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

