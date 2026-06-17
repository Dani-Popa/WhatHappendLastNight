import Foundation
import Vision
import AppKit
import Combine

// Matches exactly what your custom grid layout reads
struct MatchResult: Identifiable {
    let id = UUID()
    let fileURL: URL
    let faceCount: Int
}

class FaceMatcher: ObservableObject {
    // UI Binding State hooks matching your custom view layers exactly
    @Published var isScanning = false
    @Published var progress: Double = 0.0
    @Published var statusText = "STANDBY"
    @Published var matchedResults: [MatchResult] = []
    
    private var currentTask: Task<Void, Never>? = nil

    /// Halts ongoing looping routines safely upon explicit UI trigger requests
    func cancel() {
        currentTask?.cancel()
        cleanupScanningState(finalStatus: "SCAN CANCELED BY USER")
    }

    private func cleanupScanningState(finalStatus: String) {
        DispatchQueue.main.async {
            self.isScanning = false
            self.progress = 0.0
            self.statusText = finalStatus
        }
    }

    /// Extracts structural geometric matrix shapes from an input view canvas frame
    private func extractFaceMetrics(from nsImage: NSImage) -> [CGPoint]? {
        guard let cgImage = nsImage.cgImage(forProposedRect: nil, context: nil, hints: nil) else { return nil }
        
        let requestHandler = VNImageRequestHandler(cgImage: cgImage, options: [:])
        let request = VNDetectFaceLandmarksRequest()
        request.revision = VNDetectFaceLandmarksRequestRevision3
        
        do {
            try requestHandler.perform([request])
            guard let face = request.results?.first else { return nil }
            
            var featurePoints: [CGPoint] = []
            if let leftEye = face.landmarks?.leftEye?.normalizedPoints { featurePoints.append(contentsOf: leftEye) }
            if let rightEye = face.landmarks?.rightEye?.normalizedPoints { featurePoints.append(contentsOf: rightEye) }
            if let nose = face.landmarks?.nose?.normalizedPoints { featurePoints.append(contentsOf: nose) }
            if let outerLips = face.landmarks?.outerLips?.normalizedPoints { featurePoints.append(contentsOf: outerLips) }
            
            return featurePoints.isEmpty ? nil : featurePoints
        } catch {
            return nil
        }
    }
    
    /// Iterates through target local folder items matching against explicit strictness settings
    func scanPartyFolder(selfieImage: NSImage, folderURL: URL) async {
        // Enforce singular Task execution context boundaries
        currentTask?.cancel()
        
        let scanTask = Task {
            await MainActor.run {
                self.isScanning = true
                self.progress = 0.0
                self.statusText = "INITIALIZING BIOMETRIC IDENTITY CORE..."
                self.matchedResults.removeAll()
            }
            
            guard let targetMetrics = extractFaceMetrics(from: selfieImage) else {
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
                // Intercept loop cycles safely if task execution is dropped
                if Task.isCancelled { return }
                
                let currentProgress = Double(index + 1) / Double(totalCount)
                let currentFileName = fileURL.lastPathComponent
                
                await MainActor.run {
                    self.progress = currentProgress
                    self.statusText = "PARSING: \(currentFileName.uppERCased())"
                }
                
                guard let partyImage = NSImage(contentsOf: fileURL),
                      let cgImage = partyImage.cgImage(forProposedRect: nil, context: nil, hints: nil) else { continue }
                
                let requestHandler = VNImageRequestHandler(cgImage: cgImage, options: [:])
                let request = VNDetectFaceLandmarksRequest()
                request.revision = VNDetectFaceLandmarksRequestRevision3
                
                do {
                    try requestHandler.perform([request])
                    guard let detectedFaces = request.results else { continue }
                    let totalPeopleInPhoto = detectedFaces.count
                    
                    for face in detectedFaces {
                        var currentFacePoints: [CGPoint] = []
                        if let leftEye = face.landmarks?.leftEye?.normalizedPoints { currentFacePoints.append(contentsOf: leftEye) }
                        if let rightEye = face.landmarks?.rightEye?.normalizedPoints { currentFacePoints.append(contentsOf: rightEye) }
                        if let nose = face.landmarks?.nose?.normalizedPoints { currentFacePoints.append(contentsOf: nose) }
                        if let outerLips = face.landmarks?.outerLips?.normalizedPoints { currentFacePoints.append(contentsOf: outerLips) }
                        
                        if !currentFacePoints.isEmpty {
                            // Dynamic layout check matching coordinate metrics
                            if compareFaceMetrics(target: targetMetrics, candidate: currentFacePoints) {
                                let match = MatchResult(fileURL: fileURL, faceCount: totalPeopleInPhoto)
                                localMatches.append(match)
                                
                                await MainActor.run {
                                    self.matchedResults = localMatches
                                }
                                break
                            }
                        }
                    }
                } catch {
                    print("Structural processing dropped context trace: \(error)")
                }
            }
            
            await MainActor.run {
                self.isScanning = false
                self.statusText = localMatches.isEmpty ? "DEEP ANALYSIS FINISHED: SECURE" : "EXTRACTION COMPLETE: \(localMatches.count) TARGETS STORED"
            }
        }
        
        currentTask = scanTask
        await scanTask.value
    }
    
    private func compareFaceMetrics(target: [CGPoint], candidate: [CGPoint]) -> Bool {
        let minCount = min(target.count, candidate.count)
        if minCount < 10 { return false }
        
        var totalVariance: CGFloat = 0.0
        
        for i in 0..<minCount {
            let dx = target[i].x - candidate[i].x
            let dy = target[i].y - candidate[i].y
            totalVariance += sqrt(dx*dx + dy*dy)
        }
        
        let averageVariance = totalVariance / CGFloat(minCount)
        // Strict baseline evaluation prevents secondary matching issues
        return averageVariance < 0.075
    }
}

// Extension to cleanly transform file names in status updates
private extension String {
    func uppERCased() -> String {
        return self.uppercased()
    }
}
