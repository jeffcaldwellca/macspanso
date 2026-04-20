// macspanso/Store/EspansoConfigStore.swift
import Foundation
import Combine

@MainActor
final class EspansoConfigStore: ObservableObject {
    @Published var matchFiles: [MatchFile] = []

    /// Non-nil when a watched file changes externally while the window is open.
    /// Set to nil after the user responds to the reload banner.
    @Published var externallyChangedURL: URL? = nil

    let matchDirectory: URL
    private let watcher = FileWatcher()

    /// Reference-counted write-in-progress markers; FSEvents for these paths are suppressed.
    private var writingPaths: [String: Int] = [:]

    /// All non-package matches, flattened across all files.
    var allMatches: [EspansoMatch] {
        matchFiles.filter { !$0.isPackage }.flatMap { $0.matches }
    }

    init(matchDirectory: URL) {
        self.matchDirectory = matchDirectory
        watcher.onChange = { [weak self] url in
            Task { @MainActor in self?.handleExternalChange(at: url) }
        }
    }

    // MARK: - Load

    func load() {
        watcher.stopAll()   // clear stale watches if load() is called more than once
        let urls = scanMatchDirectory()
        matchFiles = urls.map { loadFile(at: $0) }
        watcher.watch(url: matchDirectory)
        matchFiles.forEach { watcher.watch(url: $0.url) }
    }

    private func scanMatchDirectory() -> [URL] {
        guard let enumerator = FileManager.default.enumerator(
            at: matchDirectory,
            includingPropertiesForKeys: nil
        ) else { return [] }

        return enumerator
            .compactMap { $0 as? URL }
            .filter { $0.pathExtension == "yml" }
            .sorted { $0.path < $1.path }
    }

    private func loadFile(at url: URL) -> MatchFile {
        // Anchor package detection to the known config root rather than global path search.
        let relative = url.path.replacingOccurrences(of: matchDirectory.path, with: "")
        let isPackage = relative.hasPrefix("/packages/")
        do {
            let matches = try YAMLSerializer.decode(contentsOf: url)
            return MatchFile(url: url, matches: matches, isPackage: isPackage)
        } catch {
            return MatchFile(url: url, matches: [], isPackage: isPackage,
                             parseError: error.localizedDescription)
        }
    }

    // MARK: - Write

    /// Registers a write-in-progress for `url` so that the resulting FSEvent is
    /// not mistaken for an external edit. Clears after a short delay to account
    /// for async FSEvent delivery.
    private func suppressingWatcherEvents(for url: URL, _ body: () throws -> Void) rethrows {
        let paths = [url.path, matchDirectory.path]
        paths.forEach { writingPaths[$0, default: 0] += 1 }
        try body()
        DispatchQueue.main.asyncAfter(deadline: .now() + 2.0) { [weak self] in
            guard let self else { return }
            for p in paths {
                if let count = self.writingPaths[p] {
                    if count <= 1 { self.writingPaths.removeValue(forKey: p) }
                    else { self.writingPaths[p] = count - 1 }
                }
            }
        }
    }

    /// Save a mutated match list back to the file that owns it.
    func save(matches: [EspansoMatch], in fileID: UUID) throws {
        guard let index = matchFiles.firstIndex(where: { $0.id == fileID }) else { return }
        let url = matchFiles[index].url
        try suppressingWatcherEvents(for: url) {
            try YAMLSerializer.write(matches, to: url)
        }
        matchFiles[index].matches = matches
    }

    /// Update a single match in place.
    func update(_ match: EspansoMatch) throws {
        for i in matchFiles.indices {
            if let j = matchFiles[i].matches.firstIndex(where: { $0.id == match.id }) {
                let url = matchFiles[i].url
                var updated = matchFiles[i].matches
                updated[j] = match
                // Write first; only update in-memory if the write succeeds.
                try suppressingWatcherEvents(for: url) {
                    try YAMLSerializer.write(updated, to: url)
                }
                matchFiles[i].matches = updated
                return
            }
        }
    }

    /// Add a new match. Saves to base.yml; creates the file if it doesn't exist.
    func add(_ match: EspansoMatch) throws {
        let baseURL = matchDirectory.appendingPathComponent("base.yml")
        if let index = matchFiles.firstIndex(where: { $0.url == baseURL }) {
            matchFiles[index].matches.append(match)
            let updatedMatches = matchFiles[index].matches
            try suppressingWatcherEvents(for: baseURL) {
                try YAMLSerializer.write(updatedMatches, to: baseURL)
            }
        } else {
            // base.yml doesn't exist yet — create it
            try suppressingWatcherEvents(for: baseURL) {
                try YAMLSerializer.write([match], to: baseURL)
            }
            let newFile = MatchFile(url: baseURL, matches: [match], isPackage: false)
            matchFiles.insert(newFile, at: 0)
            watcher.watch(url: baseURL)
        }
    }

    /// Delete a match by ID.
    func delete(matchID: UUID) throws {
        for i in matchFiles.indices {
            if let j = matchFiles[i].matches.firstIndex(where: { $0.id == matchID }) {
                matchFiles[i].matches.remove(at: j)
                let url = matchFiles[i].url
                let updatedMatches = matchFiles[i].matches
                try suppressingWatcherEvents(for: url) {
                    try YAMLSerializer.write(updatedMatches, to: url)
                }
                return
            }
        }
    }

    /// Returns the MatchFile that owns a given match ID.
    func file(containing matchID: UUID) -> MatchFile? {
        matchFiles.first { $0.matches.contains(where: { $0.id == matchID }) }
    }

    // MARK: - External Change Handling

    private func handleExternalChange(at url: URL) {
        guard writingPaths[url.path] == nil else { return }
        if url == matchDirectory {
            handleDirectoryChange()
        } else {
            externallyChangedURL = url
        }
    }

    /// Called when the match directory itself changes (file added or removed externally).
    /// Silently syncs matchFiles with what's on disk without prompting the user.
    private func handleDirectoryChange() {
        let urls = Set(scanMatchDirectory())
        let existingURLs = Set(matchFiles.map { $0.url })

        // Add newly discovered files
        let added = urls.subtracting(existingURLs)
        for url in added.sorted(by: { $0.path < $1.path }) {
            let file = loadFile(at: url)
            matchFiles.append(file)
            watcher.watch(url: url)
        }

        // Remove files that no longer exist on disk
        matchFiles.removeAll { !urls.contains($0.url) }

        // Re-sort to keep consistent ordering
        matchFiles.sort { $0.url.path < $1.url.path }
    }

    /// Called when the user chooses "Reload" in the external edit banner.
    func reloadFile(at url: URL) {
        guard let index = matchFiles.firstIndex(where: { $0.url == url }) else { return }
        matchFiles[index] = loadFile(at: url)
        externallyChangedURL = nil
    }

    func dismissExternalChangeNotice() {
        externallyChangedURL = nil
    }
}
