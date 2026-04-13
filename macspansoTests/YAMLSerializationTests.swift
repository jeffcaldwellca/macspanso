// macspansoTests/YAMLSerializationTests.swift
import XCTest
import Foundation
@testable import macspanso

final class YAMLSerializationTests: XCTestCase {

    func testRoundTripSimpleMatch() throws {
        let original = [EspansoMatch(trigger: "::hello", replace: "Hello!")]
        let yaml = try YAMLSerializer.encode(original)
        let decoded = try YAMLSerializer.decode(yaml: yaml)
        XCTAssertEqual(decoded[0].trigger, original[0].trigger)
        XCTAssertEqual(decoded[0].replace, original[0].replace)
    }

    func testRoundTripWithDateVar() throws {
        let match = EspansoMatch(
            trigger: "::date",
            replace: "{{d}}",
            vars: [EspansoVar(name: "d", type: .date, params: ["format": .string("%Y-%m-%d")])]
        )
        let yaml = try YAMLSerializer.encode([match])
        let decoded = try YAMLSerializer.decode(yaml: yaml)
        XCTAssertEqual(decoded[0].vars?.first?.params?["format"], .string("%Y-%m-%d"))
    }

    func testRoundTripFormMatch() throws {
        let match = EspansoMatch(
            trigger: "::greet",
            form: "Hi [[name]]",
            formFields: ["name": FormField(default: "World")]
        )
        let yaml = try YAMLSerializer.encode([match])
        let decoded = try YAMLSerializer.decode(yaml: yaml)
        XCTAssertEqual(decoded[0].form, "Hi [[name]]")
        XCTAssertEqual(decoded[0].formFields?["name"]?.default, "World")
    }

    func testUUIDNotSerializedToYAML() throws {
        let match = EspansoMatch(trigger: "::test", replace: "Test")
        let yaml = try YAMLSerializer.encode([match])
        XCTAssertFalse(yaml.contains(match.id.uuidString),
            "UUID should not appear in YAML output")
    }

    func testAtomicWriteAndRead() throws {
        let dir = FileManager.default.temporaryDirectory
        let url = dir.appendingPathComponent("test-\(UUID().uuidString).yml")
        let matches = [
            EspansoMatch(trigger: "::a", replace: "Alpha"),
            EspansoMatch(trigger: "::b", replace: "Beta"),
        ]
        try YAMLSerializer.write(matches, to: url)
        XCTAssertTrue(FileManager.default.fileExists(atPath: url.path))
        let readBack = try YAMLSerializer.decode(contentsOf: url)
        XCTAssertEqual(readBack.count, 2)
        XCTAssertEqual(readBack[0].trigger, "::a")
        XCTAssertEqual(readBack[1].replace, "Beta")
        try FileManager.default.removeItem(at: url)
    }

    func testWriteCreatesFileWhenAbsent() throws {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("new-\(UUID().uuidString).yml")
        XCTAssertFalse(FileManager.default.fileExists(atPath: url.path))
        try YAMLSerializer.write([EspansoMatch(trigger: "::x", replace: "X")], to: url)
        XCTAssertTrue(FileManager.default.fileExists(atPath: url.path))
        try FileManager.default.removeItem(at: url)
    }
}
