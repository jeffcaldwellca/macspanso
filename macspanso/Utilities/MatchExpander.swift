// macspanso/Utilities/MatchExpander.swift
import AppKit
import Foundation

/// Renders a preview of how a match would expand. Shell/script vars are not executed;
/// they show a `[shell: cmd]` placeholder so the user understands what would run without
/// the editor side-effecting the system on every keystroke. Form placeholders `[[name]]`
/// render as `[name]` to indicate they would prompt the user.
public enum MatchExpander {
    public static func preview(of match: EspansoMatch) -> String {
        let template = match.replace ?? match.form ?? ""
        var output = template

        // Substitute declared variables before form placeholders so a var named the same
        // as a form field does not get rewritten — but in practice form mode has no vars.
        for v in match.vars ?? [] {
            output = output.replacingOccurrences(of: "{{\(v.name)}}", with: resolve(v))
        }

        if match.form != nil {
            output = expandFormPlaceholders(output)
        }

        return output
    }

    private static func resolve(_ v: EspansoVar) -> String {
        switch v.type {
        case .date:
            let fmt = stringParam(v, "format") ?? "%Y-%m-%d"
            return formatDate(strftimePattern: fmt)
        case .clipboard:
            return NSPasteboard.general.string(forType: .string) ?? "[clipboard]"
        case .echo:
            return stringParam(v, "echo") ?? ""
        case .random:
            if case let .array(choices)? = v.params?["choices"], let first = choices.first {
                return first
            }
            return "[random]"
        case .shell:
            return "[shell: \(stringParam(v, "cmd") ?? "")]"
        case .script:
            return "[script]"
        case .form:
            return "[form]"
        case .match:
            return "[match]"
        }
    }

    private static func stringParam(_ v: EspansoVar, _ key: String) -> String? {
        if case let .string(s)? = v.params?[key] { return s }
        return nil
    }

    /// Convert the most common strftime tokens espanso accepts into ICU patterns
    /// understood by `DateFormatter`. Unknown tokens pass through verbatim, which
    /// matches espanso's behavior of treating unknown specifiers as literals.
    private static func formatDate(strftimePattern: String) -> String {
        let mapping: [(String, String)] = [
            ("%Y", "yyyy"), ("%y", "yy"),
            ("%m", "MM"), ("%B", "MMMM"), ("%b", "MMM"),
            ("%d", "dd"), ("%e", "d"),
            ("%H", "HH"), ("%I", "hh"),
            ("%M", "mm"), ("%S", "ss"),
            ("%A", "EEEE"), ("%a", "EEE"),
            ("%p", "a"), ("%P", "a"),
        ]
        var pattern = strftimePattern
        for (s, d) in mapping {
            pattern = pattern.replacingOccurrences(of: s, with: d)
        }
        let f = DateFormatter()
        f.dateFormat = pattern
        return f.string(from: Date())
    }

    private static func expandFormPlaceholders(_ template: String) -> String {
        template.replacing(/\[\[(\w+)\]\]/) { match in "[\(match.1)]" }
    }
}
