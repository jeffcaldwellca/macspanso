// macspanso/MenuBar/GlobalHotKeys.swift
import AppKit
import Carbon.HIToolbox

/// System-wide keyboard shortcuts that work while another app is frontmost.
/// The status menu's own ⌘M / ⌘N only fire while that menu is open.
///
/// Uses Carbon hot keys: the one global-shortcut API that needs no
/// Accessibility or Input Monitoring permission.
@MainActor
final class GlobalHotKeys {
    enum Action: UInt32, CaseIterable {
        case openMatchManager = 1
        case newMatch = 2

        fileprivate var keyCode: UInt32 {
            switch self {
            case .openMatchManager: return UInt32(kVK_ANSI_M)
            case .newMatch:         return UInt32(kVK_ANSI_N)
            }
        }

        /// ⌃⌥⌘ plus the same letter the menu uses with ⌘ alone.
        var displayString: String {
            switch self {
            case .openMatchManager: return "⌃⌥⌘M"
            case .newMatch:         return "⌃⌥⌘N"
            }
        }
    }

    var onAction: ((Action) -> Void)?

    private var hotKeyRefs: [EventHotKeyRef] = []
    private var handlerRef: EventHandlerRef?
    private static let signature: OSType = 0x4D53_504E   // 'MSPN'
    private static let modifiers = UInt32(controlKey | optionKey | cmdKey)

    var isEnabled: Bool { !hotKeyRefs.isEmpty }

    /// Register every shortcut. Returns false — with nothing left registered —
    /// if any of them is unavailable (typically: already taken by another app).
    @discardableResult
    func enable() -> Bool {
        guard !isEnabled else { return true }

        var eventType = EventTypeSpec(eventClass: OSType(kEventClassKeyboard),
                                      eventKind: UInt32(kEventHotKeyPressed))
        let status = InstallEventHandler(
            GetApplicationEventTarget(),
            { _, event, userData -> OSStatus in
                guard let event, let userData else { return OSStatus(eventNotHandledErr) }
                var hotKeyID = EventHotKeyID()
                let err = GetEventParameter(
                    event, EventParamName(kEventParamDirectObject), EventParamType(typeEventHotKeyID),
                    nil, MemoryLayout<EventHotKeyID>.size, nil, &hotKeyID)
                guard err == noErr else { return err }
                let hotKeys = Unmanaged<GlobalHotKeys>.fromOpaque(userData).takeUnretainedValue()
                let id = hotKeyID.id
                Task { @MainActor in hotKeys.fire(id) }
                return noErr
            },
            1, &eventType, Unmanaged.passUnretained(self).toOpaque(), &handlerRef)
        guard status == noErr else { return false }

        for action in Action.allCases {
            var ref: EventHotKeyRef?
            let id = EventHotKeyID(signature: Self.signature, id: action.rawValue)
            let err = RegisterEventHotKey(action.keyCode, Self.modifiers, id,
                                          GetApplicationEventTarget(), 0, &ref)
            guard err == noErr, let ref else {
                disable()
                return false
            }
            hotKeyRefs.append(ref)
        }
        return true
    }

    func disable() {
        hotKeyRefs.forEach { UnregisterEventHotKey($0) }
        hotKeyRefs = []
        if let handlerRef { RemoveEventHandler(handlerRef) }
        handlerRef = nil
    }

    private func fire(_ id: UInt32) {
        guard isEnabled, let action = Action(rawValue: id) else { return }
        onAction?(action)
    }
}
