// macspanso/MenuBar/MenuBarController.swift
import AppKit
import Combine

@MainActor
final class MenuBarController {
    private var statusItem: NSStatusItem
    private let store: EspansoConfigStore
    private let processManager: EspansoProcessManager
    private var cancellables = Set<AnyCancellable>()
    private var windowController: MatchManagerWindowController?

    private static let espansoURL = URL(string: "https://espanso.org")!

    init(store: EspansoConfigStore, processManager: EspansoProcessManager) {
        self.store = store
        self.processManager = processManager
        self.statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)

        configureIcon()
        buildMenu()

        // Rebuild menu only when the daemon state actually changes.
        processManager.$state
            .removeDuplicates()
            .receive(on: RunLoop.main)
            .sink { [weak self] _ in self?.buildMenu() }
            .store(in: &cancellables)
    }

    private func configureIcon() {
        if let button = statusItem.button {
            let icon = NSImage(named: "macspanso-sm") ?? NSImage(systemSymbolName: "text.cursor", accessibilityDescription: "macspanso")!
            icon.size = NSSize(width: 16, height: 16)
            button.image = icon
        }
    }

    private func buildMenu() {
        let menu = NSMenu()

        // Header item — shows espanso's status, not macspanso's running state
        let headerTitle: String
        switch processManager.state {
        case .running:      headerTitle = "● Espanso enabled"
        case .disabled:     headerTitle = "○ Espanso disabled"
        case .stopped:      headerTitle = "✕ Espanso stopped"
        case .notInstalled: headerTitle = "⚠ Espanso not installed"
        case .unknown:      headerTitle = "Espanso"
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
        }

        menu.addItem(.separator())
        let quitItem = NSMenuItem(title: "Quit", action: #selector(NSApplication.terminate(_:)),
                                  keyEquivalent: "q")
        menu.addItem(quitItem)

        statusItem.menu = menu
    }

    // MARK: - Actions

    @objc private func openMatchManager() {
        showMatchManager(newMatch: false)
    }

    @objc private func newMatch() {
        showMatchManager(newMatch: true)
    }

    private func showMatchManager(newMatch: Bool) {
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
        windowController?.window?.makeKeyAndOrderFront(nil)
        if newMatch {
            windowController?.focusNewMatch()
        }
    }

    @objc private func windowDidClose(_ note: Notification) {
        windowController = nil
    }

    @objc private func toggleEnabled() {
        processManager.toggleEnabled()
    }

    @objc private func restartEspanso() {
        processManager.restart()
    }

    @objc private func openEspansoSite() {
        NSWorkspace.shared.open(Self.espansoURL)
    }
}
