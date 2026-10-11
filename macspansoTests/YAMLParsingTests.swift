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

    // MARK: - Tolerant decoding of espanso constructs the editor doesn't model

    /// Decode, re-encode, decode again — the second decode must equal the first,
    /// proving the construct both loads and survives a rewrite.
    private func roundTrip(_ yaml: String) throws -> [EspansoMatch] {
        let first = try YAMLSerializer.decodeContent(yaml: yaml)
        let second = try YAMLSerializer.decodeContent(yaml: try YAMLSerializer.encode(first))
        XCTAssertEqual(first.matches?.map(\.vars), second.matches?.map(\.vars))
        XCTAssertEqual(first.matches?.map(\.formFields), second.matches?.map(\.formFields))
        return second.matches ?? []
    }

    func testChoiceVarLoadsAndRoundTrips() throws {
        let matches = try roundTrip("""
        matches:
          - trigger: ":q"
            replace: "{{c}}"
            vars:
              - name: c
                type: choice
                params:
                  values:
                    - label: First
                      id: one
                    - Second
        """)
        let v = try XCTUnwrap(matches.first?.vars?.first)
        XCTAssertEqual(v.type, .choice)
        XCTAssertEqual(v.params?["values"], .other(.array([
            .dictionary(["label": .string("First"), "id": .string("one")]),
            .string("Second"),
        ])))
    }

    func testFormVarWithFieldsLoadsAndRoundTrips() throws {
        let matches = try roundTrip("""
        matches:
          - trigger: ":f"
            replace: "{{form1.name}}"
            vars:
              - name: form1
                type: form
                params:
                  layout: "Name [[name]]"
                  fields:
                    name:
                      multiline: true
        """)
        let params = try XCTUnwrap(matches.first?.vars?.first?.params)
        XCTAssertEqual(params["layout"], .string("Name [[name]]"))
        XCTAssertEqual(params["fields"], .other(.dictionary([
            "name": .dictionary(["multiline": .bool(true)]),
        ])))
    }

    func testUnknownVarTypeLoadsAndRoundTrips() throws {
        let matches = try roundTrip("""
        matches:
          - trigger: ":x"
            replace: "{{v}}"
            vars:
              - name: v
                type: some_future_extension
                params:
                  ratio: 1.5
        """)
        let v = try XCTUnwrap(matches.first?.vars?.first)
        XCTAssertEqual(v.type.rawValue, "some_future_extension")
        XCTAssertEqual(v.params?["ratio"], .string("1.5"))
    }

    func testListFormFieldLoadsAndRoundTrips() throws {
        let matches = try roundTrip("""
        matches:
          - trigger: ":l"
            form: "[[x]] [[y]]"
            form_fields:
              x:
                type: list
                values: [a, b]
              y:
                type: text
        """)
        let fields = try XCTUnwrap(matches.first?.formFields)
        XCTAssertEqual(fields["x"]?.type, .list)
        XCTAssertEqual(fields["x"]?.values, ["a", "b"])
        XCTAssertEqual(fields["y"]?.type?.rawValue, "text")
    }

    // MARK: - Rewrites stay faithful and hand-editable

    func testVarLevelKeysSurviveRewrite() throws {
        let matches = try roundTrip("""
        matches:
          - trigger: ":v"
            replace: "{{out}}"
            vars:
              - name: out
                type: shell
                depends_on: [other]
                inject_vars: false
                params:
                  cmd: echo hi
        """)
        let v = try XCTUnwrap(matches.first?.vars?.first)
        XCTAssertEqual(v.extras["depends_on"], .array([.string("other")]))
        XCTAssertEqual(v.extras["inject_vars"], .bool(false))
    }

    func testRewriteStaysHandEditable() throws {
        let multiline = "Dear café,\nsecond line\n"
        let emoji = "shrug 🤷 done"
        let long = String(repeating: "word ", count: 40) + "end"
        let yaml = try YAMLSerializer.encode([
            EspansoMatch(trigger: ":m", replace: multiline),
            EspansoMatch(trigger: ":e", replace: emoji),
            EspansoMatch(trigger: ":long", replace: long),
        ])
        XCTAssertTrue(yaml.contains("replace: |"), "multi-line text must be a block scalar:\n\(yaml)")
        XCTAssertTrue(yaml.contains("Dear café,"), "accents must not be escaped:\n\(yaml)")
        XCTAssertTrue(yaml.contains("shrug 🤷 done"), "emoji must not be escaped:\n\(yaml)")
        XCTAssertTrue(yaml.contains(long), "long lines must not be re-wrapped:\n\(yaml)")
        let decoded = try YAMLSerializer.decode(yaml: yaml)
        XCTAssertEqual(decoded.map(\.replace), [multiline, emoji, long])
    }

    func testTextThatLooksLikeAnEscapeIsNotTurnedIntoEmoji() throws {
        // The user literally typed backslash-U; it must come back unchanged,
        // alone and next to a real emoji.
        for text in [#"\U0001F937"#, #"code \U0001F937 and 🤷"#, #"\\U0001F937 🤷"#] {
            let yaml = try YAMLSerializer.encode([EspansoMatch(trigger: ":t", replace: text)])
            XCTAssertEqual(try YAMLSerializer.decode(yaml: yaml).first?.replace, text, yaml)
        }
    }

    func testAwkwardMultilineStringsStillRoundTripExactly() throws {
        // Shapes a block scalar can't always express; the emitter must fall
        // back to quoting rather than change the text.
        let samples = ["  leading spaces\nline", "trailing space \nline", "no final newline\nline",
                       "\nstarts blank", "ends with two\n\n", "tab\tinside\nline", "# looks like comment\nx"]
        for text in samples {
            let yaml = try YAMLSerializer.encode([EspansoMatch(trigger: ":t", replace: text)])
            XCTAssertEqual(try YAMLSerializer.decode(yaml: yaml).first?.replace, text, yaml)
        }
    }

    func testFormFieldUnknownKeysSurviveRewrite() throws {
        let matches = try roundTrip("""
        matches:
          - trigger: ":l"
            form: "[[x]]"
            form_fields:
              x:
                type: choice
                values: [a, b]
                trim_string_values: true
        """)
        XCTAssertEqual(matches.first?.formFields?["x"]?.extras["trim_string_values"], .bool(true))
    }

    func testFloatParamKeepsItsText() throws {
        let matches = try roundTrip("""
        matches:
          - trigger: ":v"
            replace: "{{v}}"
            vars:
              - name: v
                type: echo
                params:
                  echo: 1.10
        """)
        XCTAssertEqual(matches.first?.vars?.first?.params?["echo"], .string("1.10"))
    }
}
