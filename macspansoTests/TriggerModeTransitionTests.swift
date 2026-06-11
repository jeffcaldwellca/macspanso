// macspansoTests/TriggerModeTransitionTests.swift
import XCTest
@testable import macspanso

/// Switching a match between Text and Regex trigger modes in the editor.
/// Regression target: toggling a multi-trigger match to Regex and back used to
/// leave BOTH `trigger:` and `triggers:` set, writing invalid YAML.
final class TriggerModeTransitionTests: XCTestCase {

    func testSingleTriggerToRegexAndBack() {
        var m = EspansoMatch(trigger: "::hello", replace: "Hi")

        let saved = TriggerModeTransition.toRegex(&m)
        XCTAssertEqual(m.regex, "::hello")
        XCTAssertNil(m.trigger)
        XCTAssertNil(m.triggers)

        TriggerModeTransition.toText(&m, restoring: saved)
        XCTAssertEqual(m.trigger, "::hello")
        XCTAssertNil(m.regex)
        XCTAssertNil(m.triggers)
    }

    func testMultiTriggerToRegexAndBackRestoresTriggersOnly() {
        var m = EspansoMatch(triggers: ["::a", "::b"], replace: "AB")

        let saved = TriggerModeTransition.toRegex(&m)
        XCTAssertEqual(m.regex, "::a")
        XCTAssertNil(m.trigger)
        XCTAssertNil(m.triggers)

        TriggerModeTransition.toText(&m, restoring: saved)
        XCTAssertEqual(m.triggers, ["::a", "::b"])
        XCTAssertNil(m.regex)
        XCTAssertNil(m.trigger,
            "trigger: and triggers: must never both be set — that's invalid espanso YAML")
    }

    func testRegexEditedWhileInRegexModeComesBackAsText() {
        var m = EspansoMatch(trigger: "::x", replace: "X")
        let saved = TriggerModeTransition.toRegex(&m)
        m.regex = ":pat\\d+"

        TriggerModeTransition.toText(&m, restoring: saved)
        XCTAssertEqual(m.trigger, ":pat\\d+")
        XCTAssertNil(m.regex)
    }

    func testMultiTriggerRoundTripNeverEncodesBothKeys() throws {
        var m = EspansoMatch(triggers: ["::a", "::b"], replace: "AB")
        let saved = TriggerModeTransition.toRegex(&m)
        TriggerModeTransition.toText(&m, restoring: saved)

        let yaml = try YAMLSerializer.encode([m])
        XCTAssertFalse(yaml.contains("trigger:") && yaml.contains("triggers:")
                        && yaml.range(of: "\n  trigger:") != nil,
            "YAML must not contain both trigger: and triggers: keys:\n\(yaml)")
    }
}
