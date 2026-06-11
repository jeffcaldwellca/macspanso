// macspansoTests/RoundTripPreservationTests.swift
import XCTest
@testable import macspanso

/// Editing a match through macspanso must not destroy YAML content the app
/// doesn't model: top-level keys like `global_vars:` and per-match keys like
/// `markdown:` or `priority:` must survive a decode→encode round trip.
final class RoundTripPreservationTests: XCTestCase {

    func testGlobalVarsSurviveRoundTrip() throws {
        let yaml = """
        global_vars:
          - name: myname
            type: echo
            params:
              echo: Jeff
        matches:
          - trigger: "::hi"
            replace: "Hello {{myname}}"
        """
        let content = try YAMLSerializer.decodeContent(yaml: yaml)
        let out = try YAMLSerializer.encode(content)
        XCTAssertTrue(out.contains("global_vars"), "global_vars key must survive: \(out)")
        XCTAssertTrue(out.contains("myname"), "global var name must survive: \(out)")

        // Re-decoding the output must produce structurally identical extras.
        let again = try YAMLSerializer.decodeContent(yaml: out)
        XCTAssertEqual(content.extras, again.extras)
        XCTAssertEqual(again.matches?.first?.trigger, "::hi")
    }

    func testUnknownMatchKeysSurviveRoundTrip() throws {
        let yaml = """
        matches:
          - trigger: ":md"
            markdown: "**bold**"
            priority: 10
            paste_shortcut: CTRL+V
        """
        let matches = try YAMLSerializer.decode(yaml: yaml)
        let out = try YAMLSerializer.encode(matches)
        XCTAssertTrue(out.contains("markdown"), "unknown match key must survive: \(out)")
        XCTAssertTrue(out.contains("**bold**"))
        XCTAssertTrue(out.contains("priority"))
        XCTAssertTrue(out.contains("paste_shortcut"))
        XCTAssertTrue(out.contains("CTRL+V"))
    }

    func testNestedUnknownStructuresSurvive() throws {
        let yaml = """
        matches:
          - trigger: ":form2"
            form: "Hi [[choices]]"
            apps:
              - title: Slack
              - exe: notes
        """
        let matches = try YAMLSerializer.decode(yaml: yaml)
        let out = try YAMLSerializer.encode(matches)
        XCTAssertTrue(out.contains("apps"), "nested unknown structure must survive: \(out)")
        XCTAssertTrue(out.contains("Slack"))
        XCTAssertTrue(out.contains("notes"))
    }

    func testKnownKeysNotDuplicatedIntoExtras() throws {
        let yaml = """
        matches:
          - trigger: "::a"
            replace: Alpha
            word: true
        """
        let matches = try YAMLSerializer.decode(yaml: yaml)
        let match = try XCTUnwrap(matches.first)
        XCTAssertTrue(match.extras.isEmpty,
            "modelled keys must not leak into extras: \(match.extras)")
    }

    func testCommentOnlyFileStillDecodesEmpty() throws {
        // Regression guard: the empty-codingPath typeMismatch catch must keep working.
        let yaml = "# just a comment\n"
        let matches = try YAMLSerializer.decode(yaml: yaml)
        XCTAssertTrue(matches.isEmpty)
    }

    @MainActor
    func testStoreUpdatePreservesGlobalVarsOnDisk() throws {
        let dir = FileManager.default.temporaryDirectory
            .appendingPathComponent("macspanso-test-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        addTeardownBlock { try? FileManager.default.removeItem(at: dir) }

        let fileURL = dir.appendingPathComponent("base.yml")
        try """
        global_vars:
          - name: city
            type: echo
            params:
              echo: Sudbury
        matches:
          - trigger: "::where"
            replace: "I live in {{city}}"
        """.write(to: fileURL, atomically: true, encoding: .utf8)

        let store = EspansoConfigStore(matchDirectory: dir)
        store.load()

        var match = try XCTUnwrap(store.allMatches.first)
        match.label = "Edited"
        try store.update(match)

        let onDisk = try String(contentsOf: fileURL, encoding: .utf8)
        XCTAssertTrue(onDisk.contains("global_vars"),
            "editing a match must not delete global_vars from the file: \(onDisk)")
        XCTAssertTrue(onDisk.contains("Sudbury"))
        XCTAssertTrue(onDisk.contains("Edited"))
    }
}

// MARK: - Global var name extraction

extension RoundTripPreservationTests {

    @MainActor
    func testStoreExposesGlobalVarNames() throws {
        let dir = FileManager.default.temporaryDirectory
            .appendingPathComponent("macspanso-gv-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        addTeardownBlock { try? FileManager.default.removeItem(at: dir) }

        try """
        global_vars:
          - name: city
            type: echo
            params:
              echo: Sudbury
          - name: signoff
            type: echo
            params:
              echo: Best
        matches:
          - trigger: "::where"
            replace: "{{city}}"
        """.write(to: dir.appendingPathComponent("base.yml"), atomically: true, encoding: .utf8)

        let store = EspansoConfigStore(matchDirectory: dir)
        store.load()
        XCTAssertEqual(store.globalVarNames, ["city", "signoff"])
    }
}
