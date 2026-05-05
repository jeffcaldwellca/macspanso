// macspanso/App/MacspansoIntents.swift
import AppIntents
import AppKit

/// AppShortcuts surface in Shortcuts.app, Spotlight, and Siri. Reach the running
/// app via the shared NSApplicationDelegate — these intents only function while
/// macspanso is running (which it usually is, since it lives in the menu bar).
@available(macOS 13.0, *)
enum MacspansoIntents {
    @MainActor
    static func appDelegate() -> AppDelegate? {
        NSApp.delegate as? AppDelegate
    }
}

// MARK: - Toggle Espanso

@available(macOS 13.0, *)
struct ToggleEspansoIntent: AppIntent {
    static var title: LocalizedStringResource = "Toggle Espanso"
    static var description = IntentDescription("Enable or disable espanso text expansion.")

    func perform() async throws -> some IntentResult {
        await MainActor.run {
            MacspansoIntents.appDelegate()?.processManager?.toggleEnabled()
        }
        return .result()
    }
}

// MARK: - Restart Espanso

@available(macOS 13.0, *)
struct RestartEspansoIntent: AppIntent {
    static var title: LocalizedStringResource = "Restart Espanso"
    static var description = IntentDescription("Restart the espanso daemon.")

    func perform() async throws -> some IntentResult {
        await MainActor.run {
            MacspansoIntents.appDelegate()?.processManager?.restart()
        }
        return .result()
    }
}

// MARK: - Snooze Espanso

@available(macOS 13.0, *)
enum SnoozePresetOption: String, AppEnum {
    case fifteenMinutes
    case oneHour
    case fourHours
    case untilTomorrow

    static var typeDisplayRepresentation: TypeDisplayRepresentation = "Snooze Duration"
    static var caseDisplayRepresentations: [SnoozePresetOption: DisplayRepresentation] = [
        .fifteenMinutes:  "15 minutes",
        .oneHour:         "1 hour",
        .fourHours:       "4 hours",
        .untilTomorrow:   "Until tomorrow",
    ]
}

@available(macOS 13.0, *)
struct SnoozeEspansoIntent: AppIntent {
    static var title: LocalizedStringResource = "Snooze Espanso"
    static var description = IntentDescription("Temporarily disable espanso text expansion.")

    @Parameter(title: "Duration", default: .fifteenMinutes)
    var duration: SnoozePresetOption

    func perform() async throws -> some IntentResult {
        let snooze: EspansoProcessManager.SnoozeDuration = {
            switch duration {
            case .fifteenMinutes: return .minutes(15)
            case .oneHour:        return .hours(1)
            case .fourHours:      return .hours(4)
            case .untilTomorrow:  return .untilTomorrow
            }
        }()
        await MainActor.run {
            MacspansoIntents.appDelegate()?.processManager?.snooze(for: snooze)
        }
        return .result()
    }
}

// MARK: - New Match From Clipboard

@available(macOS 13.0, *)
struct NewMatchFromClipboardIntent: AppIntent {
    static var title: LocalizedStringResource = "New Match From Clipboard"
    static var description = IntentDescription("Create a new espanso match with the clipboard contents as the replacement.")

    @Parameter(title: "Trigger", description: "The shortcut that triggers expansion (e.g. ::myclip)")
    var trigger: String

    func perform() async throws -> some IntentResult & ProvidesDialog {
        let pasteboard = NSPasteboard.general.string(forType: .string) ?? ""
        guard !pasteboard.isEmpty else {
            return .result(dialog: "Clipboard is empty.")
        }

        let success = await MainActor.run { () -> Bool in
            guard let store = MacspansoIntents.appDelegate()?.configStore else { return false }
            let match = EspansoMatch(trigger: trigger, replace: pasteboard)
            do {
                try store.add(match)
                return true
            } catch {
                return false
            }
        }
        if success {
            return .result(dialog: "Created match \(trigger).")
        } else {
            return .result(dialog: "Could not create match — macspanso may not be ready yet.")
        }
    }
}

// MARK: - App Shortcuts provider

@available(macOS 13.0, *)
struct MacspansoShortcuts: AppShortcutsProvider {
    static var appShortcuts: [AppShortcut] {
        AppShortcut(
            intent: ToggleEspansoIntent(),
            phrases: ["Toggle \(.applicationName)", "Toggle espanso in \(.applicationName)"],
            shortTitle: "Toggle Espanso",
            systemImageName: "power"
        )
        AppShortcut(
            intent: RestartEspansoIntent(),
            phrases: ["Restart espanso in \(.applicationName)"],
            shortTitle: "Restart Espanso",
            systemImageName: "arrow.clockwise"
        )
        AppShortcut(
            intent: SnoozeEspansoIntent(),
            phrases: ["Snooze espanso in \(.applicationName)"],
            shortTitle: "Snooze Espanso",
            systemImageName: "moon.zzz"
        )
        AppShortcut(
            intent: NewMatchFromClipboardIntent(),
            phrases: ["New match from clipboard in \(.applicationName)"],
            shortTitle: "New Match From Clipboard",
            systemImageName: "doc.on.clipboard"
        )
    }
}
