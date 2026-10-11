// macspanso/Utilities/YAMLSerializer.swift
import Foundation
import Yams

public enum YAMLSerializer {

    // MARK: - Decode

    /// Decode matches from a YAML string (used in tests and from files).
    public static func decode(yaml: String) throws -> [EspansoMatch] {
        let trimmed = yaml.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return [] }

        // Files with no "matches:" key (global_vars.yml, etc.) decode fine because
        // MatchFileContent.matches is optional — they return [].
        // Comment-only files produce a non-mapping YAML node, causing a top-level
        // typeMismatch. We catch only that case (codingPath is empty) so errors inside
        // individual matches still propagate.
        do {
            let content = try YAMLDecoder().decode(MatchFileContent.self, from: yaml)
            return content.matches ?? []
        } catch DecodingError.typeMismatch(_, let ctx) where ctx.codingPath.isEmpty {
            try requireNoContent(yaml)
            return []
        }
    }

    /// Decode matches from a file URL.
    public static func decode(contentsOf url: URL) throws -> [EspansoMatch] {
        let text = try String(contentsOf: url, encoding: .utf8)
        return try decode(yaml: text)
    }

    /// Decode the full file content, including top-level keys macspanso doesn't
    /// model (global_vars, imports, …). Prefer this over `decode(yaml:)` whenever
    /// the result will be written back to disk.
    public static func decodeContent(yaml: String) throws -> MatchFileContent {
        let trimmed = yaml.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return MatchFileContent(matches: []) }
        do {
            return try YAMLDecoder().decode(MatchFileContent.self, from: yaml)
        } catch DecodingError.typeMismatch(_, let ctx) where ctx.codingPath.isEmpty {
            try requireNoContent(yaml)
            return MatchFileContent(matches: [])
        }
    }

    /// Decode the full file content from a file URL.
    public static func decodeContent(contentsOf url: URL) throws -> MatchFileContent {
        let text = try String(contentsOf: url, encoding: .utf8)
        return try decodeContent(yaml: text)
    }

    /// A top-level type mismatch is harmless only when the file holds no YAML
    /// content at all (comments, `---`, `~`). A file whose top level is a list
    /// or a bare value has content this app can't represent; treating it as
    /// empty would make it look safe to overwrite.
    private static func requireNoContent(_ yaml: String) throws {
        guard let root = try Yams.compose(yaml: yaml) else { return }
        if case .scalar(let scalar) = root, ["", "~", "null", "Null", "NULL"].contains(scalar.string),
           scalar.style == .plain || scalar.style == .any {
            return
        }
        throw DecodingError.dataCorrupted(.init(
            codingPath: [],
            debugDescription: "The top level of a match file must be a mapping with a `matches:` key."
        ))
    }

    // MARK: - Encode

    /// Encode matches to a YAML string. Top-level extras are empty; use
    /// `encode(_ content:)` when writing back a file that may carry them.
    public static func encode(_ matches: [EspansoMatch]) throws -> String {
        try encode(MatchFileContent(matches: matches))
    }

    /// Encode full file content (matches + preserved top-level keys).
    public static func encode(_ content: MatchFileContent) throws -> String {
        let encoder = YAMLEncoder()
        // Keep the file readable for people who also edit it by hand: emoji and
        // accents stay literal instead of \U… escapes, multi-line replacements
        // stay `|` blocks instead of one escaped line, and long lines aren't re-wrapped.
        encoder.options.allowUnicode = true
        encoder.options.newLineScalarStyle = .literal
        encoder.options.width = -1
        let yaml = try encoder.encode(content)

        // libyaml still escapes characters outside the Basic Multilingual Plane
        // (most emoji) as \UXXXXXXXX even with allowUnicode. Put them back, but
        // only keep the result if it provably parses to the same content.
        let readable = unescapingAstralCharacters(in: yaml)
        guard readable != yaml,
              let reparsed = try? YAMLDecoder().decode(MatchFileContent.self, from: readable),
              (try? encoder.encode(reparsed)) == yaml
        else { return yaml }
        return readable
    }

    /// Replace `\UXXXXXXXX` escapes with the character itself. An escaped
    /// backslash (`\\U…`) is literal text, so only an odd run of backslashes counts.
    private static func unescapingAstralCharacters(in yaml: String) -> String {
        guard yaml.contains("\\U"),
              let regex = try? NSRegularExpression(pattern: #"(?<!\\)((?:\\\\)*)\\U([0-9A-Fa-f]{8})"#)
        else { return yaml }
        var result = yaml
        let ns = yaml as NSString
        for m in regex.matches(in: yaml, range: NSRange(location: 0, length: ns.length)).reversed() {
            guard let value = UInt32(ns.substring(with: m.range(at: 2)), radix: 16),
                  let scalar = Unicode.Scalar(value), value > 0xFFFF,
                  let range = Range(m.range, in: result)
            else { continue }
            result.replaceSubrange(range, with: ns.substring(with: m.range(at: 1)) + String(Character(scalar)))
        }
        return result
    }

    // MARK: - Atomic Write

    /// Write matches atomically to a file URL.
    /// Uses String.write(atomically:) which does temp-file + rename.
    /// Creates the file if it doesn't exist.
    public static func write(_ matches: [EspansoMatch], to url: URL) throws {
        try write(MatchFileContent(matches: matches), to: url)
    }

    /// Write full file content atomically, preserving top-level extras.
    public static func write(_ content: MatchFileContent, to url: URL) throws {
        let yaml = try encode(content)
        try yaml.write(to: url, atomically: true, encoding: .utf8)
    }
}
