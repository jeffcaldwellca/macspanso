// macspansoTests/MatchExpanderTests.swift
import XCTest
@testable import macspanso

final class MatchExpanderTests: XCTestCase {

    func testPlainReplacementPassesThrough() {
        let m = EspansoMatch(trigger: "::hi", replace: "Hello, world")
        XCTAssertEqual(MatchExpander.preview(of: m), "Hello, world")
    }

    func testEchoVariableSubstitutes() {
        let m = EspansoMatch(
            trigger: "::greet",
            replace: "Hello {{name}}",
            vars: [EspansoVar(name: "name", type: .echo, params: ["echo": .string("Jeff")])]
        )
        XCTAssertEqual(MatchExpander.preview(of: m), "Hello Jeff")
    }

    func testDateVariableUsesFormat() {
        let m = EspansoMatch(
            trigger: "::y",
            replace: "{{y}}",
            vars: [EspansoVar(name: "y", type: .date, params: ["format": .string("%Y")])]
        )
        let preview = MatchExpander.preview(of: m)
        let year = Calendar.current.component(.year, from: Date())
        XCTAssertEqual(preview, "\(year)")
    }

    func testShellVariableShowsPlaceholderNotExecution() {
        let m = EspansoMatch(
            trigger: "::ls",
            replace: "{{out}}",
            vars: [EspansoVar(name: "out", type: .shell, params: ["cmd": .string("rm -rf /")])]
        )
        let preview = MatchExpander.preview(of: m)
        XCTAssertTrue(preview.contains("[shell:"), "shell command must not execute in preview")
        XCTAssertTrue(preview.contains("rm -rf /"))
    }

    func testRandomVariableShowsFirstChoice() {
        let m = EspansoMatch(
            trigger: "::r",
            replace: "{{r}}",
            vars: [EspansoVar(name: "r", type: .random, params: ["choices": .array(["a", "b", "c"])])]
        )
        XCTAssertEqual(MatchExpander.preview(of: m), "a")
    }

    func testFormPlaceholdersRenderAsBracketedNames() {
        let m = EspansoMatch(
            trigger: "::email",
            form: "Hello [[name]], your email is [[email]]"
        )
        XCTAssertEqual(MatchExpander.preview(of: m), "Hello [name], your email is [email]")
    }

    func testEmptyReplacementRendersEmpty() {
        let m = EspansoMatch(trigger: "::empty")
        XCTAssertEqual(MatchExpander.preview(of: m), "")
    }
}

// MARK: - Literal text in date formats

extension MatchExpanderTests {

    private func dateMatch(format: String) -> EspansoMatch {
        EspansoMatch(
            trigger: "::d",
            replace: "{{d}}",
            vars: [EspansoVar(name: "d", type: .date, params: ["format": .string(format)])]
        )
    }

    func testDateFormatLiteralTextPassesThrough() {
        // 'd', 'a', 'y', 's' are all ICU pattern letters — they must not be
        // interpreted when they appear as literal text around a token.
        let preview = MatchExpander.preview(of: dateMatch(format: "%Y days"))
        let year = Calendar.current.component(.year, from: Date())
        XCTAssertEqual(preview, "\(year) days")
    }

    func testDateFormatLiteralPrefixWithColon() {
        let preview = MatchExpander.preview(of: dateMatch(format: "Updated: %Y"))
        let year = Calendar.current.component(.year, from: Date())
        XCTAssertEqual(preview, "Updated: \(year)")
    }

    func testDateFormatEscapedPercentIsLiteral() {
        let preview = MatchExpander.preview(of: dateMatch(format: "100%% %Y"))
        let year = Calendar.current.component(.year, from: Date())
        XCTAssertEqual(preview, "100% \(year)")
    }

    func testDateFormatMultipleTokens() {
        let f = DateFormatter()
        f.dateFormat = "yyyy-MM-dd"
        let expected = f.string(from: Date())
        XCTAssertEqual(MatchExpander.preview(of: dateMatch(format: "%Y-%m-%d")), expected)
    }
}
