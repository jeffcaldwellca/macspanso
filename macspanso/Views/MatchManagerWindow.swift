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
            contentRect: NSRect(x: 0, y: 0, width: 860, height: 640),
            styleMask: [.titled, .closable, .resizable, .fullSizeContentView],
            backing: .buffered,
            defer: false
        )
        panel.title = "macspanso"
        panel.minSize = NSSize(width: 640, height: 520)
        panel.center()
        panel.isReleasedWhenClosed = false

        // Use NSHostingController (not NSHostingView) so SwiftUI gets full responder-chain
        // integration, keyboard focus cycling, and scene-environment setup.
        let rootView = MatchManagerView(store: store, processManager: processManager)
        let hc = NSHostingController(rootView: rootView)
        panel.contentViewController = hc

        super.init(window: panel)
    }

    required init?(coder: NSCoder) { fatalError("not used") }

    func focusNewMatch() {
        // Delay by one run-loop cycle so SwiftUI has time to render MatchManagerView
        // and set up its .onReceive subscriber before the notification fires.
        // Without this, the notification fires into the void on first window open.
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.05) {
            NotificationCenter.default.post(name: .focusNewMatch, object: nil)
        }
    }
}

extension Notification.Name {
    static let focusNewMatch = Notification.Name("com.macspanso.focusNewMatch")
}
