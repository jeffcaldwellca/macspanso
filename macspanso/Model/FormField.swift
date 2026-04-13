// macspanso/Model/FormField.swift
import Foundation

public struct FormField: Codable, Equatable {
    public var `default`: String?
    public var multiline: Bool?
    public var choices: [String]?

    public init(default defaultValue: String? = nil, multiline: Bool? = nil, choices: [String]? = nil) {
        self.default = defaultValue
        self.multiline = multiline
        self.choices = choices
    }
}
