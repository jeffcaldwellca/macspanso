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
