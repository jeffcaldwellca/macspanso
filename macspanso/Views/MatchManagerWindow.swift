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
            contentRect: NSRect(x: 0, y: 0, width: 800, height: 560),
            styleMask: [.titled, .closable, .resizable, .fullSizeContentView],
            backing: .buffered,
            defer: false
        )
        panel.title = "macspanso"
        panel.minSize = NSSize(width: 600, height: 400)
        panel.center()
        panel.isReleasedWhenClosed = false

        let rootView = MatchManagerView(store: store, processManager: processManager)
        panel.contentView = NSHostingView(rootView: rootView)

        super.init(window: panel)
    }

    required init?(coder: NSCoder) { fatalError("not used") }

    func focusNewMatch() {
        // Post a notification that MatchManagerView listens to
        NotificationCenter.default.post(name: .focusNewMatch, object: nil)
    }
}

extension Notification.Name {
    static let focusNewMatch = Notification.Name("com.macspanso.focusNewMatch")
}
