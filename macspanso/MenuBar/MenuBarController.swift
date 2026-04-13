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
            button.image = NSImage(systemSymbolName: "text.cursor", accessibilityDescription: "macspanso")
            button.image?.isTemplate = true
        }
    }

    private func buildMenu() {
        let menu = NSMenu()

        // Header item (not clickable)
        let headerItem = NSMenuItem(title: "macspanso", action: nil, keyEquivalent: "")
        headerItem.isEnabled = false
        switch processManager.state {
        case .running:      headerItem.title = "macspanso  ● Running"
        case .disabled:     headerItem.title = "macspanso  ○ Disabled"
        case .stopped:      headerItem.title = "macspanso  ✕ Stopped"
        case .notInstalled: headerItem.title = "macspanso  ⚠ Not Installed"
        case .unknown:      headerItem.title = "macspanso"
        }
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

            let enableTitle = processManager.state == .disabled ? "Enable Espanso" : "Disable Espanso"
            let enableItem = NSMenuItem(title: enableTitle,
                                        action: #selector(toggleEnabled), keyEquivalent: "")
            enableItem.target = self
            if processManager.state == .running {
                enableItem.state = .on
            }
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
            // Nil our reference when the window closes so it can be deallocated.
            if let window = wc.window {
                NotificationCenter.default.addObserver(
                    self,
                    selector: #selector(windowDidClose(_:)),
                    name: NSWindow.willCloseNotification,
                    object: window
                )
            }
            windowController = wc
        }
        windowController?.showWindow(nil)
        if #available(macOS 14.0, *) {
            NSApp.activate()
        } else {
            NSApp.activate(ignoringOtherApps: true)
        }
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
