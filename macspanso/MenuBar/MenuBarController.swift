// macspanso/MenuBar/MenuBarController.swift
import AppKit
import Combine
import ServiceManagement

@MainActor
final class MenuBarController {
    private var statusItem: NSStatusItem
    private let store: EspansoConfigStore
    private let processManager: EspansoProcessManager
    private var cancellables = Set<AnyCancellable>()
    private var windowController: MatchManagerWindowController?
    private let backupManager: BackupManager
    private let updateChecker: UpdateChecker

    private static let espansoURL = URL(string: "https://espanso.org")!
    private static let releasesURL = URL(string: "https://github.com/jeffcaldwellca/macspanso/releases/latest")!

    init(store: EspansoConfigStore, processManager: EspansoProcessManager, updateChecker: UpdateChecker) {
        self.store = store
        self.processManager = processManager
        self.backupManager = BackupManager(matchDirectory: store.matchDirectory, store: store)
        self.updateChecker = updateChecker
        self.statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)

        configureIcon()
        buildMenu()

        // Rebuild menu only when the daemon state actually changes.
        processManager.$state
            .removeDuplicates()
            .receive(on: RunLoop.main)
            .sink { [weak self] _ in self?.buildMenu() }
            .store(in: &cancellables)

        // Rebuild when the snooze window starts/ends so the header reflects it.
        processManager.$snoozeUntil
            .removeDuplicates()
            .receive(on: RunLoop.main)
            .sink { [weak self] _ in self?.buildMenu() }
            .store(in: &cancellables)

        updateChecker.onStateChange = { [weak self] in
            self?.configureIcon()
            self?.buildMenu()
        }
    }

    private func configureIcon() {
        guard let button = statusItem.button else { return }
        let icon = NSImage(named: "logo-sm") ?? NSImage(systemSymbolName: "text.cursor", accessibilityDescription: "macspanso")!
        icon.isTemplate = true
        icon.size = NSSize(width: 16, height: 16)
        button.image = icon
        // Show a dot badge when an update is available.
        if updateChecker.updateAvailable {
            let dot = NSImage(systemSymbolName: "circle.fill", accessibilityDescription: nil)!
            dot.size = NSSize(width: 6, height: 6)
            button.imagePosition = .imageLeft
            let attributed = NSMutableAttributedString(string: " ")
            let attach = NSTextAttachment()
            attach.image = dot
            attributed.append(NSAttributedString(attachment: attach))
            button.attributedTitle = attributed
        } else {
            button.attributedTitle = NSAttributedString(string: "")
        }
    }

    private func buildMenu() {
        let menu = NSMenu()

        // Header item — shows espanso's status, not macspanso's running state
        let headerTitle: String
        if let until = processManager.snoozeUntil {
            headerTitle = "💤 Snoozed until \(formatSnoozeEnd(until))"
        } else {
            switch processManager.state {
            case .running:      headerTitle = "● Espanso enabled"
            case .disabled:     headerTitle = "○ Espanso disabled"
            case .stopped:      headerTitle = "✕ Espanso stopped"
            case .notInstalled: headerTitle = "⚠ Espanso not installed"
            case .unknown:      headerTitle = "Espanso"
            }
        }
        let headerItem = NSMenuItem(title: headerTitle, action: nil, keyEquivalent: "")
        headerItem.isEnabled = false
        menu.addItem(headerItem)
        menu.addItem(.separator())

        if processManager.state == .notInstalled {
            let item = NSMenuItem(title: "Espanso not found — see espanso.org",
                                  action: #selector(openEspansoSite), keyEquivalent: "")
            item.target = self
            menu.addItem(item)
        } else {
            let openItem = NSMenuItem(title: "Open Match Manager…",
                                      action: #selector(openMatchManager), keyEquivalent: "m")
            openItem.keyEquivalentModifierMask = [.command]
            openItem.target = self
            menu.addItem(openItem)

            let newItem = NSMenuItem(title: "New Match…",
                                     action: #selector(newMatch), keyEquivalent: "n")
            newItem.keyEquivalentModifierMask = [.command]
            newItem.target = self
            menu.addItem(newItem)

            menu.addItem(.separator())

            let exportItem = NSMenuItem(title: "Export Backup…",
                                        action: #selector(exportBackup), keyEquivalent: "")
            exportItem.target = self
            menu.addItem(exportItem)

            let importItem = NSMenuItem(title: "Import Backup…",
                                        action: #selector(importBackup), keyEquivalent: "")
            importItem.target = self
            menu.addItem(importItem)

            menu.addItem(buildSnapshotsMenuItem())

            menu.addItem(.separator())

            let enableItem = NSMenuItem(title: "Espanso Enabled",
                                        action: #selector(toggleEnabled), keyEquivalent: "")
            enableItem.target = self
            enableItem.state = (processManager.state == .running) ? .on : .off
            enableItem.isEnabled = (processManager.state == .running || processManager.state == .disabled)
            menu.addItem(enableItem)

            let restartItem = NSMenuItem(title: "Restart Espanso",
                                         action: #selector(restartEspanso), keyEquivalent: "")
            restartItem.target = self
            menu.addItem(restartItem)

            menu.addItem(buildSnoozeMenuItem())
        }

        menu.addItem(.separator())
        let launchAtLoginItem = NSMenuItem(title: "Launch at Login",
                                           action: #selector(toggleLaunchAtLogin), keyEquivalent: "")
        launchAtLoginItem.target = self
        launchAtLoginItem.state = (SMAppService.mainApp.status == .enabled) ? .on : .off
        menu.addItem(launchAtLoginItem)

        menu.addItem(.separator())
        let aboutItem = NSMenuItem(title: "About macspanso",
                                   action: #selector(openAbout), keyEquivalent: "")
        aboutItem.target = self
        menu.addItem(aboutItem)

        // Update items
        if updateChecker.updateAvailable, let latest = updateChecker.latestVersion {
            let updateItem = NSMenuItem(
                title: "Update Available — v\(latest) →",
                action: #selector(openReleasePage),
                keyEquivalent: ""
            )
            updateItem.target = self
            menu.addItem(updateItem)
        } else {
            let checkItem = NSMenuItem(
                title: "Check for Updates…",
                action: #selector(checkForUpdates),
                keyEquivalent: ""
            )
            checkItem.target = self
            menu.addItem(checkItem)
        }

        menu.addItem(.separator())
        let quitItem = NSMenuItem(title: "Quit", action: #selector(NSApplication.terminate(_:)),
                                  keyEquivalent: "q")
        menu.addItem(quitItem)

        statusItem.menu = menu
    }

    // MARK: - Actions

    @objc private func openMatchManager() {
        showMatchManager(focus: .none)
    }

    @objc private func newMatch() {
        showMatchManager(focus: .newMatch)
    }

    @objc private func openAbout() {
        showMatchManager(focus: .about)
    }

    private enum Focus { case none, newMatch, about }

    private func showMatchManager(focus: Focus) {
        if windowController == nil {
            let wc = MatchManagerWindowController(store: store, processManager: processManager)
            // window is guaranteed non-nil: MatchManagerWindowController calls
            // super.init(window: panel) so window is always set after init.
            let window = wc.window!
            NotificationCenter.default.addObserver(
                self,
                selector: #selector(windowDidClose(_:)),
                name: NSWindow.willCloseNotification,
                object: window
            )
            windowController = wc
        }
        if #available(macOS 14.0, *) {
            NSApp.activate()
        } else {
            NSApp.activate(ignoringOtherApps: true)
        }
        if let window = windowController?.window {
            // Display changes (docking, disconnected monitors) can leave the window
            // at coordinates no current screen covers — recenter if so.
            let onScreen = NSScreen.screens.contains { $0.frame.intersects(window.frame) }
            if !onScreen { window.center() }
            window.makeKeyAndOrderFront(nil)
        }
        switch focus {
        case .newMatch: windowController?.focusNewMatch()
        case .about:    windowController?.focusAbout()
        case .none:     break
        }
    }

    @objc private func windowDidClose(_ note: Notification) {
        windowController = nil
    }

    private func buildSnapshotsMenuItem() -> NSMenuItem {
        let topItem = NSMenuItem(title: "Restore from Snapshot", action: nil, keyEquivalent: "")
        let submenu = NSMenu()

        let snapshots = BackupManager.listSnapshots()
        if snapshots.isEmpty {
            let empty = NSMenuItem(title: "No snapshots yet", action: nil, keyEquivalent: "")
            empty.isEnabled = false
            submenu.addItem(empty)
        } else {
            for (index, snapshot) in snapshots.enumerated() {
                let item = NSMenuItem(
                    title: snapshot.displayName,
                    action: #selector(restoreSnapshot(_:)),
                    keyEquivalent: ""
                )
                item.target = self
                item.tag = index
                item.representedObject = snapshot.url
                submenu.addItem(item)
            }
            submenu.addItem(.separator())
            let revealItem = NSMenuItem(
                title: "Reveal in Finder",
                action: #selector(revealSnapshots),
                keyEquivalent: ""
            )
            revealItem.target = self
            submenu.addItem(revealItem)
        }
        topItem.submenu = submenu
        return topItem
    }

    private func buildSnoozeMenuItem() -> NSMenuItem {
        let topItem = NSMenuItem(title: "Snooze", action: nil, keyEquivalent: "")
        let submenu = NSMenu()

        if processManager.snoozeUntil != nil {
            let cancel = NSMenuItem(title: "End Snooze",
                                    action: #selector(cancelSnooze), keyEquivalent: "")
            cancel.target = self
            submenu.addItem(cancel)
        } else {
            for (title, sel) in [
                ("15 minutes", #selector(snooze15)),
                ("1 hour",     #selector(snooze1h)),
                ("4 hours",    #selector(snooze4h)),
                ("Until tomorrow", #selector(snoozeUntilTomorrow)),
            ] {
                let item = NSMenuItem(title: title, action: sel, keyEquivalent: "")
                item.target = self
                submenu.addItem(item)
            }
        }
        topItem.submenu = submenu
        return topItem
    }

    private func formatSnoozeEnd(_ date: Date) -> String {
        let f = DateFormatter()
        // Show date too if the snooze is past today (e.g. "until tomorrow").
        if Calendar.current.isDateInToday(date) {
            f.timeStyle = .short
            f.dateStyle = .none
        } else {
            f.timeStyle = .short
            f.dateStyle = .short
        }
        return f.string(from: date)
    }

    @objc private func snooze15() { processManager.snooze(for: .minutes(15)) }
    @objc private func snooze1h() { processManager.snooze(for: .hours(1)) }
    @objc private func snooze4h() { processManager.snooze(for: .hours(4)) }
    @objc private func snoozeUntilTomorrow() { processManager.snooze(for: .untilTomorrow) }
    @objc private func cancelSnooze() { processManager.cancelSnooze() }

    @objc private func toggleEnabled() {
        processManager.toggleEnabled()
    }

    @objc private func restartEspanso() {
        processManager.restart()
    }

    @objc private func openEspansoSite() {
        NSWorkspace.shared.open(Self.espansoURL)
    }

    @objc private func exportBackup() {
        Task { await backupManager.exportBackup() }
    }

    @objc private func importBackup() {
        Task { await backupManager.importBackup() }
    }

    @objc private func restoreSnapshot(_ sender: NSMenuItem) {
        guard let url = sender.representedObject as? URL else { return }
        let alert = NSAlert()
        alert.messageText = "Restore this snapshot?"
        alert.informativeText = "Your current matches will be replaced. A snapshot of the current state will be created first so this is reversible."
        alert.addButton(withTitle: "Restore")
        alert.addButton(withTitle: "Cancel")
        guard alert.runModal() == .alertFirstButtonReturn else { return }
        let snapshot = BackupManager.Snapshot(url: url, date: Date())
        Task { await backupManager.restoreSnapshot(snapshot) }
    }

    @objc private func revealSnapshots() {
        let dir = BackupManager.snapshotsDirectory
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        NSWorkspace.shared.open(dir)
    }

    @objc private func openReleasePage() {
        NSWorkspace.shared.open(Self.releasesURL)
    }

    @objc private func checkForUpdates() {
        updateChecker.checkNow()
    }

    @objc private func toggleLaunchAtLogin() {
        do {
            if SMAppService.mainApp.status == .enabled {
                try SMAppService.mainApp.unregister()
            } else {
                try SMAppService.mainApp.register()
            }
        } catch {
            NSLog("Launch at login toggle failed: %@", error.localizedDescription)
        }
        buildMenu()
    }
}
