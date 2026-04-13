// macspanso/Utilities/MatchValidator.swift
import Foundation

public enum ValidationError: Equatable {
    case emptyTrigger
    case duplicateTrigger
    case unresolvedVarReference(String)  // var name
    case duplicateVarName(String)         // var name
    case emptyShellCmd

    public static func == (lhs: ValidationError, rhs: ValidationError) -> Bool {
        switch (lhs, rhs) {
        case (.emptyTrigger, .emptyTrigger):           return true
        case (.duplicateTrigger, .duplicateTrigger):   return true
        case (.emptyShellCmd, .emptyShellCmd):         return true
        case (.unresolvedVarReference(let a), .unresolvedVarReference(let b)): return a == b
        case (.duplicateVarName(let a), .duplicateVarName(let b)): return a == b
        default: return false
        }
    }
}

public enum MatchValidator {
    public static func validate(_ match: EspansoMatch, existingMatches: [EspansoMatch]) -> [ValidationError] {
        var errors: [ValidationError] = []

        // Trigger must be present
        let hasTrigger = (match.trigger?.isEmpty == false)
            || (match.triggers?.isEmpty == false)
            || (match.regex?.isEmpty == false)
        if !hasTrigger { errors.append(.emptyTrigger) }

        // No duplicate triggers (exclude the match itself by ID)
        let others = existingMatches.filter { $0.id != match.id }
        let otherTriggers = Set(others.flatMap { m -> [String] in
            if let t = m.trigger { return [t] }
            if let ts = m.triggers { return ts }
            if let r = m.regex { return [r] }
            return []
        })
        let thisTriggers: [String] = {
            if let t = match.trigger { return [t] }
            if let ts = match.triggers { return ts }
            if let r = match.regex { return [r] }
            return []
        }()
        if thisTriggers.contains(where: { otherTriggers.contains($0) }) {
            errors.append(.duplicateTrigger)
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
        let varNames = (match.vars ?? []).map(\.name)
        let uniqueNames = Set(varNames)
        if varNames.count != uniqueNames.count {
            for name in uniqueNames where varNames.filter({ $0 == name }).count > 1 {
                errors.append(.duplicateVarName(name))
            }
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
    static func varReferences(in text: String) -> [String] {
        let pattern = #"\{\{(\w+)\}\}"#
        guard let regex = try? NSRegularExpression(pattern: pattern) else { return [] }
        let range = NSRange(text.startIndex..., in: text)
        return regex.matches(in: text, range: range).compactMap {
            Range($0.range(at: 1), in: text).map { String(text[$0]) }
        }
    }
}
