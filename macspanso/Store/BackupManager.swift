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
            try await zip(matchDirectory: matchDirectory, to: dest)
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
            // Replace is destructive — snapshot first so the user has an undo path
            // even after the source backup is gone.
            if mode == .replace {
                try? await createSnapshot()
                try deleteUserMatchFiles()
            }
            try await unzip(source, to: matchDirectory)
            store?.load()
        } catch {
            showAlert(title: "Import Failed", message: error.localizedDescription)
        }
    }

    // MARK: - Snapshots

    private static let maxSnapshots = 10

    static var snapshotsDirectory: URL {
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

    func createSnapshot() async throws {
        let dir = Self.snapshotsDirectory
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        let stamp = ISO8601DateFormatter().string(from: Date())
            .replacingOccurrences(of: ":", with: "-")
        let url = dir.appendingPathComponent("snapshot-\(stamp).\(Self.backupExtension)")
        try await zip(matchDirectory: matchDirectory, to: url)
        Self.pruneOldSnapshots()
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
            // Snapshot the current state too — restoring is itself destructive.
            try? await createSnapshot()
            try deleteUserMatchFiles()
            try await unzip(snapshot.url, to: matchDirectory)
            store?.load()
        } catch {
            showAlert(title: "Restore Failed", message: error.localizedDescription)
        }
    }

    // MARK: - Zip Operations

    private func zip(matchDirectory: URL, to destination: URL) async throws {
        if FileManager.default.fileExists(atPath: destination.path) {
            try FileManager.default.removeItem(at: destination)
        }

        let destPath = destination.path
        let dirPath = matchDirectory.path

        try await Task.detached(priority: .userInitiated) {
            let proc = Process()
            proc.executableURL = URL(fileURLWithPath: "/usr/bin/zip")
            proc.arguments = ["-r", destPath, "."]
            proc.currentDirectoryURL = URL(fileURLWithPath: dirPath)
            let errPipe = Pipe()
            proc.standardOutput = Pipe()
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

    private func unzip(_ source: URL, to destination: URL) async throws {
        let srcPath = source.path
        let destPath = destination.path

        try await Task.detached(priority: .userInitiated) {
            let proc = Process()
            proc.executableURL = URL(fileURLWithPath: "/usr/bin/unzip")
            proc.arguments = ["-o", srcPath, "-d", destPath]
            let errPipe = Pipe()
            proc.standardOutput = Pipe()
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

    // MARK: - Helpers

    private func deleteUserMatchFiles() throws {
        let fm = FileManager.default
        let packagesPrefix = matchDirectory.appendingPathComponent("packages").path
        guard let enumerator = fm.enumerator(at: matchDirectory,
                                              includingPropertiesForKeys: nil) else { return }
        for case let url as URL in enumerator {
            guard url.pathExtension == "yml" else { continue }
            guard !url.path.hasPrefix(packagesPrefix) else { continue }
            try fm.removeItem(at: url)
        }
    }

    private func askImportMode() -> ImportMode? {
        let alert = NSAlert()
        alert.messageText = "Import Backup"
        alert.informativeText = "How should the backup be imported?\n\nMerge adds matches from the backup alongside your existing ones. Replace removes your current matches first."
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
