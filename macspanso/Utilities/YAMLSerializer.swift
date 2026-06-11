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
            return MatchFileContent(matches: [])
        }
    }

    /// Decode the full file content from a file URL.
    public static func decodeContent(contentsOf url: URL) throws -> MatchFileContent {
        let text = try String(contentsOf: url, encoding: .utf8)
        return try decodeContent(yaml: text)
    }

    // MARK: - Encode

    /// Encode matches to a YAML string. Top-level extras are empty; use
    /// `encode(_ content:)` when writing back a file that may carry them.
    public static func encode(_ matches: [EspansoMatch]) throws -> String {
        try encode(MatchFileContent(matches: matches))
    }

    /// Encode full file content (matches + preserved top-level keys).
    public static func encode(_ content: MatchFileContent) throws -> String {
        try YAMLEncoder().encode(content)
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
