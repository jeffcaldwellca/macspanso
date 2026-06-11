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
}
