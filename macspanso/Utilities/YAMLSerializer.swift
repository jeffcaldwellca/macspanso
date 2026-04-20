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

    // MARK: - Encode

    /// Encode matches to a YAML string.
    public static func encode(_ matches: [EspansoMatch]) throws -> String {
        let content = MatchFileContent(matches: matches)
        return try YAMLEncoder().encode(content)
    }

    // MARK: - Atomic Write

    /// Write matches atomically to a file URL.
    /// Uses String.write(atomically:) which does temp-file + rename.
    /// Creates the file if it doesn't exist.
    public static func write(_ matches: [EspansoMatch], to url: URL) throws {
        let yaml = try encode(matches)
        try yaml.write(to: url, atomically: true, encoding: .utf8)
    }
}
