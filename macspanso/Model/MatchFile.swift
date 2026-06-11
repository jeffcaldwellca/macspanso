// macspanso/Model/MatchFile.swift
import Foundation

// Top-level structure of an espanso .yml match file.
// `matches` is optional so files that have other top-level keys but no
// `matches:` key (e.g. global_vars.yml) decode without error.
// Every top-level key other than `matches:` (global_vars, imports, …) is
// captured verbatim in `extras` and re-emitted on encode, so rewriting a
// file never deletes content macspanso doesn't model.
public struct MatchFileContent: Codable {
    public var matches: [EspansoMatch]?
    public var extras: [String: YAMLAny]

    public init(matches: [EspansoMatch]? = nil, extras: [String: YAMLAny] = [:]) {
        self.matches = matches
        self.extras = extras
    }

    private static let matchesKey = "matches"

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: AnyCodingKey.self)
        self.matches = try c.decodeIfPresent(
            [EspansoMatch].self, forKey: AnyCodingKey(stringValue: Self.matchesKey))
        var extras: [String: YAMLAny] = [:]
        for key in c.allKeys where key.stringValue != Self.matchesKey {
            extras[key.stringValue] = try c.decode(YAMLAny.self, forKey: key)
        }
        self.extras = extras
    }

    public func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: AnyCodingKey.self)
        try c.encodeIfPresent(matches, forKey: AnyCodingKey(stringValue: Self.matchesKey))
        for key in extras.keys.sorted() {
            try c.encode(extras[key]!, forKey: AnyCodingKey(stringValue: key))
        }
    }
}

// In-memory representation of a match file on disk
public struct MatchFile: Identifiable, Equatable {
    public var id: UUID
    public var url: URL
    public var matches: [EspansoMatch]
    public var isPackage: Bool
    public var parseError: String?  // non-nil if the file failed to parse
    /// Top-level YAML keys other than `matches:` (global_vars, imports, …),
    /// carried so they survive when the file is rewritten.
    public var extras: [String: YAMLAny]

    public init(id: UUID = .init(), url: URL, matches: [EspansoMatch], isPackage: Bool,
                parseError: String? = nil, extras: [String: YAMLAny] = [:]) {
        self.id = id
        self.url = url
        self.matches = matches
        self.isPackage = isPackage
        self.parseError = parseError
        self.extras = extras
    }

    public var displayName: String {
        url.lastPathComponent
    }
}
