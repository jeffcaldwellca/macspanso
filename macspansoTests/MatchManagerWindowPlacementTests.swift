// macspansoTests/MatchManagerWindowPlacementTests.swift
import XCTest
@testable import macspanso

/// The menu-bar action recenters the Match Manager window when a display change
/// (undocking, switching from an external monitor to the internal one) has left
/// it where the user can't reach it. The old guard used `frame.intersects`,
/// which is true for even a 1px overlap — so a window left straddling a screen
/// edge passed the check and was ordered front effectively off-screen, looking
/// like "the window didn't open". These tests pin the stronger contract: a
/// window only counts as visible when a real fraction of it is on a screen.
final class MatchManagerWindowPlacementTests: XCTestCase {

    /// 1440×900 internal display; menu bar eats the top 23pt, so visibleFrame
    /// height is 877. This is the screen that remains after undocking.
    private let internalVisibleFrame = CGRect(x: 0, y: 0, width: 1440, height: 877)

    /// After undocking, macOS can leave the window straddling the left edge with
    /// only a thin sliver on the remaining display. `intersects` would say "on
    /// screen"; the user sees nothing usable. This must recenter.
    func testRecentersWindowStraddlingScreenEdgeWithOnlyASliverVisible() {
        // Window spans x:-1100...100, so only 100pt of its 1200pt width overlaps.
        let frame = CGRect(x: -1100, y: 400, width: 1200, height: 820)

        let placement = MatchManagerWindowController.placement(
            forFrame: frame, visibleFrames: [internalVisibleFrame])

        XCTAssertEqual(placement, .recenter)
    }

    /// A window comfortably within the remaining display must be left alone —
    /// recentering a perfectly-visible window would be its own annoying bug.
    func testKeepsWindowComfortablyOnScreen() {
        let frame = CGRect(x: 120, y: 40, width: 1200, height: 820)

        let placement = MatchManagerWindowController.placement(
            forFrame: frame, visibleFrames: [internalVisibleFrame])

        XCTAssertEqual(placement, .keep)
    }

    /// The external monitor was to the left at negative coordinates; once it's
    /// gone, the window's frame intersects no remaining screen at all.
    func testRecentersWindowFullyOffScreen() {
        let frame = CGRect(x: -2000, y: 100, width: 1200, height: 820)

        let placement = MatchManagerWindowController.placement(
            forFrame: frame, visibleFrames: [internalVisibleFrame])

        XCTAssertEqual(placement, .recenter)
    }
}
