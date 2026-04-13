// macspansoTests/YAMLParsingTests.swift
import XCTest
@testable import macspanso

final class YAMLParsingTests: XCTestCase {

    func testSimpleTriggerReplace() throws {
        let yaml = """
        matches:
          - trigger: "::hello"
            replace: "Hello, World!"
        """
        let matches = try YAMLSerializer.decode(yaml: yaml)
        XCTAssertEqual(matches.count, 1)
        XCTAssertEqual(matches[0].trigger, "::hello")
        XCTAssertEqual(matches[0].replace, "Hello, World!")
    }

    func testMultiTriggers() throws {
        let yaml = """
        matches:
          - triggers: ["::hi", "::hey"]
            replace: "Hello!"
        """
        let matches = try YAMLSerializer.decode(yaml: yaml)
        XCTAssertEqual(matches[0].triggers, ["::hi", "::hey"])
        XCTAssertNil(matches[0].trigger)
    }

    func testRegexTrigger() throws {
        let yaml = """
        matches:
          - regex: "(:|;)brb"
            replace: "Be right back"
        """
        let matches = try YAMLSerializer.decode(yaml: yaml)
        XCTAssertEqual(matches[0].regex, "(:|;)brb")
        XCTAssertNil(matches[0].trigger)
    }

    func testDateVariable() throws {
        let yaml = """
        matches:
          - trigger: "::date"
            replace: "{{mydate}}"
            vars:
              - name: mydate
                type: date
                params:
                  format: "%Y-%m-%d"
        """
        let matches = try YAMLSerializer.decode(yaml: yaml)
        let v = try XCTUnwrap(matches[0].vars?.first)
        XCTAssertEqual(v.name, "mydate")
        XCTAssertEqual(v.type, .date)
        XCTAssertEqual(v.params?["format"], .string("%Y-%m-%d"))
    }

    func testRandomVariable() throws {
        let yaml = """
        matches:
          - trigger: "::rand"
            replace: "{{choice}}"
            vars:
              - name: choice
                type: random
                params:
                  choices:
                    - "Option A"
                    - "Option B"
        """
        let matches = try YAMLSerializer.decode(yaml: yaml)
        let v = try XCTUnwrap(matches[0].vars?.first)
        XCTAssertEqual(v.params?["choices"], .array(["Option A", "Option B"]))
    }

    func testFormMatch() throws {
        let yaml = """
        matches:
          - trigger: "::greet"
            form: "Hello [[name]], from [[company]]"
            form_fields:
              name:
                default: "World"
              company:
                multiline: false
        """
        let matches = try YAMLSerializer.decode(yaml: yaml)
        XCTAssertEqual(matches[0].form, "Hello [[name]], from [[company]]")
        XCTAssertEqual(matches[0].formFields?["name"]?.default, "World")
        XCTAssertEqual(matches[0].formFields?["company"]?.multiline, false)
    }

    func testMatchOptions() throws {
        let yaml = """
        matches:
          - trigger: "::test"
            replace: "Test"
            word: true
            propagate_case: true
        """
        let matches = try YAMLSerializer.decode(yaml: yaml)
        XCTAssertEqual(matches[0].word, true)
        XCTAssertEqual(matches[0].propagateCase, true)
    }

    func testEmptyFile() throws {
        let yaml = """
        matches: []
        """
        let matches = try YAMLSerializer.decode(yaml: yaml)
        XCTAssertEqual(matches.count, 0)
    }

    func testMissingMatchesKey() throws {
        // Comment-only content trims to a non-empty string, Yams parses it as a null
        // scalar (not a mapping), YAMLDecoder raises typeMismatch with an empty
        // codingPath, and YAMLSerializer.decode maps that to [].
        let yaml = "# empty file\n"
        let matches = try YAMLSerializer.decode(yaml: yaml)
        XCTAssertEqual(matches.count, 0)
    }

    func testFileWithOtherKeysButNoMatches() throws {
        // Real espanso pattern: global_vars.yml has no matches: key
        let yaml = """
        global_vars:
          - name: myname
            type: echo
            params:
              echo: "John"
        """
        let matches = try YAMLSerializer.decode(yaml: yaml)
        XCTAssertEqual(matches.count, 0)
    }

    func testCommentedFileWithMatches() throws {
        // Files that start with a comment header must still parse correctly
        let yaml = """
        # My custom shortcuts
        matches:
          - trigger: "::hello"
            replace: "Hello!"
        """
        let matches = try YAMLSerializer.decode(yaml: yaml)
        XCTAssertEqual(matches.count, 1)
        XCTAssertEqual(matches[0].trigger, "::hello")
    }

    func testEncodeRoundTrip() throws {
        let original = [
            EspansoMatch(trigger: "::hi", replace: "Hello"),
            EspansoMatch(triggers: ["::bye", "::cya"], replace: "Goodbye"),
        ]
        let yaml = try YAMLSerializer.encode(original)
        let decoded = try YAMLSerializer.decode(yaml: yaml)
        XCTAssertEqual(decoded.count, 2)
        XCTAssertEqual(decoded[0].trigger, "::hi")
        XCTAssertEqual(decoded[0].replace, "Hello")
        XCTAssertEqual(decoded[1].triggers, ["::bye", "::cya"])
        XCTAssertEqual(decoded[1].replace, "Goodbye")
    }

    func testTypeMismatchInsideMatchPropagate() {
        // A mapping where a scalar string is expected for `trigger` should throw,
        // not be silently swallowed by the top-level typeMismatch catch.
        let yaml = """
        matches:
          - trigger: {bad: value}
            replace: "test"
        """
        XCTAssertThrowsError(try YAMLSerializer.decode(yaml: yaml))
    }
}
