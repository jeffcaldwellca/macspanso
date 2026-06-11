// macspanso/Utilities/TriggerModeTransition.swift
import Foundation

/// Mutations applied when the editor switches a match between Text and Regex
/// trigger modes. Kept out of the view so the invariant — `trigger:` and
/// `triggers:` are never both set — is testable.
public enum TriggerModeTransition {

    /// Switch to regex mode. Returns the multi-trigger list to stash so it can
    /// be restored if the user switches back.
    public static func toRegex(_ match: inout EspansoMatch) -> [String]? {
        let saved = match.triggers
        match.regex = match.trigger ?? match.triggers?.first ?? ""
        match.trigger = nil
        match.triggers = nil
        return saved
    }

    /// Switch back to text mode, restoring a previously stashed trigger list.
    public static func toText(_ match: inout EspansoMatch, restoring savedTriggers: [String]?) {
        if var restored = savedTriggers, !restored.isEmpty {
            // Carry a pattern edited in regex mode back as the primary trigger.
            if let edited = match.regex, !edited.isEmpty { restored[0] = edited }
            match.triggers = restored
            match.trigger = nil
        } else {
            match.trigger = match.regex ?? ""
            match.triggers = nil
        }
        match.regex = nil
    }
}
