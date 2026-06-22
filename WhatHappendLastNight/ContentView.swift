import SwiftUI
import Combine
import AppKit
import UniformTypeIdentifiers
import AVFoundation
import Vision
import CoreImage

struct ContentView: View {
    @StateObject private var matcher = FaceMatcher()
    @StateObject private var savedFolders = SavedFoldersStore()
    @EnvironmentObject var theme: ThemeManager

    @State private var targetSelfie: NSImage? = nil
    @State private var targetSelfieURL: URL? = nil
    @State private var sourceFolderURL: URL? = nil
    @State private var threshold: Double = 0.55
    @State private var isSelfieHovered = false
    @State private var isFolderHovered = false
    @State private var isShowingCameraSheet = false
    @State private var isShowingPrivacyNotice = false
    @State private var hasAcceptedBiometricNotice = false
    @State private var selectedResultID: MatchResult.ID? = nil
    @State private var lightboxIndex: Int? = nil
    @State private var isShowingSaveFolderSheet = false
    @State private var saveFolderDraftName: String = ""
    /// Tracks the URL whose security scope we currently hold open, so that
    /// switching folders or clearing the session can release the old extension
    /// before adopting a new one. Always equal to (or nil alongside) sourceFolderURL.
    @State private var activeScopedURL: URL? = nil

    var body: some View {
        ZStack {
            VStack(spacing: 0) {
                header
                Divider().background(Tokens.border)

                HSplitView {
                    setupPanel
                    resultsPanel
                }

                Divider().background(Tokens.border)
                footer
            }
            .frame(minWidth: 980, minHeight: 680)
            .background(Tokens.bg)
            .foregroundColor(Tokens.textPrimary)

            if lightboxIndex != nil {
                LightboxView(
                    results: matcher.matchedResults,
                    currentIndex: $lightboxIndex
                )
                .transition(.opacity.animation(.easeInOut(duration: 0.2)))
                .zIndex(100)
            }
        }
        .preferredColorScheme(theme.preference.colorScheme)
        .animation(.easeInOut(duration: 0.20), value: theme.preference)
        .sheet(isPresented: $isShowingCameraSheet) {
            CameraCaptureSheet(isPresented: $isShowingCameraSheet) { capturedImage in
                self.setSelfie(capturedImage, url: nil)
            } onBrowseFile: {
                selectSelfieFile()
            }
        }
        .sheet(isPresented: $isShowingPrivacyNotice) {
            PrivacyNoticeSheet(
                isPresented: $isShowingPrivacyNotice,
                hasAcceptedBiometricNotice: $hasAcceptedBiometricNotice
            )
        }
        .sheet(isPresented: $isShowingSaveFolderSheet) {
            SaveFolderSheet(
                folderPath: sourceFolderURL?.path ?? "",
                name: $saveFolderDraftName,
                onCancel: { isShowingSaveFolderSheet = false },
                onConfirm: commitSaveCurrentFolder
            )
        }
    }

    private var header: some View {
        HStack(spacing: Space.m) {
            VStack(alignment: .leading, spacing: 2) {
                Text("What Happened Last Night")
                    .font(.system(size: 18, weight: .semibold, design: .serif))
                    .italic()
                    .foregroundColor(Tokens.textPrimary)
                Text("LOCAL BIOMETRIC RETRIEVAL SYSTEM / OFFLINE CORE V1")
                    .font(.system(size: 8, weight: .semibold, design: .monospaced))
                    .tracking(0.8)
                    .foregroundColor(Tokens.textTertiary)
            }

            OfflineBadge()
            Spacer()

            if let selfie = targetSelfie {
                IdentityStrip(
                    image: selfie,
                    label: targetSelfieURL?.lastPathComponent ?? "Selfie captured",
                    onClear: clearReferencePhoto
                )
            }

            if hasSessionState {
                ClearSessionButton(onClear: clearLocalData)
            }

            ThemeToggleButton()
            HeaderIconButton(
                systemName: "questionmark.circle",
                help: "Privacy details"
            ) { isShowingPrivacyNotice = true }
        }
        .padding(.horizontal, Space.xl)
        .padding(.vertical, Space.m)
        .background(Tokens.bg)
    }

    private var setupPanel: some View {
        VStack(spacing: 0) {
            ScrollView(.vertical, showsIndicators: false) {
                VStack(alignment: .leading, spacing: Space.m) {

                    StageCard(icon: "faceid", eyebrow: "1. Target identity") {
                        SelfieDropzone(
                            image: targetSelfie,
                            filename: targetSelfieURL?.lastPathComponent,
                            isHovered: $isSelfieHovered,
                            onCapture: { isShowingCameraSheet = true },
                            onDrop: loadSelfieFromDrop
                        )
                    }

                    StageCard(icon: "folder", eyebrow: "2. Photo folder") {
                        FolderDropzone(
                            folderURL: sourceFolderURL,
                            isHovered: $isFolderHovered,
                            onChoose: selectSourceFolder,
                            onDrop: loadFolderFromDrop,
                            savedFolders: savedFolders,
                            onPickSaved: pickSavedFolder,
                            onSaveCurrent: beginSaveCurrentFolder
                        )
                    }

                    ThresholdCard(threshold: $threshold)

                    if !matcher.isScanning {
                        ConsentCard(
                            consented: $hasAcceptedBiometricNotice,
                            onDetails: { isShowingPrivacyNotice = true }
                        )
                    }
                }
                .padding(Space.l)
                .frame(maxWidth: .infinity)
            }

            FindMeButton(
                matcher: matcher,
                consented: $hasAcceptedBiometricNotice,
                hasSelfie: targetSelfie != nil,
                hasFolder: sourceFolderURL != nil,
                onRun: runSelfieScan
            )
            .padding(.horizontal, Space.l)
            .padding(.bottom, Space.l)
            .padding(.top, Space.s)
            .background(Tokens.surfaceSunken)
        }
        .frame(width: 340)
        .background(Tokens.surfaceSunken)
    }

    private var resultsPanel: some View {
        VStack(spacing: 0) {
            ResultsHeader(count: matcher.matchedResults.count)
            if matcher.isScanning && matcher.matchedResults.isEmpty {
                ScanningPlaceholder(progress: matcher.progress, status: matcher.statusText)
            } else if matcher.hasScanned && matcher.matchedResults.isEmpty {
                NoMatchesState()
            } else if matcher.matchedResults.isEmpty {
                ResultsEmptyState(
                    hasSelfie: targetSelfie != nil,
                    hasFolder: sourceFolderURL != nil,
                    hasConsent: hasAcceptedBiometricNotice
                )
            } else {
                ResultsGrid(
                    results: matcher.matchedResults,
                    selectedID: $selectedResultID,
                    lightboxIndex: $lightboxIndex
                )
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Tokens.bg)
    }

    private var footer: some View {
        HStack(spacing: Space.l) {
            HStack(spacing: Space.xs + 2) {
                Circle()
                    .fill(Tokens.accentSecondary)
                    .frame(width: 5, height: 5)
                Text("ON-DEVICE ONLY · NO NETWORK")
                    .font(.system(size: 9, weight: .semibold, design: .monospaced))
                    .tracking(0.6)
                    .foregroundColor(Tokens.accentSecondary)
            }
            Text("Embeddings discarded on Clear")
                .font(.system(size: 9, design: .monospaced))
                .foregroundColor(Tokens.textTertiary)
            Spacer()
            Text("VISION + COREML FACENET")
                .font(.system(size: 9, weight: .medium, design: .monospaced))
                .tracking(0.5)
                .foregroundColor(Tokens.textTertiary)
        }
        .padding(.horizontal, Space.xl)
        .padding(.vertical, Space.s + 2)
        .background(Tokens.bg)
    }

    /// Default strictness used when the reference photo changes.
    ///
    /// 55% on the floor/ceiling mapping corresponds to cosine ~0.643 —
    /// just above the midpoint, tilted slightly toward fewer false
    /// positives while still catching strong matches. Users dial down
    /// for tough folders or up to tighten further.
    private static let defaultThreshold: Double = 0.55

    /// Sets a new reference photo and resets per-photo state: the privacy/consent
    /// acceptance is cleared and the strictness slider returns to its 60% default,
    /// so each new photo requires fresh consent.
    private func setSelfie(_ image: NSImage?, url: URL?) {
        targetSelfie = image
        targetSelfieURL = url
        hasAcceptedBiometricNotice = false
        threshold = Self.defaultThreshold
        // A new reference photo invalidates the previous run's matches.
        matcher.cancel()
        matcher.clearResults()
        selectedResultID = nil
        lightboxIndex = nil
    }

    private func selectSelfieFile() {
        let panel = NSOpenPanel()
        panel.allowedContentTypes = [.image]
        panel.canChooseFiles = true
        panel.canChooseDirectories = false
        panel.allowsMultipleSelection = false
        if panel.runModal() == .OK, let url = panel.url, let image = NSImage(contentsOf: url) {
            setSelfie(image, url: url)
        }
    }

    private func selectSourceFolder() {
        let panel = NSOpenPanel()
        panel.canChooseFiles = false
        panel.canChooseDirectories = true
        panel.allowsMultipleSelection = false
        if panel.runModal() == .OK, let url = panel.url {
            setSourceFolder(url)
        }
    }

    /// Sets the source folder from a previously-saved bookmark.
    ///
    /// Under the App Sandbox, just rebuilding a URL from the path string
    /// after relaunch grants no access — we must resolve the security-scoped
    /// bookmark we stored alongside it. The resolved URL already has its
    /// access started; `setSourceFolder` takes ownership and balances stop.
    ///
    /// When the bookmark is missing (legacy shortcut from before bookmarks
    /// were stored) or stale (folder moved / access revoked), we transparently
    /// fall back to `NSOpenPanel` pre-pointed at the saved path so the user
    /// can re-authorize with one click — and we refresh the stored bookmark
    /// in place so the same shortcut works going forward.
    private func pickSavedFolder(_ folder: SavedFolder) {
        switch savedFolders.resolve(folder) {
        case .ok(let url):
            setSourceFolder(url, scopedAccessAlreadyStarted: true)

        case .missingBookmark, .stale:
            reauthorizeShortcut(folder)
        }
    }

    /// Opens the system folder-picker pointed at a saved shortcut's path so
    /// the user can re-grant sandbox access in a single confirm. On success
    /// the bookmark is refreshed and the folder becomes the active source.
    private func reauthorizeShortcut(_ folder: SavedFolder) {
        let panel = NSOpenPanel()
        panel.canChooseFiles = false
        panel.canChooseDirectories = true
        panel.allowsMultipleSelection = false
        panel.directoryURL = URL(fileURLWithPath: folder.path, isDirectory: true)
        panel.message = "Re-authorize \"\(folder.name)\" so it can be reused after restarts"
        panel.prompt = "Authorize"

        guard panel.runModal() == .OK, let url = panel.url else { return }

        // Re-save updates the existing entry's name + bookmark in place
        // (matched by path), so the shortcut is now durable.
        savedFolders.add(name: folder.name, url: url)
        setSourceFolder(url)
    }

    /// Centralizes folder switching so both manual browse and shortcut picks
    /// behave identically: stale scan results are wiped and any prior
    /// security scope is released before we adopt the new URL.
    ///
    /// `scopedAccessAlreadyStarted` is true for bookmark-resolved URLs (the
    /// store already called `startAccessingSecurityScopedResource()`);
    /// `NSOpenPanel`/drop URLs don't need an explicit start so we don't
    /// attempt one.
    private func setSourceFolder(_ url: URL, scopedAccessAlreadyStarted: Bool = false) {
        if let previous = activeScopedURL, previous != url {
            previous.stopAccessingSecurityScopedResource()
        }
        activeScopedURL = scopedAccessAlreadyStarted ? url : nil
        sourceFolderURL = url
        matcher.cancel()
        matcher.clearResults()
    }

    /// Opens the "save current folder" sheet, pre-filled with the folder's
    /// own name as the default label.
    private func beginSaveCurrentFolder() {
        guard let url = sourceFolderURL else { return }
        saveFolderDraftName = url.lastPathComponent
        isShowingSaveFolderSheet = true
    }

    private func commitSaveCurrentFolder() {
        guard let url = sourceFolderURL else {
            isShowingSaveFolderSheet = false
            return
        }
        savedFolders.add(name: saveFolderDraftName, url: url)
        isShowingSaveFolderSheet = false
    }

    private var hasSessionState: Bool {
        targetSelfie != nil
            || sourceFolderURL != nil
            || hasAcceptedBiometricNotice
            || !matcher.matchedResults.isEmpty
            || matcher.isScanning
    }

    private func runSelfieScan() {
        guard hasAcceptedBiometricNotice else {
            isShowingPrivacyNotice = true
            return
        }
        guard let selfie = targetSelfie, let folder = sourceFolderURL else { return }
        Task {
            await matcher.scanPartyFolder(selfieImage: selfie, folderURL: folder, strictness: threshold)
        }
    }

    private func clearLocalData() {
        matcher.cancel()
        matcher.clearResults()
        targetSelfie = nil
        targetSelfieURL = nil
        // Release any held sandbox extension before dropping the URL.
        if let scoped = activeScopedURL {
            scoped.stopAccessingSecurityScopedResource()
        }
        activeScopedURL = nil
        sourceFolderURL = nil
        hasAcceptedBiometricNotice = false
        selectedResultID = nil
    }

    private func clearReferencePhoto() {
        targetSelfie = nil
        targetSelfieURL = nil
    }

    private func loadSelfieFromDrop(_ providers: [NSItemProvider]) -> Bool {
        guard let provider = providers.first else { return false }
        provider.loadItem(forTypeIdentifier: UTType.fileURL.identifier, options: nil) { item, _ in
            guard let data = item as? Data,
                  let url = URL(dataRepresentation: data, relativeTo: nil) else { return }
            DispatchQueue.main.async {
                if let image = NSImage(contentsOf: url) {
                    self.setSelfie(image, url: url)
                }
            }
        }
        return true
    }

    private func loadFolderFromDrop(_ providers: [NSItemProvider]) -> Bool {
        guard let provider = providers.first else { return false }
        provider.loadItem(forTypeIdentifier: UTType.directory.identifier, options: nil) { item, _ in
            guard let data = item as? Data,
                  let url = URL(dataRepresentation: data, relativeTo: nil) else { return }
            DispatchQueue.main.async { self.setSourceFolder(url) }
        }
        return true
    }
}

private struct StageCard<Content: View>: View {
    let icon: String
    let eyebrow: String
    @ViewBuilder let content: Content

    var body: some View {
        VStack(alignment: .leading, spacing: Space.m) {
            HStack(spacing: Space.xs + 2) {
                Image(systemName: icon)
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundColor(Tokens.accentPrimary)
                Text(eyebrow.uppercased())
                    .font(.system(size: 10, weight: .semibold, design: .monospaced))
                    .tracking(0.6)
                    .foregroundColor(Tokens.textSecondary)
            }
            content
        }
        .padding(Space.l - 2)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Tokens.surface)
        .clipShape(RoundedRectangle(cornerRadius: Radius.l))
        .overlay(
            RoundedRectangle(cornerRadius: Radius.l)
                .stroke(Tokens.border, lineWidth: 1)
        )
    }
}

private struct HeaderIconButton: View {
    let systemName: String
    let help: String
    let action: () -> Void
    @State private var isHovered = false

    var body: some View {
        Button(action: action) {
            Image(systemName: systemName)
                .font(.system(size: 13, weight: .semibold))
                .foregroundColor(Tokens.textSecondary)
                .frame(width: 28, height: 28)
                .background(isHovered ? Tokens.surfaceElevated : Color.clear)
                .clipShape(Circle())
                .overlay(Circle().stroke(Tokens.border, lineWidth: 1))
        }
        .buttonStyle(.plain)
        .onHover { isHovered = $0 }
        .help(help)
    }
}

private struct ClearSessionButton: View {
    let onClear: () -> Void
    @State private var isHovered = false

    var body: some View {
        Button(action: onClear) {
            HStack(spacing: Space.xs + 2) {
                Image(systemName: "trash")
                    .font(.system(size: 11, weight: .semibold))
                Text("Clear Session")
                    .font(.system(size: 11, weight: .semibold, design: .monospaced))
                    .tracking(0.5)
            }
            .foregroundColor(isHovered ? Tokens.error : Tokens.textSecondary)
            .padding(.horizontal, Space.s + 2)
            .padding(.vertical, 6)
            .background(isHovered ? Tokens.error.opacity(0.12) : Color.clear)
            .clipShape(RoundedRectangle(cornerRadius: Radius.s))
            .overlay(
                RoundedRectangle(cornerRadius: Radius.s)
                    .stroke(isHovered ? Tokens.error.opacity(0.5) : Tokens.border,
                            lineWidth: 1)
            )
        }
        .buttonStyle(.plain)
        .onHover { isHovered = $0 }
        .help("Withdraw consent and erase all in-memory session data")
        .accessibilityLabel("Clear session and withdraw biometric consent")
    }
}

private struct ThemeToggleButton: View {
    @EnvironmentObject var theme: ThemeManager
    @State private var isHovered = false

    private var next: AppearancePreference {
        switch theme.preference {
        case .system: return .light
        case .light:  return .dark
        case .dark:   return .system
        }
    }

    var body: some View {
        Button {
            withAnimation(.easeInOut(duration: 0.18)) {
                theme.preference = next
            }
        } label: {
            Image(systemName: theme.preference.sfSymbol)
                .font(.system(size: 14, weight: .semibold))
                .foregroundColor(Tokens.textSecondary)
                .frame(width: 28, height: 28)
                .background(isHovered ? Tokens.surfaceElevated : Color.clear)
                .clipShape(Circle())
        }
        .buttonStyle(.plain)
        .onHover { isHovered = $0 }
        .help("Appearance: \(theme.preference.label) — click for \(next.label)")
        .accessibilityLabel("Appearance: \(theme.preference.label)")
        .accessibilityHint("Switches to \(next.label)")
    }
}

private struct OfflineBadge: View {
    var body: some View {
        HStack(spacing: Space.xs + 2) {
            Image(systemName: "shield.lefthalf.filled")
                .font(.system(size: 10, weight: .semibold))
                .foregroundColor(Tokens.accentSecondary)
            Text("OFFLINE MODE")
                .font(.system(size: 10, weight: .semibold, design: .monospaced))
                .tracking(0.7)
                .foregroundColor(Tokens.accentSecondary)
        }
        .padding(.horizontal, Space.m)
        .padding(.vertical, 5)
        .background(Tokens.scoreHighBg)
        .clipShape(Capsule())
        .overlay(
            Capsule().stroke(Tokens.accentSecondary.opacity(0.35), lineWidth: 1)
        )
        .help("Network access is disabled for this app. Zero outbound requests this session.")
        .accessibilityLabel("Offline mode. Network access is disabled.")
    }
}

private struct IdentityStrip: View {
    let image: NSImage
    let label: String
    let onClear: () -> Void

    @State private var isHovered = false

    var body: some View {
        HStack(spacing: Space.s) {
            Image(nsImage: image)
                .resizable()
                .scaledToFill()
                .frame(width: 30, height: 30)
                .clipShape(RoundedRectangle(cornerRadius: Radius.s - 2))
            VStack(alignment: .leading, spacing: 1) {
                Text("REFERENCE")
                    .font(.system(size: 9, weight: .semibold, design: .monospaced))
                    .tracking(0.5)
                    .foregroundColor(Tokens.textTertiary)
                Text(label)
                    .font(.system(size: 11, weight: .medium, design: .monospaced))
                    .foregroundColor(Tokens.textPrimary)
                    .lineLimit(1)
                    .truncationMode(.middle)
                    .frame(maxWidth: 180, alignment: .leading)
            }
            Button(action: onClear) {
                Image(systemName: "xmark")
                    .font(.system(size: 9, weight: .bold))
                    .foregroundColor(isHovered ? Tokens.error : Tokens.textTertiary)
                    .frame(width: 18, height: 18)
                    .background(isHovered ? Tokens.error.opacity(0.12) : Color.clear)
                    .clipShape(Circle())
            }
            .buttonStyle(.plain)
            .onHover { isHovered = $0 }
            .help("Remove reference photo")
            .animation(.easeOut(duration: 0.12), value: isHovered)
        }
        .padding(.horizontal, Space.s + 2)
        .padding(.vertical, 5)
        .background(Tokens.surface)
        .clipShape(RoundedRectangle(cornerRadius: Radius.m))
        .overlay(
            RoundedRectangle(cornerRadius: Radius.m)
                .stroke(Tokens.border, lineWidth: 1)
        )
    }
}

private struct SelfieDropzone: View {
    let image: NSImage?
    let filename: String?
    @Binding var isHovered: Bool
    let onCapture: () -> Void
    let onDrop: ([NSItemProvider]) -> Bool

    private let boxHeight: CGFloat = 200

    var body: some View {
        VStack(spacing: Space.s) {
            Button(action: onCapture) {
                Group {
                    if let image = image {
                        ZStack {
                            RoundedRectangle(cornerRadius: Radius.m)
                                .fill(Tokens.surfaceSunken)
                            Image(nsImage: image)
                                .resizable()
                                .scaledToFit()
                                .clipShape(RoundedRectangle(cornerRadius: Radius.m - 2))
                        }
                        .frame(maxWidth: .infinity)
                        .frame(height: boxHeight)
                        .clipShape(RoundedRectangle(cornerRadius: Radius.m))
                        .overlay(
                            RoundedRectangle(cornerRadius: Radius.m)
                                .stroke(
                                    isHovered ? Tokens.accentPrimary : Tokens.border,
                                    lineWidth: isHovered ? 1.5 : 1
                                )
                        )
                    } else {
                        VStack(spacing: Space.s) {
                            Image(systemName: "camera.badge.ellipsis")
                                .font(.system(size: 28, weight: .light))
                                .foregroundColor(isHovered ? Tokens.accentPrimary : Tokens.textTertiary)
                            Text("UPLOAD IMAGE")
                                .font(.system(size: 11, weight: .semibold, design: .monospaced))
                                .tracking(0.8)
                                .foregroundColor(Tokens.textSecondary)
                        }
                        .frame(maxWidth: .infinity)
                        .frame(height: boxHeight)
                        .background(Tokens.surfaceSunken.opacity(0.5))
                        .clipShape(RoundedRectangle(cornerRadius: Radius.m))
                        .overlay(
                            RoundedRectangle(cornerRadius: Radius.m)
                                .stroke(
                                    isHovered ? Tokens.accentPrimary : Tokens.borderStrong.opacity(0.55),
                                    style: StrokeStyle(lineWidth: isHovered ? 1.5 : 1, dash: [5, 4])
                                )
                        )
                    }
                }
            }
            .buttonStyle(.plain)
            .onHover { isHovered = $0 }
            .onDrop(of: [.fileURL], isTargeted: nil, perform: onDrop)
            .help("Click to capture, or drag an image here")
            .animation(.easeOut(duration: 0.15), value: isHovered)

            if image != nil {
                Text(filename ?? "identity_preview.png")
                    .font(.system(size: 11, weight: .medium, design: .monospaced))
                    .foregroundColor(Tokens.accentPrimary)
                    .lineLimit(1)
                    .truncationMode(.middle)
            } else {
                Text("No image selected")
                    .font(.system(size: 11, design: .monospaced))
                    .foregroundColor(Tokens.textTertiary)
            }
        }
    }
}

private struct FolderDropzone: View {
    let folderURL: URL?
    @Binding var isHovered: Bool
    let onChoose: () -> Void
    let onDrop: ([NSItemProvider]) -> Bool
    @ObservedObject var savedFolders: SavedFoldersStore
    let onPickSaved: (SavedFolder) -> Void
    let onSaveCurrent: () -> Void

    private var currentSaved: SavedFolder? {
        guard let url = folderURL else { return nil }
        return savedFolders.entry(for: url)
    }

    private var hasSaved: Bool { !savedFolders.folders.isEmpty }

    var body: some View {
        VStack(alignment: .leading, spacing: Space.s) {
            // Action row: appears only when there's something to act on
            // (saved shortcuts to pick, or a folder to save).
            if hasSaved || folderURL != nil {
                FolderActionRow(
                    savedFolders: savedFolders,
                    currentURL: folderURL,
                    currentIsSaved: currentSaved != nil,
                    onPickSaved: onPickSaved,
                    onSaveCurrent: onSaveCurrent
                )
            }

            // Main folder card — adapts between empty and filled states.
            Button(action: onChoose) {
                Group {
                    if let url = folderURL {
                        FolderCardSelected(
                            url: url,
                            savedName: currentSaved?.name,
                            isHovered: isHovered
                        )
                    } else {
                        FolderCardEmpty(isHovered: isHovered)
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            .buttonStyle(.plain)
            .onHover { isHovered = $0 }
            .onDrop(of: [.directory], isTargeted: nil, perform: onDrop)
            .help(folderURL == nil ? "Click to pick a folder, or drag one here" : "Click to choose a different folder")
            .animation(.easeOut(duration: 0.18), value: isHovered)
            .animation(.easeOut(duration: 0.18), value: folderURL)
        }
    }
}

/// Empty-state card — dashed border invites the user to drop or click.
private struct FolderCardEmpty: View {
    let isHovered: Bool

    var body: some View {
        HStack(spacing: Space.m) {
            ZStack {
                Circle()
                    .fill(isHovered
                          ? Tokens.accentPrimary.opacity(0.12)
                          : Tokens.surfaceSunken.opacity(0.7))
                    .frame(width: 38, height: 38)
                Image(systemName: "folder.badge.plus")
                    .font(.system(size: 17, weight: .regular))
                    .foregroundColor(isHovered ? Tokens.accentPrimary : Tokens.textTertiary)
            }

            VStack(alignment: .leading, spacing: 2) {
                Text("Choose a folder")
                    .font(Typography.bodyStrong)
                    .foregroundColor(Tokens.textPrimary)
                Text("Click to browse, or drop a folder here")
                    .font(Typography.caption)
                    .foregroundColor(Tokens.textTertiary)
            }
            Spacer(minLength: 0)
        }
        .padding(.horizontal, Space.m)
        .padding(.vertical, Space.m)
        .background(Tokens.surfaceSunken.opacity(isHovered ? 0.45 : 0.30))
        .clipShape(RoundedRectangle(cornerRadius: Radius.m))
        .overlay(
            RoundedRectangle(cornerRadius: Radius.m)
                .stroke(
                    isHovered ? Tokens.accentPrimary : Tokens.borderStrong.opacity(0.45),
                    style: StrokeStyle(lineWidth: isHovered ? 1.5 : 1, dash: [4, 4])
                )
        )
    }
}

/// Filled-state card — clean solid border, integrated bookmark badge when
/// the current folder is a saved shortcut, single source of truth for the path.
private struct FolderCardSelected: View {
    let url: URL
    let savedName: String?
    let isHovered: Bool

    private var displayTitle: String {
        savedName ?? url.lastPathComponent
    }

    var body: some View {
        HStack(spacing: Space.m) {
            ZStack {
                RoundedRectangle(cornerRadius: 9)
                    .fill(Tokens.accentPrimary.opacity(0.14))
                    .frame(width: 38, height: 38)
                Image(systemName: "folder.fill")
                    .font(.system(size: 17, weight: .regular))
                    .foregroundColor(Tokens.accentPrimary)
            }

            VStack(alignment: .leading, spacing: 3) {
                HStack(spacing: 6) {
                    if savedName != nil {
                        Image(systemName: "bookmark.fill")
                            .font(.system(size: 9, weight: .bold))
                            .foregroundColor(Tokens.accentPrimary)
                    }
                    Text(displayTitle)
                        .font(Typography.bodyStrong)
                        .foregroundColor(Tokens.textPrimary)
                        .lineLimit(1)
                        .truncationMode(.middle)
                }
                Text(url.path)
                    .font(.system(size: 11, design: .monospaced))
                    .foregroundColor(Tokens.textTertiary)
                    .lineLimit(1)
                    .truncationMode(.middle)
            }

            Spacer(minLength: 0)

            // Affordance: subtle "change" cue on hover.
            Image(systemName: "arrow.triangle.2.circlepath")
                .font(.system(size: 11, weight: .semibold))
                .foregroundColor(isHovered ? Tokens.accentPrimary : Tokens.textTertiary.opacity(0.6))
                .opacity(isHovered ? 1.0 : 0.7)
        }
        .padding(.horizontal, Space.m)
        .padding(.vertical, Space.m)
        .background(Tokens.surface)
        .clipShape(RoundedRectangle(cornerRadius: Radius.m))
        .overlay(
            RoundedRectangle(cornerRadius: Radius.m)
                .stroke(
                    isHovered ? Tokens.accentPrimary.opacity(0.55) : Tokens.border,
                    lineWidth: isHovered ? 1.25 : 1
                )
        )
    }
}

/// Compact row above the folder card with two ghost-style actions:
///   • Saved shortcuts menu — shown only when the user has any
///   • Save-shortcut button — shown only when the current folder isn't saved
private struct FolderActionRow: View {
    @ObservedObject var savedFolders: SavedFoldersStore
    let currentURL: URL?
    let currentIsSaved: Bool
    let onPickSaved: (SavedFolder) -> Void
    let onSaveCurrent: () -> Void

    @State private var renameTarget: SavedFolder? = nil
    @State private var renameDraft: String = ""

    var body: some View {
        HStack(spacing: Space.xs + 2) {
            if !savedFolders.folders.isEmpty {
                savedFoldersMenu
            }

            Spacer(minLength: 0)

            if currentURL != nil && !currentIsSaved {
                saveShortcutButton
            }
        }
        .frame(height: 24)
        .sheet(item: $renameTarget) { folder in
            RenameSavedFolderSheet(
                originalName: folder.name,
                draft: $renameDraft,
                onCancel: { renameTarget = nil },
                onConfirm: {
                    savedFolders.rename(folder, to: renameDraft)
                    renameTarget = nil
                }
            )
        }
    }

    private var savedFoldersMenu: some View {
        Menu {
            Section("Use shortcut") {
                ForEach(savedFolders.folders) { folder in
                    Button {
                        onPickSaved(folder)
                    } label: {
                        Label(folder.name, systemImage: "folder")
                    }
                }
            }
            Divider()
            Section("Manage") {
                ForEach(savedFolders.folders) { folder in
                    Menu(folder.name) {
                        Button("Rename…") {
                            renameDraft = folder.name
                            renameTarget = folder
                        }
                        Button("Remove", role: .destructive) {
                            savedFolders.remove(folder)
                        }
                    }
                }
            }
        } label: {
            HStack(spacing: 5) {
                Image(systemName: "bookmark")
                    .font(.system(size: 10, weight: .semibold))
                Text("Shortcuts")
                    .font(.system(size: 12, weight: .medium))
                Image(systemName: "chevron.down")
                    .font(.system(size: 8, weight: .bold))
                    .opacity(0.7)
            }
            .foregroundColor(Tokens.textSecondary)
            .padding(.horizontal, 10)
            .padding(.vertical, 5)
            .background(
                Capsule()
                    .fill(Tokens.surfaceSunken.opacity(0.6))
            )
            .overlay(
                Capsule()
                    .stroke(Tokens.border, lineWidth: 0.75)
            )
        }
        .menuStyle(.borderlessButton)
        .menuIndicator(.hidden)
        .fixedSize()
        .help("Use a saved folder shortcut")
    }

    private var saveShortcutButton: some View {
        Button(action: onSaveCurrent) {
            HStack(spacing: 5) {
                Image(systemName: "bookmark")
                    .font(.system(size: 10, weight: .semibold))
                Text("Save shortcut")
                    .font(.system(size: 12, weight: .medium))
            }
            .foregroundColor(Tokens.accentPrimary)
            .padding(.horizontal, 10)
            .padding(.vertical, 5)
            .background(
                Capsule()
                    .fill(Tokens.accentPrimary.opacity(0.10))
            )
        }
        .buttonStyle(.plain)
        .help("Save this folder for quick reuse")
    }
}

/// Sheet shown when the user taps "Save" on the current folder. They give the
/// bookmark a friendly name (defaulting to the folder's own name).
private struct SaveFolderSheet: View {
    let folderPath: String
    @Binding var name: String
    let onCancel: () -> Void
    let onConfirm: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: Space.m) {
            Text("Save folder shortcut")
                .font(Typography.bodyStrong)
                .foregroundColor(Tokens.textPrimary)
            Text(folderPath)
                .font(.system(size: 11, design: .monospaced))
                .foregroundColor(Tokens.textTertiary)
                .lineLimit(2)
                .truncationMode(.middle)
            TextField("Display name", text: $name)
                .textFieldStyle(.roundedBorder)
                .frame(minWidth: 320)
            HStack {
                Spacer()
                Button("Cancel", action: onCancel)
                    .keyboardShortcut(.cancelAction)
                Button("Save", action: onConfirm)
                    .keyboardShortcut(.defaultAction)
                    .disabled(name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            }
        }
        .padding(Space.l)
        .frame(minWidth: 360)
    }
}

/// Small sheet for renaming a saved folder shortcut.
private struct RenameSavedFolderSheet: View {
    let originalName: String
    @Binding var draft: String
    let onCancel: () -> Void
    let onConfirm: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: Space.m) {
            Text("Rename saved folder")
                .font(Typography.bodyStrong)
                .foregroundColor(Tokens.textPrimary)
            Text("Was: \(originalName)")
                .font(.system(size: 11, design: .monospaced))
                .foregroundColor(Tokens.textTertiary)
            TextField("Folder name", text: $draft)
                .textFieldStyle(.roundedBorder)
                .frame(minWidth: 280)
            HStack {
                Spacer()
                Button("Cancel", action: onCancel)
                    .keyboardShortcut(.cancelAction)
                Button("Save", action: onConfirm)
                    .keyboardShortcut(.defaultAction)
                    .disabled(draft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            }
        }
        .padding(Space.l)
        .frame(minWidth: 320)
    }
}

private struct ThresholdCard: View {
    @Binding var threshold: Double

    var body: some View {
        VStack(alignment: .leading, spacing: Space.s) {
            HStack(spacing: Space.xs + 2) {
                Image(systemName: "slider.horizontal.3")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundColor(Tokens.accentPrimary)
                Text("STRICTNESS")
                    .font(.system(size: 10, weight: .semibold, design: .monospaced))
                    .tracking(0.6)
                    .foregroundColor(Tokens.textSecondary)
                Spacer()
                Text("\(Int(threshold * 100))%")
                    .font(Typography.scoreNumeral)
                    .foregroundColor(Tokens.accentPrimary)
            }
            ZStack {
                RoundedRectangle(cornerRadius: Radius.s)
                    .fill(Tokens.surfaceSunken)
                    .frame(height: 30)
                Slider(
                    value: $threshold,
                    in: 0.05...0.95,
                    minimumValueLabel: Text("5%")
                        .font(.system(size: 10, weight: .semibold, design: .monospaced))
                        .foregroundColor(Tokens.textTertiary),
                    maximumValueLabel: Text("95%")
                        .font(.system(size: 10, weight: .semibold, design: .monospaced))
                        .foregroundColor(Tokens.textTertiary)
                ) {
                    EmptyView()
                }
                .tint(Tokens.accentPrimary)
                .padding(.horizontal, Space.s)
            }
            HStack {
                Text("MORE RESULTS")
                    .font(.system(size: 9, weight: .semibold, design: .monospaced))
                    .tracking(0.6)
                    .foregroundColor(Tokens.textTertiary)
                Spacer()
                Text("FEWER FALSE POSITIVES")
                    .font(.system(size: 9, weight: .semibold, design: .monospaced))
                    .tracking(0.6)
                    .foregroundColor(Tokens.textTertiary)
            }
        }
        .padding(Space.l - 2)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Tokens.surface)
        .clipShape(RoundedRectangle(cornerRadius: Radius.l))
        .overlay(
            RoundedRectangle(cornerRadius: Radius.l)
                .stroke(Tokens.border, lineWidth: 1)
        )
    }
}

private struct FindMeButton: View {
    @ObservedObject var matcher: FaceMatcher
    @Binding var consented: Bool
    let hasSelfie: Bool
    let hasFolder: Bool
    let onRun: () -> Void

    private var canRun: Bool { hasSelfie && hasFolder && consented }

    private var disabledReason: String {
        if !hasSelfie { return "Add a selfie first" }
        if !hasFolder { return "Pick a folder first" }
        if !consented { return "Give explicit consent to biometric processing first" }
        return ""
    }

    var body: some View {
        VStack(alignment: .leading, spacing: Space.s) {
            if matcher.isScanning {
                VStack(spacing: Space.s) {
                    ProgressView(value: matcher.progress, total: 1.0)
                        .progressViewStyle(.linear)
                        .tint(Tokens.accentPrimary)
                    HStack {
                        Text(matcher.statusText.localizedCapitalized)
                            .font(Typography.caption)
                            .foregroundColor(Tokens.textSecondary)
                            .lineLimit(1)
                        Spacer()
                        Text("\(Int(matcher.progress * 100))%")
                            .font(Typography.scoreNumeral)
                            .foregroundColor(Tokens.textPrimary)
                    }
                }
                Button(action: matcher.cancel) {
                    Text("Cancel scan")
                        .font(Typography.bodyStrong)
                        .foregroundColor(Tokens.error)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, Space.s + 2)
                        .background(Tokens.surface)
                        .overlay(
                            RoundedRectangle(cornerRadius: Radius.m)
                                .stroke(Tokens.error.opacity(0.4), lineWidth: 1)
                        )
                        .clipShape(RoundedRectangle(cornerRadius: Radius.m))
                }
                .buttonStyle(.plain)
            } else {
                Button(action: onRun) {
                    HStack(spacing: Space.s) {
                        Image(systemName: "wand.and.stars")
                            .font(.system(size: 14, weight: .semibold))
                        Text("Find Me")
                            .font(.system(size: 15, weight: .semibold))
                    }
                    .foregroundColor(canRun ? Tokens.onAccent : Tokens.accentPrimary.opacity(0.75))
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, Space.m)
                    .background(canRun ? Tokens.accentPrimary : Tokens.accentPrimary.opacity(0.35))
                    .clipShape(RoundedRectangle(cornerRadius: Radius.m))
                }
                .buttonStyle(.plain)
                .disabled(!canRun)
                .keyboardShortcut(.return, modifiers: [.command])
                .help(canRun ? "⌘↩  Start scanning" : disabledReason)
            }
        }
    }
}

private struct ConsentCard: View {
    @Binding var consented: Bool
    let onDetails: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: Space.s) {
            HStack(spacing: Space.xs + 2) {
                Image(systemName: "lock.shield")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundColor(Tokens.accentSecondary)
                Text("PRIVACY & CONSENT · GDPR ART. 9")
                    .font(.system(size: 10, weight: .semibold, design: .monospaced))
                    .tracking(0.6)
                    .foregroundColor(Tokens.accentSecondary)
            }

            Text("Face matching produces biometric data — a special category under GDPR Article 9. Processing happens only on this device. Nothing is uploaded, logged, or written to disk. You can withdraw consent any time via Clear Session.")
                .font(Typography.caption)
                .foregroundColor(Tokens.textSecondary)
                .fixedSize(horizontal: false, vertical: true)

            Toggle(isOn: $consented) {
                Text("I give explicit consent to on-device biometric processing for this session (GDPR Art. 9(2)(a)).")
                    .font(Typography.body)
                    .foregroundColor(Tokens.textPrimary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .toggleStyle(.checkbox)

            Button(action: onDetails) {
                HStack(spacing: Space.xs + 2) {
                    Image(systemName: "info.circle")
                        .font(.system(size: 11, weight: .semibold))
                    Text("PRIVACY DETAILS")
                        .font(.system(size: 10, weight: .semibold, design: .monospaced))
                        .tracking(0.6)
                }
                .foregroundColor(Tokens.textSecondary)
                .frame(maxWidth: .infinity)
                .padding(.vertical, Space.s + 2)
                .background(Tokens.surface)
                .clipShape(RoundedRectangle(cornerRadius: Radius.m))
                .overlay(
                    RoundedRectangle(cornerRadius: Radius.m)
                        .stroke(Tokens.border, lineWidth: 1)
                )
            }
            .buttonStyle(.plain)
            .help("Read the full privacy notice")
        }
        .padding(Space.l - 2)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Tokens.scoreHighBg)
        .clipShape(RoundedRectangle(cornerRadius: Radius.l))
        .overlay(
            RoundedRectangle(cornerRadius: Radius.l)
                .stroke(Tokens.accentSecondary.opacity(consented ? 0.55 : 0.30),
                        lineWidth: consented ? 1.5 : 1)
        )
        .animation(.easeInOut(duration: 0.15), value: consented)
    }
}

private struct ResultsHeader: View {
    let count: Int

    var body: some View {
        HStack {
            VStack(alignment: .leading, spacing: Space.xs) {
                Text("Matches")
                    .font(.system(size: 28, weight: .bold))
                    .foregroundColor(Tokens.textPrimary)
                HStack(spacing: Space.xs + 2) {
                    Circle()
                        .fill(Tokens.accentSecondary)
                        .frame(width: 6, height: 6)
                    Text(count == 0
                         ? "Ready when you are"
                         : "\(count) photo\(count == 1 ? "" : "s") above threshold")
                        .font(Typography.body)
                        .foregroundColor(Tokens.textSecondary)
                }
            }
            Spacer()
        }
        .padding(.horizontal, Space.xl)
        .padding(.vertical, Space.l)
        .background(Tokens.bg)
    }
}

private struct NoMatchesState: View {
    var body: some View {
        VStack(spacing: Space.xl) {
            ZStack {
                Circle()
                    .fill(Tokens.textTertiary.opacity(0.08))
                    .frame(width: 110, height: 110)
                    .blur(radius: 8)
                Circle()
                    .fill(Tokens.surfaceElevated)
                    .frame(width: 88, height: 88)
                    .overlay(Circle().stroke(Tokens.border, lineWidth: 1))
                Image(systemName: "person.fill.questionmark")
                    .font(.system(size: 32, weight: .regular))
                    .foregroundColor(Tokens.textTertiary)
            }

            VStack(spacing: Space.s) {
                Text("No matches found")
                    .font(.system(size: 22, weight: .semibold))
                    .foregroundColor(Tokens.textPrimary)
                Text("Nobody in the scanned folder matched your reference above the current strictness threshold. Try lowering the strictness slider and scanning again.")
                    .font(Typography.body)
                    .foregroundColor(Tokens.textSecondary)
                    .multilineTextAlignment(.center)
                    .frame(maxWidth: 360)
            }

            HStack(spacing: Space.xs + 2) {
                Image(systemName: "slider.horizontal.3")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundColor(Tokens.accentPrimary)
                Text("Lower strictness → more results")
                    .font(.system(size: 11, weight: .medium, design: .monospaced))
                    .foregroundColor(Tokens.textTertiary)
            }
            .padding(.horizontal, Space.l)
            .padding(.vertical, Space.s + 2)
            .background(Tokens.surfaceElevated.opacity(0.6))
            .clipShape(RoundedRectangle(cornerRadius: Radius.m))
            .overlay(RoundedRectangle(cornerRadius: Radius.m).stroke(Tokens.border, lineWidth: 1))
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .padding(Space.xl)
    }
}

private struct ResultsEmptyState: View {
    let hasSelfie: Bool
    let hasFolder: Bool
    let hasConsent: Bool

    private var allReady: Bool { hasSelfie && hasFolder && hasConsent }

    private var title: String {
        allReady ? "Ready to find you" : "No local matches yet"
    }

    private var subtitle: String {
        allReady
            ? "Press Find Me to scan your folder on-device."
            : "Provide a reference selfie, point to a folder, and confirm consent — everything runs locally."
    }

    var body: some View {
        VStack(spacing: Space.xl) {
            ZStack {
                Circle()
                    .fill(Tokens.accentSecondary.opacity(0.10))
                    .frame(width: 110, height: 110)
                    .blur(radius: 8)
                Circle()
                    .fill(Tokens.surfaceElevated)
                    .frame(width: 88, height: 88)
                    .overlay(Circle().stroke(Tokens.border, lineWidth: 1))
                Image(systemName: "doc.text.magnifyingglass")
                    .font(.system(size: 34, weight: .regular))
                    .foregroundColor(Tokens.textTertiary)
            }

            VStack(spacing: Space.s) {
                Text(title)
                    .font(.system(size: 22, weight: .semibold))
                    .foregroundColor(Tokens.textPrimary)
                Text(subtitle)
                    .font(Typography.body)
                    .foregroundColor(Tokens.textSecondary)
                    .multilineTextAlignment(.center)
                    .frame(maxWidth: 360)
            }

            VStack(alignment: .leading, spacing: Space.s) {
                EmptyStateStep(done: hasSelfie,  text: "Add a reference selfie")
                EmptyStateStep(done: hasFolder,  text: "Choose a folder of photos")
                EmptyStateStep(done: hasConsent, text: "Confirm privacy consent")
            }
            .padding(.horizontal, Space.l)
            .padding(.vertical, Space.m)
            .background(Tokens.surfaceElevated.opacity(0.6))
            .clipShape(RoundedRectangle(cornerRadius: Radius.m))
            .overlay(
                RoundedRectangle(cornerRadius: Radius.m)
                    .stroke(Tokens.border, lineWidth: 1)
            )
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

private struct EmptyStateStep: View {
    let done: Bool
    let text: String

    var body: some View {
        HStack(spacing: Space.s + 2) {
            ZStack {
                Circle()
                    .fill(done ? Tokens.accentSecondary : Color.clear)
                    .frame(width: 18, height: 18)
                Circle()
                    .stroke(done ? Tokens.accentSecondary : Tokens.borderStrong, lineWidth: 1.5)
                    .frame(width: 18, height: 18)
                if done {
                    Image(systemName: "checkmark")
                        .font(.system(size: 10, weight: .bold))
                        .foregroundColor(Tokens.onAccent)
                }
            }
            Text(text)
                .font(Typography.body)
                .foregroundColor(done ? Tokens.textPrimary : Tokens.textSecondary)
        }
        .animation(.easeInOut(duration: 0.15), value: done)
    }
}

private struct ScanningPlaceholder: View {
    let progress: Double
    let status: String

    var body: some View {
        VStack(spacing: Space.m) {
            ProgressView(value: progress, total: 1.0)
                .progressViewStyle(.linear)
                .tint(Tokens.accentPrimary)
                .frame(maxWidth: 280)
            Text(status.localizedCapitalized)
                .font(Typography.body)
                .foregroundColor(Tokens.textSecondary)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Tokens.bg)
    }
}

private struct ResultsGrid: View {
    let results: [MatchResult]
    @Binding var selectedID: MatchResult.ID?
    @Binding var lightboxIndex: Int?

    private let columns = [GridItem(.adaptive(minimum: 260, maximum: 360), spacing: Space.xl)]

    var body: some View {
        ScrollView {
            LazyVGrid(columns: columns, spacing: Space.xl) {
                ForEach(Array(results.enumerated()), id: \.element.id) { index, r in
                    ResultTile(
                        result: r,
                        isSelected: selectedID == r.id
                    )
                    .onTapGesture {
                        selectedID = r.id
                        lightboxIndex = index
                    }
                }
            }
            .padding(Space.xl)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Tokens.bg)
    }
}

private struct LightboxView: View {
    let results: [MatchResult]
    @Binding var currentIndex: Int?

    @State private var fullImage: NSImage? = nil
    @State private var zoomScale: CGFloat = 1.0
    @State private var offset: CGSize = .zero
    @GestureState private var dragOffset: CGSize = .zero
    @GestureState private var magnifyDelta: CGFloat = 1.0
    @State private var eventMonitor: Any? = nil

    private var index: Int { currentIndex ?? 0 }
    private var result: MatchResult { results[index] }
    private var tier: ScoreTier { ScoreTier.from(result.similarity) }
    private var pct: Int { Int((result.similarity * 100).rounded()) }
    private var hasPrev: Bool { index > 0 }
    private var hasNext: Bool { index < results.count - 1 }

    var body: some View {
        ZStack {
            Color.black.opacity(0.88)
                .ignoresSafeArea()
                .onTapGesture { dismiss() }

            VStack(spacing: 0) {
                HStack(spacing: Space.s) {
                    HStack(spacing: 6) {
                        Circle().fill(tier.color).frame(width: 7, height: 7)
                        Text("\(pct)%")
                            .font(.system(size: 13, weight: .bold, design: .monospaced))
                            .foregroundColor(.white)
                    }
                    .padding(.horizontal, 10).padding(.vertical, 5)
                    .background(.ultraThinMaterial)
                    .clipShape(Capsule())

                    if results.count > 1 {
                        Text("\(index + 1) / \(results.count)")
                            .font(.system(size: 11, weight: .semibold, design: .monospaced))
                            .foregroundColor(.white.opacity(0.55))
                    }

                    Text(result.fileURL.lastPathComponent)
                        .font(.system(size: 12, weight: .medium, design: .monospaced))
                        .foregroundColor(.white.opacity(0.75))
                        .lineLimit(1)
                        .truncationMode(.middle)

                    Spacer()

                    HStack(spacing: Space.s) {
                        Button { zoomOut() } label: { toolbarIcon("minus.magnifyingglass") }
                            .buttonStyle(.plain).help("Zoom out")

                        Button { resetZoom() } label: {
                            Text(zoomScale == 1.0 ? "1×" : String(format: "%.1f×", zoomScale))
                                .font(.system(size: 11, weight: .semibold, design: .monospaced))
                                .foregroundColor(.white)
                                .frame(minWidth: 36)
                                .frame(height: 30)
                                .background(.ultraThinMaterial)
                                .clipShape(Capsule())
                        }.buttonStyle(.plain).help("Reset zoom")

                        Button { zoomIn() } label: { toolbarIcon("plus.magnifyingglass") }
                            .buttonStyle(.plain).help("Zoom in")

                        Button(action: revealInFinder) { toolbarIcon("arrow.up.right.square") }
                            .buttonStyle(.plain).help("Reveal in Finder")

                        Button(action: dismiss) { toolbarIcon("xmark") }
                            .buttonStyle(.plain).help("Close (Esc)")
                    }
                }
                .padding(.horizontal, Space.l)
                .padding(.vertical, Space.m)
                .background(.ultraThinMaterial)

                ZStack {
                    GeometryReader { geo in
                        let effectiveScale = zoomScale * magnifyDelta
                        let effectiveOffset = CGSize(
                            width: offset.width + dragOffset.width,
                            height: offset.height + dragOffset.height
                        )

                        ZStack {
                            if let img = fullImage {
                                Image(nsImage: img)
                                    .resizable()
                                    .scaledToFit()
                                    .scaleEffect(effectiveScale)
                                    .offset(effectiveOffset)
                                    .gesture(
                                        MagnifyGesture()
                                            .updating($magnifyDelta) { val, state, _ in state = val.magnification }
                                            .onEnded { val in
                                                zoomScale = max(1.0, min(8.0, zoomScale * val.magnification))
                                                clampOffset(in: geo.size)
                                            }
                                    )
                                    .gesture(
                                        DragGesture()
                                            .updating($dragOffset) { val, state, _ in state = val.translation }
                                            .onEnded { val in
                                                offset = CGSize(
                                                    width: offset.width + val.translation.width,
                                                    height: offset.height + val.translation.height
                                                )
                                                clampOffset(in: geo.size)
                                            }
                                    )
                                    .onScrollWheel { delta in
                                        let factor = 1.0 - delta.y * 0.05
                                        zoomScale = max(1.0, min(8.0, zoomScale * factor))
                                        clampOffset(in: geo.size)
                                    }
                            } else {
                                ProgressView().scaleEffect(1.2).tint(.white)
                            }
                        }
                        .frame(width: geo.size.width, height: geo.size.height)
                        .contentShape(Rectangle())
                        .onTapGesture(count: 2) {
                            withAnimation(.spring(response: 0.3, dampingFraction: 0.75)) {
                                if zoomScale > 1.0 { resetZoom() } else { zoomScale = 2.5 }
                            }
                        }
                    }

                    HStack {
                        CarouselArrow(direction: .prev, enabled: hasPrev) { navigateTo(index - 1) }
                        Spacer()
                        CarouselArrow(direction: .next, enabled: hasNext) { navigateTo(index + 1) }
                    }
                    .padding(.horizontal, Space.l)
                }
                .clipped()
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
        .onAppear {
            loadImage(for: result)
            startKeyMonitor()
        }
        .onDisappear {
            if let m = eventMonitor { NSEvent.removeMonitor(m); eventMonitor = nil }
        }
    }

    @ViewBuilder
    private func toolbarIcon(_ name: String) -> some View {
        Image(systemName: name)
            .font(.system(size: 14, weight: .semibold))
            .foregroundColor(.white)
            .frame(width: 30, height: 30)
            .background(.ultraThinMaterial)
            .clipShape(Circle())
    }

    private func navigateTo(_ newIndex: Int) {
        guard results.indices.contains(newIndex) else { return }
        resetZoom()
        fullImage = nil
        currentIndex = newIndex
        loadImage(for: results[newIndex])
    }

    private func loadImage(for r: MatchResult) {
        DispatchQueue.global(qos: .userInitiated).async {
            let img = NSImage(contentsOf: r.fileURL)
            DispatchQueue.main.async { fullImage = img }
        }
    }

    private func dismiss() { currentIndex = nil }

    private func startKeyMonitor() {
        eventMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { event in
            switch event.keyCode {
            case 123: navigateTo(index - 1); return nil
            case 124: navigateTo(index + 1); return nil
            case 53:  dismiss();             return nil
            default:  return event
            }
        }
    }

    private func zoomIn()  { withAnimation(.easeOut(duration: 0.2)) { zoomScale = min(8.0, zoomScale * 1.5) } }
    private func zoomOut() {
        withAnimation(.easeOut(duration: 0.2)) {
            zoomScale = max(1.0, zoomScale / 1.5)
            if zoomScale <= 1.0 { offset = .zero }
        }
    }
    private func resetZoom() {
        withAnimation(.spring(response: 0.3, dampingFraction: 0.75)) { zoomScale = 1.0; offset = .zero }
    }
    private func clampOffset(in size: CGSize) {
        let maxX = max(0, (size.width  * (zoomScale - 1)) / 2)
        let maxY = max(0, (size.height * (zoomScale - 1)) / 2)
        offset = CGSize(
            width:  max(-maxX, min(maxX, offset.width)),
            height: max(-maxY, min(maxY, offset.height))
        )
    }
    private func revealInFinder() {
        NSWorkspace.shared.activateFileViewerSelecting([result.fileURL])
    }
}

private enum ArrowDirection { case prev, next }

private struct CarouselArrow: View {
    let direction: ArrowDirection
    let enabled: Bool
    let action: () -> Void
    @State private var isHovered = false

    var body: some View {
        Button(action: action) {
            Image(systemName: direction == .prev ? "chevron.left" : "chevron.right")
                .font(.system(size: 18, weight: .semibold))
                .foregroundColor(.white.opacity(enabled ? 1.0 : 0.25))
                .frame(width: 44, height: 44)
                .background(.ultraThinMaterial.opacity(isHovered && enabled ? 1 : 0.55))
                .clipShape(Circle())
                .scaleEffect(isHovered && enabled ? 1.08 : 1.0)
        }
        .buttonStyle(.plain)
        .disabled(!enabled)
        .onHover { isHovered = $0 }
        .animation(.easeOut(duration: 0.15), value: isHovered)
        .help(direction == .prev ? "Previous photo (←)" : "Next photo (→)")
    }
}

private struct ScrollWheelModifier: ViewModifier {
    let action: (CGPoint) -> Void
    func body(content: Content) -> some View {
        content.background(ScrollWheelView(action: action))
    }
}

private struct ScrollWheelView: NSViewRepresentable {
    let action: (CGPoint) -> Void
    func makeNSView(context: Context) -> _ScrollWheelNSView {
        let v = _ScrollWheelNSView()
        v.action = action
        return v
    }
    func updateNSView(_ nsView: _ScrollWheelNSView, context: Context) {}
}

class _ScrollWheelNSView: NSView {
    var action: ((CGPoint) -> Void)?
    override func scrollWheel(with event: NSEvent) {
        action?(CGPoint(x: event.deltaX, y: event.deltaY))
    }
}

extension View {
    func onScrollWheel(_ action: @escaping (CGPoint) -> Void) -> some View {
        modifier(ScrollWheelModifier(action: action))
    }
}

private struct ResultTile: View {
    let result: MatchResult
    let isSelected: Bool

    @State private var thumbnail: NSImage? = nil
    @State private var isHovered = false

    private var tier: ScoreTier { ScoreTier.from(result.similarity) }
    private var pct: Int { Int((result.similarity * 100).rounded()) }

    private var glowRadius: CGFloat {
        switch tier {
        case .high:   return isHovered ? 22 : 14
        case .medium: return isHovered ? 12 : 6
        case .low:    return 0
        }
    }

    private var glowOpacity: Double {
        switch tier {
        case .high:   return 0.50
        case .medium: return 0.25
        case .low:    return 0.0
        }
    }

    var body: some View {
        ZStack(alignment: .bottom) {
            ZStack(alignment: .topTrailing) {
                Rectangle()
                    .fill(Tokens.surfaceSunken)
                    .overlay {
                        if let thumbnail {
                            Image(nsImage: thumbnail)
                                .resizable()
                                .scaledToFill()
                                .transition(.opacity.animation(.easeIn(duration: 0.25)))
                        } else {
                            ProgressView()
                                .scaleEffect(0.7)
                        }
                    }
                    .clipped()

                HStack(spacing: 4) {
                    Circle()
                        .fill(tier.color)
                        .frame(width: 6, height: 6)
                    Text("\(pct)%")
                        .font(.system(size: 13, weight: .bold, design: .monospaced))
                        .foregroundColor(.white)
                }
                .padding(.horizontal, 10)
                .padding(.vertical, 5)
                .background(.ultraThinMaterial)
                .clipShape(Capsule())
                .padding(10)
            }
            .frame(maxWidth: .infinity)
            .aspectRatio(4/3, contentMode: .fit)
            .clipped()

            HStack(spacing: Space.xs) {
                Image(systemName: "photo")
                    .font(.system(size: 10, weight: .medium))
                    .foregroundColor(.white.opacity(0.7))
                Text(result.fileURL.lastPathComponent)
                    .font(.system(size: 11, weight: .semibold, design: .monospaced))
                    .foregroundColor(.white)
                    .lineLimit(1)
                    .truncationMode(.middle)
                Spacer(minLength: 0)
                if result.faceCount > 1 {
                    HStack(spacing: 3) {
                        Image(systemName: "person.2.fill")
                            .font(.system(size: 9))
                        Text("\(result.faceCount)")
                            .font(.system(size: 10, weight: .semibold, design: .monospaced))
                    }
                    .foregroundColor(.white.opacity(0.8))
                }
                Button(action: revealInFinder) {
                    Image(systemName: "arrow.up.right.square")
                        .font(.system(size: 13, weight: .medium))
                        .foregroundColor(.white.opacity(0.8))
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .help("Reveal in Finder")
            }
            .padding(.horizontal, Space.m)
            .padding(.vertical, Space.s + 2)
            .background(
                LinearGradient(
                    colors: [.black.opacity(0.0), .black.opacity(0.72)],
                    startPoint: .top,
                    endPoint: .bottom
                )
            )
        }
        .clipShape(RoundedRectangle(cornerRadius: Radius.l))
        .overlay(
            RoundedRectangle(cornerRadius: Radius.l)
                .stroke(
                    isSelected ? Tokens.accentPrimary : tier.color.opacity(tier == .low ? 0.18 : 0.60),
                    lineWidth: isSelected ? 2.5 : (tier == .high ? 1.5 : 1)
                )
        )
        .shadow(color: tier.color.opacity(glowOpacity), radius: glowRadius, x: 0, y: 4)
        .scaleEffect(isHovered ? 1.02 : 1.0)
        .animation(.spring(response: 0.25, dampingFraction: 0.7), value: isHovered)
        .onHover { isHovered = $0 }
        .onAppear(perform: loadThumbnailAsync)
        .accessibilityLabel("\(result.fileURL.lastPathComponent), \(tier.label), \(pct) percent")
    }

    private func loadThumbnailAsync() {
        DispatchQueue.global(qos: .userInitiated).async {
            if let image = NSImage(contentsOf: result.fileURL) {
                let resized = image.resized(to: NSSize(width: 480, height: 360))
                DispatchQueue.main.async { self.thumbnail = resized }
            }
        }
    }

    private func revealInFinder() {
        NSWorkspace.shared.activateFileViewerSelecting([result.fileURL])
    }
}

struct PrivacyNoticeSheet: View {
    @Binding var isPresented: Bool
    @Binding var hasAcceptedBiometricNotice: Bool

    var body: some View {
        ScrollView(.vertical, showsIndicators: true) {
            VStack(alignment: .leading, spacing: Space.l) {
                HStack(spacing: Space.s) {
                    Image(systemName: "lock.shield")
                        .font(.system(size: 22, weight: .semibold))
                        .foregroundColor(Tokens.accentSecondary)
                    Text("Privacy Notice (GDPR)")
                        .font(Typography.h2)
                        .foregroundColor(Tokens.textPrimary)
                }

                VStack(alignment: .leading, spacing: Space.m) {
                    PrivacyNoticeRow(
                        title: "Controller",
                        message: "The natural person running this app on their own Mac acts as the data controller for their own selfie and selected photos. The project author / distributor is not a controller because no data leaves the device. See PRIVACY.md for contact details."
                    )
                    PrivacyNoticeRow(
                        title: "Purpose",
                        message: "Compare a selfie you provide with faces found in image files you choose, only to show possible matches in this session."
                    )
                    PrivacyNoticeRow(
                        title: "Lawful basis (Art. 9(2)(a))",
                        message: "Processing of biometric data — a special category under GDPR Article 9 — is performed on the basis of your explicit, informed, freely given consent for this session only."
                    )
                    PrivacyNoticeRow(
                        title: "Local processing",
                        message: "Face detection, crops, and FaceNet embeddings run on this device using Apple Vision and CoreML. The app target has incoming and outgoing network access disabled at the macOS sandbox level."
                    )
                    PrivacyNoticeRow(
                        title: "Storage and retention",
                        message: "Selfies, source photos, biometric embeddings, similarity scores, and match results are held in memory only for the duration of the session. Nothing is written to app storage, UserDefaults, Keychain, or any database. Clear Session removes all in-memory state immediately."
                    )
                    PrivacyNoticeRow(
                        title: "Your rights",
                        message: "Because no personal data is stored or transmitted, requests for access, rectification, erasure, restriction, portability, and objection (Art. 15–21) are satisfied automatically: closing the app or pressing Clear Session erases everything. You can withdraw consent at any time without affecting the lawfulness of processing done before withdrawal (Art. 7(3))."
                    )
                    PrivacyNoticeRow(
                        title: "Third parties",
                        message: "No third-party SDKs, analytics, telemetry, tracking, advertising, or fonts are loaded. Apple Vision and CoreML run entirely on-device."
                    )
                    PrivacyNoticeRow(
                        title: "Logging",
                        message: "Debug logs do not include personal photo filenames, similarity scores, or embedding values. A generic message may note that one selected file was skipped without naming the file."
                    )
                }

                Divider()

                Toggle(isOn: $hasAcceptedBiometricNotice) {
                    Text("I give explicit consent to on-device biometric processing for this session (GDPR Art. 9(2)(a)).")
                        .font(Typography.body)
                        .foregroundColor(Tokens.textPrimary)
                        .fixedSize(horizontal: false, vertical: true)
                }
                .toggleStyle(.checkbox)

                Text("You may withdraw consent at any time by pressing Clear Session in the header. Withdrawal stops further processing and clears all in-memory data.")
                    .font(Typography.caption)
                    .foregroundColor(Tokens.textSecondary)
                    .fixedSize(horizontal: false, vertical: true)

                HStack {
                    Spacer()
                    Button("Close") { isPresented = false }
                        .keyboardShortcut(.cancelAction)
                    Button("Accept and Continue") {
                        hasAcceptedBiometricNotice = true
                        isPresented = false
                    }
                    .keyboardShortcut(.defaultAction)
                }
            }
            .padding(Space.xl)
        }
        .frame(width: 600, height: 620)
        .background(Tokens.surface)
    }
}

struct PrivacyNoticeRow: View {
    let title: String
    let message: String

    var body: some View {
        VStack(alignment: .leading, spacing: Space.xs) {
            Text(title)
                .font(Typography.label)
                .foregroundColor(Tokens.accentPrimary)
            Text(message)
                .font(Typography.body)
                .foregroundColor(Tokens.textSecondary)
                .fixedSize(horizontal: false, vertical: true)
        }
    }
}

extension NSImage {
    /// Resizes while preserving the original aspect ratio. The result fits
    /// inside `bounds` (no stretching/squashing). The card's `.scaledToFill()`
    /// then crops it to the tile shape without distorting the photo.
    func resized(to bounds: NSSize) -> NSImage {
        let original = self.size
        guard original.width > 0, original.height > 0 else { return self }

        let scale = min(bounds.width / original.width, bounds.height / original.height)
        let targetSize = NSSize(width: original.width * scale, height: original.height * scale)

        let destRect = NSRect(origin: .zero, size: targetSize)
        let newImage = NSImage(size: targetSize)
        newImage.lockFocus()
        NSGraphicsContext.current?.imageInterpolation = .high
        self.draw(in: destRect, from: NSRect(origin: .zero, size: original), operation: .copy, fraction: 1.0)
        newImage.unlockFocus()
        return newImage
    }
}

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
    private let context = CIContext(options: [.useSoftwareRenderer: false])
    private let delegateHelper = CameraDelegateHelper()

    init() { checkPermission() }

    func checkPermission() {
        switch AVCaptureDevice.authorizationStatus(for: .video) {
        case .authorized:
            DispatchQueue.main.async { self.permissionGranted = true }
            self.setupSession()
        case .notDetermined:
            AVCaptureDevice.requestAccess(for: .video) { granted in
                DispatchQueue.main.async {
                    self.permissionGranted = granted
                    if granted { self.setupSession() }
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
                self.session.commitConfiguration()
                return
            }

            do {
                let videoInput = try AVCaptureDeviceInput(device: videoDevice)
                if self.session.canAddInput(videoInput) { self.session.addInput(videoInput) }

                self.videoOutput.alwaysDiscardsLateVideoFrames = true
                self.videoOutput.videoSettings = [
                    kCVPixelBufferPixelFormatTypeKey as String: Int(kCVPixelFormatType_32BGRA)
                ]

                self.delegateHelper.onFrame = { [weak self] sb in self?.handleSampleBuffer(sb) }

                if self.session.canAddOutput(self.videoOutput) {
                    self.session.addOutput(self.videoOutput)
                    self.videoOutput.setSampleBufferDelegate(
                        self.delegateHelper,
                        queue: DispatchQueue(label: "sample.buffer.queue")
                    )
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
            if !self.session.isRunning { self.session.startRunning() }
        }
    }

    func stop() {
        sessionQueue.async { [weak self] in
            guard let self = self else { return }
            if self.session.isRunning { self.session.stopRunning() }
        }
    }

    private func handleSampleBuffer(_ sampleBuffer: CMSampleBuffer) {
        guard let cvBuffer = CMSampleBufferGetImageBuffer(sampleBuffer) else { return }
        let ciImage = CIImage(cvImageBuffer: cvBuffer)
        let mirrored = ciImage.oriented(.upMirrored)

        guard let cgImage = context.createCGImage(mirrored, from: mirrored.extent) else { return }

        let size = NSSize(width: cgImage.width, height: cgImage.height)
        let nsImage = NSImage(cgImage: cgImage, size: size)

        DispatchQueue.main.async { [weak self] in
            self?.currentImage = nsImage
        }
    }
}

/// Shared CIContext for camera-side image work. Reusing a single context
/// across captures avoids the cost of recompiling the rendering graph.
private let selfieCropContext = CIContext(options: [.useSoftwareRenderer: false])

/// Crops a freshly-captured selfie to the dominant face with generous
/// padding (so the result still looks like a selfie, not a tight headshot).
///
/// The on-screen oval guide is purely advisory — without this crop, the
/// captured frame keeps every pixel of the camera's wide field of view,
/// including everything behind the user. Falls back to the original image
/// if no face passes the confidence/size threshold.
private func cropSelfieToFace(_ image: NSImage) -> NSImage {
    guard let cgImage = image.cgImage(forProposedRect: nil, context: nil, hints: nil) else {
        return image
    }

    let request = VNDetectFaceRectanglesRequest()
    if #available(macOS 11.0, *) {
        request.revision = VNDetectFaceRectanglesRequestRevision3
    }
    let handler = VNImageRequestHandler(cgImage: cgImage, options: [:])
    do {
        try handler.perform([request])
    } catch {
        return image
    }

    // Pick the largest face with enough confidence — covers the case of
    // bystanders being faintly visible behind the user.
    guard let face = (request.results ?? [])
        .filter({ $0.confidence >= 0.70 })
        .max(by: { ($0.boundingBox.width * $0.boundingBox.height)
                 < ($1.boundingBox.width * $1.boundingBox.height) })
    else {
        return image
    }

    let imageWidth = CGFloat(cgImage.width)
    let imageHeight = CGFloat(cgImage.height)
    let imageRect = CGRect(x: 0, y: 0, width: imageWidth, height: imageHeight)

    let raw = VNImageRectForNormalizedRect(face.boundingBox, Int(imageWidth), Int(imageHeight))
    let maxDim = max(raw.width, raw.height)

    // Bias the crop upward so the forehead/hair stays in frame — Vision's
    // face box stops at the eyebrows. Coordinates are bottom-left because
    // we're working in CIImage/Vision space.
    let center = CGPoint(x: raw.midX, y: raw.midY + raw.height * 0.18)
    // 2.4× padding — generous enough that the captured selfie still works
    // when the user didn't perfectly center inside the on-screen oval (a
    // common case: a bit too close, off-center, or with hair extending
    // beyond the face box). The matcher re-detects/re-crops the face from
    // this selfie later, so extra surrounding area costs nothing.
    let paddedSize = maxDim * 2.4

    var rect = CGRect(
        x: center.x - paddedSize / 2,
        y: center.y - paddedSize / 2,
        width: paddedSize,
        height: paddedSize
    ).integral

    if rect.minX < 0 { rect.origin.x = 0 }
    if rect.minY < 0 { rect.origin.y = 0 }
    if rect.maxX > imageWidth { rect.origin.x = imageWidth - rect.width }
    if rect.maxY > imageHeight { rect.origin.y = imageHeight - rect.height }
    rect = rect.intersection(imageRect).integral

    // Sanity: refuse to return a microscopic crop.
    guard rect.width >= 120, rect.height >= 120 else { return image }

    let ciImage = CIImage(cgImage: cgImage).cropped(to: rect)
    guard let cropped = selfieCropContext.createCGImage(ciImage, from: rect) else { return image }
    return NSImage(cgImage: cropped, size: NSSize(width: cropped.width, height: cropped.height))
}

struct CameraCaptureSheet: View {
    @StateObject private var cameraManager = CameraManager()
    @Binding var isPresented: Bool
    var onCapture: (NSImage) -> Void
    var onBrowseFile: () -> Void

    var body: some View {
        VStack(spacing: Space.l) {
            HStack(spacing: Space.s) {
                Image(systemName: "camera")
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundColor(Tokens.accentPrimary)
                Text("Take a reference selfie")
                    .font(Typography.h3)
                    .foregroundColor(Tokens.textPrimary)
                Spacer()
            }

            if cameraManager.permissionGranted {
                ZStack {
                    CameraPreviewView(session: cameraManager.session)
                        .frame(width: 460, height: 320)
                        .clipShape(RoundedRectangle(cornerRadius: Radius.l))
                        .overlay(
                            RoundedRectangle(cornerRadius: Radius.l)
                                .stroke(Tokens.border, lineWidth: 1)
                        )
                    Ellipse()
                        .stroke(Tokens.accentSecondary.opacity(0.55),
                                style: StrokeStyle(lineWidth: 1.5, dash: [6, 4]))
                        .frame(width: 200, height: 250)
                }
            } else {
                VStack(spacing: Space.s) {
                    Image(systemName: "camera.fill")
                        .font(.system(size: 28))
                        .foregroundColor(Tokens.textTertiary)
                    Text("Waiting for camera access…")
                        .font(Typography.body)
                        .foregroundColor(Tokens.textSecondary)
                }
                .frame(width: 460, height: 320)
                .background(Tokens.surfaceSunken)
                .clipShape(RoundedRectangle(cornerRadius: Radius.l))
                .overlay(
                    RoundedRectangle(cornerRadius: Radius.l)
                        .stroke(Tokens.border, lineWidth: 1)
                )
            }

            Text("Frames are kept only in memory for this session.")
                .font(Typography.caption)
                .foregroundColor(Tokens.textTertiary)
                .multilineTextAlignment(.center)

            HStack(spacing: Space.m) {
                Button {
                    cameraManager.stop()
                    isPresented = false
                    onBrowseFile()
                } label: {
                    HStack(spacing: 6) {
                        Image(systemName: "folder")
                        Text("Choose file")
                    }
                    .font(Typography.bodyStrong)
                    .foregroundColor(Tokens.textPrimary)
                    .padding(.horizontal, Space.l)
                    .padding(.vertical, Space.s + 2)
                    .background(Tokens.surfaceSunken)
                    .clipShape(RoundedRectangle(cornerRadius: Radius.m))
                }
                .buttonStyle(.plain)

                Spacer()

                Button {
                    cameraManager.stop()
                    isPresented = false
                } label: {
                    Text("Cancel")
                        .font(Typography.bodyStrong)
                        .foregroundColor(Tokens.textSecondary)
                        .padding(.horizontal, Space.l)
                        .padding(.vertical, Space.s + 2)
                }
                .buttonStyle(.plain)
                .keyboardShortcut(.cancelAction)

                Button {
                    if let image = cameraManager.currentImage {
                        cameraManager.stop()
                        // Crop to the detected face so the saved selfie matches
                        // what the on-screen oval guide implied.
                        onCapture(cropSelfieToFace(image))
                        isPresented = false
                    }
                } label: {
                    HStack(spacing: 6) {
                        Image(systemName: "camera.fill")
                        Text("Capture")
                    }
                    .font(Typography.bodyStrong)
                    .foregroundColor(Tokens.onAccent)
                    .padding(.horizontal, Space.l)
                    .padding(.vertical, Space.s + 2)
                    .background(Tokens.accentPrimary)
                    .clipShape(RoundedRectangle(cornerRadius: Radius.m))
                }
                .buttonStyle(.plain)
                .keyboardShortcut(.defaultAction)
                .disabled(cameraManager.currentImage == nil)
            }
        }
        .padding(Space.xl)
        .frame(width: 540)
        .background(Tokens.surface)
        .onAppear { cameraManager.start() }
        .onDisappear { cameraManager.stop() }
    }
}
