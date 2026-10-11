// macspanso/Model/FormField.swift
import Foundation

public struct FormField: Codable, Equatable {
    /// `choice` (dropdown) or `list` (list box) for fields that pick from
    /// `values`; `nil` for plain text. Open-ended so an unrecognised kind
    /// doesn't make the whole file fail to parse.
    public struct FieldKind: RawRepresentable, Codable, Equatable {
        public let rawValue: String
        public init(rawValue: String) { self.rawValue = rawValue }

        public static let choice = FieldKind(rawValue: "choice")
        public static let list   = FieldKind(rawValue: "list")
    }

    public var type: FieldKind?
    /// Default value pre-filled in the text input.
    public var `default`: String?
    /// Whether the text input accepts multiple lines.
    public var multiline: Bool?
    /// Options to pick from. Only meaningful when `isDropdown`.
    public var values: [String]?

    /// YAML keys on this field that macspanso doesn't model
    /// (trim_string_values, …), preserved verbatim so editing never destroys them.
    public var extras: [String: YAMLAny] = [:]

    public var isDropdown: Bool { type == .choice || type == .list }

    public init(
        type: FieldKind? = nil,
        default defaultValue: String? = nil,
        multiline: Bool? = nil,
        values: [String]? = nil
    ) {
        self.type = type
        self.default = defaultValue
        self.multiline = multiline
        self.values = values
    }

    /// A plain text field with no special configuration — the espanso default.
    public static let textDefault = FormField()

    /// A dropdown field with the given options.
    public static func dropdown(_ values: [String] = [""]) -> FormField {
        FormField(type: .choice, values: values)
    }

    // MARK: - Codable

    private enum CodingKeys: String, CodingKey, CaseIterable {
        case type, `default`, multiline, values
    }

    private static let knownKeys: Set<String> =
        Set(CodingKeys.allCases.map(\.rawValue))

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        self.type      = try c.decodeIfPresent(FieldKind.self, forKey: .type)
        self.default   = try c.decodeIfPresent(String.self,    forKey: .default)
        self.multiline = try c.decodeIfPresent(Bool.self,      forKey: .multiline)
        self.values    = try c.decodeIfPresent([String].self,  forKey: .values)

        let dynamic = try decoder.container(keyedBy: AnyCodingKey.self)
        var extras: [String: YAMLAny] = [:]
        for key in dynamic.allKeys where !Self.knownKeys.contains(key.stringValue) {
            extras[key.stringValue] = try dynamic.decode(YAMLAny.self, forKey: key)
        }
        self.extras = extras
    }

    /// Custom encode using encodeIfPresent so nil fields are omitted entirely from YAML,
    /// rather than being written as `null` by the synthesized encoder.
    public func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encodeIfPresent(type,      forKey: .type)
        try c.encodeIfPresent(`default`, forKey: .default)
        try c.encodeIfPresent(multiline, forKey: .multiline)
        try c.encodeIfPresent(values,    forKey: .values)

        var dynamic = encoder.container(keyedBy: AnyCodingKey.self)
        for key in extras.keys.sorted() {
            try dynamic.encode(extras[key]!, forKey: AnyCodingKey(stringValue: key))
        }
    }
}
