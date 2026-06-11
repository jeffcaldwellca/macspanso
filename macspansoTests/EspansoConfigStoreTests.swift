// macspansoTests/EspansoConfigStoreTests.swift
import XCTest
@testable import macspanso

/// Write-path consistency: a failed disk write must leave the in-memory store
/// unchanged, and must not permanently suppress external-change detection.
@MainActor
final class EspansoConfigStoreTests: XCTestCase {

    private var dir: URL!

    override func setUp() async throws {
        dir = FileManager.default.temporaryDirectory
            .appendingPathComponent("macspanso-store-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
    }

    override func tearDown() async throws {
        // Restore permissions so cleanup can delete the tree.
        try? FileManager.default.setAttributes(
            [.posixPermissions: 0o755], ofItemAtPath: dir.path)
        try? FileManager.default.removeItem(at: dir)
    }

    private func makeStore(yaml: String, file: String = "base.yml") throws -> EspansoConfigStore {
        try yaml.write(to: dir.appendingPathComponent(file), atomically: true, encoding: .utf8)
        let store = EspansoConfigStore(matchDirectory: dir)
        store.load()
        return store
    }

    /// Atomic writes create a temp file in the target directory, so removing
    /// directory write permission makes every store write throw.
    private func makeDirectoryUnwritable() throws {
        try FileManager.default.setAttributes(
            [.posixPermissions: 0o555], ofItemAtPath: dir.path)
    }

    private func makeDirectoryWritable() throws {
        try FileManager.default.setAttributes(
            [.posixPermissions: 0o755], ofItemAtPath: dir.path)
    }

    // MARK: - Failed-write consistency

    func testFailedDeleteLeavesMatchInStore() throws {
        let store = try makeStore(yaml: """
        matches:
          - trigger: "::a"
            replace: Alpha
        """)
        let match = try XCTUnwrap(store.allMatches.first)

        try makeDirectoryUnwritable()
        XCTAssertThrowsError(try store.delete(matchID: match.id))

        XCTAssertTrue(store.allMatches.contains(where: { $0.id == match.id }),
            "a failed delete must not remove the match from memory — disk still has it")
    }

    func testFailedAddLeavesStoreUnchanged() throws {
        let store = try makeStore(yaml: """
        matches:
          - trigger: "::a"
            replace: Alpha
        """)

        try makeDirectoryUnwritable()
        let newMatch = EspansoMatch(trigger: "::b", replace: "Beta")
        XCTAssertThrowsError(try store.add(newMatch))

        XCTAssertFalse(store.allMatches.contains(where: { $0.id == newMatch.id }),
            "a failed add must not appear in memory — disk doesn't have it")
        XCTAssertEqual(store.allMatches.count, 1)
    }

    // MARK: - Watcher suppression after failed writes

    func testExternalChangeStillDetectedAfterFailedWrite() throws {
        let store = try makeStore(yaml: """
        matches:
          - trigger: "::a"
            replace: Alpha
        """)
        let fileURL = dir.appendingPathComponent("base.yml")
        var match = try XCTUnwrap(store.allMatches.first)
        match.label = "edited"

        // Failed write: with the leak, the suppression counter is incremented
        // and never released, so external edits are swallowed forever.
        try makeDirectoryUnwritable()
        XCTAssertThrowsError(try store.update(match))
        try makeDirectoryWritable()

        // Wait out the legitimate 2-second post-write suppression window.
        let window = XCTestExpectation(description: "suppression window elapsed")
        DispatchQueue.main.asyncAfter(deadline: .now() + 2.5) { window.fulfill() }
        wait(for: [window], timeout: 5)

        // Simulate an external edit.
        try """
        matches:
          - trigger: "::a"
            replace: Alpha (externally edited)
        """.write(to: fileURL, atomically: true, encoding: .utf8)

        let detected = XCTNSPredicateExpectation(
            predicate: NSPredicate { _, _ in store.externallyChangedURL != nil },
            object: nil
        )
        wait(for: [detected], timeout: 5)
        XCTAssertEqual(store.externallyChangedURL, fileURL)
    }
}

// MARK: - Directory scanning & watching

extension EspansoConfigStoreTests {

    func testScanIncludesYamlExtension() throws {
        // espanso v2 loads both .yml and .yaml files.
        let store = try makeStore(yaml: """
        matches:
          - trigger: "::a"
            replace: A
        """)
        try """
        matches:
          - trigger: "::b"
            replace: B
        """.write(to: dir.appendingPathComponent("extra.yaml"), atomically: true, encoding: .utf8)
        store.load()

        XCTAssertTrue(store.matchFiles.contains { $0.displayName == "extra.yaml" },
            "files with .yaml extension must be loaded: \(store.matchFiles.map(\.displayName))")
        XCTAssertEqual(store.allMatches.count, 2)
    }

    func testFileAddedInSubdirectoryIsDetected() throws {
        let sub = dir.appendingPathComponent("work")
        try FileManager.default.createDirectory(at: sub, withIntermediateDirectories: true)
        let store = try makeStore(yaml: """
        matches:
          - trigger: "::a"
            replace: A
        """)

        // Externally create a file inside the (pre-existing) subdirectory.
        try """
        matches:
          - trigger: "::sub"
            replace: S
        """.write(to: sub.appendingPathComponent("new.yml"), atomically: true, encoding: .utf8)

        let detected = XCTNSPredicateExpectation(
            predicate: NSPredicate { _, _ in
                store.matchFiles.contains { $0.displayName == "new.yml" }
            },
            object: nil
        )
        wait(for: [detected], timeout: 5)
        XCTAssertTrue(store.allMatches.contains { $0.trigger == "::sub" })
    }
}
