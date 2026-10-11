// macspansoTests/MatchValidationTests.swift
import XCTest
@testable import macspanso

final class MatchValidationTests: XCTestCase {

    func testEmptyTriggerIsInvalid() {
        let match = EspansoMatch(trigger: "", replace: "Hello")
        let errors = MatchValidator.validate(match, existingMatches: [])
        XCTAssertTrue(errors.contains(.emptyTrigger))
    }

    func testDuplicateTriggerIsInvalid() {
        let existing = [EspansoMatch(trigger: "::hello", replace: "Hi")]
        let duplicate = EspansoMatch(trigger: "::hello", replace: "Howdy")
        let errors = MatchValidator.validate(duplicate, existingMatches: existing)
        XCTAssertTrue(errors.contains(.duplicateTrigger))
    }

    func testSameTriggerOnSameMatchIsNotDuplicate() {
        // Editing an existing match — its own trigger should not count as a duplicate
        let match = EspansoMatch(id: UUID(), trigger: "::hello", replace: "Hi")
        let errors = MatchValidator.validate(match, existingMatches: [match])
        XCTAssertFalse(errors.contains(.duplicateTrigger))
    }

    func testUnresolvedVarReference() {
        let match = EspansoMatch(trigger: "::date", replace: "{{mydate}}")
        // No vars declared — {{mydate}} is unresolved
        let errors = MatchValidator.validate(match, existingMatches: [])
        XCTAssertTrue(errors.contains(.unresolvedVarReference("mydate")))
    }

    func testResolvedVarReferenceIsValid() {
        let match = EspansoMatch(
            trigger: "::date",
            replace: "{{d}}",
            vars: [EspansoVar(name: "d", type: .date)]
        )
        let errors = MatchValidator.validate(match, existingMatches: [])
        XCTAssertFalse(errors.contains(.unresolvedVarReference("d")))
    }

    func testDuplicateVarNameIsInvalid() {
        let match = EspansoMatch(
            trigger: "::test",
            replace: "{{a}}",
            vars: [
                EspansoVar(name: "a", type: .date),
                EspansoVar(name: "a", type: .clipboard),
            ]
        )
        let errors = MatchValidator.validate(match, existingMatches: [])
        XCTAssertTrue(errors.contains(.duplicateVarName("a")))
    }

    func testShellVarWithEmptyCmdIsInvalid() {
        let match = EspansoMatch(
            trigger: "::shell",
            replace: "{{out}}",
            vars: [EspansoVar(name: "out", type: .shell, params: ["cmd": .string("")])]
        )
        let errors = MatchValidator.validate(match, existingMatches: [])
        XCTAssertTrue(errors.contains(.emptyShellCmd))
    }

    func testShellVarWithNilCmdIsInvalid() {
        let match = EspansoMatch(
            trigger: "::shell",
            replace: "{{out}}",
            vars: [EspansoVar(name: "out", type: .shell, params: nil)]
        )
        let errors = MatchValidator.validate(match, existingMatches: [])
        XCTAssertTrue(errors.contains(.emptyShellCmd))
    }

    func testValidMatchHasNoErrors() {
        let match = EspansoMatch(trigger: "::sig", replace: "Best regards,\nJeff")
        let errors = MatchValidator.validate(match, existingMatches: [])
        XCTAssertTrue(errors.isEmpty)
    }

    func testNoTriggerIsInvalid() {
        let match = EspansoMatch(replace: "Hello")  // trigger, triggers, regex all nil
        let errors = MatchValidator.validate(match, existingMatches: [])
        XCTAssertTrue(errors.contains(.emptyTrigger))
    }
}

// MARK: - Global variable references

extension MatchValidationTests {

    func testReferenceToGlobalVarIsValid() {
        // A {{name}} declared in global_vars (another file) must not block saving.
        let m = EspansoMatch(trigger: "::where", replace: "I live in {{city}}")
        let errors = MatchValidator.validate(
            m, existingMatches: [], globalVarNames: ["city"])
        XCTAssertTrue(errors.isEmpty, "global var reference flagged: \(errors)")
    }

    func testUnknownVarStillReportedWithGlobalsPresent() {
        let m = EspansoMatch(trigger: "::x", replace: "{{nope}}")
        let errors = MatchValidator.validate(
            m, existingMatches: [], globalVarNames: ["city"])
        XCTAssertEqual(errors, [.unresolvedVarReference("nope")])
    }

    // MARK: - Regex named groups

    func testRegexNamedGroupsAreValidReferences() {
        // The example from espanso's own docs.
        let match = EspansoMatch(regex: #":greet\((?P<person>.*)\)"#, replace: "Hi {{person}}!")
        XCTAssertEqual(MatchValidator.validate(match, existingMatches: []), [])

        let unknown = EspansoMatch(regex: "(?<a>x)", replace: "{{a}} {{b}}")
        XCTAssertEqual(MatchValidator.validate(unknown, existingMatches: []),
                       [.unresolvedVarReference("b")])
    }

    func testEspansoRegexCompilesForInAppTester() throws {
        let pattern = MatchValidator.icuPattern(fromEspansoRegex: #":greet\((?P<person>.*)\)"#)
        let regex = try NSRegularExpression(pattern: pattern)
        let input = ":greet(Jeff)"
        XCTAssertEqual(regex.numberOfMatches(in: input, range: NSRange(input.startIndex..., in: input)), 1)
    }

    // MARK: - Replacement required

    func testMatchWithoutAnyReplacementIsInvalid() {
        let match = EspansoMatch(trigger: "::x")
        XCTAssertEqual(MatchValidator.validate(match, existingMatches: []), [.emptyReplacement])
    }

    func testUnmodelledReplacementKindsCountAsAReplacement() {
        var image = EspansoMatch(trigger: "::img")
        image.extras["image_path"] = .string("/tmp/a.png")
        XCTAssertEqual(MatchValidator.validate(image, existingMatches: []), [])
    }

    // MARK: - Search

    func testSearchCoversAlternateTriggersLabelAndReplacement() {
        let match = EspansoMatch(triggers: ["::first", "::Second"], replace: "Body text", label: "My Label")
        XCTAssertTrue(match.matches(searchText: "second"), "alternate triggers must be searchable")
        XCTAssertTrue(match.matches(searchText: "label"))
        XCTAssertTrue(match.matches(searchText: "BODY"))
        XCTAssertFalse(match.matches(searchText: "nope"))
    }
}
