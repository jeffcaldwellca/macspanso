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

    private func loadFile(at url: URL, reusingIDsFrom previous: [EspansoMatch] = []) -> MatchFile {
        // Anchor package detection to the known config root rather than global path search.
        let relative = url.path.replacingOccurrences(of: matchDirectory.path, with: "")
        let isPackage = relative.hasPrefix("/packages/")
        do {
            var matches = try YAMLSerializer.decode(contentsOf: url)
            if !previous.isEmpty {
                Self.reassociateIDs(into: &matches, from: previous)
            }
            return MatchFile(url: url, matches: matches, isPackage: isPackage)
        } catch {
            return MatchFile(url: url, matches: [], isPackage: isPackage,
                             parseError: error.localizedDescription)
        }
    }

    /// After a reload, decoded matches receive freshly-generated UUIDs. Walk through them
    /// and reuse the prior UUID whenever a previous match has the same identity (primary
    /// trigger or regex pattern). This keeps the editor's selection alive across external
    /// edits to unrelated matches in the same file.
    nonisolated static func reassociateIDs(into fresh: inout [EspansoMatch], from previous: [EspansoMatch]) {
        var available = previous
        for i in fresh.indices {
            guard let j = available.firstIndex(where: { matchKey(for: $0) == matchKey(for: fresh[i]) })
            else { continue }
            fresh[i].id = available[j].id
            available.remove(at: j)
        }
    }

    /// Identity used to re-associate a match across reloads. Primary trigger (or regex
    /// pattern) is the canonical, user-meaningful key; collisions are guarded by the
    /// validator at edit time, so duplicates here are vanishingly rare.
    nonisolated private static func matchKey(for m: EspansoMatch) -> String {
        if let r = m.regex { return "regex:\(r)" }
        if let t = m.trigger { return "t:\(t)" }
        if let first = m.triggers?.first { return "t:\(first)" }
        return "label:\(m.label ?? "")"
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

    /// Add a new match. Saves to `targetURL` if provided; otherwise to base.yml.
    /// Creates the file if it doesn't exist. Refuses to write into package files.
    func add(_ match: EspansoMatch, to targetURL: URL? = nil) throws {
        let url = targetURL ?? matchDirectory.appendingPathComponent("base.yml")
        if let existing = matchFiles.first(where: { $0.url == url }), existing.isPackage {
            throw NSError(
                domain: "macspanso.add",
                code: 1,
                userInfo: [NSLocalizedDescriptionKey: "Cannot add matches to a package file."]
            )
        }
        if let index = matchFiles.firstIndex(where: { $0.url == url }) {
            matchFiles[index].matches.append(match)
            let updatedMatches = matchFiles[index].matches
            try suppressingWatcherEvents(for: url) {
                try YAMLSerializer.write(updatedMatches, to: url)
            }
        } else {
            // File doesn't exist yet — create it
            try suppressingWatcherEvents(for: url) {
                try YAMLSerializer.write([match], to: url)
            }
            let newFile = MatchFile(url: url, matches: [match], isPackage: false)
            matchFiles.append(newFile)
            matchFiles.sort { $0.url.path < $1.url.path }
            watcher.watch(url: url)
        }
    }

    /// Files that the user can write matches into (excludes packages and parse-errored files).
    var writableFiles: [MatchFile] {
        matchFiles.filter { !$0.isPackage && $0.parseError == nil }
    }

    /// One occurrence of a trigger string in a specific match within a specific file.
    /// Used to surface cross-file trigger collisions (`::hello` defined in two files).
    struct TriggerOccurrence: Hashable {
        let trigger: String
        let fileURL: URL
        let matchID: UUID
    }

    struct TriggerConflict: Identifiable {
        let trigger: String
        let occurrences: [TriggerOccurrence]
        var id: String { trigger }
    }

    /// Find triggers that appear in more than one non-package file. Within-file duplicates
    /// are caught by `MatchValidator` at edit time; this surfaces the cross-file case the
    /// validator can't see (espanso silently picks one and ignores the rest).
    func triggerConflicts() -> [TriggerConflict] {
        var byTrigger: [String: [TriggerOccurrence]] = [:]
        for file in matchFiles where !file.isPackage {
            for match in file.matches {
                var triggers: [String] = []
                if let t = match.trigger { triggers.append(t) }
                if let arr = match.triggers { triggers.append(contentsOf: arr) }
                // Regex patterns aren't compared as literal triggers — different match type.
                for t in triggers where !t.isEmpty {
                    byTrigger[t, default: []].append(
                        TriggerOccurrence(trigger: t, fileURL: file.url, matchID: match.id)
                    )
                }
            }
        }
        return byTrigger
            .filter { _, occs in Set(occs.map(\.fileURL)).count > 1 }
            .map { TriggerConflict(trigger: $0.key, occurrences: $0.value) }
            .sorted { $0.trigger < $1.trigger }
    }

    /// Duplicate a match: insert a copy directly after the original in the same file.
    /// The copy gets a fresh UUID and an unused trigger derived from the original
    /// (e.g. `::hello` → `::hello-copy`, then `::hello-copy-2`, etc.). Multi-trigger
    /// and regex matches duplicate the primary trigger only — secondary triggers and
    /// the regex pattern are preserved as-is, then deduplicated against existing matches.
    /// Returns the new match so callers can select it.
    @discardableResult
    func duplicate(matchID: UUID) throws -> EspansoMatch {
        for i in matchFiles.indices {
            guard let j = matchFiles[i].matches.firstIndex(where: { $0.id == matchID })
            else { continue }

            let original = matchFiles[i].matches[j]
            var copy = original
            copy.id = UUID()
            copy.label = original.label.map { "\($0) (copy)" }

            // Derive a unique primary trigger so the copy does not collide.
            let usedLiteral = Set(allMatches.flatMap { m -> [String] in
                var ts: [String] = []
                if let t = m.trigger { ts.append(t) }
                if let arr = m.triggers { ts.append(contentsOf: arr) }
                return ts
            })
            let usedRegex = Set(allMatches.compactMap { $0.regex })

            if let regex = original.regex {
                copy.regex = uniqueTrigger(base: regex, suffix: "-copy", taken: usedRegex)
            } else if let trig = original.trigger {
                copy.trigger = uniqueTrigger(base: trig, suffix: "-copy", taken: usedLiteral)
            } else if let triggers = original.triggers, let first = triggers.first {
                var newTriggers = triggers
                newTriggers[0] = uniqueTrigger(base: first, suffix: "-copy", taken: usedLiteral)
                copy.triggers = newTriggers
            }

            var updated = matchFiles[i].matches
            updated.insert(copy, at: j + 1)
            let url = matchFiles[i].url
            try suppressingWatcherEvents(for: url) {
                try YAMLSerializer.write(updated, to: url)
            }
            matchFiles[i].matches = updated
            return copy
        }
        throw NSError(
            domain: "macspanso.duplicate",
            code: 1,
            userInfo: [NSLocalizedDescriptionKey: "Match not found"]
        )
    }

    private func uniqueTrigger(base: String, suffix: String, taken: Set<String>) -> String {
        let first = base + suffix
        if !taken.contains(first) { return first }
        var n = 2
        while taken.contains("\(first)-\(n)") { n += 1 }
        return "\(first)-\(n)"
    }

    /// Move a match to a different file. Removes from the source file and appends to
    /// the destination file, writing both. No-op if the match is already in `targetURL`.
    /// Refuses to move into package files or files with parse errors.
    func move(matchID: UUID, to targetURL: URL) throws {
        // Locate the source file and match
        guard let sourceIndex = matchFiles.firstIndex(where: { f in
                  f.matches.contains(where: { $0.id == matchID })
              }),
              let matchIndex = matchFiles[sourceIndex].matches.firstIndex(where: { $0.id == matchID })
        else {
            throw NSError(
                domain: "macspanso.move",
                code: 1,
                userInfo: [NSLocalizedDescriptionKey: "Match not found"]
            )
        }

        let sourceURL = matchFiles[sourceIndex].url
        guard sourceURL != targetURL else { return }

        if let existing = matchFiles.first(where: { $0.url == targetURL }),
           existing.isPackage || existing.parseError != nil {
            throw NSError(
                domain: "macspanso.move",
                code: 2,
                userInfo: [NSLocalizedDescriptionKey: "Cannot move matches into a package or unreadable file."]
            )
        }

        let match = matchFiles[sourceIndex].matches[matchIndex]

        // Compose the new state for both files before writing.
        var newSource = matchFiles[sourceIndex].matches
        newSource.remove(at: matchIndex)

        // Write source first; if that fails, in-memory state is unchanged.
        try suppressingWatcherEvents(for: sourceURL) {
            try YAMLSerializer.write(newSource, to: sourceURL)
        }

        // Write destination — on failure we restore the source on disk so we don't
        // silently delete the user's match.
        do {
            if let destIndex = matchFiles.firstIndex(where: { $0.url == targetURL }) {
                var newDest = matchFiles[destIndex].matches
                newDest.append(match)
                try suppressingWatcherEvents(for: targetURL) {
                    try YAMLSerializer.write(newDest, to: targetURL)
                }
                matchFiles[destIndex].matches = newDest
            } else {
                // Destination file doesn't exist yet — create it.
                try suppressingWatcherEvents(for: targetURL) {
                    try YAMLSerializer.write([match], to: targetURL)
                }
                let newFile = MatchFile(url: targetURL, matches: [match], isPackage: false)
                matchFiles.append(newFile)
                matchFiles.sort { $0.url.path < $1.url.path }
                watcher.watch(url: targetURL)
            }
            matchFiles[sourceIndex].matches = newSource
        } catch {
            // Roll back the source file write so the match isn't lost.
            try? suppressingWatcherEvents(for: sourceURL) {
                try YAMLSerializer.write(matchFiles[sourceIndex].matches, to: sourceURL)
            }
            throw error
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
        let previous = matchFiles[index].matches
        matchFiles[index] = loadFile(at: url, reusingIDsFrom: previous)
        externallyChangedURL = nil
    }

    func dismissExternalChangeNotice() {
        externallyChangedURL = nil
    }
}
