// macspanso/Model/EspansoMatch.swift
import Foundation

public struct EspansoMatch: Identifiable, Codable, Equatable {
    public var id: UUID

    // Trigger — exactly one of these should be set
    public var trigger: String?
    public var triggers: [String]?
    public var regex: String?

    // Replacement — exactly one of these should be set
    public var replace: String?
    public var form: String?

    public var formFields: [String: FormField]?
    public var vars: [EspansoVar]?
    public var label: String?
    public var propagateCase: Bool?
    public var word: Bool?

    public init(
        id: UUID = .init(),
        trigger: String? = nil,
        triggers: [String]? = nil,
        regex: String? = nil,
        replace: String? = nil,
        form: String? = nil,
        formFields: [String: FormField]? = nil,
        vars: [EspansoVar]? = nil,
        label: String? = nil,
        propagateCase: Bool? = nil,
        word: Bool? = nil
    ) {
        self.id = id
        self.trigger = trigger
        self.triggers = triggers
        self.regex = regex
        self.replace = replace
        self.form = form
        self.formFields = formFields
        self.vars = vars
        self.label = label
        self.propagateCase = propagateCase
        self.word = word
    }

    // id is internal — exclude from YAML encode/decode
    private enum CodingKeys: String, CodingKey {
        case trigger, triggers, regex, replace, form, vars, label, word
        case formFields    = "form_fields"
        case propagateCase = "propagate_case"
    }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        self.id            = UUID()
        self.trigger       = try c.decodeIfPresent(String.self,              forKey: .trigger)
        self.triggers      = try c.decodeIfPresent([String].self,            forKey: .triggers)
        self.regex         = try c.decodeIfPresent(String.self,              forKey: .regex)
        self.replace       = try c.decodeIfPresent(String.self,              forKey: .replace)
        self.form          = try c.decodeIfPresent(String.self,              forKey: .form)
        self.formFields    = try c.decodeIfPresent([String: FormField].self, forKey: .formFields)
        self.vars          = try c.decodeIfPresent([EspansoVar].self,        forKey: .vars)
        self.label         = try c.decodeIfPresent(String.self,              forKey: .label)
        self.propagateCase = try c.decodeIfPresent(Bool.self,                forKey: .propagateCase)
        self.word          = try c.decodeIfPresent(Bool.self,                forKey: .word)
        // `form:` takes precedence — clear `replace:` if both are present in malformed YAML.
        if self.form != nil { self.replace = nil }
    }

    public func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encodeIfPresent(trigger,       forKey: .trigger)
        try c.encodeIfPresent(triggers,      forKey: .triggers)
        try c.encodeIfPresent(regex,         forKey: .regex)
        try c.encodeIfPresent(replace,       forKey: .replace)
        try c.encodeIfPresent(form,          forKey: .form)
        try c.encodeIfPresent(formFields,    forKey: .formFields)
        try c.encodeIfPresent(vars,          forKey: .vars)
        try c.encodeIfPresent(label,         forKey: .label)
        try c.encodeIfPresent(propagateCase, forKey: .propagateCase)
        try c.encodeIfPresent(word,          forKey: .word)
    }

    // Convenience: the primary trigger string for display
    public var primaryTrigger: String {
        trigger ?? triggers?.first ?? regex ?? "(no trigger)"
    }

    // Convenience: a short preview of the replacement for display
    public var replacementPreview: String {
        (replace ?? form ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
    }
}
