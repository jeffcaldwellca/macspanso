// macspanso/Model/FormField.swift
import Foundation

public struct FormField: Codable, Equatable {
    /// `choice` for dropdown fields (espanso `type: choice`); `nil` for plain text.
    public enum FieldKind: String, Codable, Equatable {
        case choice
    }

    public var type: FieldKind?
    /// Default value pre-filled in the text input.
    public var `default`: String?
    /// Whether the text input accepts multiple lines.
    public var multiline: Bool?
    /// Options shown in the dropdown. Only meaningful when `type == .choice`.
    public var values: [String]?

    public var isDropdown: Bool { type == .choice }

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

    private enum CodingKeys: String, CodingKey {
        case type, `default`, multiline, values
    }

    /// Custom encode using encodeIfPresent so nil fields are omitted entirely from YAML,
    /// rather than being written as `null` by the synthesized encoder.
    public func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encodeIfPresent(type,      forKey: .type)
        try c.encodeIfPresent(`default`, forKey: .default)
        try c.encodeIfPresent(multiline, forKey: .multiline)
        try c.encodeIfPresent(values,    forKey: .values)
    }
}
