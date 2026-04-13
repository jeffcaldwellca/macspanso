// macspanso/App/AppDelegate.swift
import AppKit

final class AppDelegate: NSObject, NSApplicationDelegate {
    var menuBarController: MenuBarController?

    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.accessory)
        menuBarController = MenuBarController()
    }

    func applicationWillTerminate(_ notification: Notification) {
        menuBarController = nil
    }
}
