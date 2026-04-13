// macspanso/Store/EspansoConfigStore.swift
import Foundation
import Combine

@MainActor
final class EspansoConfigStore: ObservableObject {
    @Published var matchFiles: [MatchFile] = []

    /// Non-nil when a watched file changes externally while the window is open.
    /// Set to nil after the user responds to the reload banner.
    @Published var externallyChangedURL: URL? = nil

    private let matchDirectory: URL
    private let watcher = FileWatcher()

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
        let urls = scanMatchDirectory()
        matchFiles = urls.map { loadFile(at: $0) }
        // Watch the directory and each file
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
        let isPackage = url.path.contains("/packages/")
        do {
            let matches = try YAMLSerializer.decode(contentsOf: url)
            return MatchFile(url: url, matches: matches, isPackage: isPackage)
        } catch {
            return MatchFile(url: url, matches: [], isPackage: isPackage,
                             parseError: error.localizedDescription)
        }
    }

    // MARK: - Write

    /// Save a mutated match list back to the file that owns it.
    func save(matches: [EspansoMatch], in fileID: UUID) throws {
        guard let index = matchFiles.firstIndex(where: { $0.id == fileID }) else { return }
        try YAMLSerializer.write(matches, to: matchFiles[index].url)
        matchFiles[index].matches = matches
    }

    /// Update a single match in place.
    func update(_ match: EspansoMatch) throws {
        for i in matchFiles.indices {
            if let j = matchFiles[i].matches.firstIndex(where: { $0.id == match.id }) {
                matchFiles[i].matches[j] = match
                try YAMLSerializer.write(matchFiles[i].matches, to: matchFiles[i].url)
                return
            }
        }
    }

    /// Add a new match. Saves to base.yml; creates the file if it doesn't exist.
    func add(_ match: EspansoMatch) throws {
        let baseURL = matchDirectory.appendingPathComponent("base.yml")
        if let index = matchFiles.firstIndex(where: { $0.url == baseURL }) {
            matchFiles[index].matches.append(match)
            try YAMLSerializer.write(matchFiles[index].matches, to: baseURL)
        } else {
            // base.yml doesn't exist yet — create it
            try YAMLSerializer.write([match], to: baseURL)
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
                try YAMLSerializer.write(matchFiles[i].matches, to: matchFiles[i].url)
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
        externallyChangedURL = url
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
