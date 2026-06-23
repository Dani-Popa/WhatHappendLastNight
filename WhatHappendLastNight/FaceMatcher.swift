import Foundation
import Vision
import AppKit
import Combine
import CoreImage
import CoreML
import CoreVideo
import ImageIO
import Accelerate
import CryptoKit

struct MatchResult: Identifiable {
    let id = UUID()
    let fileURL: URL
    let faceCount: Int
    let similarity: Double
    /// Bounding box of the face that produced this match, in Vision's
    /// normalized coordinate space (origin bottom-left, 0..1 on each axis).
    /// `nil` when the result didn't come from the live scan (e.g. preview).
    let faceBoundingBox: CGRect?

    init(fileURL: URL,
         faceCount: Int,
         similarity: Double = 1.0,
         faceBoundingBox: CGRect? = nil) {
        self.fileURL = fileURL
        self.faceCount = faceCount
        self.similarity = similarity
        self.faceBoundingBox = faceBoundingBox
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

        let (yStride, xStride, cStride) = Self.spatialStrides(shape: normalizedShape, strides: strides)

        let scale: Float = 1.0 / 128.0
        let bias: Float = -127.5 / 128.0

        for y in 0..<imageSize {
            let row = src.advanced(by: y * bytesPerRow)
            let yOffset = y * yStride
            for x in 0..<imageSize {
                let pixel = row.advanced(by: x * 4)
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

    private static func spatialStrides(shape: [Int], strides: [Int]) -> (Int, Int, Int) {
        guard shape.count == strides.count, shape.count >= 3 else {
            return (shape.count >= 2 ? shape[1] * 3 : 3, 3, 1)
        }

        var channelAxis = shape.firstIndex(of: 3) ?? (shape.count - 1)
        if shape.filter({ $0 == 3 }).count > 1, shape.last == 3 {
            channelAxis = shape.count - 1
        }

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
    @Published var isScanning = false
    @Published var progress: Double = 0.0
    @Published var statusText = "STANDBY"
    @Published var matchedResults: [MatchResult] = []
    @Published var hasScanned = false
    /// Wall-clock time the most recent completed scan took, in seconds. `nil`
    /// until a scan finishes (or after `clearResults`) so the UI can tell the
    /// "never scanned" state apart from a real zero-duration measurement.
    @Published var lastScanDuration: TimeInterval? = nil

    private var currentTask: Task<Void, Never>? = nil
    private let ciContext = CIContext(options: [.useSoftwareRenderer: false])
    private let embeddingModel: FaceEmbeddingModel?
    private let modelLoadError: Error?

    private let maxScanImageDimension: Int = 2400
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
            self.lastScanDuration = nil
        }
    }

    private func cleanupScanningState(finalStatus: String) {
        DispatchQueue.main.async {
            self.isScanning = false
            self.progress = 0.0
            self.statusText = finalStatus
        }
    }

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

    /// A cheap content fingerprint used to detect duplicate copies of the same
    /// photo across different subfolders. Combines the file size with a hash of
    /// the first 256 KB, which uniquely separates distinct photos while reading
    /// only a small slice of each file. Falls back to the full path if the file
    /// can't be read, so unreadable files are never wrongly merged.
    private static func contentSignature(for url: URL) -> String {
        let size = (try? url.resourceValues(forKeys: [.fileSizeKey]).fileSize) ?? -1
        guard let handle = try? FileHandle(forReadingFrom: url) else {
            return "path:\(url.path)"
        }
        defer { try? handle.close() }
        let head = (try? handle.read(upToCount: 256 * 1024)) ?? Data()
        var hasher = SHA256()
        hasher.update(data: Data("\(size)|".utf8))
        hasher.update(data: head)
        return hasher.finalize().map { String(format: "%02x", $0) }.joined()
    }

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
                // Reset any previous duration so the header doesn't display a
                // stale "scanned in 12s" label while the new scan is in flight.
                self.lastScanDuration = nil
            }

            // Time the full scan — folder enumeration, embedding inference,
            // and result aggregation — so the UI can show how long it took.
            let scanStartTime = Date()

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

            // The selected folder is security-scoped under the macOS sandbox.
            // Activate access so the deep enumerator can open descriptors inside
            // subfolders (fresh panel URLs return false but are still usable).
            let didStartAccess = folderURL.startAccessingSecurityScopedResource()
            defer { if didStartAccess { folderURL.stopAccessingSecurityScopedResource() } }

            // Recursively walk the selected folder and every subfolder. The error
            // handler keeps the walk going if one subfolder can't be read.
            guard let enumerator = fileManager.enumerator(
                at: folderURL,
                includingPropertiesForKeys: keys,
                options: [.skipsHiddenFiles, .skipsPackageDescendants],
                errorHandler: { _, _ in true }
            ) else {
                await MainActor.run {
                    self.isScanning = false
                    self.statusText = "ERROR: INVALID REPOSITORY TARGET LOCATION"
                }
                return
            }

            let allowedExtensions: Set<String> = ["jpg", "jpeg", "png", "heic"]
            var imageFiles: [URL] = []
            // De-duplicate identical photos that appear in more than one
            // subfolder so the same image isn't listed multiple times.
            var seenSignatures = Set<String>()
            for case let url as URL in enumerator {
                guard allowedExtensions.contains(url.pathExtension.lowercased()) else { continue }
                let signature = Self.contentSignature(for: url)
                if seenSignatures.insert(signature).inserted {
                    imageFiles.append(url)
                }
            }
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
            let scanDuration = Date().timeIntervalSince(scanStartTime)

            await MainActor.run {
                if wasCancelled {
                    self.isScanning = false
                    self.progress = 0.0
                    self.matchedResults = finalMatches
                    self.statusText = "SCAN CANCELED BY USER"
                    // Cancelled runs don't get a duration label — the number
                    // would be misleading since work stopped partway through.
                    self.lastScanDuration = nil
                } else {
                    self.matchedResults = finalMatches
                    self.isScanning = false
                    self.hasScanned = true
                    self.lastScanDuration = scanDuration
                    self.statusText = totalFound == 0
                        ? "FACENET SCAN FINISHED: NO LOCAL RESULTS"
                        : "FACENET SCAN COMPLETE: \(totalFound) TARGETS FOUND"
                }
            }
        }

        currentTask = scanTask
        await scanTask.value
    }

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
            var bestFaceBox: CGRect? = nil
            for face in usableFaces {
                if Task.isCancelled { return nil }
                guard let croppedFace = cropFace(from: cgImage, boundingBox: face.boundingBox) else {
                    continue
                }
                let candidateEmbedding = try embeddingModel.embedding(from: croppedFace)
                let similarity = cosineSimilarity(candidateEmbedding, targetEmbedding)

                #if DEBUG
                print("Score: \(similarity) - File: \(fileURL.lastPathComponent)")
                #endif

                if similarity > bestSimilarity {
                    bestSimilarity = similarity
                    // Remember which face in the photo produced the best score —
                    // the lightbox uses it to draw an overlay so the user knows
                    // which person in a group shot was matched.
                    bestFaceBox = face.boundingBox
                }
                if bestSimilarity >= 0.985 { break }
            }

            if bestSimilarity >= minimumSimilarity {
                // Persist the user-facing confidence (remapped from cosine) so
                // displayed match percentages line up with the slider's units —
                // a 60% match means "passes a 60% strictness threshold."
                return MatchResult(
                    fileURL: fileURL,
                    faceCount: totalPeopleInPhoto,
                    similarity: Self.displayConfidence(from: bestSimilarity),
                    faceBoundingBox: bestFaceBox
                )
            }
        } catch {
            #if DEBUG
            print("FaceNet recognition skipped one selected file: \(error.localizedDescription)")
            #endif
        }
        return nil
    }

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
        let request = VNDetectFaceRectanglesRequest()
        if #available(macOS 11.0, *) {
            request.revision = VNDetectFaceRectanglesRequestRevision3
        }
        try requestHandler.perform([request])
        return request.results ?? []
    }

    private func isUsableFace(_ face: VNFaceObservation, in cgImage: CGImage) -> Bool {
        // Slightly looser confidence threshold — Vision rates partial-profile
        // and side-lit faces lower, and we don't want to drop them before
        // FaceNet even gets a look.
        guard face.confidence >= 0.55 else { return false }

        let rect = VNImageRectForNormalizedRect(face.boundingBox, cgImage.width, cgImage.height)
        // 36×36px minimum — below this FaceNet's 160×160 input upscale loses
        // too much detail to be reliable, but anything larger should be
        // given a chance even at the back of a group shot.
        guard rect.width >= 36, rect.height >= 36 else { return false }

        return true
    }

    private func cropFace(from cgImage: CGImage, boundingBox: CGRect) -> CGImage? {
        let imageWidth = CGFloat(cgImage.width)
        let imageHeight = CGFloat(cgImage.height)
        let imageRect = CGRect(x: 0, y: 0, width: imageWidth, height: imageHeight)

        let rawRect = VNImageRectForNormalizedRect(boundingBox, Int(imageWidth), Int(imageHeight))
        let maxDimension = max(rawRect.width, rawRect.height)

        // Adjust vertical coordinate up slightly to capture the complete forehead area
        let center = CGPoint(x: rawRect.midX, y: rawRect.midY + (rawRect.height * 0.12))
        let paddedSize = maxDimension * 1.50

        var squareRect = CGRect(
            x: center.x - (paddedSize / 2),
            y: center.y - (paddedSize / 2),
            width: paddedSize,
            height: paddedSize
        ).integral

        if squareRect.minX < 0 { squareRect.origin.x = 0 }
        if squareRect.minY < 0 { squareRect.origin.y = 0 }
        if squareRect.maxX > imageWidth { squareRect.origin.x = imageWidth - squareRect.width }
        if squareRect.maxY > imageHeight { squareRect.origin.y = imageHeight - squareRect.height }

        squareRect = squareRect.intersection(imageRect).integral
        guard squareRect.width >= 55, squareRect.height >= 55 else { return nil }

        let ciImage = CIImage(cgImage: cgImage)
        let croppedImage = ciImage.cropped(to: squareRect)
        return ciContext.createCGImage(croppedImage, from: squareRect)
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

    // MARK: - Confidence scaling
    //
    // FaceNet cosine similarity has a narrow useful band: roughly 0.55 is the
    // noise floor where two *different* human faces tend to land, and 0.95+
    // is the regime where you can be confident two crops are the same person.
    // Showing the raw 0.0–1.0 value directly was misleading — a "62% match"
    // displayed as a percentage feels meaningful, but in cosine space it's
    // essentially "this is some human face." We remap that 0.55–0.95 band
    // onto the user-facing 0–100% confidence scale so both the strictness
    // slider and displayed match scores correspond to the user's intuition.

    /// Lower bound of the useful FaceNet cosine band. Set below the typical
    /// noise floor so the slider's loose end reaches real matches in tough
    /// conditions (side angle, harsh lighting, user in back of a group),
    /// whose genuine same-person scores can dip into 0.55–0.65.
    static let cosineFloor: Float = 0.45
    /// Upper bound — at or above this we treat the match as essentially certain.
    /// Deliberately tight (0.80) so real same-person matches at cosine
    /// 0.65–0.75 — the common range for varied real-world photos — land in
    /// the 50–85% displayed range and feel like confident matches rather
    /// than weak ones.
    static let cosineCeiling: Float = 0.80

    /// Maximum value the displayed confidence can reach. Capped below 100%
    /// because face matching is never truly certain — claiming a perfect
    /// match would overstate what the model actually knows.
    static let displayCeiling: Double = 0.95

    /// Maps a raw cosine similarity onto the user-facing confidence scale.
    /// Floor maps to 0%, ceiling maps to `displayCeiling` (95%), and very
    /// strong matches above the ceiling are clamped to that same 95% — we
    /// never display 100%.
    static func displayConfidence(from cosine: Float) -> Double {
        let clamped = max(cosineFloor, min(cosineCeiling, cosine))
        let normalized = Double((clamped - cosineFloor) / (cosineCeiling - cosineFloor))
        return min(normalized, displayCeiling)
    }

    /// Inverse of `displayConfidence` — maps the slider position (0..1 in
    /// confidence units) back to the raw cosine cutoff used for filtering.
    static func cosineCutoff(forConfidence strictness: Double) -> Float {
        let clamped = Float(max(0.0, min(1.0, strictness)))
        return cosineFloor + clamped * (cosineCeiling - cosineFloor)
    }

    private func minimumCosineSimilarity(for strictness: Double) -> Float {
        Self.cosineCutoff(forConfidence: strictness)
    }
}
