// macspanso/Model/YAMLAny.swift
import Foundation

/// An arbitrary YAML value. Used to round-trip content macspanso doesn't model
/// (top-level keys like `global_vars:`, unknown per-match keys like `markdown:`)
/// so that rewriting a file never destroys user data.
public indirect enum YAMLAny: Codable, Equatable {
    case null
    case bool(Bool)
    case int(Int)
    case double(Double)
    case string(String)
    case array([YAMLAny])
    case dictionary([String: YAMLAny])

    public init(from decoder: Decoder) throws {
        // Scalars first; bool before int (YAML core schema), int before double
        // so whole numbers don't decode lossily as doubles.
        if let c = try? decoder.singleValueContainer() {
            if c.decodeNil()                          { self = .null;      return }
            if let v = try? c.decode(Bool.self)       { self = .bool(v);   return }
            if let v = try? c.decode(Int.self)        { self = .int(v);    return }
            if let v = try? c.decode(Double.self)     { self = .double(v); return }
            if let v = try? c.decode(String.self)     { self = .string(v); return }
        }
        if var c = try? decoder.unkeyedContainer() {
            var items: [YAMLAny] = []
            while !c.isAtEnd { items.append(try c.decode(YAMLAny.self)) }
            self = .array(items)
            return
        }
        if let c = try? decoder.container(keyedBy: AnyCodingKey.self) {
            var dict: [String: YAMLAny] = [:]
            for key in c.allKeys {
                dict[key.stringValue] = try c.decode(YAMLAny.self, forKey: key)
            }
            self = .dictionary(dict)
            return
        }
        throw DecodingError.dataCorrupted(.init(
            codingPath: decoder.codingPath,
            debugDescription: "Unsupported YAML value"
        ))
    }

    public func encode(to encoder: Encoder) throws {
        switch self {
        case .null:
            var c = encoder.singleValueContainer()
            try c.encodeNil()
        case .bool(let v):
            var c = encoder.singleValueContainer()
            try c.encode(v)
        case .int(let v):
            var c = encoder.singleValueContainer()
            try c.encode(v)
        case .double(let v):
            var c = encoder.singleValueContainer()
            try c.encode(v)
        case .string(let v):
            var c = encoder.singleValueContainer()
            try c.encode(v)
        case .array(let items):
            var c = encoder.unkeyedContainer()
            for item in items { try c.encode(item) }
        case .dictionary(let dict):
            var c = encoder.container(keyedBy: AnyCodingKey.self)
            // Sort for deterministic output.
            for key in dict.keys.sorted() {
                try c.encode(dict[key]!, forKey: AnyCodingKey(stringValue: key))
            }
        }
    }
}

/// A coding key over arbitrary string names, for dynamic keyed containers.
public struct AnyCodingKey: CodingKey {
    public var stringValue: String
    public var intValue: Int? { nil }

    public init(stringValue: String) { self.stringValue = stringValue }
    public init?(intValue: Int) { nil }
}
