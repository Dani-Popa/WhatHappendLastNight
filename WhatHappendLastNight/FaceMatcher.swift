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
            return "Face recognition CoreML model not found. Add one of these to the app target: \(names.map { $0 + ".mlmodel(c) or .mlpackage" }.joined(separator: ", "))"
        case .modelHasNoInputs:
            return "The CoreML model has no input description."
        case .modelHasNoOutputs:
            return "The CoreML model has no output description."
        case .unsupportedInputType(let type):
            return "Unsupported model input type: \(type). Expected image or MLMultiArray."
        case .pixelBufferCreationFailed:
            return "Could not create the normalized face pixel buffer."
        case .pixelBufferContextFailed:
            return "Could not create CGContext for face preprocessing."
        case .missingModelOutput(let name):
            return "The model did not return output named \(name)."
        case .unsupportedModelOutput:
            return "The model output is not an MLMultiArray embedding."
        case .noFaceDetected:
            return "No usable face detected."
        }
    }
}

/// Which face recognition architecture is loaded. Preprocessing, channel
/// order, and the useful cosine band all differ between FaceNet (Inception
/// ResNet, 160×160 RGB, [-1,1]) and AdaFace (IResNet, 112×112 BGR, [-1,1]).
/// We carry the kind alongside the model so inference and confidence scaling
/// can fork on it without scattering string-matching across the file.
enum FaceModelKind {
    case facenet
    case adaface
    /// David Sandberg's pretrained FaceNet checkpoint (`20180402-114759`,
    /// Inception-ResNet-v1 trained on VGGFace2, 512-d embedding, 160×160 RGB).
    /// Same preprocessing as `.facenet` but kept as a distinct kind so the
    /// picker can advertise it separately and we can swap weights at runtime.
    case facenet512

    /// Best-guess from the model's file name. AdaFace and ArcFace-family
    /// backbones (IResNet "IR18/IR50/IR100") all use the same preprocessing
    /// and cosine band, so we lump them together as `.adaface`. The Sandberg
    /// VGGFace2 checkpoint is detected by its timestamped name or any of the
    /// usual aliases.
    static func infer(from modelFileName: String) -> FaceModelKind {
        let lower = modelFileName.lowercased()
        if lower.contains("adaface")
            || lower.contains("arcface")
            || lower.contains("ir18")
            || lower.contains("ir50")
            || lower.contains("ir100")
            || lower.contains("iresnet") {
            return .adaface
        }
        if lower.contains("20180402")
            || lower.contains("vggface2")
            || lower.contains("facenet512")
            || lower.contains("facenet_512") {
            return .facenet512
        }
        return .facenet
    }

    /// FaceNet's TF-style preprocessing — `(x - 127.5) / 128` — vs. AdaFace's
    /// PyTorch-style `(x - 127.5) / 127.5`. Functionally close, but using the
    /// exact training-time normalization noticeably improves cosine scores.
    var pixelScale: Float {
        switch self {
        case .facenet, .facenet512: return 1.0 / 128.0
        case .adaface: return 1.0 / 127.5
        }
    }

    var pixelBias: Float {
        switch self {
        case .facenet, .facenet512: return -127.5 / 128.0
        case .adaface: return -1.0
        }
    }

    /// AdaFace was trained on BGR-ordered crops (ArcFace lineage); FaceNet on
    /// RGB. Getting this wrong silently halves the model's accuracy — the
    /// network still produces an embedding, just a worse one — so it's worth
    /// being explicit here.
    var useBGRChannelOrder: Bool {
        switch self {
        case .facenet, .facenet512: return false
        case .adaface: return true
        }
    }

    /// Fallback input size if the model description doesn't expose one.
    /// FaceNet ships at 160; AdaFace/ArcFace IResNet variants at 112.
    var fallbackImageSize: Int {
        switch self {
        case .facenet, .facenet512: return 160
        case .adaface: return 112
        }
    }

    /// Padding multiplier applied to the detected face bounding box when
    /// producing a loose square crop. The optimal value depends on what the
    /// network was trained to see:
    /// - AdaFace (ArcFace lineage): MTCNN-aligned crops where the face fills
    ///   the frame and the InsightFace template places eyes ~10px from the
    ///   edges of a 112-px image (≈9% margin). Anything looser puts the
    ///   network well off-distribution. ~1.20x bbox is the sweet spot.
    /// - FaceNet512 (Sandberg VGGFace2 / 20180402-114759): MTCNN with a
    ///   32-px margin on a 160-px crop ≈ 1.30x bbox padding.
    /// - Facenet6 (legacy triplet loss): trained on loose, unaligned crops;
    ///   the original 1.50x padding matches its training distribution.
    /// Wrong padding silently degrades cosine scores — the network still
    /// embeds, just on a frame that doesn't match what it saw in training.
    var cropPadding: CGFloat {
        switch self {
        case .adaface:    return 1.20
        case .facenet512: return 1.30
        case .facenet:    return 1.50
        }
    }

    /// Fraction of the bounding-box height by which the crop center is shifted
    /// upward, to include more forehead and less neck. Tuned per model:
    /// - Tight AdaFace crops lose the chin if shifted much, so 6%.
    /// - FaceNet512's MTCNN training distribution sits roughly centered, 8%.
    /// - Facenet6's loose training crops tended to sit lower, leave at 12%.
    var cropVerticalShift: CGFloat {
        switch self {
        case .adaface:    return 0.06
        case .facenet512: return 0.08
        case .facenet:    return 0.12
        }
    }

    /// Side length the aligned crop should be rendered at. We render at the
    /// network's native input size so the embedder doesn't re-resample.
    /// AdaFace wants 112; the two FaceNet variants want 160. Rendering a
    /// 112-pixel aligned crop and then upscaling to 160 inside the embedder
    /// loses ~22% of pixel area to interpolation, which measurably degrades
    /// the embedding on FaceNet512.
    var alignedCropSize: Int {
        switch self {
        case .adaface:    return 112
        case .facenet, .facenet512: return 160
        }
    }

    /// Short, user-facing label shown in the toolbar picker.
    var displayName: String {
        switch self {
        case .facenet: return "FaceNet"
        case .adaface: return "AdaFace"
        case .facenet512: return "FaceNet 512"
        }
    }

    /// One-line description used in the picker menu so the user can tell why
    /// they'd pick one over the other without digging into the source.
    var blurb: String {
        switch self {
        case .facenet: return "Inception ResNet · 160×160 · legacy"
        case .adaface: return "IResNet IR18 · 112×112 · recommended"
        case .facenet512: return "VGGFace2 · 160×160 · 512-d (Sandberg)"
        }
    }

    /// SF Symbol used as the picker's leading icon.
    var sfSymbol: String {
        switch self {
        case .facenet: return "person.crop.square"
        case .adaface: return "person.crop.square.badge.checkmark"
        case .facenet512: return "person.crop.square.filled.and.at.rectangle"
        }
    }
}

private extension Array where Element: Hashable {
    /// Stable de-dup — preserves first occurrence order. Used to build the
    /// model load chain without listing the preferred kind twice.
    func uniqued() -> [Element] {
        var seen = Set<Element>()
        return filter { seen.insert($0).inserted }
    }
}

final class FaceEmbeddingModel {
    /// Try these in order, AdaFace first. Both " 2" and underscore variants
    /// are listed because Finder appends " 2" when duplicating a file and the
    /// user may drag either spelling into Xcode. Xcode compiles .mlpackage
    /// directly to .mlmodelc at build time, so we look for that extension.
    static let adafaceModelNames = [
        "AdaFace_IR18",
        "AdaFace_IR18 2",
        "AdaFace-IR18",
        "AdaFaceIR18",
        "AdaFace_IR50",
        "AdaFace",
        "ArcFace",
        "ArcFace_IR18"
    ]

    static let facenetModelNames = [
        "Facenet6",
        "FaceNet",
        "facenet",
        "Facenet",
        "InceptionResnetV1",
        "model"
    ]

    /// David Sandberg's `20180402-114759` checkpoint, once converted to
    /// CoreML. Finder strips the leading digit on duplicates and Xcode
    /// normalizes underscores, so we list a few common spellings.
    static let facenet512ModelNames = [
        "20180402-114759",
        "20180402_114759",
        "FaceNet512_VGGFace2",
        "FaceNet512",
        "FaceNetVGGFace2",
        "facenet512"
    ]

    /// Default load order — try every AdaFace candidate, then the new
    /// 512-d FaceNet, then fall back to the legacy FaceNet bundle.
    /// Whichever name actually exists in the bundle wins.
    static let defaultModelNames = adafaceModelNames + facenet512ModelNames + facenetModelNames

    let kind: FaceModelKind
    private let model: MLModel
    private let inputName: String
    private let outputName: String
    private let inputDescription: MLFeatureDescription
    private let imageSize: Int
    private let ciContext = CIContext(options: [.useSoftwareRenderer: false])

    init(modelNames: [String] = FaceEmbeddingModel.defaultModelNames) throws {
        let (modelURL, resolvedName) = try Self.findCompiledModelURL(modelNames: modelNames)
        let configuration = MLModelConfiguration()
        configuration.computeUnits = .all

        self.model = try MLModel(contentsOf: modelURL, configuration: configuration)
        self.kind = FaceModelKind.infer(from: resolvedName)

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
        self.imageSize = Self.inferImageSize(from: firstInput.value) ?? kind.fallbackImageSize

        #if DEBUG
        print("Loaded face model: \(modelURL.lastPathComponent) [\(kind)], input: \(inputName), output: \(outputName), size: \(imageSize)x\(imageSize)")
        #endif
    }

    /// Cheap availability probe. Walks the bundle for any of the supplied
    /// candidate names with `.mlmodelc` (Xcode-compiled) or `.mlmodel` (raw)
    /// extensions, without actually loading the model. The picker UI uses
    /// this to decide which options to enable.
    static func isAnyResourceBundled(names: [String]) -> Bool {
        for name in names {
            if Bundle.main.url(forResource: name, withExtension: "mlmodelc") != nil { return true }
            if Bundle.main.url(forResource: name, withExtension: "mlmodel") != nil { return true }
        }
        return false
    }

    /// Returns the resolved bundle URL together with the resource name we
    /// matched on — the name drives `FaceModelKind` inference so the caller
    /// can't accidentally lose track of which architecture is loaded.
    private static func findCompiledModelURL(modelNames: [String]) throws -> (URL, String) {
        for name in modelNames {
            if let compiled = Bundle.main.url(forResource: name, withExtension: "mlmodelc") {
                return (compiled, name)
            }
            if let raw = Bundle.main.url(forResource: name, withExtension: "mlmodel") {
                return (try MLModel.compileModel(at: raw), name)
            }
        }

        // Last-resort discovery: if exactly one compiled model is bundled,
        // use it. The file name still drives kind inference.
        let bundledCompiledModels = Bundle.main.urls(forResourcesWithExtension: "mlmodelc", subdirectory: nil) ?? []
        if bundledCompiledModels.count == 1, let onlyModel = bundledCompiledModels.first {
            let stem = onlyModel.deletingPathExtension().lastPathComponent
            return (onlyModel, stem)
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

        // Fast path: a contiguous Float32 embedding (the [1,512] output of all
        // three models) can be copied straight from the backing buffer instead
        // of boxing every element through NSNumber. Falls back to the safe
        // element-wise read for any other dtype/layout.
        let vector: [Float]
        if outputArray.dataType == .float32,
           outputArray.strides.last?.intValue == 1 {
            let ptr = outputArray.dataPointer.assumingMemoryBound(to: Float.self)
            vector = Array(UnsafeBufferPointer(start: ptr, count: outputArray.count))
        } else {
            var v = [Float]()
            v.reserveCapacity(outputArray.count)
            for index in 0..<outputArray.count {
                v.append(outputArray[index].floatValue)
            }
            vector = v
        }

        return l2Normalized(vector)
    }

    /// Test-time augmentation: embed both the original crop and its horizontal
    /// flip, then average. Standard AdaFace/ArcFace inference trick — costs
    /// 2× the per-face latency but eliminates pose-dependent embedding noise
    /// (faces rarely sit perfectly head-on, and a network trained on randomly
    /// flipped data is invariant to mirror reflection). FaceNet gains less
    /// from this (its embedding is already fairly flip-invariant from its
    /// triplet loss training), so we only apply TTA when AdaFace is loaded.
    func embeddingWithTTA(from faceCGImage: CGImage) throws -> [Float] {
        // TTA helps the alignment-trained models (AdaFace and the Sandberg
        // 512-d FaceNet, both trained on MTCNN-aligned faces with random
        // horizontal flips). The legacy Facenet6.mlmodel was trained on
        // loose, unaligned crops with a triplet loss that's already fairly
        // flip-invariant, so TTA there is a wash.
        guard kind == .adaface || kind == .facenet512 else {
            return try embedding(from: faceCGImage)
        }

        let original = try embedding(from: faceCGImage)

        // Horizontal flip via CIImage. The flip transform mirrors around
        // x=0 and shifts back so the image stays in positive coords —
        // CIImage's coordinate system is bottom-left origin so we only flip
        // X, not Y.
        let flippedCI = CIImage(cgImage: faceCGImage)
            .transformed(by: CGAffineTransform(scaleX: -1, y: 1)
                .translatedBy(x: -CGFloat(faceCGImage.width), y: 0))
        let flippedExtent = CGRect(x: 0, y: 0,
                                   width: faceCGImage.width,
                                   height: faceCGImage.height)
        guard let flippedCG = ciContext.createCGImage(flippedCI, from: flippedExtent) else {
            // If we can't render the flip, fall back to the unaugmented
            // embedding — better to have a slightly worse result than to
            // fail the whole match.
            return original
        }

        let flipped = try embedding(from: flippedCG)

        // Both embeddings are already L2-normalized by `embedding(from:)`,
        // so summing then re-normalizing gives us the unit-length midpoint
        // direction, which is what we want.
        var combined = [Float](repeating: 0, count: min(original.count, flipped.count))
        for i in 0..<combined.count {
            combined[i] = original[i] + flipped[i]
        }
        let count = vDSP_Length(combined.count)
        var sumOfSquares: Float = 0
        vDSP_svesq(combined, 1, &sumOfSquares, count)
        var inverseNorm = 1.0 / sqrt(max(sumOfSquares, 1e-12))
        vDSP_vsmul(combined, 1, &inverseNorm, &combined, 1, count)
        return combined
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

        // Preprocessing differs per architecture — see `FaceModelKind` for
        // the exact constants. The pixel buffer is always BGRA (we create it
        // with `kCVPixelFormatType_32BGRA` upstream), so we read B/G/R from
        // fixed byte offsets here and only the *write order* into the tensor
        // changes between FaceNet (RGB) and AdaFace (BGR).
        let scale: Float = kind.pixelScale
        let bias: Float = kind.pixelBias
        // BGRA byte offsets: 0=B, 1=G, 2=R. AdaFace wants B,G,R written into
        // channels 0,1,2; FaceNet wants R,G,B. Resolve the order once, then
        // read three scalars per pixel directly — no per-pixel `[Float]`
        // allocation. This loop runs imageSize² times per embedding (25,600×
        // for Facenet6's 160×160 MultiArray input), and the old array literal
        // heap-allocated on every iteration. Output is bit-identical (verified
        // numerically for both BGR and RGB write orders).
        let useBGR = kind.useBGRChannelOrder

        for y in 0..<imageSize {
            let row = src.advanced(by: y * bytesPerRow)
            let yOffset = y * yStride
            for x in 0..<imageSize {
                let pixel = row.advanced(by: x * 4)
                let b = Float(pixel[0])
                let g = Float(pixel[1])
                let r = Float(pixel[2])
                let c0: Float, c1: Float, c2: Float
                if useBGR { c0 = b; c1 = g; c2 = r } else { c0 = r; c1 = g; c2 = b }
                let base = yOffset + x * xStride
                dst[base + 0 * cStride] = c0 * scale + bias
                dst[base + 1 * cStride] = c1 * scale + bias
                dst[base + 2 * cStride] = c2 * scale + bias
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
    /// The active embedder. Marked `@Published` so the toolbar can show which
    /// architecture is loaded and react when the user switches models.
    @Published private(set) var embeddingModel: FaceEmbeddingModel? = nil
    /// Which architectures are actually bundled with this build. Used by the
    /// model picker UI to disable choices that aren't available so users
    /// aren't offered options that would silently fail.
    @Published private(set) var availableKinds: Set<FaceModelKind> = []
    @Published private(set) var modelLoadError: Error? = nil

    /// Convenience for SwiftUI bindings — current architecture, or `nil` if
    /// nothing loaded.
    var activeKind: FaceModelKind? { embeddingModel?.kind }

    /// UserDefaults key for the user's chosen architecture. Persisted so the
    /// picker remembers the choice between launches.
    private static let preferredKindDefaultsKey = "FaceMatcher.preferredModelKind"

    private let maxScanImageDimension: Int = 2400
    private let uiPublishInterval: TimeInterval = 0.12

    init(modelNames: [String] = FaceEmbeddingModel.defaultModelNames) {
        // Probe the bundle to see which architectures the build actually ships
        // with. This drives both the picker UI (so options aren't enabled when
        // the file isn't there) and the load fallback chain below.
        var available: Set<FaceModelKind> = []
        if FaceEmbeddingModel.isAnyResourceBundled(names: FaceEmbeddingModel.adafaceModelNames) {
            available.insert(.adaface)
        }
        if FaceEmbeddingModel.isAnyResourceBundled(names: FaceEmbeddingModel.facenetModelNames) {
            available.insert(.facenet)
        }
        if FaceEmbeddingModel.isAnyResourceBundled(names: FaceEmbeddingModel.facenet512ModelNames) {
            available.insert(.facenet512)
        }
        self.availableKinds = available

        // Load order: previously-chosen kind (if available) > AdaFace > FaceNet > FaceNet 512.
        // Each branch falls through to the next on failure so an unconfigured
        // build still works the same as before.
        let savedKind = Self.loadSavedKind()
        let loadOrder: [FaceModelKind]
        switch savedKind {
        case .some(let kind) where available.contains(kind):
            loadOrder = [kind, .adaface, .facenet, .facenet512].uniqued()
        default:
            loadOrder = [.adaface, .facenet, .facenet512]
        }

        for kind in loadOrder {
            do {
                let model = try FaceEmbeddingModel(modelNames: Self.modelNames(for: kind) + modelNames)
                self.embeddingModel = model
                self.modelLoadError = nil
                #if DEBUG
                print("Face matcher using \(kind) model.")
                #endif
                return
            } catch {
                #if DEBUG
                print("Could not load \(kind) model: \(error.localizedDescription)")
                #endif
                self.modelLoadError = error
            }
        }

        // Nothing loaded — `embeddingModel` stays nil and the UI will surface
        // `modelLoadError` from the last attempt.
        self.embeddingModel = nil
    }

    /// Switch architectures at runtime. Used by the toolbar picker. Returns
    /// `true` if the swap succeeded; on failure the existing model is kept so
    /// the user can keep scanning while they fix the bundling issue.
    @discardableResult
    func selectModel(_ kind: FaceModelKind) -> Bool {
        // No-op if it's already loaded — avoid the cost of recompiling the
        // CoreML model just because the picker re-emitted the same value.
        if embeddingModel?.kind == kind { return true }

        do {
            let model = try FaceEmbeddingModel(modelNames: Self.modelNames(for: kind))
            DispatchQueue.main.async {
                self.embeddingModel = model
                self.modelLoadError = nil
                self.statusText = "MODEL SET: \(kind.displayName.uppercased())"
            }
            Self.saveKind(kind)
            #if DEBUG
            print("Face matcher switched to \(kind) model.")
            #endif
            return true
        } catch {
            DispatchQueue.main.async {
                self.modelLoadError = error
                self.statusText = "ERROR: \(error.localizedDescription)"
            }
            #if DEBUG
            print("Failed to switch to \(kind) model: \(error.localizedDescription)")
            #endif
            return false
        }
    }

    private static func modelNames(for kind: FaceModelKind) -> [String] {
        switch kind {
        case .adaface: return FaceEmbeddingModel.adafaceModelNames
        case .facenet: return FaceEmbeddingModel.facenetModelNames
        case .facenet512: return FaceEmbeddingModel.facenet512ModelNames
        }
    }

    private static func loadSavedKind() -> FaceModelKind? {
        guard let raw = UserDefaults.standard.string(forKey: preferredKindDefaultsKey) else {
            return nil
        }
        switch raw {
        case "adaface": return .adaface
        case "facenet": return .facenet
        case "facenet512": return .facenet512
        default: return nil
        }
    }

    private static func saveKind(_ kind: FaceModelKind) {
        let raw: String
        switch kind {
        case .adaface: raw = "adaface"
        case .facenet: raw = "facenet"
        case .facenet512: raw = "facenet512"
        }
        UserDefaults.standard.set(raw, forKey: preferredKindDefaultsKey)
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

    /// Extracts one or more anchor embeddings from the selfie. The match
    /// pipeline scores each candidate face against every anchor and keeps the
    /// best (max) similarity — this is the "multi-anchor" trick that helps
    /// when the user's selfie was taken at a different angle/crop than the
    /// party photos. For AdaFace we generate two anchors (landmark-aligned
    /// and bounding-box-cropped); for FaceNet a single anchor is enough since
    /// it was trained on loose crops anyway.
    private func extractTargetFaceEmbeddings(from nsImage: NSImage, using model: FaceEmbeddingModel) throws -> [[Float]] {
        guard let cgImage = nsImage.cgImage(forProposedRect: nil, context: nil, hints: nil) else {
            throw FaceMatcherError.noFaceDetected
        }

        let faces = try detectFaces(in: cgImage).filter { isUsableFace($0, in: cgImage) }
        guard let largestFace = faces.max(by: {
            ($0.boundingBox.width * $0.boundingBox.height) < ($1.boundingBox.width * $1.boundingBox.height)
        }) else {
            throw FaceMatcherError.noFaceDetected
        }

        var anchors: [[Float]] = []

        // Up to two anchors for AdaFace, one for FaceNet. The match pipeline
        // takes max similarity across all anchors, so more anchors only
        // increases recall (at the cost of selfie-side setup time, which is
        // a one-shot per scan).

        // Anchor 1 (alignment-trained models, frontal selfies only):
        // eye-pupil-aligned crop. The strongest anchor when available —
        // matches the training distribution of AdaFace and the Sandberg
        // 512-d FaceNet (both expect MTCNN-aligned input). Skipped for
        // profile selfies via the yaw gate inside `alignedFaceCrop`.
        let kindWantsAlignment = model.kind == .adaface || model.kind == .facenet512
        if kindWantsAlignment,
           let alignedCrop = alignedFaceCrop(from: cgImage, observation: largestFace, kind: model.kind) {
            if let embedding = try? model.embeddingWithTTA(from: alignedCrop) {
                anchors.append(embedding)
            }
        }

        // Anchor 2 (all kinds): padded bounding-box crop. Always included —
        // it's the universal anchor that matches photos where alignment
        // failed (profile views) or where the user's selfie was itself a
        // profile. TTA only applies when the selfie is frontal and the
        // model benefits from it (alignment-trained kinds).
        let selfieIsProfile = isProfileFace(largestFace)
        if let croppedFace = cropFace(from: cgImage, boundingBox: largestFace.boundingBox, kind: model.kind) {
            let useTTA = kindWantsAlignment && !selfieIsProfile
            let embedding = try (useTTA
                ? model.embeddingWithTTA(from: croppedFace)
                : model.embedding(from: croppedFace))
            anchors.append(embedding)
        }

        guard !anchors.isEmpty else {
            throw FaceMatcherError.noFaceDetected
        }
        return anchors
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
                self.statusText = "LOADING FACE RECOGNITION CORE..."
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
                    self.statusText = "ERROR: \(self.modelLoadError?.localizedDescription ?? "FACE MODEL MISSING")"
                }
                return
            }

            let targetEmbeddings: [[Float]]
            do {
                targetEmbeddings = try self.extractTargetFaceEmbeddings(from: selfieImage, using: embeddingModel)
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
                            targetEmbeddings: targetEmbeddings,
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
                        ? "SCAN FINISHED: NO LOCAL RESULTS"
                        : "SCAN COMPLETE: \(totalFound) TARGETS FOUND"
                }
            }
        }

        currentTask = scanTask
        await scanTask.value
    }

    private func processFile(
        fileURL: URL,
        targetEmbeddings: [[Float]],
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

                // Crop strategy for alignment-trained models (AdaFace and
                // the Sandberg 512-d FaceNet): eye-pupil alignment for
                // frontal/3-quarter faces, loose bounding-box crop for
                // profile faces (where eye alignment is unreliable because
                // one pupil is occluded). The yaw check inside
                // `alignedFaceCrop` returns nil on profiles so the `??`
                // falls through. The legacy Facenet6 always takes the loose
                // crop — it was trained that way.
                let preparedCrop: CGImage?
                let kindWantsAlignment = embeddingModel.kind == .adaface
                    || embeddingModel.kind == .facenet512
                if kindWantsAlignment {
                    preparedCrop = alignedFaceCrop(from: cgImage, observation: face, kind: embeddingModel.kind)
                        ?? cropFace(from: cgImage, boundingBox: face.boundingBox, kind: embeddingModel.kind)
                } else {
                    preparedCrop = cropFace(from: cgImage, boundingBox: face.boundingBox, kind: embeddingModel.kind)
                }
                guard let croppedFace = preparedCrop else { continue }

                // TTA averages the original embedding with its horizontal flip.
                // For *frontal* faces that's a free accuracy boost (the model
                // is flip-equivariant, so the two embeddings should agree).
                // For *profile* faces it averages a left-facing view with a
                // right-facing one — two different views of the same person —
                // producing a chimera embedding that matches neither. So we
                // gate TTA off on profiles.
                let useTTA = kindWantsAlignment && !isProfileFace(face)
                let candidateEmbedding = useTTA
                    ? try embeddingModel.embeddingWithTTA(from: croppedFace)
                    : try embeddingModel.embedding(from: croppedFace)

                // Multi-anchor: score against every selfie anchor and take
                // the max. The target person's true embedding only has to be
                // close to *one* of our anchors to count as a match — this
                // dramatically improves recall for selfies that don't match
                // the crop style of the photos being scanned.
                var similarity: Float = -1.0
                for anchor in targetEmbeddings {
                    let score = cosineSimilarity(candidateEmbedding, anchor)
                    if score > similarity { similarity = score }
                }

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
                // Early-out at "definitely the same person" so we don't keep
                // scoring more faces in a busy group shot once we've found a
                // strong match. The threshold is per-architecture because the
                // three models have very different upper score distributions
                // — legacy FaceNet hits 0.95+, AdaFace tops out around 0.85,
                // the Sandberg 512-d model rarely exceeds 0.75.
                let earlyOut: Float
                switch embeddingModel.kind {
                case .adaface: earlyOut = 0.85
                case .facenet512: earlyOut = 0.70
                case .facenet: earlyOut = 0.985
                }
                if bestSimilarity >= earlyOut { break }
            }

            if bestSimilarity >= minimumSimilarity {
                // Persist the user-facing confidence (remapped from cosine) so
                // displayed match percentages line up with the slider's units —
                // a 60% match means "passes a 60% strictness threshold."
                return MatchResult(
                    fileURL: fileURL,
                    faceCount: totalPeopleInPhoto,
                    similarity: displayConfidence(from: bestSimilarity),
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

    /// Vision face detection. When an alignment-trained model is loaded
    /// (AdaFace or the Sandberg 512-d FaceNet) we ask for landmarks too —
    /// eye/nose/mouth points feed the alignment step in `alignedFaceCrop`.
    /// The legacy Facenet6 doesn't benefit from alignment (it was trained
    /// on loose bounding-box crops, not MTCNN-aligned ones), so the faster
    /// `VNDetectFaceRectanglesRequest` is used as a small optimization.
    private func detectFaces(in cgImage: CGImage) throws -> [VNFaceObservation] {
        let requestHandler = VNImageRequestHandler(cgImage: cgImage, options: [:])
        let wantLandmarks = embeddingModel?.kind == .adaface
            || embeddingModel?.kind == .facenet512

        if wantLandmarks {
            let request = VNDetectFaceLandmarksRequest()
            if #available(macOS 11.0, *) {
                request.revision = VNDetectFaceLandmarksRequestRevision3
            }
            try requestHandler.perform([request])
            return request.results ?? []
        } else {
            let request = VNDetectFaceRectanglesRequest()
            if #available(macOS 11.0, *) {
                request.revision = VNDetectFaceRectanglesRequestRevision3
            }
            try requestHandler.perform([request])
            return request.results ?? []
        }
    }

    private func isUsableFace(_ face: VNFaceObservation, in cgImage: CGImage) -> Bool {
        // Confidence floor 0.40 — lowered from 0.55 so we don't reject
        // profile faces before the embedder gets a look. Vision rates
        // profile and partial-profile faces meaningfully lower (often 0.45-
        // 0.65) because the classifier was trained on frontal data; staying
        // tight here was systematically dropping side-angle shots. Anything
        // below 0.40 tends to be a textured object misfiring as a face, so
        // we don't go lower.
        guard face.confidence >= 0.40 else { return false }

        let rect = VNImageRectForNormalizedRect(face.boundingBox, cgImage.width, cgImage.height)
        // 28×28px minimum (was 36) — profile faces have narrower bounding
        // boxes than frontal faces of the same person because only half the
        // face is visible. A 28px-wide profile is roughly equivalent to a
        // 36px-wide frontal face in terms of detail content.
        guard rect.width >= 28, rect.height >= 28 else { return false }

        return true
    }

    /// Threshold above which a face is treated as "profile" (in radians,
    /// matching Vision's yaw units). 0.4 rad ≈ 23° — at this angle one eye
    /// starts becoming unreliable as a landmark and the canonical 5-point
    /// template stops being a good match for the face's actual geometry.
    /// Empirically chosen: 0.4 catches clear profile shots while leaving
    /// 3-quarter views (which DO benefit from eye alignment) on the eye-
    /// aligned path.
    private static let profileYawThreshold: CGFloat = 0.4

    /// True if Vision considers this face a profile view. Profile faces
    /// take a different alignment path (loose crop, no TTA) because eye-
    /// alignment and mirror-augmentation both assume frontal symmetry.
    private func isProfileFace(_ observation: VNFaceObservation) -> Bool {
        guard let yaw = observation.yaw else { return false }
        return abs(CGFloat(yaw.doubleValue)) >= Self.profileYawThreshold
    }

    /// AdaFace was trained on MTCNN-aligned 112×112 crops with a specific
    /// canonical position for eyes/nose/mouth (the "InsightFace template").
    /// Loose bounding-box crops have eye positions that wander by 20+ pixels,
    /// which puts the network well off-distribution and tanks accuracy on
    /// frontal/3-quarter views. This function uses Vision's eye-pupil
    /// landmarks to compute a similarity transform (rotation + uniform
    /// scale + translation) that maps the detected face onto the canonical
    /// template, then renders a 112×112 aligned crop.
    ///
    /// Returns `nil` for profile faces (|yaw| ≥ ~23°). On a profile, Vision
    /// still returns *some* coordinate for the occluded pupil — usually a
    /// best-guess that's wildly wrong — so this function would otherwise
    /// "succeed" with garbage alignment. Caller falls back to a loose
    /// bounding-box crop for profiles, which is closer to what the model
    /// actually saw of profile faces during training (rare, but present).
    ///
    /// We use 2-point alignment (eyes only) rather than the textbook 5-point
    /// Umeyama similarity transform. The 2-point version handles rotation +
    /// scale + translation but ignores the nose/mouth points, which costs
    /// roughly 1-2% recall vs. 5-point. The win is that it's ~30 lines instead
    /// of ~100, doesn't need a linear algebra dependency, and the dominant
    /// AdaFace gain over loose crops comes from getting the eyes in the right
    /// place anyway.
    private func alignedFaceCrop(
        from cgImage: CGImage,
        observation: VNFaceObservation,
        kind: FaceModelKind
    ) -> CGImage? {
        // Render the aligned crop at the model's native input size so the
        // embedder doesn't re-resample. 112 for AdaFace, 160 for FaceNet512.
        let outputSize = kind.alignedCropSize

        // Bail on profile faces — landmark positions for the occluded eye
        // are unreliable and produce worse crops than skipping alignment.
        if isProfileFace(observation) { return nil }

        guard let landmarks = observation.landmarks,
              let leftPupilRegion = landmarks.leftPupil,
              let rightPupilRegion = landmarks.rightPupil,
              let leftPupilNorm = leftPupilRegion.normalizedPoints.first,
              let rightPupilNorm = rightPupilRegion.normalizedPoints.first else {
            return nil
        }

        // Vision returns landmarks in face-bounding-box-normalized coords
        // with bottom-left origin. CIImage's coordinate system is also
        // bottom-left origin, so once we convert landmark coords to absolute
        // pixel positions in CIImage space we don't need to flip Y.
        let imageWidth = CGFloat(cgImage.width)
        let imageHeight = CGFloat(cgImage.height)
        let bbInPixels = VNImageRectForNormalizedRect(observation.boundingBox,
                                                      cgImage.width,
                                                      cgImage.height)

        // Vision's `boundingBox` is in bottom-left normalized image coords —
        // `VNImageRectForNormalizedRect` converts to pixels but keeps origin
        // at bottom-left. CIImage uses the same convention, so this rect can
        // feed into CIImage space directly.
        _ = imageHeight  // silence warning if Y-flip becomes needed later
        _ = imageWidth

        let leftEye = CGPoint(
            x: bbInPixels.minX + leftPupilNorm.x * bbInPixels.width,
            y: bbInPixels.minY + leftPupilNorm.y * bbInPixels.height
        )
        let rightEye = CGPoint(
            x: bbInPixels.minX + rightPupilNorm.x * bbInPixels.width,
            y: bbInPixels.minY + rightPupilNorm.y * bbInPixels.height
        )

        // Canonical InsightFace 5-point template, eyes only. The template is
        // defined at 112×112 in top-left origin. We scale linearly to the
        // requested outputSize — the eye positions stay at the same relative
        // location, so the model still gets the canonical geometry it was
        // trained on, just at higher resolution for FaceNet512 (160×160).
        // Y is converted to bottom-left origin to match CIImage.
        let templateScale: CGFloat = CGFloat(outputSize) / 112.0
        let templateLeftEyeTL = CGPoint(x: 38.2946 * templateScale,
                                        y: 51.6963 * templateScale)
        let templateRightEyeTL = CGPoint(x: 73.5318 * templateScale,
                                         y: 51.5014 * templateScale)
        let canonical = CGFloat(outputSize)
        let templateLeftEye = CGPoint(x: templateLeftEyeTL.x,
                                      y: canonical - templateLeftEyeTL.y)
        let templateRightEye = CGPoint(x: templateRightEyeTL.x,
                                       y: canonical - templateRightEyeTL.y)

        // Compute the similarity transform: rotate so the eye line is
        // horizontal, scale so the inter-pupil distance matches the template,
        // translate so the eye midpoint lands on the template midpoint.
        let dx = rightEye.x - leftEye.x
        let dy = rightEye.y - leftEye.y
        let eyeDistance = max(hypot(dx, dy), 1.0)
        let angle = atan2(dy, dx)
        let templateDx = templateRightEye.x - templateLeftEye.x
        let templateDy = templateRightEye.y - templateLeftEye.y
        let templateEyeDistance = max(hypot(templateDx, templateDy), 1.0)
        let scale = templateEyeDistance / eyeDistance

        let eyeMidpoint = CGPoint(x: (leftEye.x + rightEye.x) / 2,
                                  y: (leftEye.y + rightEye.y) / 2)
        let templateMidpoint = CGPoint(x: (templateLeftEye.x + templateRightEye.x) / 2,
                                       y: (templateLeftEye.y + templateRightEye.y) / 2)

        // Build the affine: translate eye-midpoint to origin → rotate by
        // -angle → uniform scale → translate to template midpoint. Compose
        // by post-multiplying so applying to a point runs in declaration
        // order (translate to origin, then rotate, then scale, then translate
        // to canonical).
        var transform = CGAffineTransform.identity
        transform = transform.translatedBy(x: templateMidpoint.x, y: templateMidpoint.y)
        transform = transform.scaledBy(x: scale, y: scale)
        transform = transform.rotated(by: -angle)
        transform = transform.translatedBy(x: -eyeMidpoint.x, y: -eyeMidpoint.y)

        // `clampedToExtent()` before the transform extends the image's edge
        // pixels outward to an infinite extent, so a face near the frame edge
        // produces an aligned crop with edge-replicated borders instead of
        // black bars. Black borders shift the embedding (the network reads them
        // as real pixels); edge replication is the standard alignment behavior
        // and is strictly closer to the MTCNN-aligned crops these models were
        // trained on. Faces fully inside the frame are unaffected.
        let ciImage = CIImage(cgImage: cgImage)
            .clampedToExtent()
            .transformed(by: transform)
        let cropRect = CGRect(x: 0, y: 0, width: outputSize, height: outputSize)

        // Render explicitly to a small RGB context — `createCGImage(from:)`
        // honors the rect we ask for, producing a 112×112 aligned image even
        // if the transformed CIImage has a much larger extent.
        return ciContext.createCGImage(ciImage, from: cropRect)
    }

    private func cropFace(
        from cgImage: CGImage,
        boundingBox: CGRect,
        kind: FaceModelKind
    ) -> CGImage? {
        let imageWidth = CGFloat(cgImage.width)
        let imageHeight = CGFloat(cgImage.height)
        let imageRect = CGRect(x: 0, y: 0, width: imageWidth, height: imageHeight)

        let rawRect = VNImageRectForNormalizedRect(boundingBox, Int(imageWidth), Int(imageHeight))
        let maxDimension = max(rawRect.width, rawRect.height)

        // Per-kind vertical shift: nudge the crop upward to capture the
        // forehead. Tight crops (AdaFace) use a small shift to avoid losing
        // the chin; loose crops (Facenet6) use a larger one because there's
        // room to spare. See `FaceModelKind.cropVerticalShift` for the why.
        let center = CGPoint(
            x: rawRect.midX,
            y: rawRect.midY + (rawRect.height * kind.cropVerticalShift)
        )
        // Per-kind padding around the bounding box. AdaFace's training crops
        // are tight (face fills the frame); Facenet6 wants loose crops; the
        // Sandberg FaceNet512 sits between the two. See `cropPadding`.
        let paddedSize = maxDimension * kind.cropPadding

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
    // Cosine similarity has a narrow useful band, and the band differs by
    // architecture. The user-facing "strictness" slider maps 0..1 onto that
    // band so the same slider position means the same thing across models.
    // Raw cosine is never shown.
    //
    // Calibration intent: slider 70% is the "clean matches" operating point
    // for every model — the cosine cutoff at slider 0.70 sits at each
    // architecture's real same/different decision boundary. Below 70%
    // the slider widens toward the impostor tail (more recall, more false
    // positives); above 70% it tightens toward "definitely the same person."
    //
    // To make the slider behave consistently across models, all three bands
    // are 0.30 cosine wide. That way one notch of slider movement tightens
    // the filter by the same fractional amount no matter which model loaded.
    //
    // Per-model distributions (measured / from literature):
    // - Facenet6 (legacy Inception ResNet, 160×160 RGB, triplet loss):
    //   same-person 0.55–0.95, impostors 0.20–0.45. Boundary ~0.66.
    // - AdaFace (IResNet IR18, 112×112 BGR): same-person 0.30–0.65,
    //   impostors near 0 with a tail to ~0.10. Boundary ~0.35.
    // - FaceNet512 (Sandberg VGGFace2, 160×160 RGB, 512-d): same-person
    //   0.50–0.75, impostor tail to ~0.40 for hard cases. LFW operating
    //   point ~0.45. Empirically the slider's "clean" zone starts at ~0.60.

    /// Lower bound of the Facenet6 cosine band. Slider 70% → 0.66 cosine,
    /// matching the legacy triplet-loss model's same/different boundary.
    static let facenetCosineFloor: Float = 0.45
    /// Upper bound. Slider 100% → 0.75 (very strong matches only).
    static let facenetCosineCeiling: Float = 0.75

    /// Lower bound of the AdaFace cosine band. Set at 0.15 — above the
    /// impostor tail (~0.10) so even the loose end of the slider rejects
    /// noise. Slider 70% → 0.36 cosine, AdaFace's real boundary.
    static let adafaceCosineFloor: Float = 0.15
    /// Upper bound. Slider 100% → 0.45 (clearly same person; the model rarely
    /// exceeds 0.65 even on near-identical crops, so 0.45 is "strict").
    static let adafaceCosineCeiling: Float = 0.45

    /// Lower bound of the FaceNet 512 cosine band. Set at 0.40 — just below
    /// the hard-impostor tail (~0.40-0.45) and the LFW operating point
    /// (~0.45). Slider 70% → 0.61 cosine, the empirical "clean matches"
    /// boundary for this checkpoint.
    static let facenet512CosineFloor: Float = 0.40
    /// Upper bound. Slider 100% → 0.70 (very strong; this model rarely
    /// exceeds 0.75 even on the same-person frontal pair).
    static let facenet512CosineCeiling: Float = 0.70

    /// Maximum value the displayed confidence can reach. Capped below 100%
    /// because face matching is never truly certain — claiming a perfect
    /// match would overstate what the model actually knows.
    static let displayCeiling: Double = 0.95

    /// Returns the cosine band (`floor`, `ceiling`) for the currently loaded
    /// model. Falls back to FaceNet's band when no model is loaded so the UI
    /// can still render a sensible strictness slider before scanning.
    private var cosineBand: (floor: Float, ceiling: Float) {
        Self.cosineBand(for: embeddingModel?.kind ?? .facenet)
    }

    static func cosineBand(for kind: FaceModelKind) -> (floor: Float, ceiling: Float) {
        switch kind {
        case .facenet: return (facenetCosineFloor, facenetCosineCeiling)
        case .adaface: return (adafaceCosineFloor, adafaceCosineCeiling)
        // Distinct band — see comment on `facenet512CosineFloor`. The
        // Sandberg checkpoint's embeddings sit lower on the cosine scale
        // than legacy Facenet6, so reusing FaceNet's 0.45 floor was
        // cutting valid same-person matches.
        case .facenet512: return (facenet512CosineFloor, facenet512CosineCeiling)
        }
    }

    /// Width every band is held at, so one notch of slider travel means the
    /// same change in strictness across all three models.
    static let bandWidth: Float = 0.30
    /// Slider position treated as the recommended operating point.
    static let recommendedSliderFraction: Float = 0.70

    /// EMPIRICAL CALIBRATION — the rigorous way to put the slider's 70% notch
    /// on each model's *best* same/different threshold.
    ///
    /// The hard-coded bands above are sensible per-architecture priors, but the
    /// truly optimal cutoff depends on YOUR data (lighting, crop style, who's in
    /// the photos). To lock it in:
    ///
    ///   1. Collect cosine scores with the loaded model + current preprocessing:
    ///      - `genuineScores`:  scores for pairs you KNOW are the same person.
    ///      - `impostorScores`: scores for pairs you KNOW are different people.
    ///      (Score a labeled folder via `cosineSimilarity(_:_:)` on the
    ///       embeddings `FaceEmbeddingModel.embedding(from:)` produces.)
    ///   2. Call this with at least ~30 of each.
    ///   3. Paste the returned `floor`/`ceiling` into the constants above for
    ///      that model.
    ///
    /// It picks the threshold T* that maximizes Youden's J (TPR + TNR − 1) — the
    /// point that best separates genuine from impostor — then centers the band
    /// so the 70% notch sits exactly on T*:
    ///     floor = T* − 0.70 · width,  ceiling = floor + width.
    ///
    /// `targetMaxFAR` (optional) instead picks the strictest T* whose impostor
    /// false-accept rate is ≤ the given value — use it when a false match is
    /// far costlier than a miss.
    static func recommendedBand(
        genuineScores: [Float],
        impostorScores: [Float],
        width: Float = bandWidth,
        targetMaxFAR: Float? = nil
    ) -> (floor: Float, ceiling: Float, threshold: Float, youdenJ: Float)? {
        guard !genuineScores.isEmpty, !impostorScores.isEmpty else { return nil }

        let candidates = Array(Set(genuineScores + impostorScores)).sorted()
        let gCount = Float(genuineScores.count)
        let iCount = Float(impostorScores.count)

        func tpr(_ t: Float) -> Float { Float(genuineScores.filter { $0 >= t }.count) / gCount }
        func far(_ t: Float) -> Float { Float(impostorScores.filter { $0 >= t }.count) / iCount }

        var bestT = candidates[0]
        var bestScore = -Float.greatestFiniteMagnitude

        for t in candidates {
            let score: Float
            if let maxFAR = targetMaxFAR {
                // Among thresholds meeting the FAR budget, prefer the loosest
                // (highest recall); score = TPR, but disqualify if FAR too high.
                score = far(t) <= maxFAR ? tpr(t) : -Float.greatestFiniteMagnitude
            } else {
                score = tpr(t) + (1 - far(t)) - 1   // Youden's J
            }
            // Prefer the lower threshold on ties (keeps recall up).
            if score > bestScore { bestScore = score; bestT = t }
        }

        let floor = max(0, bestT - recommendedSliderFraction * width)
        let ceiling = floor + width
        let j = tpr(bestT) + (1 - far(bestT)) - 1
        return (floor, ceiling, bestT, j)
    }

    /// Maps a raw cosine similarity onto the user-facing confidence scale.
    /// Floor maps to 0%, ceiling maps to `displayCeiling` (95%), and very
    /// strong matches above the ceiling are clamped to that same 95% — we
    /// never display 100%.
    func displayConfidence(from cosine: Float) -> Double {
        let band = cosineBand
        let clamped = max(band.floor, min(band.ceiling, cosine))
        let normalized = Double((clamped - band.floor) / (band.ceiling - band.floor))
        return min(normalized, Self.displayCeiling)
    }

    /// Static variant for call sites that don't have a `FaceMatcher` instance
    /// (e.g. SwiftUI previews). Assumes the FaceNet band for back-compat.
    static func displayConfidence(from cosine: Float) -> Double {
        let band = cosineBand(for: .facenet)
        let clamped = max(band.floor, min(band.ceiling, cosine))
        let normalized = Double((clamped - band.floor) / (band.ceiling - band.floor))
        return min(normalized, displayCeiling)
    }

    /// Inverse of `displayConfidence` — maps the slider position (0..1 in
    /// confidence units) back to the raw cosine cutoff used for filtering.
    func cosineCutoff(forConfidence strictness: Double) -> Float {
        let band = cosineBand
        let clamped = Float(max(0.0, min(1.0, strictness)))
        return band.floor + clamped * (band.ceiling - band.floor)
    }

    /// Back-compat static variant — assumes the FaceNet band.
    static func cosineCutoff(forConfidence strictness: Double) -> Float {
        let band = cosineBand(for: .facenet)
        let clamped = Float(max(0.0, min(1.0, strictness)))
        return band.floor + clamped * (band.ceiling - band.floor)
    }

    private func minimumCosineSimilarity(for strictness: Double) -> Float {
        cosineCutoff(forConfidence: strictness)
    }
}
