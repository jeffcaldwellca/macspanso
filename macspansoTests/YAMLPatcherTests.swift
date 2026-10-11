// macspansoTests/YAMLPatcherTests.swift
import XCTest
@testable import macspanso

/// Saving must keep what the user wrote by hand. Each test loads a commented
/// file, makes one kind of change, and checks both the text and the content.
final class YAMLPatcherTests: XCTestCase {

    private let source = """
    # My espanso matches
    # yaml-language-server: $schema=https://example.invalid/match.json

    global_vars:
      # who I am
      - name: me
        type: echo
        params:
          echo: Jeff

    matches:
      # --- Greetings ---
      - trigger: ":hi"      # short hello
        replace: "Hello"

      # Signature block
      - trigger: ":sig"
        replace: |
          Best,
          # not a comment, part of the text
          Jeff

      - {trigger: ":flow", replace: "flow style"}

    # trailing note

    """

    private func load() throws -> [EspansoMatch] {
        try YAMLSerializer.decode(yaml: source)
    }

    /// Patch, assert it succeeded, and check the result decodes to `new`.
    private func patch(_ old: [EspansoMatch], _ new: [EspansoMatch],
                       file: StaticString = #filePath, line: UInt = #line) throws -> String {
        let out = try XCTUnwrap(
            YAMLPatcher.patch(original: source, oldMatches: old, newMatches: new),
            "expected an in-place patch", file: file, line: line)
        let decoded = try YAMLSerializer.decode(yaml: out)
        XCTAssertEqual(decoded.map(\.trigger), new.map(\.trigger), file: file, line: line)
        XCTAssertEqual(decoded.map(\.replace), new.map(\.replace), file: file, line: line)
        return out
    }

    func testNoChangeReproducesFileExactly() throws {
        let old = try load()
        XCTAssertEqual(try patch(old, old), source)
    }

    func testEditingOneMatchLeavesEverythingElseByteForByte() throws {
        let old = try load()
        var new = old
        new[0].replace = "Hello there"

        let out = try patch(old, new)
        XCTAssertTrue(out.contains("replace: Hello there"))
        XCTAssertFalse(out.contains("# short hello"), "a comment inside the edited match can't be kept")
        // Everything outside the edited match is untouched.
        let before = source.components(separatedBy: "  - trigger: \":hi\"")[0]
        XCTAssertTrue(out.hasPrefix(before), "header, global_vars and the match's leading comment must survive")
        let after = "\n\n  # Signature block" + source.components(separatedBy: "\n\n  # Signature block")[1]
        XCTAssertTrue(out.hasSuffix(after), "later matches and the footer must be byte-for-byte identical")
    }

    func testAddingAMatchAppendsWithoutTouchingTheRest() throws {
        let old = try load()
        let out = try patch(old, old + [EspansoMatch(trigger: ":new", replace: "N")])

        XCTAssertTrue(out.contains("  - trigger: :new\n    replace: N\n"), "new match uses the file's indent:\n\(out)")
        XCTAssertTrue(out.hasSuffix("\n# trailing note\n"), "the trailing comment stays last")
        for kept in ["# My espanso matches", "# who I am", "# --- Greetings ---", "# short hello",
                     "# Signature block", "# not a comment, part of the text", "{trigger: \":flow\""] {
            XCTAssertTrue(out.contains(kept), "lost: \(kept)")
        }
    }

    func testDeletingAMatchRemovesItsLeadingCommentOnly() throws {
        let old = try load()
        let out = try patch(old, [old[0], old[2]])

        XCTAssertFalse(out.contains("# Signature block"))
        XCTAssertFalse(out.contains("Best,"))
        for kept in ["# --- Greetings ---", "# short hello", "{trigger: \":flow\"", "# trailing note", "# who I am"] {
            XCTAssertTrue(out.contains(kept), "lost: \(kept)")
        }
    }

    func testDeletingEveryMatchKeepsTheRestOfTheFile() throws {
        let old = try load()
        let out = try patch(old, [])
        XCTAssertTrue(out.contains("# who I am"))
        XCTAssertTrue(out.contains("# trailing note"))
        XCTAssertEqual(try YAMLSerializer.decodeContent(yaml: out).extras,
                       try YAMLSerializer.decodeContent(yaml: source).extras)
    }

    func testReorderingMovesCommentsWithTheirMatch() throws {
        let old = try load()
        let out = try patch(old, [old[1], old[0], old[2]])
        let sig = try XCTUnwrap(out.range(of: "# Signature block"))
        let greet = try XCTUnwrap(out.range(of: "# --- Greetings ---"))
        XCTAssertLessThan(sig.lowerBound, greet.lowerBound)
        XCTAssertTrue(out.contains("# short hello"))
    }

    func testAddingToFileWithoutMatchesKey() throws {
        let original = "# shared vars\nglobal_vars:\n  - name: me   # that's me\n    type: echo\n    params:\n      echo: Jeff\n"
        let new = [EspansoMatch(trigger: ":a", replace: "A")]
        let out = try XCTUnwrap(YAMLPatcher.patch(original: original, oldMatches: [], newMatches: new))
        XCTAssertTrue(out.hasPrefix(original))
        XCTAssertEqual(try YAMLSerializer.decode(yaml: out).map(\.trigger), [":a"])
    }

    func testDeclinesWhenTheTextIsNotWhatTheAppThinksItIs() throws {
        // Stale in-memory state (e.g. after "Keep Mine"): must not pair ids with the wrong text.
        var stale = try load()
        stale[0].replace = "something the file never contained"
        XCTAssertNil(YAMLPatcher.patch(original: source, oldMatches: stale, newMatches: stale))
    }

    func testDeclinesFlowStyleSequenceAndCRLF() throws {
        let flow = "matches: [{trigger: \":a\", replace: A}]\n"
        let old = try YAMLSerializer.decode(yaml: flow)
        XCTAssertNil(YAMLPatcher.patch(original: flow, oldMatches: old,
                                       newMatches: old + [EspansoMatch(trigger: ":b", replace: "B")]))

        let crlf = "matches:\r\n  - trigger: \":a\"\r\n    replace: A\r\n"
        let oldCRLF = try YAMLSerializer.decode(yaml: crlf)
        XCTAssertNil(YAMLPatcher.patch(original: crlf, oldMatches: oldCRLF, newMatches: []))
    }

    func testKeepTrailingBlankLinesScalarIsNeverCorrupted() throws {
        // `|+` makes trailing blank lines part of the text, which the chunking
        // treats as separators. Whatever the patcher does, content must be exact.
        let original = "matches:\n  - trigger: \":a\"\n    replace: |+\n      text\n\n\n  - trigger: \":b\"\n    replace: B\n"
        let old = try YAMLSerializer.decode(yaml: original)
        XCTAssertEqual(old[0].replace, "text\n\n\n")
        for new in [[old[1], old[0]], [old[0]], [old[1]]] {
            if let out = YAMLPatcher.patch(original: original, oldMatches: old, newMatches: new) {
                XCTAssertEqual(try YAMLSerializer.decode(yaml: out).map(\.replace), new.map(\.replace))
            }
        }
    }
}
