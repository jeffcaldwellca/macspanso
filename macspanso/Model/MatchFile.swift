// macspanso/Model/MatchFile.swift
import Foundation

// Top-level structure of an espanso .yml match file.
// `matches` is optional so files that have other top-level keys but no
// `matches:` key (e.g. global_vars.yml) decode without error.
public struct MatchFileContent: Codable {
    public var matches: [EspansoMatch]?

    public init(matches: [EspansoMatch]? = nil) {
        self.matches = matches
    }
}

// In-memory representation of a match file on disk
public struct MatchFile: Identifiable, Equatable {
    public var id: UUID
    public var url: URL
    public var matches: [EspansoMatch]
    public var isPackage: Bool
    public var parseError: String?  // non-nil if the file failed to parse

    public init(id: UUID = .init(), url: URL, matches: [EspansoMatch], isPackage: Bool, parseError: String? = nil) {
        self.id = id
        self.url = url
        self.matches = matches
        self.isPackage = isPackage
        self.parseError = parseError
    }

    public var displayName: String {
        url.lastPathComponent
    }
}
