// macspanso/App/AppDelegate.swift
import AppKit

final class AppDelegate: NSObject, NSApplicationDelegate {
    var menuBarController: MenuBarController?
    var configStore: EspansoConfigStore?
    var processManager: EspansoProcessManager?

    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.accessory)

        // Resolve the match directory off the main thread (spawns `espanso path`),
        // then finish setup back on main.
        Task { @MainActor in
            let matchDir = await EspansoProcessManager.resolveMatchDirectory()
            let store = EspansoConfigStore(matchDirectory: matchDir)
            let procMgr = EspansoProcessManager()

            store.load()
            procMgr.startPolling()

            self.configStore = store
            self.processManager = procMgr
            self.menuBarController = MenuBarController(store: store, processManager: procMgr)
        }
    }

    func applicationWillTerminate(_ notification: Notification) {
        processManager?.stopPolling()
    }
}
