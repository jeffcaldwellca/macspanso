// macspanso/Views/MatchManagerWindow.swift
import AppKit
import SwiftUI

final class MatchManagerWindowController: NSWindowController {
    private let store: EspansoConfigStore
    private let processManager: EspansoProcessManager

    init(store: EspansoConfigStore, processManager: EspansoProcessManager) {
        self.store = store
        self.processManager = processManager

        let panel = NSPanel(
            contentRect: NSRect(x: 0, y: 0, width: 1200, height: 820),
            styleMask: [.titled, .closable, .resizable, .fullSizeContentView],
            backing: .buffered,
            defer: false
        )
        panel.title = "macspanso"
        panel.minSize = NSSize(width: 640, height: 520)
        let autosaveName: NSWindow.FrameAutosaveName = "MatchManagerWindow"
        if !panel.setFrameUsingName(autosaveName) {
            panel.center()
        }
        panel.setFrameAutosaveName(autosaveName)
        panel.isReleasedWhenClosed = false
        panel.collectionBehavior.insert(.moveToActiveSpace)
        // NSPanel defaults to hiding when the app deactivates — wrong for a
        // main editing window; users expect it to stay put when they switch apps.
        panel.hidesOnDeactivate = false

        // Use NSHostingController (not NSHostingView) so SwiftUI gets full responder-chain
        // integration, keyboard focus cycling, and scene-environment setup.
        let rootView = MatchManagerView(store: store, processManager: processManager)
        let hc = NSHostingController(rootView: rootView)
        panel.contentViewController = hc

        super.init(window: panel)
    }

    required init?(coder: NSCoder) { fatalError("not used") }

    enum WindowPlacement: Equatable { case keep, recenter }

    /// Decide whether a window at `frame` is reachable on the current displays,
    /// or should be recentered. Pure so it can be unit-tested without real
    /// screens.
    ///
    /// `frame.intersects(screen)` is too weak: it's true for even a 1px overlap,
    /// so a window left straddling a screen edge after undocking passes it and
    /// gets ordered front effectively off-screen. Instead we require at least
    /// `minVisibleFraction` of the window's area to fall within a single screen's
    /// visible frame; otherwise the user can't reach it and we recenter.
    static func placement(forFrame frame: CGRect,
                          visibleFrames: [CGRect],
                          minVisibleFraction: CGFloat = 0.5) -> WindowPlacement {
        let windowArea = frame.width * frame.height
        guard windowArea > 0 else { return .recenter }
        let bestOverlapArea = visibleFrames.reduce(CGFloat(0)) { best, screen in
            let overlap = screen.intersection(frame)
            guard !overlap.isNull else { return best }
            return max(best, overlap.width * overlap.height)
        }
        return bestOverlapArea >= windowArea * minVisibleFraction ? .keep : .recenter
    }

    func focusNewMatch() {
        postDelayed(.focusNewMatch)
    }

    func focusAbout() {
        postDelayed(.focusAbout)
    }

    /// Delays one run-loop cycle so SwiftUI has rendered MatchManagerView
    /// and wired up its .onReceive subscribers before the notification fires.
    private func postDelayed(_ name: Notification.Name) {
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.05) {
            NotificationCenter.default.post(name: name, object: nil)
        }
    }
}

extension Notification.Name {
    static let focusNewMatch = Notification.Name("com.macspanso.focusNewMatch")
    static let focusAbout    = Notification.Name("com.macspanso.focusAbout")
}
