// macspanso/App/macspansoApp.swift
import SwiftUI

@main
struct macspansoApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) var appDelegate

    var body: some Scene {
        // No windows — menu bar only. LSUIElement suppresses the Dock icon.
        Settings { EmptyView() }
    }
}
