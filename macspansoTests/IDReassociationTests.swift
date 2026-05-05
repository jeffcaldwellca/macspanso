// macspansoTests/IDReassociationTests.swift
import XCTest
@testable import macspanso

final class IDReassociationTests: XCTestCase {

    func testReassociatesByPrimaryTrigger() {
        let oldA = EspansoMatch(trigger: "::hello", replace: "Hi")
        let oldB = EspansoMatch(trigger: "::bye", replace: "Bye")

        // Simulate reload: new instances with fresh UUIDs but same triggers.
        var fresh = [
            EspansoMatch(trigger: "::hello", replace: "Hi (edited)"),
            EspansoMatch(trigger: "::bye", replace: "Bye"),
        ]

        EspansoConfigStore.reassociateIDs(into: &fresh, from: [oldA, oldB])

        XCTAssertEqual(fresh[0].id, oldA.id)
        XCTAssertEqual(fresh[1].id, oldB.id)
    }

    func testNewMatchesGetFreshIDs() {
        let oldA = EspansoMatch(trigger: "::hello", replace: "Hi")
        var fresh = [
            EspansoMatch(trigger: "::hello", replace: "Hi"),
            EspansoMatch(trigger: "::brand-new", replace: "New"),
        ]
        let originalNewID = fresh[1].id

        EspansoConfigStore.reassociateIDs(into: &fresh, from: [oldA])

        XCTAssertEqual(fresh[0].id, oldA.id)
        XCTAssertEqual(fresh[1].id, originalNewID, "Match without prior should keep its fresh ID")
    }

    func testRegexMatchReassociation() {
        let oldR = EspansoMatch(regex: "foo.*bar")
        var fresh = [EspansoMatch(regex: "foo.*bar")]

        EspansoConfigStore.reassociateIDs(into: &fresh, from: [oldR])

        XCTAssertEqual(fresh[0].id, oldR.id)
    }

    func testMultiTriggerReassociatesByFirstTrigger() {
        let old = EspansoMatch(triggers: ["::hi", "::hey"], replace: "Hello")
        var fresh = [EspansoMatch(triggers: ["::hi", "::howdy"], replace: "Hello")]

        EspansoConfigStore.reassociateIDs(into: &fresh, from: [old])

        XCTAssertEqual(fresh[0].id, old.id)
    }

    func testRenamedTriggerLosesAssociation() {
        // If a user renames a trigger externally, we can't recover the old ID.
        // Selection will be lost — accepted limitation.
        let old = EspansoMatch(trigger: "::hello", replace: "Hi")
        var fresh = [EspansoMatch(trigger: "::greet", replace: "Hi")]
        let originalNewID = fresh[0].id

        EspansoConfigStore.reassociateIDs(into: &fresh, from: [old])

        XCTAssertEqual(fresh[0].id, originalNewID)
    }
}
