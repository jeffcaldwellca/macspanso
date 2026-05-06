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

        // Use NSHostingController (not NSHostingView) so SwiftUI gets full responder-chain
        // integration, keyboard focus cycling, and scene-environment setup.
        let rootView = MatchManagerView(store: store, processManager: processManager)
        let hc = NSHostingController(rootView: rootView)
        panel.contentViewController = hc

        super.init(window: panel)
    }

    required init?(coder: NSCoder) { fatalError("not used") }

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
