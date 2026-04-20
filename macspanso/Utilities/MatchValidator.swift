// macspanso/Utilities/MatchValidator.swift
import Foundation

public enum ValidationError: Equatable {
    case emptyTrigger
    case duplicateTrigger
    case unresolvedVarReference(String)  // var name
    case duplicateVarName(String)         // var name
    case emptyShellCmd
    case emptyFormTemplate
}

public enum MatchValidator {
    public static func validate(_ match: EspansoMatch, existingMatches: [EspansoMatch]) -> [ValidationError] {
        var errors: [ValidationError] = []

        // Build the canonical trigger strings for this match (non-empty only)
        let thisTriggers: [String] = {
            var all: [String] = []
            if let t = match.trigger { all.append(t) }
            if let ts = match.triggers { all.append(contentsOf: ts) }
            if let r = match.regex { all.append(r) }
            return all
        }()

        let nonEmptyTriggers = thisTriggers.filter { !$0.isEmpty }

        // Trigger must be present and non-empty
        if nonEmptyTriggers.isEmpty { errors.append(.emptyTrigger) }

        // No duplicate triggers (exclude the match itself by ID, compare non-empty only)
        let others = existingMatches.filter { $0.id != match.id }
        let otherTriggers = Set(others.flatMap { m -> [String] in
            var all: [String] = []
            if let t = m.trigger { all.append(t) }
            if let ts = m.triggers { all.append(contentsOf: ts) }
            // Note: do NOT include regex in literal trigger comparison (different match type)
            return all
        }.filter { !$0.isEmpty })

        let otherRegexTriggers = Set(others.compactMap { $0.regex }.filter { !$0.isEmpty })

        // Only compare same-kind triggers to avoid false duplicates
        let thisLiteralTriggers: [String] = match.regex == nil ? nonEmptyTriggers : []
        let thisRegexTriggers = match.regex.map { [$0] } ?? []

        if thisLiteralTriggers.contains(where: { otherTriggers.contains($0) })
            || thisRegexTriggers.contains(where: { otherRegexTriggers.contains($0) }) {
            errors.append(.duplicateTrigger)
        }

        // Form template must not be empty
        if let form = match.form, form.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            errors.append(.emptyFormTemplate)
        }

        // {{varName}} references in replace must resolve to declared vars
        if let replace = match.replace {
            let refs = varReferences(in: replace)
            let declared = Set((match.vars ?? []).map(\.name))
            for ref in refs where !declared.contains(ref) {
                errors.append(.unresolvedVarReference(ref))
            }
        }

        // Duplicate var names
        var nameFreq = [String: Int]()
        for name in (match.vars ?? []).map(\.name) { nameFreq[name, default: 0] += 1 }
        for (name, count) in nameFreq where count > 1 {
            errors.append(.duplicateVarName(name))
        }

        // Shell vars must have a non-empty cmd
        for v in match.vars ?? [] where v.type == .shell {
            let cmd = v.params?["cmd"]
            if cmd == nil || cmd == .string("") {
                errors.append(.emptyShellCmd)
            }
        }

        return errors
    }

    /// Extract {{varName}} references from a replacement string.
    private static func varReferences(in text: String) -> [String] {
        let pattern = #"\{\{(\w+)\}\}"#
        guard let regex = try? NSRegularExpression(pattern: pattern) else { return [] }
        let range = NSRange(text.startIndex..., in: text)
        return regex.matches(in: text, range: range).compactMap {
            Range($0.range(at: 1), in: text).map { String(text[$0]) }
        }
    }
}
