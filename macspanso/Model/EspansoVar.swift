// macspanso/Model/EspansoVar.swift
import Foundation

// Espanso var param values: string, int, bool, or array of strings.
// e.g. date: {format: "%Y-%m-%d"}, random: {choices: ["a","b"]}, shell: {cmd: "date"}
public enum YAMLValue: Codable, Equatable {
    case string(String)
    case int(Int)
    case bool(Bool)
    case array([String])

    public init(from decoder: Decoder) throws {
        let c = try decoder.singleValueContainer()
        // Order matters: bool before int — Yams-specific: YAML's core schema treats
        // true/false as booleans. This order is correct for Yams but would break with
        // JSONDecoder (which doesn't conflate 0/false). Do not use YAMLValue with JSONDecoder.
        if let v = try? c.decode(Bool.self)     { self = .bool(v);   return }
        if let v = try? c.decode(Int.self)      { self = .int(v);    return }
        if let v = try? c.decode(String.self)   { self = .string(v); return }
        if let v = try? c.decode([String].self) { self = .array(v);  return }
        throw DecodingError.typeMismatch(
            YAMLValue.self,
            .init(codingPath: decoder.codingPath, debugDescription: "Unsupported YAML param value")
        )
    }

    public func encode(to encoder: Encoder) throws {
        var c = encoder.singleValueContainer()
        switch self {
        case .string(let v): try c.encode(v)
        case .int(let v):    try c.encode(v)
        case .bool(let v):   try c.encode(v)
        case .array(let v):  try c.encode(v)
        }
    }
}

public typealias VarParams = [String: YAMLValue]

public enum VarType: String, Codable, CaseIterable, Equatable {
    case date, clipboard, shell, script, random, form, match, echo
}

public struct EspansoVar: Codable, Equatable {
    public var name: String
    public var type: VarType
    public var params: VarParams?

    public init(name: String, type: VarType, params: VarParams? = nil) {
        self.name = name
        self.type = type
        self.params = params
    }
}
