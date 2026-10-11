// macspansoTests/BackupManagerTests.swift
import XCTest
@testable import macspanso

/// Backups must not capture or overwrite espanso-managed package files:
/// exporting skips packages/, and importing never extracts into packages/.
@MainActor
final class BackupManagerTests: XCTestCase {

    private var dir: URL!

    override func setUp() async throws {
        dir = FileManager.default.temporaryDirectory
            .appendingPathComponent("macspanso-backup-\(UUID().uuidString)")
        try FileManager.default.createDirectory(
            at: dir.appendingPathComponent("packages/somepkg"),
            withIntermediateDirectories: true)
        try "matches:\n  - trigger: \"::a\"\n    replace: A\n"
            .write(to: dir.appendingPathComponent("base.yml"), atomically: true, encoding: .utf8)
        try "matches:\n  - trigger: \"::pkg\"\n    replace: P\n"
            .write(to: dir.appendingPathComponent("packages/somepkg/package.yml"),
                   atomically: true, encoding: .utf8)
    }

    override func tearDown() async throws {
        try? FileManager.default.removeItem(at: dir)
    }

    func testZipExcludesPackages() async throws {
        let dest = dir.appendingPathComponent("backup.macspanso")
        try await BackupManager.zipMatchDirectory(dir, to: dest)

        let listing = try listEntries(of: dest)
        XCTAssertTrue(listing.contains(where: { $0.contains("base.yml") }),
            "user file missing from backup: \(listing)")
        XCTAssertFalse(listing.contains(where: { $0.contains("packages/") }),
            "packages must not be captured in backups: \(listing)")
    }

    func testUnzipNeverWritesIntoPackages() async throws {
        // A legacy backup that DOES contain packages (created before exclusion).
        let legacyZip = dir.appendingPathComponent("legacy.macspanso")
        let zipProc = Process()
        zipProc.executableURL = URL(fileURLWithPath: "/usr/bin/zip")
        zipProc.arguments = ["-r", legacyZip.path, "."]
        zipProc.currentDirectoryURL = dir
        zipProc.standardOutput = Pipe()
        try zipProc.run()
        zipProc.waitUntilExit()

        let target = FileManager.default.temporaryDirectory
            .appendingPathComponent("macspanso-restore-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: target, withIntermediateDirectories: true)
        addTeardownBlock { try? FileManager.default.removeItem(at: target) }

        try await BackupManager.unzipBackup(legacyZip, to: target)

        XCTAssertTrue(FileManager.default.fileExists(
            atPath: target.appendingPathComponent("base.yml").path))
        XCTAssertFalse(FileManager.default.fileExists(
            atPath: target.appendingPathComponent("packages/somepkg/package.yml").path),
            "restore must never overwrite espanso-managed packages")
    }

    private func listEntries(of zip: URL) throws -> [String] {
        let proc = Process()
        proc.executableURL = URL(fileURLWithPath: "/usr/bin/zipinfo")
        proc.arguments = ["-1", zip.path]
        let pipe = Pipe()
        proc.standardOutput = pipe
        try proc.run()
        let data = pipe.fileHandleForReading.readDataToEndOfFile()
        proc.waitUntilExit()
        return String(data: data, encoding: .utf8)?
            .components(separatedBy: "\n").filter { !$0.isEmpty } ?? []
    }

    // MARK: - Restore safety

    func testVerifyRejectsDamagedBackup() async throws {
        let bogus = dir.appendingPathComponent("bogus.macspanso")
        try "this is not a zip".write(to: bogus, atomically: true, encoding: .utf8)
        do {
            try await BackupManager.verifyBackup(bogus)
            XCTFail("a damaged backup must be rejected before anything is deleted")
        } catch {}

        let good = dir.appendingPathComponent("good.macspanso")
        try await BackupManager.zipMatchDirectory(dir, to: good)
        try await BackupManager.verifyBackup(good)
    }

    func testUserMatchFilesCoversBothExtensionsAndSkipsPackages() throws {
        try "matches: []\n".write(to: dir.appendingPathComponent("extra.yaml"),
                                   atomically: true, encoding: .utf8)
        try "x".write(to: dir.appendingPathComponent("notes.txt"), atomically: true, encoding: .utf8)
        let names = Set(BackupManager.userMatchFiles(in: dir).map(\.lastPathComponent))
        XCTAssertEqual(names, ["base.yml", "extra.yaml"])
    }

    // MARK: - Restore ordering

    private func useTemporarySnapshotsDirectory() throws -> URL {
        let snapshots = FileManager.default.temporaryDirectory
            .appendingPathComponent("macspanso-snapshots-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: snapshots, withIntermediateDirectories: true)
        BackupManager.snapshotsDirectoryOverride = snapshots
        addTeardownBlock {
            await MainActor.run { BackupManager.snapshotsDirectoryOverride = nil }
            try? FileManager.default.removeItem(at: snapshots)
        }
        return snapshots
    }

    private func triggersOnDisk() throws -> [String] {
        try BackupManager.userMatchFiles(in: dir)
            .sorted { $0.path < $1.path }
            .flatMap { try YAMLSerializer.decode(contentsOf: $0) }
            .compactMap(\.trigger)
    }

    func testRestoringTheOldestSnapshotSurvivesPruning() async throws {
        let snapshots = try useTemporarySnapshotsDirectory()
        let store = EspansoConfigStore(matchDirectory: dir)
        store.load()
        let manager = BackupManager(matchDirectory: dir, store: store)

        // The snapshot to restore holds "::a"; make it the oldest of a full set.
        let oldest = try await manager.createSnapshot()
        try FileManager.default.setAttributes(
            [.modificationDate: Date(timeIntervalSinceNow: -86_400)], ofItemAtPath: oldest.path)
        for i in 0..<9 {
            let filler = snapshots.appendingPathComponent("snapshot-filler-\(i).macspanso")
            try FileManager.default.copyItem(at: oldest, to: filler)
            try FileManager.default.setAttributes(
                [.modificationDate: Date(timeIntervalSinceNow: Double(-3600 + i))], ofItemAtPath: filler.path)
        }
        XCTAssertEqual(BackupManager.listSnapshots().count, 10)
        XCTAssertEqual(BackupManager.listSnapshots().last?.url.lastPathComponent, oldest.lastPathComponent)

        // Current state differs from the snapshot.
        try "matches:\n  - trigger: \"::current\"\n    replace: C\n"
            .write(to: dir.appendingPathComponent("base.yml"), atomically: true, encoding: .utf8)

        try await manager.performRestore(from: oldest)

        XCTAssertEqual(try triggersOnDisk(), ["::a"], "the chosen snapshot must be what ends up on disk")
        XCTAssertEqual(store.allMatches.compactMap(\.trigger), ["::a"], "the store must be reloaded")
    }

    func testFailedRestoreLeavesCurrentFilesInPlace() async throws {
        _ = try useTemporarySnapshotsDirectory()
        let store = EspansoConfigStore(matchDirectory: dir)
        store.load()
        let manager = BackupManager(matchDirectory: dir, store: store)

        let bogus = dir.appendingPathComponent("bogus.macspanso")
        try "not a zip".write(to: bogus, atomically: true, encoding: .utf8)
        do {
            try await manager.performRestore(from: bogus)
            XCTFail("restoring a damaged archive must throw")
        } catch {}
        XCTAssertEqual(try triggersOnDisk(), ["::a"])
        XCTAssertTrue(BackupManager.listSnapshots().isEmpty, "nothing should have been touched")
    }

    func testReplaceImportRemovesYamlFilesToo() async throws {
        _ = try useTemporarySnapshotsDirectory()
        let backup = FileManager.default.temporaryDirectory
            .appendingPathComponent("macspanso-import-\(UUID().uuidString).macspanso")
        addTeardownBlock { try? FileManager.default.removeItem(at: backup) }
        try await BackupManager.zipMatchDirectory(dir, to: backup)   // holds only base.yml (::a)

        try "matches:\n  - trigger: \"::stale\"\n    replace: S\n"
            .write(to: dir.appendingPathComponent("old.yaml"), atomically: true, encoding: .utf8)
        let store = EspansoConfigStore(matchDirectory: dir)
        store.load()
        let manager = BackupManager(matchDirectory: dir, store: store)

        try await manager.performImport(from: backup, replacing: true)

        XCTAssertEqual(try triggersOnDisk(), ["::a"])
        XCTAssertEqual(BackupManager.listSnapshots().count, 1, "the replaced state must be recoverable")
    }
}
