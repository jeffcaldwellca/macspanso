// macspanso/App/AppDelegate.swift
import AppKit

final class AppDelegate: NSObject, NSApplicationDelegate {
    var menuBarController: MenuBarController?
    var configStore: EspansoConfigStore?
    var processManager: EspansoProcessManager?

    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.accessory)

        let matchDir = EspansoProcessManager.resolveMatchDirectory()
        let store = EspansoConfigStore(matchDirectory: matchDir)
        let procMgr = EspansoProcessManager()

        store.load()
        procMgr.startPolling()

        configStore = store
        processManager = procMgr
        menuBarController = MenuBarController(store: store, processManager: procMgr)
    }

    func applicationWillTerminate(_ notification: Notification) {
        processManager?.stopPolling()
    }
}
