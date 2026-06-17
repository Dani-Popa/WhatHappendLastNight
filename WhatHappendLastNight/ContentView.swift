import SwiftUI
import Combine
import AppKit
import UniformTypeIdentifiers
import AVFoundation

struct ContentView: View {
    @StateObject private var matcher = FaceMatcher()
    
    // State variables
    @State private var targetSelfie: NSImage? = nil
    @State private var targetSelfieURL: URL? = nil
    @State private var sourceFolderURL: URL? = nil
    @State private var threshold: Double = 0.75
    @State private var isSelfieHovered = false
    @State private var isFolderHovered = false
    @State private var isShowingCameraSheet = false
    @State private var isShowingPrivacyNotice = false
    @State private var hasAcceptedBiometricNotice = false
    
    // Aesthetic Palette constants (Gold & Charcoal Core)
    private let darkBackground = Color(NSColor(red: 0.02, green: 0.02, blue: 0.02, alpha: 1.0))
    private let richCard = Color(NSColor(red: 0.04, green: 0.04, blue: 0.04, alpha: 1.0))
    private let deepSlate = Color(NSColor(red: 0.06, green: 0.06, blue: 0.06, alpha: 1.0))
    private let goldAccent = Color(NSColor(red: 0.83, green: 0.69, blue: 0.22, alpha: 1.0)) // #D4AF37
    private let textMuted = Color(NSColor(red: 0.40, green: 0.40, blue: 0.40, alpha: 1.0))
    private let textLight = Color(NSColor(red: 0.88, green: 0.85, blue: 0.82, alpha: 1.0))
    
    var body: some View {
        VStack(spacing: 0) {
            // MARK: Professional Header
            HStack {
                VStack(alignment: .leading, spacing: 4) {
                    Text("What Happened Last Night")
                        .font(.custom("Georgia", size: 24))
                        .italic()
                        .foregroundColor(textLight)
                    
                    Text("LOCAL FACENET MATCHING / OFFLINE CORE V2")
                        .font(.system(.caption, design: .monospaced))
                        .foregroundColor(textMuted)
                        .kerning(1.5)
                }
                
                Spacer()
                
                // Connection indicator
                HStack(spacing: 6) {
                    Circle()
                        .fill(Color.emerald)
                        .frame(width: 6, height: 6)
                    Text("OFFLINE LOCAL MODE")
                        .font(.system(size: 9, design: .monospaced))
                        .fontWeight(.bold)
                        .foregroundColor(textMuted)
                }
                .padding(.horizontal, 10)
                .padding(.vertical, 6)
                .background(Color.black)
                .cornerRadius(4)
                .overlay(
                    RoundedRectangle(cornerRadius: 4)
                        .stroke(Color(white: 0.12), lineWidth: 1)
                )
            }
            .padding(.horizontal, 24)
            .padding(.vertical, 16)
            .background(darkBackground)
            
            Divider().background(Color(white: 0.1))
            
            // MARK: Primary Split Screen
            HSplitView {
                // MARK: LEFT SIDE: SETUP PANELS
                VStack(spacing: 16) {
                    // Segment 1: Biometric Target Identity Selection
                    VStack(alignment: .leading, spacing: 10) {
                        HStack(spacing: 6) {
                            Image(systemName: "faceid")
                                .foregroundColor(goldAccent)
                            Text("1. Target Identity")
                                .font(.system(size: 10, design: .monospaced))
                                .fontWeight(.bold)
                                .foregroundColor(textMuted)
                        }
                        
                        // Drag-and-drop identity zone (opens native Camera Capture tool)
                        Button(action: { isShowingCameraSheet = true }) {
                            VStack(spacing: 12) {
                                if let targetSelfie = targetSelfie {
                                    Image(nsImage: targetSelfie)
                                        .resizable()
                                        .scaledToFit()
                                        .frame(maxHeight: 140)
                                        .cornerRadius(8)
                                        .overlay(
                                            RoundedRectangle(cornerRadius: 8)
                                                .stroke(goldAccent.opacity(0.4), lineWidth: 1)
                                        )
                                        .shadow(radius: 6)
                                    
                                    Text(targetSelfieURL?.lastPathComponent ?? "Facetime HD Snapshot Captured")
                                        .font(.system(size: 9, design: .monospaced))
                                        .foregroundColor(goldAccent)
                                        .truncationMode(.middle)
                                        .lineLimit(1)
                                } else {
                                    Image(systemName: "camera")
                                        .font(.system(size: 24))
                                        .foregroundColor(textMuted)
                                    
                                    Text("CLICK TO CAPTURE WITH MAC CAMERA")
                                        .font(.system(size: 10, weight: .bold))
                                        .foregroundColor(textLight.opacity(0.70))
                                    
                                    Text("Selfie stays on this device until cleared")
                                        .font(.system(size: 8))
                                        .foregroundColor(textMuted)
                                }
                            }
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 20)
                            .background(targetSelfie == nil ? richCard : Color.black.opacity(0.4))
                            .cornerRadius(12)
                            .overlay(
                                RoundedRectangle(cornerRadius: 12)
                                    .stroke(isSelfieHovered ? goldAccent.opacity(0.6) : Color(white: 0.12), style: StrokeStyle(lineWidth: 1, dash: targetSelfie == nil ? [4] : []))
                            )
                        }
                        .buttonStyle(PlainButtonStyle())
                        .onHover { h in isSelfieHovered = h }
                        .onDrop(of: [.fileURL], isTargeted: nil) { providers in
                            loadSelfieFromDrop(providers)
                        }
                    }
                    .padding(16)
                    .background(richCard)
                    .cornerRadius(16)
                    .overlay(
                        RoundedRectangle(cornerRadius: 16)
                            .stroke(Color(white: 0.08), lineWidth: 1)
                    )
                    
                    // Segment 2: Source Folders
                    VStack(alignment: .leading, spacing: 10) {
                        HStack(spacing: 6) {
                            Image(systemName: "folder")
                                .foregroundColor(goldAccent)
                            Text("2. Repository Media Folder")
                                .font(.system(size: 10, design: .monospaced))
                                .fontWeight(.bold)
                                .foregroundColor(textMuted)
                        }
                        
                        Button(action: selectSourceFolder) {
                            VStack(spacing: 12) {
                                Image(systemName: "folder.badge.gearshape")
                                    .font(.system(size: 24))
                                    .foregroundColor(sourceFolderURL == nil ? textMuted : goldAccent)
                                
                                Text(sourceFolderURL == nil ? "CHOOSE PORTABLE SOURCE FOLDER" : "FOLDER MOUNTED")
                                    .font(.system(size: 10, weight: .bold))
                                    .foregroundColor(textLight.opacity(0.70))
                                
                                Text(sourceFolderURL?.path ?? "Reads only image files from a folder you select")
                                    .font(.system(size: 8, design: .monospaced))
                                    .foregroundColor(textMuted)
                                    .lineLimit(2)
                                    .multilineTextAlignment(.center)
                                    .padding(.horizontal, 8)
                            }
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 20)
                            .background(sourceFolderURL == nil ? richCard : Color.black.opacity(0.4))
                            .cornerRadius(12)
                            .overlay(
                                RoundedRectangle(cornerRadius: 12)
                                    .stroke(isFolderHovered ? goldAccent.opacity(0.6) : Color(white: 0.12), style: StrokeStyle(lineWidth: 1, dash: [4]))
                            )
                        }
                        .buttonStyle(PlainButtonStyle())
                        .onHover { h in isFolderHovered = h }
                        .onDrop(of: [.directory], isTargeted: nil) { providers in
                            loadFolderFromDrop(providers)
                        }
                    }
                    .padding(16)
                    .background(richCard)
                    .cornerRadius(16)
                    .overlay(
                        RoundedRectangle(cornerRadius: 16)
                            .stroke(Color(white: 0.08), lineWidth: 1)
                    )
                    
                    // Matcher Strictness Settings
                    VStack(alignment: .leading, spacing: 8) {
                        HStack {
                            Text("FACENET STRICTNESS / STRICTEȚE")
                                .font(.system(size: 9, design: .monospaced))
                                .fontWeight(.bold)
                                .foregroundColor(textMuted)
                            Spacer()
                            Text("\(Int(threshold * 100))%")
                                .font(.system(size: 9, design: .monospaced))
                                .foregroundColor(goldAccent)
                        }
                        
                        Slider(value: $threshold, in: 0.0...1.0)
                            .accentColor(goldAccent)
                        
                        HStack {
                            Text("Lenient (Mai multe rezultate)")
                                .font(.system(size: 8))
                                .foregroundColor(textMuted)
                            Spacer()
                            Text("Strict (Mai puține false positives)")
                                .font(.system(size: 8))
                                .foregroundColor(textMuted)
                        }
                    }
                    .padding(12)
                    .background(richCard.opacity(0.6))
                    .cornerRadius(8)

                    VStack(alignment: .leading, spacing: 10) {
                        HStack(spacing: 6) {
                            Image(systemName: "lock.shield")
                                .foregroundColor(goldAccent)
                            Text("Privacy & Consent")
                                .font(.system(size: 10, design: .monospaced))
                                .fontWeight(.bold)
                                .foregroundColor(textMuted)
                        }

                        Text("Face matching runs locally. Selfies, face embeddings, and selected photos are not written to disk by this app and are not sent over the network.")
                            .font(.system(size: 9))
                            .foregroundColor(textMuted)
                            .fixedSize(horizontal: false, vertical: true)

                        Toggle(isOn: $hasAcceptedBiometricNotice) {
                            Text("I consent to local face matching for this session")
                                .font(.system(size: 9, weight: .semibold))
                                .foregroundColor(textLight.opacity(0.85))
                        }
                        .toggleStyle(.checkbox)

                        HStack(spacing: 8) {
                            Button(action: { isShowingPrivacyNotice = true }) {
                                Text("PRIVACY SUMMARY")
                                    .font(.system(size: 9, design: .monospaced))
                                    .fontWeight(.bold)
                                    .foregroundColor(goldAccent)
                            }
                            .buttonStyle(PlainButtonStyle())

                            Spacer()

                            Button(action: clearLocalData) {
                                Text("CLEAR SESSION")
                                    .font(.system(size: 9, design: .monospaced))
                                    .fontWeight(.bold)
                                    .foregroundColor(.red)
                            }
                            .buttonStyle(PlainButtonStyle())
                        }
                    }
                    .padding(12)
                    .background(richCard.opacity(0.6))
                    .cornerRadius(8)
                    
                    Spacer()
                    
                    // Segment 3: Biometric detection control trigger
                    VStack(spacing: 12) {
                        if matcher.isScanning {
                            VStack(spacing: 6) {
                                ProgressView(value: matcher.progress, total: 1.0)
                                    .progressViewStyle(LinearProgressViewStyle())
                                    .accentColor(goldAccent)
                                
                                HStack {
                                    Text(matcher.statusText)
                                        .font(.system(size: 9, design: .monospaced))
                                        .foregroundColor(goldAccent)
                                    Spacer()
                                    Text("\(Int(matcher.progress * 100))%")
                                        .font(.system(size: 9, design: .monospaced))
                                        .foregroundColor(textLight)
                                }
                            }
                            
                            Button(action: { matcher.cancel() }) {
                                Text("CANCEL DEEP SCAN")
                                    .font(.system(size: 10, design: .monospaced))
                                    .fontWeight(.bold)
                                    .foregroundColor(.red)
                                    .frame(maxWidth: .infinity)
                                    .padding(.vertical, 10)
                                    .background(Color.red.opacity(0.1))
                                    .cornerRadius(8)
                            }
                            .buttonStyle(PlainButtonStyle())
                        } else {
                            Button(action: runSelfieScan) {
                                HStack {
                                    Image(systemName: "sparkles")
                                    Text("TRIGGER MATCHING SCANNER")
                                        .font(.system(size: 10, design: .monospaced))
                                        .fontWeight(.bold)
                                }
                                .foregroundColor(targetSelfie == nil || sourceFolderURL == nil || !hasAcceptedBiometricNotice ? textMuted : Color.black)
                                .frame(maxWidth: .infinity)
                                .padding(.vertical, 12)
                                .background(targetSelfie == nil || sourceFolderURL == nil || !hasAcceptedBiometricNotice ? deepSlate : goldAccent)
                                .cornerRadius(8)
                                .shadow(color: targetSelfie != nil && sourceFolderURL != nil && hasAcceptedBiometricNotice ? goldAccent.opacity(0.15) : Color.clear, radius: 8)
                            }
                            .buttonStyle(PlainButtonStyle())
                            .disabled(targetSelfie == nil || sourceFolderURL == nil || !hasAcceptedBiometricNotice)
                        }
                    }
                    .padding(16)
                    .background(richCard)
                    .cornerRadius(16)
                }
                .frame(width: 310)
                .padding(16)
                .background(darkBackground)
                
                // MARK: RIGHT SIDE: RESULT SNAPSHOT CONTAINER
                VStack(spacing: 0) {
                    // Title info drawer
                    HStack {
                        VStack(alignment: .leading, spacing: 4) {
                            Text("LOCAL MATCH RESULTS")
                                .font(.system(size: 11, weight: .bold))
                                .foregroundColor(textLight)
                            
                            Text(matcher.matchedResults.isEmpty ? "OFFLINE PHOTO GRID STANDBY" : "POTENTIAL LOCAL MATCHES: \(matcher.matchedResults.count) FRAMES")
                                .font(.system(size: 9, design: .monospaced))
                                .foregroundColor(textMuted)
                        }
                        Spacer()
                    }
                    .padding(20)
                    .background(richCard)
                    
                    Divider().background(Color(white: 0.1))
                    
                    if matcher.matchedResults.isEmpty {
                        // Empty Standby view
                        VStack(spacing: 16) {
                            Image(systemName: "doc.text.magnifyingglass")
                                .font(.system(size: 52))
                                .foregroundColor(textMuted.opacity(0.4))
                            
                            Text("No local matches found yet")
                                .font(.system(size: 13, weight: .semibold))
                                .foregroundColor(textLight.opacity(0.6))
                            
                            Text("Provide a target selfie, choose a folder, and confirm consent to run local-only matching.")
                                .font(.system(size: 10))
                                .foregroundColor(textMuted)
                                .multilineTextAlignment(.center)
                                .frame(maxWidth: 340)
                        }
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                        .background(darkBackground)
                    } else {
                        // Matched photos grid
                        ScrollView {
                            LazyVGrid(columns: [GridItem(.adaptive(minimum: 160, maximum: 220), spacing: 16)], spacing: 16) {
                                ForEach(matcher.matchedResults) { result in
                                    ResultCardView(result: result, accent: goldAccent, muted: textMuted, light: textLight, cardBg: richCard)
                                }
                            }
                            .padding(20)
                        }
                        .background(darkBackground)
                    }
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .background(darkBackground)
            }
            
            Divider().background(Color(white: 0.1))
            
            // MARK: Static elegant footer branding
            HStack {
                Text("© 2026 What Happened Last Night. LOCAL PRIVACY MODE ACTIVE.")
                    .font(.system(size: 8, design: .monospaced))
                    .foregroundColor(textMuted)
                
                Spacer()
                
                HStack(spacing: 12) {
                    Text("COREML FACENET EMBEDDING PIPELINE")
                        .font(.system(size: 8, design: .monospaced))
                        .foregroundColor(textMuted)
                    Circle()
                        .fill(goldAccent.opacity(0.5))
                        .frame(width: 4, height: 4)
                    Text("NO NETWORK UPLOADS")
                        .font(.system(size: 8, design: .monospaced))
                        .foregroundColor(textMuted)
                }
            }
            .padding(.horizontal, 24)
            .padding(.vertical, 12)
            .background(darkBackground)
        }
        .frame(minWidth: 950, minHeight: 650)
        .background(darkBackground)
        .sheet(isPresented: $isShowingCameraSheet) {
            CameraCaptureSheet(isPresented: $isShowingCameraSheet) { capturedImage in
                self.targetSelfie = capturedImage
                self.targetSelfieURL = nil
            } onBrowseFile: {
                selectSelfieFile()
            }
        }
        .sheet(isPresented: $isShowingPrivacyNotice) {
            PrivacyNoticeSheet(isPresented: $isShowingPrivacyNotice, hasAcceptedBiometricNotice: $hasAcceptedBiometricNotice)
        }
    }
    
    // MARK: Actions
    
    /// Present native macOS File Picker to pick selfie
    private func selectSelfieFile() {
        let panel = NSOpenPanel()
        panel.allowedContentTypes = [.image]
        panel.canChooseFiles = true
        panel.canChooseDirectories = false
        panel.allowsMultipleSelection = false
        
        if panel.runModal() == .OK {
            if let url = panel.url, let image = NSImage(contentsOf: url) {
                self.targetSelfie = image
                self.targetSelfieURL = url
            }
        }
    }
    
    /// Native folder picker panel
    private func selectSourceFolder() {
        let panel = NSOpenPanel()
        panel.canChooseFiles = false
        panel.canChooseDirectories = true
        panel.allowsMultipleSelection = false
        
        if panel.runModal() == .OK {
            if let url = panel.url {
                self.sourceFolderURL = url
            }
        }
    }
    
    private func runSelfieScan() {
            guard hasAcceptedBiometricNotice else {
                isShowingPrivacyNotice = true
                return
            }

            guard let selfie = self.targetSelfie,
                  let folder = self.sourceFolderURL else { return }
            
            Task {
                await matcher.scanPartyFolder(selfieImage: selfie, folderURL: folder, strictness: threshold)
            }
        }

    private func clearLocalData() {
        matcher.cancel()
        matcher.clearResults()
        targetSelfie = nil
        targetSelfieURL = nil
        sourceFolderURL = nil
        hasAcceptedBiometricNotice = false
    }
    
    // MARK: Drag and drop loaders
    
    private func loadSelfieFromDrop(_ providers: [NSItemProvider]) -> Bool {
        guard let provider = providers.first else { return false }
        
        provider.loadItem(forTypeIdentifier: UTType.fileURL.identifier, options: nil) { item, error in
            guard let data = item as? Data, let url = URL(dataRepresentation: data, relativeTo: nil) else { return }
            
            DispatchQueue.main.async {
                if let image = NSImage(contentsOf: url) {
                    self.targetSelfie = image
                    self.targetSelfieURL = url
                }
            }
        }
        return true
    }
    
    private func loadFolderFromDrop(_ providers: [NSItemProvider]) -> Bool {
        guard let provider = providers.first else { return false }
        
        provider.loadItem(forTypeIdentifier: UTType.directory.identifier, options: nil) { item, error in
            guard let data = item as? Data, let url = URL(dataRepresentation: data, relativeTo: nil) else { return }
            
            DispatchQueue.main.async {
                self.sourceFolderURL = url
            }
        }
        return true
    }
}

// MARK: Individual matching thumbnail card rendering
struct ResultCardView: View {
    let result: MatchResult
    let accent: Color
    let muted: Color
    let light: Color
    let cardBg: Color
    
    @State private var thumbnail: NSImage? = nil
    @State private var isHovered = false
    
    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            // Thumbnail container
            ZStack(alignment: .topTrailing) {
                if let thumbnail = thumbnail {
                    Image(nsImage: thumbnail)
                        .resizable()
                        .scaledToFill()
                        .frame(height: 154)
                        .clipped()
                } else {
                    Rectangle()
                        .fill(cardBg)
                        .frame(height: 154)
                        .overlay(
                            ProgressView()
                                .scaleEffect(0.6)
                        )
                }
                
                // Spot identification ribbon
                Text("SPOTTED")
                    .font(.system(size: 8, weight: .bold, design: .monospaced))
                    .foregroundColor(.emerald)
                    .padding(.horizontal, 6)
                    .padding(.vertical, 3)
                    .background(Color.black.opacity(0.85))
                    .cornerRadius(4)
                    .padding(8)
                    .overlay(
                        RoundedRectangle(cornerRadius: 4)
                            .stroke(Color.emerald.opacity(0.3), lineWidth: 1)
                            .padding(8)
                    )
            }
            .frame(height: 154)
            .background(Color.black)
            .overlay(
                // Interactive hover zoom action overlay
                Group {
                    if isHovered {
                        Color.black.opacity(0.4)
                        Button(action: revealInFinder) {
                            HStack(spacing: 4) {
                                Image(systemName: "magnifyingglass")
                                Text("REVEAL FILE")
                            }
                            .font(.system(size: 9, weight: .bold, design: .monospaced))
                            .foregroundColor(.black)
                            .padding(.horizontal, 10)
                            .padding(.vertical, 6)
                            .background(accent)
                            .cornerRadius(4)
                        }
                        .buttonStyle(PlainButtonStyle())
                    }
                }
            )
            
            // Description drawer
            VStack(alignment: .leading, spacing: 6) {
                Text(result.fileURL.lastPathComponent)
                    .font(.system(size: 9, design: .monospaced))
                    .fontWeight(.bold)
                    .foregroundColor(light)
                    .lineLimit(1)
                
                HStack {
                    Text("Faces found: \(result.faceCount)")
                        .font(.system(size: 8))
                        .foregroundColor(muted)
                    
                    Spacer()
                    
                    Button(action: revealInFinder) {
                        Image(systemName: "arrow.right.circle")
                            .font(.system(size: 11))
                            .foregroundColor(accent)
                    }
                    .buttonStyle(PlainButtonStyle())
                    .help("Show on disk in macOS Finder")
                }
            }
            .padding(10)
            .background(cardBg)
        }
        .cornerRadius(10)
        .overlay(
            RoundedRectangle(cornerRadius: 10)
                .stroke(isHovered ? accent.opacity(0.35) : Color(white: 0.12), lineWidth: 1)
        )
        .shadow(radius: isHovered ? 8 : 2)
        .onHover { h in isHovered = h }
        .onAppear {
            loadThumbnailAsync()
        }
    }
    
    /// Generate quick preview asynchronously so UI loads immediately
    private func loadThumbnailAsync() {
        DispatchQueue.global(qos: .userInitiated).async {
            // Load custom local image and cache aspect ratios
            if let image = NSImage(contentsOf: result.fileURL) {
                // Resize for local presentation performance
                let targetSize = NSSize(width: 300, height: 260)
                let resized = image.resized(to: targetSize)
                DispatchQueue.main.async {
                    self.thumbnail = resized
                }
            }
        }
    }
    
    /// Trigger local macOS spatial file locator spotlight
    private func revealInFinder() {
        NSWorkspace.shared.activateFileViewerSelecting([result.fileURL])
    }
}

struct PrivacyNoticeSheet: View {
    @Binding var isPresented: Bool
    @Binding var hasAcceptedBiometricNotice: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack {
                Image(systemName: "lock.shield")
                    .font(.system(size: 22))
                    .foregroundColor(Color(NSColor(red: 0.83, green: 0.69, blue: 0.22, alpha: 1.0)))
                Text("Privacy Summary")
                    .font(.system(size: 18, weight: .bold))
                    .foregroundColor(Color(NSColor(red: 0.88, green: 0.85, blue: 0.82, alpha: 1.0)))
            }

            VStack(alignment: .leading, spacing: 10) {
                PrivacyNoticeRow(title: "Purpose", message: "The app compares a selfie with faces found in image files you choose, only to show possible matches in this session.")
                PrivacyNoticeRow(title: "Local Processing", message: "Face detection, crops, and FaceNet embeddings are processed on this device. The app has outgoing network access disabled.")
                PrivacyNoticeRow(title: "Storage", message: "The app does not write selfies, selected photos, embeddings, or match results to its own storage. Clear Session removes in-memory state.")
                PrivacyNoticeRow(title: "Control", message: "You can cancel scanning at any time and choose a different folder or selfie. Only user-selected files are read.")
            }

            Toggle(isOn: $hasAcceptedBiometricNotice) {
                Text("I consent to local face matching for this session")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundColor(Color(NSColor(red: 0.88, green: 0.85, blue: 0.82, alpha: 1.0)))
            }
            .toggleStyle(.checkbox)

            HStack {
                Spacer()
                Button("Close") {
                    isPresented = false
                }
                .keyboardShortcut(.cancelAction)

                Button("Accept and Continue") {
                    hasAcceptedBiometricNotice = true
                    isPresented = false
                }
                .keyboardShortcut(.defaultAction)
            }
        }
        .padding(24)
        .frame(width: 520)
        .background(Color(NSColor(red: 0.03, green: 0.03, blue: 0.03, alpha: 1.0)))
    }
}

struct PrivacyNoticeRow: View {
    let title: String
    let message: String

    var body: some View {
        VStack(alignment: .leading, spacing: 3) {
            Text(title)
                .font(.system(size: 10, weight: .bold, design: .monospaced))
                .foregroundColor(Color(NSColor(red: 0.83, green: 0.69, blue: 0.22, alpha: 1.0)))
            Text(message)
                .font(.system(size: 11))
                .foregroundColor(Color(NSColor(red: 0.55, green: 0.55, blue: 0.55, alpha: 1.0)))
                .fixedSize(horizontal: false, vertical: true)
        }
    }
}

// Quick extension for NSImage scaling helper
extension NSImage {
    func resized(to newSize: NSSize) -> NSImage {
        let destRect = NSRect(origin: .zero, size: newSize)
        let newImage = NSImage(size: newSize)
        
        newImage.lockFocus()
        self.draw(in: destRect, from: NSRect(origin: .zero, size: self.size), operation: .copy, fraction: 1.0)
        newImage.unlockFocus()
        
        return newImage
    }
}

// System color compatibility indicators
extension Color {
    static let emerald = Color(NSColor(red: 0.20, green: 0.78, blue: 0.35, alpha: 1.0))
}

// MARK: - FaceTime HD Camera Capture Components

struct CameraPreviewView: NSViewRepresentable {
    let session: AVCaptureSession
    
    func makeNSView(context: Context) -> NSView {
        let view = NSView()
        let previewLayer = AVCaptureVideoPreviewLayer(session: session)
        previewLayer.videoGravity = .resizeAspectFill
        view.layer = previewLayer
        view.wantsLayer = true
        return view
    }
    
    func updateNSView(_ nsView: NSView, context: Context) {
        nsView.layer?.sublayers?.forEach { layer in
            if let previewLayer = layer as? AVCaptureVideoPreviewLayer {
                previewLayer.frame = nsView.bounds
            }
        }
    }
}

class CameraDelegateHelper: NSObject, AVCaptureVideoDataOutputSampleBufferDelegate {
    nonisolated(unsafe) var onFrame: ((CMSampleBuffer) -> Void)?
    
    nonisolated func captureOutput(_ output: AVCaptureOutput, didOutput sampleBuffer: CMSampleBuffer, from connection: AVCaptureConnection) {
        onFrame?(sampleBuffer)
    }
}

class CameraManager: ObservableObject {
    let session = AVCaptureSession()
    @Published var permissionGranted = false
    @Published var currentImage: NSImage? = nil
    
    private var videoOutput = AVCaptureVideoDataOutput()
    private let sessionQueue = DispatchQueue(label: "camera.session.queue")
    private let context = CIContext(options: [.useSoftwareRenderer: false]) // Optimized for Apple Silicon GPU
    private let delegateHelper = CameraDelegateHelper()
    
    init() {
        checkPermission()
    }
    
    func checkPermission() {
        switch AVCaptureDevice.authorizationStatus(for: .video) {
        case .authorized:
            DispatchQueue.main.async { self.permissionGranted = true }
            self.setupSession()
        case .notDetermined:
            AVCaptureDevice.requestAccess(for: .video) { granted in
                DispatchQueue.main.async {
                    self.permissionGranted = granted
                    if granted {
                        self.setupSession()
                    }
                }
            }
        default:
            DispatchQueue.main.async { self.permissionGranted = false }
        }
    }
    
    func setupSession() {
        sessionQueue.async { [weak self] in
            guard let self = self else { return }
            self.session.beginConfiguration()
            
            guard let videoDevice = AVCaptureDevice.default(for: .video) else {
                #if DEBUG
                print("No video device found")
                #endif
                self.session.commitConfiguration()
                return
            }
            
            do {
                let videoInput = try AVCaptureDeviceInput(device: videoDevice)
                if self.session.canAddInput(videoInput) {
                    self.session.addInput(videoInput)
                }
                
                self.videoOutput.alwaysDiscardsLateVideoFrames = true
                self.videoOutput.videoSettings = [kCVPixelBufferPixelFormatTypeKey as String: Int(kCVPixelFormatType_32BGRA)]
                
                self.delegateHelper.onFrame = { [weak self] sampleBuffer in
                    self?.handleSampleBuffer(sampleBuffer)
                }
                
                if self.session.canAddOutput(self.videoOutput) {
                    self.session.addOutput(self.videoOutput)
                    self.videoOutput.setSampleBufferDelegate(self.delegateHelper, queue: DispatchQueue(label: "sample.buffer.queue"))
                }
            } catch {
                #if DEBUG
                print("Could not initialize camera input: \(error.localizedDescription)")
                #endif
            }
            
            self.session.commitConfiguration()
            self.session.startRunning()
        }
    }
    
    func start() {
        sessionQueue.async { [weak self] in
            guard let self = self else { return }
            if !self.session.isRunning {
                self.session.startRunning()
            }
        }
    }
    
    func stop() {
        sessionQueue.async { [weak self] in
            guard let self = self else { return }
            if self.session.isRunning {
                self.session.stopRunning()
            }
        }
    }
    
    private func handleSampleBuffer(_ sampleBuffer: CMSampleBuffer) {
        guard let cvBuffer = CMSampleBufferGetImageBuffer(sampleBuffer) else { return }
        let ciImage = CIImage(cvImageBuffer: cvBuffer)
        let mirrored = ciImage.oriented(.upMirrored)
        
        guard let cgImage = context.createCGImage(mirrored, from: mirrored.extent) else { return }
        
        let size = NSSize(width: cgImage.width, height: cgImage.height)
        let nsImage = NSImage(cgImage: cgImage, size: size)
        
        // CRITICAL FIX: Always push UI updates back to the Main Thread
        DispatchQueue.main.async { [weak self] in
            self?.currentImage = nsImage
        }
    }
}

struct CameraCaptureSheet: View {
    @StateObject private var cameraManager = CameraManager()
    @Binding var isPresented: Bool
    var onCapture: (NSImage) -> Void
    var onBrowseFile: () -> Void
    
    var body: some View {
        VStack(spacing: 16) {
            Text("FACETIME HD SELFIE CAMERA")
                .font(.system(size: 11, weight: .bold, design: .monospaced))
                .foregroundColor(Color(NSColor(red: 0.83, green: 0.69, blue: 0.22, alpha: 1.0)))
                .padding(.top, 20)
            
            if cameraManager.permissionGranted {
                ZStack {
                    CameraPreviewView(session: cameraManager.session)
                        .frame(width: 420, height: 300)
                        .cornerRadius(12)
                        .overlay(
                            RoundedRectangle(cornerRadius: 12)
                                .stroke(Color(white: 0.16), lineWidth: 1)
                        )
                    
                    // Centered oval guideline for alignment
                    Ellipse()
                        .stroke(Color(NSColor(red: 0.83, green: 0.69, blue: 0.22, alpha: 0.4)), style: StrokeStyle(lineWidth: 1.5, dash: [5]))
                        .frame(width: 200, height: 250)
                }
            } else {
                VStack(spacing: 12) {
                    Image(systemName: "camera.fill")
                        .font(.system(size: 32))
                        .foregroundColor(Color(white: 0.2))
                    Text("WAITING FOR CAMERA ACCESS PERMISSION...")
                        .font(.system(size: 9, design: .monospaced))
                        .foregroundColor(Color(white: 0.4))
                }
                .frame(width: 420, height: 300)
                .background(Color.black.opacity(0.8))
                .cornerRadius(12)
                .overlay(
                    RoundedRectangle(cornerRadius: 12)
                        .stroke(Color(white: 0.1), lineWidth: 1)
                )
            }

            Text("Camera frames are used only to create the in-memory selfie reference for local matching.")
                .font(.system(size: 9))
                .foregroundColor(Color(white: 0.45))
                .multilineTextAlignment(.center)
                .frame(maxWidth: 380)
            
            HStack(spacing: 16) {
                Button(action: {
                    cameraManager.stop()
                    isPresented = false
                    onBrowseFile()
                }) {
                    HStack(spacing: 6) {
                        Image(systemName: "folder")
                        Text("ALEGE FIȘIER INSTEAD")
                    }
                    .font(.system(size: 10, weight: .bold, design: .monospaced))
                    .foregroundColor(Color(white: 0.8))
                    .padding(.horizontal, 14)
                    .padding(.vertical, 10)
                    .background(Color(white: 0.1))
                    .cornerRadius(8)
                }
                .buttonStyle(PlainButtonStyle())
                
                Button(action: {
                    if let image = cameraManager.currentImage {
                        cameraManager.stop()
                        onCapture(image)
                        isPresented = false
                    }
                }) {
                    HStack(spacing: 6) {
                        Image(systemName: "camera.fill")
                        Text("FA SELFIE / CAPTURE")
                    }
                    .font(.system(size: 10, weight: .bold, design: .monospaced))
                    .foregroundColor(.black)
                    .padding(.horizontal, 18)
                    .padding(.vertical, 10)
                    .background(Color(NSColor(red: 0.83, green: 0.69, blue: 0.22, alpha: 1.0)))
                    .cornerRadius(8)
                }
                .buttonStyle(PlainButtonStyle())
                .disabled(cameraManager.currentImage == nil)
                
                Button(action: {
                    cameraManager.stop()
                    isPresented = false
                }) {
                    Text("RENUNȚĂ / CANCEL")
                        .font(.system(size: 10, weight: .bold, design: .monospaced))
                        .foregroundColor(.red)
                        .padding(.horizontal, 14)
                        .padding(.vertical, 10)
                        .background(Color.red.opacity(0.08))
                        .cornerRadius(8)
                }
                .buttonStyle(PlainButtonStyle())
            }
            .padding(.bottom, 20)
        }
        .padding(.horizontal, 24)
        .background(Color(NSColor(red: 0.03, green: 0.03, blue: 0.03, alpha: 1.0)))
        .frame(width: 480, height: 420)
        .onAppear {
            cameraManager.start()
        }
        .onDisappear {
            cameraManager.stop()
        }
    }
}

