// macspanso/Store/BackupManager.swift
import AppKit
import UniformTypeIdentifiers

private enum ImportMode { case merge, replace }

@MainActor
final class BackupManager {
    private let matchDirectory: URL
    private weak var store: EspansoConfigStore?

    private static let backupExtension = "macspanso"
    private static let backupType = UTType(filenameExtension: backupExtension) ?? .data

    init(matchDirectory: URL, store: EspansoConfigStore) {
        self.matchDirectory = matchDirectory
        self.store = store
    }

    // MARK: - Export

    func exportBackup() async {
        let panel = NSSavePanel()
        panel.nameFieldStringValue = "espanso-backup.\(Self.backupExtension)"
        panel.allowedContentTypes = [Self.backupType]
        panel.message = "Save espanso match backup"
        panel.canCreateDirectories = true

        guard await panel.begin() == .OK, var dest = panel.url else { return }

        if dest.pathExtension != Self.backupExtension {
            dest = dest.deletingPathExtension().appendingPathExtension(Self.backupExtension)
        }

        do {
            try await Self.zipMatchDirectory(matchDirectory, to: dest)
        } catch {
            showAlert(title: "Export Failed", message: error.localizedDescription)
        }
    }

    // MARK: - Import

    func importBackup() async {
        let panel = NSOpenPanel()
        panel.message = "Choose a macspanso backup file"
        panel.allowedContentTypes = [Self.backupType]
        panel.allowsMultipleSelection = false
        panel.canChooseDirectories = false

        guard await panel.begin() == .OK, let source = panel.url else { return }
        guard let mode = askImportMode() else { return }

        do {
            try await performImport(from: source, replacing: mode == .replace)
        } catch {
            showAlert(title: "Import Failed", message: error.localizedDescription)
        }
    }

    /// Import without UI. Whatever happens, the store is reloaded afterwards so
    /// it never keeps showing files that are no longer what's on disk.
    func performImport(from source: URL, replacing: Bool) async throws {
        defer { store?.load() }
        if replacing {
            try await replaceUserMatchFiles(from: source)
        } else {
            try await Self.verifyBackup(source)
            // Merging overwrites any file the backup also contains, so it
            // needs an undo path too.
            if !Self.userMatchFiles(in: matchDirectory).isEmpty {
                try await createSnapshot()
            }
            try await Self.unzipBackup(source, to: matchDirectory)
        }
    }

    // MARK: - Snapshots

    private static let maxSnapshots = 10

    /// Tests point this at a temp directory; nil means the real location.
    static var snapshotsDirectoryOverride: URL?

    static var snapshotsDirectory: URL {
        if let override = snapshotsDirectoryOverride { return override }
        let appSupport = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
            ?? FileManager.default.homeDirectoryForCurrentUser
                .appendingPathComponent("Library/Application Support")
        return appSupport.appendingPathComponent("macspanso/snapshots")
    }

    struct Snapshot: Identifiable {
        let url: URL
        let date: Date
        var id: String { url.path }
        var displayName: String {
            let f = DateFormatter()
            f.dateStyle = .medium
            f.timeStyle = .short
            return f.string(from: date)
        }
    }

    @discardableResult
    func createSnapshot() async throws -> URL {
        let dir = Self.snapshotsDirectory
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        let stamp = ISO8601DateFormatter().string(from: Date())
            .replacingOccurrences(of: ":", with: "-")
        let url = dir.appendingPathComponent("snapshot-\(stamp).\(Self.backupExtension)")
        try await Self.zipMatchDirectory(matchDirectory, to: url)
        Self.pruneOldSnapshots()
        return url
    }

    static func listSnapshots() -> [Snapshot] {
        let fm = FileManager.default
        guard let urls = try? fm.contentsOfDirectory(
            at: snapshotsDirectory,
            includingPropertiesForKeys: [.contentModificationDateKey]
        ) else { return [] }

        return urls
            .filter { $0.pathExtension == backupExtension }
            .compactMap { url -> Snapshot? in
                let attrs = try? fm.attributesOfItem(atPath: url.path)
                let date = (attrs?[.modificationDate] as? Date) ?? Date.distantPast
                return Snapshot(url: url, date: date)
            }
            .sorted { $0.date > $1.date }
    }

    private static func pruneOldSnapshots() {
        let snapshots = listSnapshots()
        guard snapshots.count > maxSnapshots else { return }
        let stale = snapshots.dropFirst(maxSnapshots)
        for s in stale {
            try? FileManager.default.removeItem(at: s.url)
        }
    }

    func restoreSnapshot(_ snapshot: Snapshot) async {
        do {
            try await performRestore(from: snapshot.url)
        } catch {
            showAlert(title: "Restore Failed", message: error.localizedDescription)
        }
    }

    /// Restore without UI; reloads the store whatever the outcome.
    func performRestore(from archive: URL) async throws {
        defer { store?.load() }
        try await replaceUserMatchFiles(from: archive)
    }

    /// Replace the user's match files with the contents of `archive`.
    ///
    /// Order matters at every step, because this deletes the user's files:
    /// 1. Work from a private copy — taking the safety snapshot prunes old
    ///    snapshots, and the archive being restored may be the oldest one.
    /// 2. Verify the copy is readable before touching anything.
    /// 3. Snapshot the current files; if that fails, delete nothing.
    /// 4. Delete, then extract. If extraction fails anyway, put the snapshot
    ///    back so the user is left where they started, not with nothing.
    private func replaceUserMatchFiles(from archive: URL) async throws {
        let fm = FileManager.default
        let copy = fm.temporaryDirectory
            .appendingPathComponent("macspanso-restore-\(UUID().uuidString).\(Self.backupExtension)")
        try fm.copyItem(at: archive, to: copy)
        defer { try? fm.removeItem(at: copy) }

        try await Self.verifyBackup(copy)

        let current = Self.userMatchFiles(in: matchDirectory)
        var safetySnapshot: URL?
        // With no files there is nothing to lose (and `zip` fails on an empty directory).
        if !current.isEmpty {
            safetySnapshot = try await createSnapshot()
            for url in current { try fm.removeItem(at: url) }
        }

        do {
            try await Self.unzipBackup(copy, to: matchDirectory)
        } catch {
            if let safetySnapshot {
                try? await Self.unzipBackup(safetySnapshot, to: matchDirectory)
            }
            throw error
        }
    }

    // MARK: - Zip Operations

    /// Zip the user's match files into `destination`. Espanso-managed
    /// `packages/` content is the package manager's to back up, not ours.
    static func zipMatchDirectory(_ matchDirectory: URL, to destination: URL) async throws {
        if FileManager.default.fileExists(atPath: destination.path) {
            try FileManager.default.removeItem(at: destination)
        }

        let destPath = destination.path
        let dirPath = matchDirectory.path

        try await Task.detached(priority: .userInitiated) {
            let proc = Process()
            proc.executableURL = URL(fileURLWithPath: "/usr/bin/zip")
            // Both pattern forms — zip may store entries with or without "./".
            proc.arguments = ["-r", "-q", destPath, ".",
                              "-x", "packages/*", "./packages/*"]
            proc.currentDirectoryURL = URL(fileURLWithPath: dirPath)
            let errPipe = Pipe()
            // Nobody reads stdout; a pipe would fill and block the child.
            proc.standardOutput = FileHandle.nullDevice
            proc.standardError = errPipe
            try proc.run()
            proc.waitUntilExit()
            guard proc.terminationStatus == 0 else {
                let msg = String(data: errPipe.fileHandleForReading.readDataToEndOfFile(),
                                 encoding: .utf8) ?? "Unknown error"
                throw NSError(domain: "BackupManager", code: 1,
                              userInfo: [NSLocalizedDescriptionKey: msg])
            }
        }.value
    }

    /// Extract a backup into `destination`. Never writes into `packages/`,
    /// even when restoring a legacy backup that captured package files.
    static func unzipBackup(_ source: URL, to destination: URL) async throws {
        let srcPath = source.path
        let destPath = destination.path

        try await Task.detached(priority: .userInitiated) {
            let proc = Process()
            proc.executableURL = URL(fileURLWithPath: "/usr/bin/unzip")
            proc.arguments = ["-o", "-q", srcPath, "-d", destPath,
                              "-x", "packages/*", "./packages/*"]
            let errPipe = Pipe()
            // Nobody reads stdout; a pipe would fill and block the child.
            proc.standardOutput = FileHandle.nullDevice
            proc.standardError = errPipe
            try proc.run()
            proc.waitUntilExit()
            guard proc.terminationStatus == 0 else {
                let msg = String(data: errPipe.fileHandleForReading.readDataToEndOfFile(),
                                 encoding: .utf8) ?? "Unknown error"
                throw NSError(domain: "BackupManager", code: 2,
                              userInfo: [NSLocalizedDescriptionKey: msg])
            }
        }.value
    }

    /// Check the archive is readable end to end. Run before anything is
    /// deleted, so a corrupt backup can't leave the user with no matches.
    static func verifyBackup(_ source: URL) async throws {
        let srcPath = source.path
        try await Task.detached(priority: .userInitiated) {
            let proc = Process()
            proc.executableURL = URL(fileURLWithPath: "/usr/bin/unzip")
            proc.arguments = ["-t", "-qq", srcPath]
            proc.standardOutput = FileHandle.nullDevice
            proc.standardError = FileHandle.nullDevice
            try proc.run()
            proc.waitUntilExit()
            guard proc.terminationStatus == 0 else {
                throw NSError(domain: "BackupManager", code: 3,
                              userInfo: [NSLocalizedDescriptionKey:
                                "The backup file is damaged or isn't a valid archive. Nothing was changed."])
            }
        }.value
    }

    // MARK: - Helpers

    /// The user's own match files — everything espanso loads outside `packages/`.
    static func userMatchFiles(in matchDirectory: URL) -> [URL] {
        let fm = FileManager.default
        // Resolve both sides: enumeration yields /private/var/… where the
        // root may be spelled /var/….
        let packagesPrefix = matchDirectory.resolvingSymlinksInPath()
            .appendingPathComponent("packages").path + "/"
        guard let enumerator = fm.enumerator(at: matchDirectory,
                                              includingPropertiesForKeys: nil) else { return [] }
        return enumerator
            .compactMap { $0 as? URL }
            .filter { EspansoConfigStore.matchExtensions.contains($0.pathExtension) }
            .filter { !$0.resolvingSymlinksInPath().path.hasPrefix(packagesPrefix) }
    }

    private func askImportMode() -> ImportMode? {
        let alert = NSAlert()
        alert.messageText = "Import Backup"
        alert.informativeText = "How should the backup be imported?\n\nMerge adds the backup's files to your match folder; a file with the same name is replaced by the backup's version. Replace removes all your current match files first.\n\nEither way, a snapshot of the current state is saved first."
        alert.addButton(withTitle: "Merge")
        alert.addButton(withTitle: "Replace")
        alert.addButton(withTitle: "Cancel")
        switch alert.runModal() {
        case .alertFirstButtonReturn:  return .merge
        case .alertSecondButtonReturn: return .replace
        default:                       return nil
        }
    }

    private func showAlert(title: String, message: String) {
        let alert = NSAlert()
        alert.messageText = title
        alert.informativeText = message
        alert.runModal()
    }
}
