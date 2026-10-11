// macspanso/Store/EspansoConfigStore.swift
import Foundation
import Combine

@MainActor
final class EspansoConfigStore: ObservableObject {
    @Published var matchFiles: [MatchFile] = []

    /// Files changed on disk that the user hasn't yet chosen to reload or keep,
    /// oldest first. Writes to these are refused until the choice is made, so a
    /// save can't silently replace an external edit with stale in-memory content.
    @Published private(set) var externallyChangedURLs: [URL] = []

    /// The change the reload banner is currently asking about.
    var externallyChangedURL: URL? { externallyChangedURLs.first }

    /// Modification date of each file as last read or written by this store.
    /// A different date on disk means someone else changed it — this catches
    /// edits the watcher missed (events are suppressed around our own writes).
    private var knownModDates: [URL: Date] = [:]

    let matchDirectory: URL
    private let watcher = FileWatcher()

    /// Reference-counted write-in-progress markers; FSEvents for these paths are suppressed.
    private var writingPaths: [String: Int] = [:]

    /// All non-package matches, flattened across all files.
    var allMatches: [EspansoMatch] {
        matchFiles.filter { !$0.isPackage }.flatMap { $0.matches }
    }

    /// Names declared under `global_vars:` in any loaded file, sorted.
    /// Matches may reference these without declaring them locally.
    var globalVarNames: [String] {
        var names = Set<String>()
        for file in matchFiles {
            guard case let .array(items)? = file.extras["global_vars"] else { continue }
            for case let .dictionary(entry) in items {
                if case let .string(name)? = entry["name"] { names.insert(name) }
            }
        }
        return names.sorted()
    }

    init(matchDirectory: URL) {
        // Resolve symlinks once at the boundary: directory enumeration returns
        // symlink-resolved URLs (/private/var vs /var), and the store compares
        // constructed URLs against enumerated ones by equality throughout.
        self.matchDirectory = matchDirectory.resolvingSymlinksInPath()
        watcher.onChange = { [weak self] url in
            Task { @MainActor in self?.handleExternalChange(at: url) }
        }
    }

    // MARK: - Load

    func load() {
        watcher.stopAll()   // clear stale watches if load() is called more than once
        externallyChangedURLs = []
        knownModDates = [:]
        let urls = scanMatchDirectory()
        matchFiles = urls.map { loadFile(at: $0) }
        // Watch every directory in the tree: a dispatch source on the root
        // doesn't fire for files created inside subdirectories.
        watcher.watch(url: matchDirectory)
        scanSubdirectories().forEach { watcher.watch(url: $0) }
        matchFiles.forEach { watcher.watch(url: $0.url) }
    }

    /// espanso v2 loads both extensions.
    static let matchExtensions: Set<String> = ["yml", "yaml"]

    private func scanMatchDirectory() -> [URL] {
        guard let enumerator = FileManager.default.enumerator(
            at: matchDirectory,
            includingPropertiesForKeys: nil
        ) else { return [] }

        return enumerator
            .compactMap { $0 as? URL }
            .filter { Self.matchExtensions.contains($0.pathExtension) }
            // Normalize: enumeration yields /private/var/… for symlinked roots, while
            // URLs built via appendingPathComponent(_:) keep /var/…. Resolving strips
            // the /private prefix so URL equality works across the store.
            .map { $0.resolvingSymlinksInPath() }
            .sorted { $0.path < $1.path }
    }

    private func scanSubdirectories() -> [URL] {
        guard let enumerator = FileManager.default.enumerator(
            at: matchDirectory,
            includingPropertiesForKeys: [.isDirectoryKey]
        ) else { return [] }

        return enumerator
            .compactMap { $0 as? URL }
            .filter { (try? $0.resourceValues(forKeys: [.isDirectoryKey]))?.isDirectory == true }
            .map { $0.resolvingSymlinksInPath() }
    }

    private func loadFile(at url: URL, reusingIDsFrom previous: [EspansoMatch] = []) -> MatchFile {
        // Anchor package detection to the known config root rather than global path search.
        let relative = url.path.replacingOccurrences(of: matchDirectory.path, with: "")
        let isPackage = relative.hasPrefix("/packages/")
        knownModDates[url] = Self.modDate(of: url)
        do {
            let content = try YAMLSerializer.decodeContent(contentsOf: url)
            var matches = content.matches ?? []
            if !previous.isEmpty {
                Self.reassociateIDs(into: &matches, from: previous)
            }
            return MatchFile(url: url, matches: matches, isPackage: isPackage,
                             extras: content.extras)
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

    /// Full file content for a write: the new matches plus whatever top-level
    /// extras (global_vars, imports, …) the file carried when loaded.
    private func fileContent(_ matches: [EspansoMatch], for url: URL) -> MatchFileContent {
        let extras = matchFiles.first(where: { $0.url == url })?.extras ?? [:]
        return MatchFileContent(matches: matches, extras: extras)
    }

    nonisolated private static func modDate(of url: URL) -> Date? {
        (try? FileManager.default.attributesOfItem(atPath: url.path))?[.modificationDate] as? Date
    }

    /// A file can exist on disk without the store knowing it: created while
    /// directory events were suppressed around one of our own writes, or in a
    /// match folder that didn't exist at launch. Load it before writing "to a
    /// new file" at that path, which would replace whatever it holds.
    private func adoptIfOnDiskButUnknown(_ url: URL) {
        guard !matchFiles.contains(where: { $0.url == url }),
              FileManager.default.fileExists(atPath: url.path)
        else { return }
        matchFiles.append(loadFile(at: url))
        matchFiles.sort { $0.url.path < $1.url.path }
        watcher.watch(url: url)
    }

    /// The single funnel for every write. Refuses when the file has changed on
    /// disk since it was last read and the user hasn't resolved that yet.
    private func write(_ matches: [EspansoMatch], to url: URL) throws {
        // Backstop for the case `adoptIfOnDiskButUnknown` exists to prevent.
        if !matchFiles.contains(where: { $0.url == url }),
           FileManager.default.fileExists(atPath: url.path) {
            throw NSError(
                domain: "macspanso.write",
                code: 1,
                userInfo: [NSLocalizedDescriptionKey:
                    "\(url.lastPathComponent) already exists but hasn't been loaded, so nothing was written to it."]
            )
        }
        if !externallyChangedURLs.contains(url),
           let known = knownModDates[url], let onDisk = Self.modDate(of: url), onDisk != known {
            externallyChangedURLs.append(url)
        }
        if externallyChangedURLs.contains(url) {
            throw NSError(
                domain: "macspanso.externalChange",
                code: 1,
                userInfo: [NSLocalizedDescriptionKey:
                    "\(url.lastPathComponent) was changed outside macspanso. Open the Match Manager and choose Reload or Keep Mine first."]
            )
        }
        try suppressingWatcherEvents(for: url) {
            // Prefer editing the existing text in place, which keeps the user's
            // comments and formatting. Regenerating the file is the fallback.
            if let file = matchFiles.first(where: { $0.url == url }), file.parseError == nil,
               let original = try? String(contentsOf: url, encoding: .utf8),
               let patched = YAMLPatcher.patch(original: original,
                                               oldMatches: file.matches,
                                               newMatches: matches) {
                try patched.write(to: url, atomically: true, encoding: .utf8)
            } else {
                try YAMLSerializer.write(fileContent(matches, for: url), to: url)
            }
        }
        knownModDates[url] = Self.modDate(of: url)
    }

    /// Registers a write-in-progress for `url` so that the resulting FSEvent is
    /// not mistaken for an external edit. Clears after a short delay to account
    /// for async FSEvent delivery.
    private func suppressingWatcherEvents(for url: URL, _ body: () throws -> Void) rethrows {
        // Suppress the file itself, its parent directory (atomic writes rename
        // into it), and the root — all three can emit events for our own write.
        let paths = [url.path, url.deletingLastPathComponent().path, matchDirectory.path]
        paths.forEach { writingPaths[$0, default: 0] += 1 }
        // Schedule the decrement even when the write throws — otherwise the
        // counter leaks and external-edit detection is suppressed forever.
        defer {
            DispatchQueue.main.asyncAfter(deadline: .now() + 2.0) { [weak self] in
                guard let self else { return }
                for p in paths {
                    if let count = self.writingPaths[p] {
                        if count <= 1 { self.writingPaths.removeValue(forKey: p) }
                        else { self.writingPaths[p] = count - 1 }
                    }
                }
                // Directory events were ignored for the whole window; catch up
                // on any file another process added or removed meanwhile.
                if self.writingPaths[self.matchDirectory.path] == nil {
                    self.handleDirectoryChange()
                }
            }
        }
        try body()
    }

    /// Save a mutated match list back to the file that owns it.
    func save(matches: [EspansoMatch], in fileID: UUID) throws {
        guard let index = matchFiles.firstIndex(where: { $0.id == fileID }) else { return }
        if matchFiles[index].parseError != nil {
            throw NSError(
                domain: "macspanso.save",
                code: 1,
                userInfo: [NSLocalizedDescriptionKey:
                    "\(matchFiles[index].displayName) couldn't be read, so nothing was written to it."]
            )
        }
        let url = matchFiles[index].url
        try write(matches, to: url)
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
                try write(updated, to: url)
                matchFiles[i].matches = updated
                return
            }
        }
    }

    /// Add a new match. Saves to `targetURL` if provided; otherwise to base.yml.
    /// Creates the file if it doesn't exist. Refuses to write into package files
    /// and files that failed to parse.
    func add(_ match: EspansoMatch, to targetURL: URL? = nil) throws {
        let url = targetURL ?? matchDirectory.appendingPathComponent("base.yml")
        adoptIfOnDiskButUnknown(url)
        if let existing = matchFiles.first(where: { $0.url == url }), existing.isPackage {
            throw NSError(
                domain: "macspanso.add",
                code: 1,
                userInfo: [NSLocalizedDescriptionKey: "Cannot add matches to a package file."]
            )
        }
        // A file that failed to parse is held in memory as empty; writing to it
        // would replace everything on disk with just this match.
        if let existing = matchFiles.first(where: { $0.url == url }), existing.parseError != nil {
            throw NSError(
                domain: "macspanso.add",
                code: 2,
                userInfo: [NSLocalizedDescriptionKey:
                    "\(existing.displayName) couldn't be read, so nothing was written to it. Fix the file (see the file tree for the error) or choose another file."]
            )
        }
        if let index = matchFiles.firstIndex(where: { $0.url == url }) {
            // Write first; only update in-memory if the write succeeds.
            let updatedMatches = matchFiles[index].matches + [match]
            try write(updatedMatches, to: url)
            matchFiles[index].matches = updatedMatches
        } else {
            // File doesn't exist yet — create it
            try write([match], to: url)
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

    /// User files that failed to parse. Their matches are invisible to the app,
    /// so "no matches" must not be presented as an empty config when this is non-empty.
    var unreadableFiles: [MatchFile] {
        matchFiles.filter { !$0.isPackage && $0.parseError != nil }
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
            try write(updated, to: url)
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

    /// Move a match to a different file. No-op if the match is already in `targetURL`.
    /// Refuses to move into package files or files with parse errors.
    func move(matchID: UUID, to targetURL: URL) throws {
        guard let source = file(containing: matchID) else {
            throw NSError(
                domain: "macspanso.move",
                code: 1,
                userInfo: [NSLocalizedDescriptionKey: "Match not found"]
            )
        }
        guard source.url != targetURL else { return }
        try move(matchIDs: [matchID], to: targetURL)
    }

    /// Move several matches into `targetURL`, writing the destination once and
    /// each source file once. Matches already in the destination are skipped.
    ///
    /// The destination is written first, so a failure can only ever leave a
    /// match in both places, never in neither; a source file that then fails to
    /// write keeps its matches and they are taken back out of the destination.
    func move(matchIDs: Set<UUID>, to targetURL: URL) throws {
        adoptIfOnDiskButUnknown(targetURL)
        if let existing = matchFiles.first(where: { $0.url == targetURL }),
           existing.isPackage || existing.parseError != nil {
            throw NSError(
                domain: "macspanso.move",
                code: 2,
                userInfo: [NSLocalizedDescriptionKey: "Cannot move matches into a package or unreadable file."]
            )
        }

        // What each source file keeps, and what leaves it (in file order).
        var remainingBySource: [URL: [EspansoMatch]] = [:]
        var moving: [EspansoMatch] = []
        var sourceOfMoved: [UUID: URL] = [:]
        for file in matchFiles where file.url != targetURL && !file.isPackage {
            let leaving = file.matches.filter { matchIDs.contains($0.id) }
            guard !leaving.isEmpty else { continue }
            remainingBySource[file.url] = file.matches.filter { !matchIDs.contains($0.id) }
            moving += leaving
            leaving.forEach { sourceOfMoved[$0.id] = file.url }
        }
        guard !moving.isEmpty else { return }

        let existingDest = matchFiles.first(where: { $0.url == targetURL })?.matches ?? []
        try write(existingDest + moving, to: targetURL)
        if let destIndex = matchFiles.firstIndex(where: { $0.url == targetURL }) {
            matchFiles[destIndex].matches = existingDest + moving
        } else {
            matchFiles.append(MatchFile(url: targetURL, matches: moving, isPackage: false))
            watcher.watch(url: targetURL)
        }

        var firstError: Error?
        var failedSources: Set<URL> = []
        for (url, remaining) in remainingBySource {
            guard let index = matchFiles.firstIndex(where: { $0.url == url }) else { continue }
            do {
                try write(remaining, to: url)
                matchFiles[index].matches = remaining
            } catch {
                firstError = firstError ?? error
                failedSources.insert(url)
            }
        }

        if !failedSources.isEmpty, let destIndex = matchFiles.firstIndex(where: { $0.url == targetURL }) {
            let corrected = matchFiles[destIndex].matches.filter { m in
                sourceOfMoved[m.id].map { !failedSources.contains($0) } ?? true
            }
            if (try? write(corrected, to: targetURL)) != nil {
                matchFiles[destIndex].matches = corrected
            }
        }
        matchFiles.sort { $0.url.path < $1.url.path }
        if let firstError { throw firstError }
    }

    /// Delete a match by ID.
    func delete(matchID: UUID) throws {
        for i in matchFiles.indices {
            if let j = matchFiles[i].matches.firstIndex(where: { $0.id == matchID }) {
                let url = matchFiles[i].url
                // Write first; only update in-memory if the write succeeds.
                var updatedMatches = matchFiles[i].matches
                updatedMatches.remove(at: j)
                try write(updatedMatches, to: url)
                matchFiles[i].matches = updatedMatches
                return
            }
        }
    }

    /// Delete several matches, writing each affected file once. Files are
    /// independent: one that fails to write keeps its matches, the rest still
    /// go through, and the first error is rethrown after all were attempted.
    func delete(matchIDs: Set<UUID>) throws {
        var firstError: Error?
        for i in matchFiles.indices {
            let remaining = matchFiles[i].matches.filter { !matchIDs.contains($0.id) }
            guard remaining.count != matchFiles[i].matches.count else { continue }
            do {
                try write(remaining, to: matchFiles[i].url)
                matchFiles[i].matches = remaining
            } catch {
                firstError = firstError ?? error
            }
        }
        if let firstError { throw firstError }
    }

    /// Returns the MatchFile that owns a given match ID.
    func file(containing matchID: UUID) -> MatchFile? {
        matchFiles.first { $0.matches.contains(where: { $0.id == matchID }) }
    }

    // MARK: - External Change Handling

    private func handleExternalChange(at url: URL) {
        guard writingPaths[url.path] == nil else { return }
        var isDirectory: ObjCBool = false
        let exists = FileManager.default.fileExists(atPath: url.path, isDirectory: &isDirectory)
        if url == matchDirectory || isDirectory.boolValue || !exists {
            // A deleted file isn't "changed" — there is nothing to reload. Sync
            // the file list instead, which also drops its watch.
            handleDirectoryChange()
        } else if !externallyChangedURLs.contains(url) {
            externallyChangedURLs.append(url)
        }
    }

    /// Called when the match directory (or a subdirectory) changes — a file or
    /// folder added or removed externally. Silently syncs matchFiles with disk.
    private func handleDirectoryChange() {
        // The root may not have existed at launch; newly created
        // subdirectories need their own watch. (Both are no-ops if watched.)
        watcher.watch(url: matchDirectory)
        scanSubdirectories().forEach { watcher.watch(url: $0) }

        let urls = Set(scanMatchDirectory())
        let existingURLs = Set(matchFiles.map { $0.url })

        // Add newly discovered files
        let added = urls.subtracting(existingURLs)
        for url in added.sorted(by: { $0.path < $1.path }) {
            let file = loadFile(at: url)
            matchFiles.append(file)
            watcher.watch(url: url)
        }

        // Remove files that no longer exist on disk (and stop watching them,
        // so their dispatch sources and file descriptors don't leak)
        for file in matchFiles where !urls.contains(file.url) {
            watcher.stopWatching(url: file.url)
        }
        matchFiles.removeAll { !urls.contains($0.url) }
        externallyChangedURLs.removeAll { !urls.contains($0) }
        knownModDates = knownModDates.filter { urls.contains($0.key) }

        // Re-sort to keep consistent ordering
        matchFiles.sort { $0.url.path < $1.url.path }
    }

    /// Called when the user chooses "Reload" in the external edit banner.
    func reloadFile(at url: URL) {
        externallyChangedURLs.removeAll { $0 == url }
        guard let index = matchFiles.firstIndex(where: { $0.url == url }) else { return }
        let previous = matchFiles[index].matches
        matchFiles[index] = loadFile(at: url, reusingIDsFrom: previous)
    }

    /// Called when the user chooses "Keep Mine": the in-memory version wins, so
    /// accept the file's current state on disk as known and allow writes again.
    func dismissExternalChangeNotice() {
        guard let url = externallyChangedURLs.first else { return }
        externallyChangedURLs.removeFirst()
        knownModDates[url] = Self.modDate(of: url)
    }
}
