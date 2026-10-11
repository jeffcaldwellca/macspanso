// macspanso/Model/EspansoVar.swift
import Foundation

// Espanso var param values: string, int, bool, or array of strings.
// e.g. date: {format: "%Y-%m-%d"}, random: {choices: ["a","b"]}, shell: {cmd: "date"}
// Anything else (form `fields:` mappings, choice `values:` with label/id entries,
// floats, null) is carried verbatim in `.other` so the file still loads and the
// param survives a rewrite.
public enum YAMLValue: Codable, Equatable {
    case string(String)
    case int(Int)
    case bool(Bool)
    case array([String])
    case other(YAMLAny)

    public init(from decoder: Decoder) throws {
        // Order matters: bool before int — Yams-specific: YAML's core schema treats
        // true/false as booleans. This order is correct for Yams but would break with
        // JSONDecoder (which doesn't conflate 0/false). Do not use YAMLValue with JSONDecoder.
        // Floats deliberately fall through to string: decoding `echo: 1.10` as
        // a number would write it back as 1.1e+0 and change the expanded text.
        if let c = try? decoder.singleValueContainer() {
            if let v = try? c.decode(Bool.self)     { self = .bool(v);           return }
            if let v = try? c.decode(Int.self)      { self = .int(v);            return }
            if let v = try? c.decode(String.self)   { self = .string(v);         return }
            if let v = try? c.decode([String].self) { self = .array(v);          return }
        }
        self = .other(try YAMLAny(from: decoder))
    }

    public func encode(to encoder: Encoder) throws {
        if case .other(let v) = self { try v.encode(to: encoder); return }
        var c = encoder.singleValueContainer()
        switch self {
        case .string(let v): try c.encode(v)
        case .int(let v):    try c.encode(v)
        case .bool(let v):   try c.encode(v)
        case .array(let v):  try c.encode(v)
        case .other:         break
        }
    }
}

public typealias VarParams = [String: YAMLValue]

/// An espanso extension name. Open-ended rather than an enum: a type this app
/// doesn't know (a newer espanso extension, a typo) must not make the whole
/// file fail to parse — it just gets no type-specific editor.
public struct VarType: RawRepresentable, Codable, Hashable, CaseIterable {
    public let rawValue: String
    public init(rawValue: String) { self.rawValue = rawValue }

    public static let date      = VarType(rawValue: "date")
    public static let clipboard = VarType(rawValue: "clipboard")
    public static let shell     = VarType(rawValue: "shell")
    public static let script    = VarType(rawValue: "script")
    public static let random    = VarType(rawValue: "random")
    public static let choice    = VarType(rawValue: "choice")
    public static let form      = VarType(rawValue: "form")
    public static let match     = VarType(rawValue: "match")
    public static let echo      = VarType(rawValue: "echo")

    /// Types offered when adding a variable in the editor. `choice` loads and
    /// round-trips but has no builder UI yet, so it isn't offered.
    public static let allCases: [VarType] =
        [.date, .clipboard, .shell, .script, .random, .form, .match, .echo]
}

public struct EspansoVar: Codable, Equatable {
    public var name: String
    public var type: VarType
    public var params: VarParams?

    /// YAML keys on this var that macspanso doesn't model (depends_on,
    /// inject_vars, …), preserved verbatim so editing never destroys them.
    public var extras: [String: YAMLAny] = [:]

    public init(name: String, type: VarType, params: VarParams? = nil) {
        self.name = name
        self.type = type
        self.params = params
    }

    private enum CodingKeys: String, CodingKey, CaseIterable {
        case name, type, params
    }

    private static let knownKeys: Set<String> =
        Set(CodingKeys.allCases.map(\.rawValue))

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        self.name   = try c.decode(String.self,             forKey: .name)
        self.type   = try c.decode(VarType.self,            forKey: .type)
        self.params = try c.decodeIfPresent(VarParams.self, forKey: .params)

        let dynamic = try decoder.container(keyedBy: AnyCodingKey.self)
        var extras: [String: YAMLAny] = [:]
        for key in dynamic.allKeys where !Self.knownKeys.contains(key.stringValue) {
            extras[key.stringValue] = try dynamic.decode(YAMLAny.self, forKey: key)
        }
        self.extras = extras
    }

    public func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encode(name, forKey: .name)
        try c.encode(type, forKey: .type)
        try c.encodeIfPresent(params, forKey: .params)

        var dynamic = encoder.container(keyedBy: AnyCodingKey.self)
        for key in extras.keys.sorted() {
            try dynamic.encode(extras[key]!, forKey: AnyCodingKey(stringValue: key))
        }
    }
}
