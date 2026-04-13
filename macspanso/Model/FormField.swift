// macspanso/Model/FormField.swift
import Foundation

public struct FormField: Codable, Equatable {
    public enum FieldKind: String, Codable, Equatable {
        case list
    }

    /// `list` for dropdown fields; `nil` for plain text fields.
    public var type: FieldKind?
    /// Default value shown in the text input.
    public var `default`: String?
    /// Whether the text input is multiline.
    public var multiline: Bool?
    /// Choices shown in the dropdown. Only meaningful when `type == .list`.
    public var values: [String]?

    public var isDropdown: Bool { type == .list }

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
        FormField(type: .list, values: values)
    }
}
