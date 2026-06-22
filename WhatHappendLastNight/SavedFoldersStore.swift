import Foundation
import Combine

/// One named folder shortcut that the user has saved for quick selection.
///
/// `path` is kept for human-readable display (the dropdown label, tooltips).
/// `bookmark` is the macOS App Sandbox security-scoped bookmark that
/// re-grants the app access to the same folder across launches — without it,
/// a sandboxed build can read the folder only during the same session as the
/// originating `NSOpenPanel` pick.
struct SavedFolder: Identifiable, Codable, Equatable, Hashable {
    var id: UUID
    var name: String
    var path: String
    /// Security-scoped bookmark created with `.withSecurityScope`. Optional
    /// so we can decode legacy entries (saved before this field existed) —
    /// those will resolve to `nil` and be treated as broken shortcuts.
    var bookmark: Data?

    init(id: UUID = UUID(), name: String, path: String, bookmark: Data? = nil) {
        self.id = id
        self.name = name
        self.path = path
        self.bookmark = bookmark
    }
}

/// Persists the list of user-saved photo folders so they can be re-selected
/// quickly from a dropdown across app launches.
///
/// Under the macOS App Sandbox, file access granted via `NSOpenPanel` does
/// not survive process restart — we must persist a security-scoped bookmark
/// for each saved folder and resolve it back to a usable `URL` on demand.
@MainActor
final class SavedFoldersStore: ObservableObject {
    @Published private(set) var folders: [SavedFolder] = []

    private let defaultsKey = "whln.savedFolders.v2"
    private let defaults: UserDefaults

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        load()
    }

    // MARK: - Mutations

    /// Adds a folder shortcut. The URL must be live (i.e. just returned by
    /// `NSOpenPanel` or a drop) so we can mint a security-scoped bookmark
    /// from it. If a shortcut for the same path already exists, its name and
    /// bookmark are refreshed (re-picking re-authorises the path).
    @discardableResult
    func add(name: String, url: URL) -> SavedFolder {
        let cleanName = name.trimmingCharacters(in: .whitespacesAndNewlines)
        let displayName = cleanName.isEmpty ? url.lastPathComponent : cleanName
        let path = url.path
        let bookmark = makeBookmark(for: url)

        if let idx = folders.firstIndex(where: { $0.path == path }) {
            folders[idx].name = displayName
            // Replace the bookmark whenever we have a fresh one — a re-pick
            // is the user's chance to extend access.
            if let bookmark { folders[idx].bookmark = bookmark }
            persist()
            return folders[idx]
        }

        let entry = SavedFolder(name: displayName, path: path, bookmark: bookmark)
        folders.append(entry)
        persist()
        return entry
    }

    func remove(_ folder: SavedFolder) {
        folders.removeAll { $0.id == folder.id }
        persist()
    }

    func rename(_ folder: SavedFolder, to newName: String) {
        let trimmed = newName.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty,
              let idx = folders.firstIndex(where: { $0.id == folder.id }) else { return }
        folders[idx].name = trimmed
        persist()
    }

    /// Returns the saved entry matching this URL's path, if any.
    func entry(for url: URL) -> SavedFolder? {
        folders.first { $0.path == url.path }
    }

    // MARK: - Bookmark resolution

    /// Resolution outcome for a saved shortcut.
    enum Resolution {
        /// Bookmark resolved successfully. The URL has security scope already
        /// started — the caller MUST balance with `stopAccessingSecurityScopedResource()`
        /// on the same URL when finished.
        case ok(URL)
        /// Bookmark was never minted (legacy entry) — user must re-pick the
        /// folder to grant access again.
        case missingBookmark
        /// Bookmark exists but no longer points anywhere usable (folder moved,
        /// deleted, drive unmounted, or sandbox permissions revoked).
        case stale
    }

    /// Resolves a saved shortcut into a usable, sandbox-authorised URL.
    /// On success the security scope is already active — call
    /// `stopAccessingSecurityScopedResource()` on the returned URL when done.
    /// If the bookmark resolves but is marked stale, we refresh it
    /// transparently so subsequent uses don't pay the resolution cost twice.
    func resolve(_ folder: SavedFolder) -> Resolution {
        guard let data = folder.bookmark else { return .missingBookmark }

        var isStale = false
        let resolved: URL
        do {
            resolved = try URL(
                resolvingBookmarkData: data,
                options: [.withSecurityScope],
                relativeTo: nil,
                bookmarkDataIsStale: &isStale
            )
        } catch {
            return .stale
        }

        guard resolved.startAccessingSecurityScopedResource() else {
            return .stale
        }

        if isStale, let refreshed = makeBookmark(for: resolved) {
            if let idx = folders.firstIndex(where: { $0.id == folder.id }) {
                folders[idx].bookmark = refreshed
                persist()
            }
        }

        return .ok(resolved)
    }

    // MARK: - Persistence

    private func makeBookmark(for url: URL) -> Data? {
        do {
            return try url.bookmarkData(
                options: [.withSecurityScope],
                includingResourceValuesForKeys: nil,
                relativeTo: nil
            )
        } catch {
            // Most common cause: the URL doesn't have an active sandbox
            // extension at the moment of the call. Without a bookmark the
            // shortcut still saves (label + path) but won't work after a
            // restart — the user can re-pick to grant access.
            return nil
        }
    }

    private func load() {
        guard let data = defaults.data(forKey: defaultsKey) else {
            // Best-effort one-time migration from the v1 (path-only) store.
            migrateLegacyV1IfNeeded()
            return
        }
        if let decoded = try? JSONDecoder().decode([SavedFolder].self, from: data) {
            folders = decoded
        }
    }

    private func persist() {
        if let data = try? JSONEncoder().encode(folders) {
            defaults.set(data, forKey: defaultsKey)
        }
    }

    /// Reads v1 entries (path-only) and writes them under the v2 key with
    /// missing bookmarks. The user will need to re-pick once to authorise,
    /// but their list of remembered names is preserved.
    private func migrateLegacyV1IfNeeded() {
        let legacyKey = "whln.savedFolders.v1"
        guard let data = defaults.data(forKey: legacyKey),
              let decoded = try? JSONDecoder().decode([SavedFolder].self, from: data) else { return }
        folders = decoded
        persist()
        defaults.removeObject(forKey: legacyKey)
    }
}
