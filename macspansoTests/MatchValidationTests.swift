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
