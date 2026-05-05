// macspansoTests/TriggerConflictTests.swift
import XCTest
@testable import macspanso

@MainActor
final class TriggerConflictTests: XCTestCase {

    private func makeStore(in dir: URL) -> EspansoConfigStore {
        EspansoConfigStore(matchDirectory: dir)
    }

    private var tempDir: URL {
        let dir = FileManager.default.temporaryDirectory
            .appendingPathComponent("macspanso-conflicts-\(UUID().uuidString)")
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir
    }

    func testNoConflictsWithDistinctTriggers() throws {
        let dir = tempDir
        try YAMLSerializer.write(
            [EspansoMatch(trigger: "::hello", replace: "Hi")],
            to: dir.appendingPathComponent("a.yml")
        )
        try YAMLSerializer.write(
            [EspansoMatch(trigger: "::bye", replace: "Bye")],
            to: dir.appendingPathComponent("b.yml")
        )
        let store = makeStore(in: dir)
        store.load()
        XCTAssertEqual(store.triggerConflicts().count, 0)
    }

    func testCrossFileConflictDetected() throws {
        let dir = tempDir
        try YAMLSerializer.write(
            [EspansoMatch(trigger: "::shared", replace: "from a")],
            to: dir.appendingPathComponent("a.yml")
        )
        try YAMLSerializer.write(
            [EspansoMatch(trigger: "::shared", replace: "from b")],
            to: dir.appendingPathComponent("b.yml")
        )
        let store = makeStore(in: dir)
        store.load()
        let conflicts = store.triggerConflicts()
        XCTAssertEqual(conflicts.count, 1)
        XCTAssertEqual(conflicts.first?.trigger, "::shared")
        XCTAssertEqual(conflicts.first?.occurrences.count, 2)
    }

    func testDuplicateWithinSameFileIsNotCrossFileConflict() throws {
        // Same-file duplicates are caught by MatchValidator at edit time.
        // triggerConflicts() only surfaces the cross-file case.
        let dir = tempDir
        try YAMLSerializer.write(
            [
                EspansoMatch(trigger: "::dup", replace: "1"),
                EspansoMatch(trigger: "::dup", replace: "2"),
            ],
            to: dir.appendingPathComponent("a.yml")
        )
        let store = makeStore(in: dir)
        store.load()
        XCTAssertEqual(store.triggerConflicts().count, 0)
    }
}
