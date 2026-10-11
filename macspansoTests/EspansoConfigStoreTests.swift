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

    // MARK: - External edits are never silently overwritten

    private func writeExternally(_ yaml: String, to name: String) throws {
        try yaml.write(to: dir.appendingPathComponent(name), atomically: true, encoding: .utf8)
    }

    func testSaveAfterExternalEditIsRefusedUntilResolved() throws {
        let store = try makeStore(yaml: "matches:\n  - trigger: \"::a\"\n    replace: A\n")
        let url = dir.appendingPathComponent("base.yml").resolvingSymlinksInPath()
        let external = "# edited by hand\nmatches:\n  - trigger: \"::a\"\n    replace: External\n"
        try writeExternally(external, to: "base.yml")

        // No waiting for the watcher: the write itself must notice.
        XCTAssertThrowsError(try store.add(EspansoMatch(trigger: "::b", replace: "B")))
        XCTAssertEqual(try String(contentsOf: url, encoding: .utf8), external)
        XCTAssertEqual(store.externallyChangedURL, url)
        XCTAssertEqual(store.allMatches.count, 1, "memory must not change when the write is refused")

        // Reload picks up the external version and unblocks writes.
        store.reloadFile(at: url)
        XCTAssertNil(store.externallyChangedURL)
        XCTAssertEqual(store.allMatches.first?.replace, "External")
        XCTAssertNoThrow(try store.add(EspansoMatch(trigger: "::b", replace: "B")))
    }

    func testKeepMineAllowsOverwritingExternalEdit() throws {
        let store = try makeStore(yaml: "matches:\n  - trigger: \"::a\"\n    replace: A\n")
        let url = dir.appendingPathComponent("base.yml")
        try writeExternally("matches:\n  - trigger: \"::a\"\n    replace: External\n", to: "base.yml")
        XCTAssertThrowsError(try store.add(EspansoMatch(trigger: "::b", replace: "B")))

        store.dismissExternalChangeNotice()
        XCTAssertNil(store.externallyChangedURL)
        XCTAssertNoThrow(try store.add(EspansoMatch(trigger: "::b", replace: "B")))
        let onDisk = try YAMLSerializer.decode(contentsOf: url)
        XCTAssertEqual(onDisk.map(\.replace), ["A", "B"])
    }

    func testEveryExternallyChangedFileIsQueued() throws {
        try writeExternally("matches:\n  - trigger: \"::o\"\n    replace: O\n", to: "other.yml")
        let store = try makeStore(yaml: "matches:\n  - trigger: \"::a\"\n    replace: A\n")
        try writeExternally("matches:\n  - trigger: \"::a\"\n    replace: A2\n", to: "base.yml")
        try writeExternally("matches:\n  - trigger: \"::o\"\n    replace: O2\n", to: "other.yml")

        let both = XCTNSPredicateExpectation(
            predicate: NSPredicate { _, _ in store.externallyChangedURLs.count == 2 }, object: nil)
        wait(for: [both], timeout: 5)

        // Resolving one must leave the other pending.
        store.reloadFile(at: try XCTUnwrap(store.externallyChangedURL))
        XCTAssertEqual(store.externallyChangedURLs.count, 1)
        store.reloadFile(at: try XCTUnwrap(store.externallyChangedURL))
        XCTAssertEqual(Set(store.allMatches.compactMap(\.replace)), ["A2", "O2"])
    }

    func testExternallyDeletedFileIsRemovedNotReportedAsChanged() throws {
        try writeExternally("matches:\n  - trigger: \"::o\"\n    replace: O\n", to: "other.yml")
        let store = try makeStore(yaml: "matches:\n  - trigger: \"::a\"\n    replace: A\n")
        XCTAssertEqual(store.matchFiles.count, 2)

        try FileManager.default.removeItem(at: dir.appendingPathComponent("other.yml"))
        let gone = XCTNSPredicateExpectation(
            predicate: NSPredicate { _, _ in store.matchFiles.count == 1 }, object: nil)
        wait(for: [gone], timeout: 5)
        XCTAssertNil(store.externallyChangedURL)
    }

    // MARK: - Comments survive saves

    func testStoreEditsKeepCommentsOnDisk() throws {
        let store = try makeStore(yaml: """
        # header comment
        matches:
          # first
          - trigger: "::a"
            replace: A
          # second
          - trigger: "::b"
            replace: B
        """)
        let url = dir.appendingPathComponent("base.yml")

        var a = try XCTUnwrap(store.allMatches.first)
        a.replace = "A2"
        try store.update(a)
        try store.add(EspansoMatch(trigger: "::c", replace: "C"))
        try store.duplicate(matchID: a.id)
        try store.delete(matchID: try XCTUnwrap(store.allMatches.first { $0.trigger == "::b" }).id)

        let text = try String(contentsOf: url, encoding: .utf8)
        XCTAssertTrue(text.hasPrefix("# header comment\nmatches:\n  # first\n"), text)
        XCTAssertFalse(text.contains("# second"), "a deleted match takes its own comment with it")
        XCTAssertEqual(try YAMLSerializer.decode(yaml: text).compactMap(\.trigger),
                       ["::a", "::a-copy", "::c"])
        XCTAssertEqual(store.allMatches.compactMap(\.trigger), ["::a", "::a-copy", "::c"])
    }

    // MARK: - Files the store must not mistake for empty or new

    func testFileWhoseTopLevelIsAListIsAnErrorNotAnEmptyFile() throws {
        let yaml = "# forgot the matches: key\n- trigger: \"::a\"\n  replace: A\n"
        let store = try makeStore(yaml: yaml)
        XCTAssertNotNil(store.matchFiles.first?.parseError)
        XCTAssertTrue(store.writableFiles.isEmpty)
        XCTAssertThrowsError(try store.add(EspansoMatch(trigger: "::new", replace: "N")))
        XCTAssertEqual(try String(contentsOf: dir.appendingPathComponent("base.yml"), encoding: .utf8), yaml)
    }

    func testAddingToCommentOnlyOrEmptyListFileKeepsItsComments() throws {
        for yaml in ["# - trigger: old\n#   replace: commented out\n", "# notes\nmatches: []\n# end\n"] {
            let store = try makeStore(yaml: yaml)
            XCTAssertNil(store.matchFiles.first?.parseError)
            try store.add(EspansoMatch(trigger: "::new", replace: "N"))
            let text = try String(contentsOf: dir.appendingPathComponent("base.yml"), encoding: .utf8)
            for line in yaml.split(separator: "\n") where line.hasPrefix("#") {
                XCTAssertTrue(text.contains(line), "lost \(line) in:\n\(text)")
            }
            XCTAssertEqual(try YAMLSerializer.decode(yaml: text).compactMap(\.trigger), ["::new"])
        }
    }

    func testAddingToAFileThatAppearedOnDiskUnnoticedDoesNotReplaceIt() throws {
        let store = try makeStore(yaml: "matches:\n  - trigger: \"::a\"\n    replace: A\n")
        // Created by someone else; the store hasn't heard about it yet.
        try writeExternally("# theirs\nmatches:\n  - trigger: \"::w\"\n    replace: W\n", to: "work.yml")
        let work = dir.appendingPathComponent("work.yml").resolvingSymlinksInPath()

        try store.add(EspansoMatch(trigger: "::new", replace: "N"), to: work)

        let text = try String(contentsOf: work, encoding: .utf8)
        XCTAssertTrue(text.hasPrefix("# theirs\n"))
        XCTAssertEqual(try YAMLSerializer.decode(yaml: text).compactMap(\.trigger), ["::w", "::new"])
        XCTAssertEqual(store.allMatches.count, 3)
    }

    func testRefusedMoveLeavesSourceFileUntouched() throws {
        try writeExternally("matches:\n  - trigger: \"::d\"\n    replace: D\n", to: "dest.yml")
        let source = "# header\nmatches:\n  # about a\n  - trigger: \"::a\"   # inline\n    replace: A\n"
        let store = try makeStore(yaml: source)
        let dest = try XCTUnwrap(store.matchFiles.first { $0.displayName == "dest.yml" }).url
        let a = try XCTUnwrap(store.allMatches.first { $0.trigger == "::a" })

        // Destination has an unresolved external edit, so the move must be refused…
        try writeExternally("matches:\n  - trigger: \"::d\"\n    replace: D2\n", to: "dest.yml")
        XCTAssertThrowsError(try store.move(matchID: a.id, to: dest))
        // …without the source having been rewritten at all.
        XCTAssertEqual(try String(contentsOf: dir.appendingPathComponent("base.yml"), encoding: .utf8), source)
    }

    // MARK: - Batch move

    func testBatchMoveFromSeveralFilesIntoOne() throws {
        try writeExternally("matches:\n  - trigger: \"::o1\"\n    replace: O1\n  - trigger: \"::o2\"\n    replace: O2\n", to: "other.yml")
        try writeExternally("# keep me\nmatches:\n  - trigger: \"::d\"\n    replace: D\n", to: "dest.yml")
        let store = try makeStore(yaml: "matches:\n  - trigger: \"::a\"\n    replace: A\n  - trigger: \"::b\"\n    replace: B\n")
        let dest = try XCTUnwrap(store.matchFiles.first { $0.displayName == "dest.yml" }).url
        let ids = Set(store.allMatches.filter { ["::a", "::o2", "::d"].contains($0.trigger) }.map(\.id))

        try store.move(matchIDs: ids, to: dest)

        func triggers(_ name: String) throws -> [String] {
            try YAMLSerializer.decode(contentsOf: dir.appendingPathComponent(name)).compactMap(\.trigger)
        }
        XCTAssertEqual(try triggers("base.yml"), ["::b"])
        XCTAssertEqual(try triggers("other.yml"), ["::o1"])
        XCTAssertEqual(try triggers("dest.yml"), ["::d", "::a", "::o2"])
        XCTAssertTrue(try String(contentsOf: dest, encoding: .utf8).hasPrefix("# keep me\n"))
        XCTAssertEqual(store.allMatches.count, 5, "nothing lost, nothing duplicated")
        XCTAssertEqual(store.file(containing: try XCTUnwrap(ids.first))?.url, dest)
    }

    func testBatchMoveNeverLosesMatchesWhenASourceCannotBeWritten() throws {
        try writeExternally("matches:\n  - trigger: \"::d\"\n    replace: D\n", to: "dest.yml")
        let store = try makeStore(yaml: "matches:\n  - trigger: \"::a\"\n    replace: A\n")
        let dest = try XCTUnwrap(store.matchFiles.first { $0.displayName == "dest.yml" }).url
        let a = try XCTUnwrap(store.allMatches.first { $0.trigger == "::a" })

        // An unresolved external edit makes the source refuse writes.
        try writeExternally("matches:\n  - trigger: \"::a\"\n    replace: A\n# touched\n", to: "base.yml")

        XCTAssertThrowsError(try store.move(matchIDs: [a.id], to: dest))
        let onDisk = try YAMLSerializer.decode(contentsOf: dir.appendingPathComponent("base.yml"))
            + YAMLSerializer.decode(contentsOf: dest)
        XCTAssertEqual(onDisk.compactMap(\.trigger).sorted(), ["::a", "::d"],
                       "the match must end up in exactly one file")
        XCTAssertEqual(store.allMatches.compactMap(\.trigger).sorted(), ["::a", "::d"])
    }

    // MARK: - Batch delete

    func testBatchDeleteRemovesAcrossFilesWithOneConsistentResult() throws {
        try writeExternally("matches:\n  - trigger: \"::o1\"\n    replace: O1\n  - trigger: \"::o2\"\n    replace: O2\n", to: "other.yml")
        let store = try makeStore(yaml: "matches:\n  - trigger: \"::a\"\n    replace: A\n  - trigger: \"::b\"\n    replace: B\n")
        let doomed = Set(store.allMatches.filter { ["::a", "::o2"].contains($0.trigger) }.map(\.id))

        try store.delete(matchIDs: doomed)

        XCTAssertEqual(Set(store.allMatches.compactMap(\.trigger)), ["::b", "::o1"])
        let base = try YAMLSerializer.decode(contentsOf: dir.appendingPathComponent("base.yml"))
        let other = try YAMLSerializer.decode(contentsOf: dir.appendingPathComponent("other.yml"))
        XCTAssertEqual(base.compactMap(\.trigger), ["::b"])
        XCTAssertEqual(other.compactMap(\.trigger), ["::o1"])
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

    // MARK: - Unparseable files are never written to

    private var brokenYAML: String { """
    matches:
      - trigger: "::keep"
        replace: [this, is, not, a, string]
    """ }

    func testAddRefusesToOverwriteFileThatFailedToParse() throws {
        let store = try makeStore(yaml: brokenYAML)
        let url = dir.appendingPathComponent("base.yml")
        XCTAssertNotNil(store.matchFiles.first?.parseError, "fixture must fail to parse")
        XCTAssertEqual(store.unreadableFiles.count, 1)

        // Default target (base.yml) and explicit target both hit the broken file.
        XCTAssertThrowsError(try store.add(EspansoMatch(trigger: "::new", replace: "N")))
        XCTAssertThrowsError(try store.add(EspansoMatch(trigger: "::new", replace: "N"), to: url))

        XCTAssertEqual(try String(contentsOf: url, encoding: .utf8), brokenYAML,
                       "the unparseable file must be left byte-for-byte intact")
        XCTAssertTrue(store.allMatches.isEmpty)
    }

    func testSaveRefusesToOverwriteFileThatFailedToParse() throws {
        let store = try makeStore(yaml: brokenYAML)
        let url = dir.appendingPathComponent("base.yml")
        let fileID = try XCTUnwrap(store.matchFiles.first).id

        XCTAssertThrowsError(
            try store.save(matches: [EspansoMatch(trigger: "::new", replace: "N")], in: fileID))
        XCTAssertEqual(try String(contentsOf: url, encoding: .utf8), brokenYAML)
    }
}
