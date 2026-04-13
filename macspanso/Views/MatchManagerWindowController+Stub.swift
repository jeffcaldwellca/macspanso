// macspanso/Views/MatchManagerWindowController+Stub.swift
// Stub — replaced in Task 8
import AppKit

@MainActor
final class MatchManagerWindowController: NSWindowController {
    init(store: EspansoConfigStore, processManager: EspansoProcessManager) {
        super.init(window: nil)
    }
    required init?(coder: NSCoder) { fatalError("not used") }
    func focusNewMatch() {}
}
