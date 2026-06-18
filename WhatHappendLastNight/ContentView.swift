import SwiftUI
import Combine
import AppKit
import UniformTypeIdentifiers
import AVFoundation

// MARK: - Root view
//
// Implements the design system from DESIGN_GUIDE.md:
// — Calm, trust-signaling palette (navy + teal) with full light/dark parity.
// — System fonts (SF Pro) at the type scale defined in §2.
// — One primary CTA per screen; persistent identity strip; offline glyph in title.
// — Two-panel comparison and a results grid with per-tile color + score percentage.

struct ContentView: View {
    @StateObject private var matcher = FaceMatcher()
    @EnvironmentObject var theme: ThemeManager

    // ---- State -------------------------------------------------------------

    @State private var targetSelfie: NSImage? = nil
    @State private var targetSelfieURL: URL? = nil
    @State private var sourceFolderURL: URL? = nil
    @State private var threshold: Double = 0.75
    @State private var isSelfieHovered = false
    @State private var isFolderHovered = false
    @State private var isShowingCameraSheet = false
    @State private var isShowingPrivacyNotice = false
    @State private var hasAcceptedBiometricNotice = false
    @State private var selectedResultID: MatchResult.ID? = nil
    @State private var lightboxIndex: Int? = nil

    // ---- Layout ------------------------------------------------------------

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

            // Full-window lightbox — sits above every panel
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
                self.targetSelfie = capturedImage
                self.targetSelfieURL = nil
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
    }

    // MARK: Header — title + persistent identity strip + offline glyph

    private var header: some View {
        HStack(spacing: Space.m) {
            // ── Left: wordmark + subtitle ───────────────────────────────
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

            // Offline badge — sits right of the wordmark
            OfflineBadge()

            Spacer()

            // ── Right: identity strip + clear session ────────────────────
            // The × inside IdentityStrip only removes the reference photo;
            // full session wipe lives in the always-visible Clear Session
            // button below.
            if let selfie = targetSelfie {
                IdentityStrip(
                    image: selfie,
                    label: targetSelfieURL?.lastPathComponent ?? "Selfie captured",
                    onClear: clearReferencePhoto
                )
            }

            // Always-available, clearly-labeled Clear Session button. Visible
            // whenever there is anything to clear — including just granted
            // consent without a selfie yet. This honors the GDPR Art. 7(3)
            // "withdraw consent at any time" promise made in PRIVACY.md.
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

    // MARK: Left — setup panel (selfie · folder · threshold · run)
    //
    // Designed to fit at ~680pt window height without scrolling. Privacy lives
    // *next to the action button*, not at the top — the user can pick the
    // selfie and folder in any order, and consent is asked only once, right
    // before scanning. If they hit Find Me without consenting, the full
    // PrivacyNoticeSheet auto-opens (see runSelfieScan).

    private var setupPanel: some View {
        VStack(spacing: 0) {
            ScrollView(.vertical, showsIndicators: false) {
                VStack(alignment: .leading, spacing: Space.m) {

                    StageCard(icon: "faceid", eyebrow: "1. Target identity") {
                        SelfieDropzone(
                            image: targetSelfie,
                            filename: targetSelfieURL?.lastPathComponent,
                            bestMatch: matcher.matchedResults.first?.similarity,
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
                            onDrop: loadFolderFromDrop
                        )
                    }

                    ThresholdCard(threshold: $threshold)

                    // Privacy consent card scrolls with the content so it
                    // stays close to the setup steps it relates to.
                    if !matcher.isScanning {
                        ConsentCard(
                            consented: $hasAcceptedBiometricNotice,
                            onDetails: { isShowingPrivacyNotice = true }
                        )
                    }
                }
                .padding(Space.l)
                .frame(maxWidth: .infinity) // Constrain width so ScrollView doesn't bleed
            }

            // Only the action button (and scan progress) is pinned so it is
            // always reachable without scrolling.
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

    // MARK: Right — results

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

    // MARK: Footer

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

    // MARK: Actions

    private func selectSelfieFile() {
        let panel = NSOpenPanel()
        panel.allowedContentTypes = [.image]
        panel.canChooseFiles = true
        panel.canChooseDirectories = false
        panel.allowsMultipleSelection = false
        if panel.runModal() == .OK, let url = panel.url, let image = NSImage(contentsOf: url) {
            targetSelfie = image
            targetSelfieURL = url
        }
    }

    private func selectSourceFolder() {
        let panel = NSOpenPanel()
        panel.canChooseFiles = false
        panel.canChooseDirectories = true
        panel.allowsMultipleSelection = false
        if panel.runModal() == .OK, let url = panel.url {
            sourceFolderURL = url
        }
    }

    /// True whenever there is *any* in-memory session state the user might
    /// want to clear: a selfie, a folder reference, results, or even just a
    /// granted-but-not-yet-used consent. Drives visibility of the always-
    /// available Clear Session button in the header.
    private var hasSessionState: Bool {
        targetSelfie != nil
            || sourceFolderURL != nil
            || hasAcceptedBiometricNotice
            || !matcher.matchedResults.isEmpty
            || matcher.isScanning
    }

    private func runSelfieScan() {
        // GDPR Art. 9(2)(a) gate: explicit biometric consent must be granted;
        // otherwise re-open the full privacy notice so the user sees what they
        // are agreeing to.
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
        // Acts as the withdraw-consent + erase-all-in-memory-data control
        // (GDPR Art. 7(3) and Art. 17). After Clear, consent must be re-granted
        // before any further biometric processing can occur.
        matcher.cancel()
        matcher.clearResults()
        targetSelfie = nil
        targetSelfieURL = nil
        sourceFolderURL = nil
        hasAcceptedBiometricNotice = false
        selectedResultID = nil
    }

    /// Scoped to the × inside the reference identity strip: only the
    /// reference selfie (and its filename) are dropped. Folder, consent,
    /// and existing match results are preserved — full session wipe lives
    /// in the always-visible Clear Session header button.
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
                    self.targetSelfie = image
                    self.targetSelfieURL = url
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
            DispatchQueue.main.async { self.sourceFolderURL = url }
        }
        return true
    }
}

// MARK: - Reusable card chrome

/// Production card — bordered surface with an eyebrow header row + content.
/// The card owns the chrome (padding, background, border, radius), so child
/// dropzones can focus purely on their interactive content. Matches the
/// original v1 layout where each setup step sat in its own polished panel.
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

// MARK: - Header subviews

/// Compact circular icon button used in the header (theme toggle, help).
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

/// Always-visible "Clear Session" header button. Wipes all in-memory
/// state (selfie, folder, embeddings, results) and withdraws consent.
/// Surfaced as a labeled button rather than a tiny icon so users can
/// find the withdraw-consent control easily (GDPR Art. 7(3)).
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

/// Single-button appearance picker visible in the header.
/// Click cycles System → Light → Dark → System; the icon and tooltip update
/// to reflect the current preference. The full View → Appearance menu still
/// works for keyboard users (⌘⌥0/1/2).
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
            // ── X dismiss button ─────────────────────────────────────
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

// MARK: - Dropzones

private struct SelfieDropzone: View {
    let image: NSImage?
    let filename: String?
    /// Best similarity from the most recent scan, if any. Shown as a green
    /// caption under the thumbnail — matches the "76%" label in the design.
    var bestMatch: Double? = nil
    @Binding var isHovered: Bool
    let onCapture: () -> Void
    let onDrop: ([NSItemProvider]) -> Bool

    /// Fixed preview size so the dropzone keeps an identical footprint whether
    /// it is empty or holding a selfie — the box never resizes around the photo.
    private let boxHeight: CGFloat = 200

    var body: some View {
        VStack(spacing: Space.s) {
            Button(action: onCapture) {
                Group {
                    if let image = image {
                        ZStack {
                            // Subtle tinted background fills any letterbox gaps
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

            // Caption row sits OUTSIDE the dropzone, in the parent card chrome.
            if let bestMatch = bestMatch {
                Text("\(Int((bestMatch * 100).rounded()))%")
                    .font(Typography.scoreNumeral)
                    .foregroundColor(Tokens.accentSecondary)
            } else if image != nil {
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

    var body: some View {
        Button(action: onChoose) {
            HStack(spacing: Space.m) {
                Image(systemName: folderURL == nil ? "folder" : "folder.fill")
                    .font(.system(size: 22, weight: .regular))
                    .foregroundColor(folderURL == nil
                                     ? (isHovered ? Tokens.accentPrimary : Tokens.textTertiary)
                                     : Tokens.accentPrimary)
                    .frame(width: 26)

                VStack(alignment: .leading, spacing: 2) {
                    Text(folderURL == nil ? "No folder selected" : "Folder selected")
                        .font(Typography.bodyStrong)
                        .foregroundColor(Tokens.textPrimary)
                        .lineLimit(1)
                    Text(folderURL?.path ?? "Click to browse...")
                        .font(.system(size: 11, design: .monospaced))
                        .foregroundColor(Tokens.textTertiary)
                        .lineLimit(1)
                        .truncationMode(.middle)
                }

                Spacer(minLength: 0)
            }
            .padding(.horizontal, Space.m)
            .padding(.vertical, Space.s + 2)
            .frame(maxWidth: .infinity, alignment: .leading)
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
        .buttonStyle(.plain)
        .onHover { isHovered = $0 }
        .onDrop(of: [.directory], isTargeted: nil, perform: onDrop)
        .help("Click to pick a folder, or drag one here")
        .animation(.easeOut(duration: 0.15), value: isHovered)
    }
}

// MARK: - Threshold card

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
            // Wrap the slider in a tinted pill so the white system thumb has
            // enough contrast against the card in light mode.
            ZStack {
                RoundedRectangle(cornerRadius: Radius.s)
                    .fill(Tokens.surfaceSunken)
                    .frame(height: 30)
                Slider(value: $threshold, in: 0.30...0.95)
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

// MARK: - Find Me button (pinned) + scan progress

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

// MARK: - Consent card (visible privacy gate, sits right above Find Me)

private struct ConsentCard: View {
    @Binding var consented: Bool
    /// Opens the full privacy notice sheet. Surfaced both here (in-card button)
    /// and from the `?` button in the header.
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

// MARK: - Results header / empty / scanning

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

/// Shown when a scan completed successfully but found zero matches above threshold.
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

/// Empty state for the results panel.
///
/// Carries the informational feel of the original ("here's what to do next")
/// but with a polished modern presentation: hero glyph + descriptive line +
/// a three-step checklist that ticks off as the user completes prerequisites,
/// so they always know exactly where they are in the flow.
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
            // Hero glyph — the magnifying-glass spec from the original empty
            // state, with a soft accent halo for a more luminous feel.
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

            // Step checklist — gives the user an at-a-glance map of remaining
            // setup work. Each row ticks green as the prerequisite is met.
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

// MARK: - Results grid

private struct ResultsGrid: View {
    let results: [MatchResult]
    @Binding var selectedID: MatchResult.ID?
    @Binding var lightboxIndex: Int?

    private let columns = [GridItem(.adaptive(minimum: 260, maximum: 360), spacing: Space.m)]

    var body: some View {
        ScrollView {
            LazyVGrid(columns: columns, spacing: Space.m) {
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
            .padding(Space.l)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Tokens.bg)
    }
}

// MARK: - Lightbox (full-window, carousel + pinch/scroll zoom)

private struct LightboxView: View {
    let results: [MatchResult]
    /// Binding to the current index; set to nil to dismiss.
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
            // ── Scrim ────────────────────────────────────────────────────
            Color.black.opacity(0.88)
                .ignoresSafeArea()
                .onTapGesture { dismiss() }

            VStack(spacing: 0) {
                // ── Toolbar ──────────────────────────────────────────────
                HStack(spacing: Space.s) {
                    // Score badge
                    HStack(spacing: 6) {
                        Circle().fill(tier.color).frame(width: 7, height: 7)
                        Text("\(pct)%")
                            .font(.system(size: 13, weight: .bold, design: .monospaced))
                            .foregroundColor(.white)
                    }
                    .padding(.horizontal, 10).padding(.vertical, 5)
                    .background(.ultraThinMaterial)
                    .clipShape(Capsule())

                    // Index counter
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

                // ── Photo + side arrows ───────────────────────────────────
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

                    // ── Carousel arrows ───────────────────────────────────
                    HStack {
                        CarouselArrow(direction: .prev, enabled: hasPrev) { navigateTo(index - 1) }
                        Spacer()
                        CarouselArrow(direction: .next, enabled: hasNext) { navigateTo(index + 1) }
                    }
                    .padding(.horizontal, Space.l)
                }
                // Clip the photo+arrows layer so scaleEffect can never
                // overflow into the toolbar above or the screen edges.
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

    // ── Helpers ──────────────────────────────────────────────────────────────

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
            case 123: navigateTo(index - 1); return nil   // ← left arrow
            case 124: navigateTo(index + 1); return nil   // → right arrow
            case 53:  dismiss();             return nil   // Esc
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

// ── Carousel arrow button ─────────────────────────────────────────────────

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

// Scroll-wheel modifier for zoom support
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

// MARK: - Result tile

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
            // ── Photo area ──────────────────────────────────────────────
            ZStack(alignment: .topTrailing) {
                // Background fill while loading
                Rectangle()
                    .fill(Tokens.surfaceSunken)

                if let thumbnail {
                    Image(nsImage: thumbnail)
                        .resizable()
                        .scaledToFill()
                        .transition(.opacity.animation(.easeIn(duration: 0.25)))
                } else {
                    ProgressView()
                        .scaleEffect(0.7)
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                }

                // Score badge — top-right corner
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
            .aspectRatio(4/3, contentMode: .fit)
            .clipped()

            // ── Bottom overlay bar ──────────────────────────────────────
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
                // People count badge
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

// MARK: - Privacy sheet

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

// MARK: - NSImage helper

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

// MARK: - Camera capture sheet

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
                        onCapture(image)
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
