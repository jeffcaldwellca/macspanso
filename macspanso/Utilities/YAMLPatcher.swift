// macspanso/Utilities/YAMLPatcher.swift
import Foundation
import Yams

/// Rewrites a match file by editing its text in place instead of regenerating
/// it, so everything the user wrote by hand — comments, blank lines, key order,
/// quoting, top-level sections — survives a save. Only the matches that
/// actually changed are re-emitted; unchanged ones are copied byte for byte.
///
/// The file is cut into a header, one chunk of lines per match, and a footer.
/// Comment and blank lines directly above a match travel with that match.
///
/// This never guesses: the result is parsed back and must equal the intended
/// content exactly, otherwise `patch` returns nil and the caller falls back to
/// regenerating the whole file (correct content, hand formatting lost).
public enum YAMLPatcher {

    /// - Parameters:
    ///   - original: The file's current text.
    ///   - oldMatches: The matches `original` holds, in file order, carrying the
    ///     ids the app knows them by.
    ///   - newMatches: The matches the file should hold after the save.
    /// - Returns: The patched text, or nil if the file can't be patched safely.
    public static func patch(
        original: String,
        oldMatches: [EspansoMatch],
        newMatches: [EspansoMatch]
    ) -> String? {
        // Mixed line endings aren't worth the risk; regenerate instead.
        // (Scalar view: as a Character, "\r\n" is one grapheme and never equals "\r".)
        guard !original.unicodeScalars.contains("\r") else { return nil }

        // `oldMatches` must really be what's in the text, or chunk ↔ id pairing is wrong.
        guard let originalContent = try? YAMLSerializer.decodeContent(yaml: original),
              sameIgnoringIDs(originalContent.matches ?? [], oldMatches)
        else { return nil }

        // No document at all (empty or comment-only file) is fine: there is
        // simply no `matches:` key yet. Any other non-mapping root is not.
        let pairs: [(key: Node, value: Node)]
        switch try? Yams.compose(yaml: original) {
        case .none:
            pairs = []
        case .some(let root):
            guard let mapping = root.mapping else { return nil }
            pairs = Array(mapping)
        }

        var lines = original.components(separatedBy: "\n")
        let endsWithNewline = lines.last == ""
        if endsWithNewline { lines.removeLast() }

        var output: [String]

        if let matchesPair = pairs.first(where: { $0.key.string == "matches" }) {
            guard let keyLine = matchesPair.key.mark.map({ $0.line - 1 }),
                  lines.indices.contains(keyLine)
            else { return nil }
            // First line of whatever top-level key follows `matches:`, else end of file.
            let sectionEnd = pairs
                .compactMap { $0.key.mark.map { $0.line - 1 } }
                .filter { $0 > keyLine }
                .min() ?? lines.count

            if let sequence = matchesPair.value.sequence, !oldMatches.isEmpty {
                // The parser doesn't report block vs flow style; `Layout` rejects
                // flow (`matches: [...]`) because its items don't start `- ` lines.
                guard let layout = Layout(lines: lines, items: Array(sequence),
                                          keyLine: keyLine, sectionEnd: sectionEnd),
                      layout.bodies.count == oldMatches.count
                else { return nil }

                var indexByID: [UUID: Int] = [:]
                for (i, m) in oldMatches.enumerated() { indexByID[m.id] = i }

                output = layout.header
                for match in newMatches {
                    if let i = indexByID[match.id] {
                        output += layout.leaders[i]
                        if oldMatches[i] == match {
                            output += layout.bodies[i]
                        } else {
                            guard let rendered = render(match, indent: layout.dashColumn) else { return nil }
                            output += rendered
                        }
                    } else {
                        guard let rendered = render(match, indent: layout.dashColumn) else { return nil }
                        output += rendered
                    }
                }
                output += layout.footer
            } else if oldMatches.isEmpty, !newMatches.isEmpty,
                      ["matches:", "matches: []"].contains(
                        lines[keyLine].trimmingCharacters(in: .whitespaces)) {
                // A bare `matches:` (or an explicitly empty list) with nothing under it yet.
                lines[keyLine] = "matches:"
                var rendered: [String] = []
                for match in newMatches {
                    guard let r = render(match, indent: 2) else { return nil }
                    rendered += r
                }
                output = Array(lines[...keyLine]) + rendered + Array(lines[(keyLine + 1)...])
            } else {
                return nil   // flow style (`matches: [...]`) or anything unusual
            }
        } else {
            // No `matches:` key (e.g. a file of only global_vars): add one at the end.
            guard !newMatches.isEmpty else { return nil }
            output = lines + ["matches:"]
            for match in newMatches {
                guard let r = render(match, indent: 2) else { return nil }
                output += r
            }
        }

        let patched = output.joined(separator: "\n") + (endsWithNewline ? "\n" : "")

        // The proof: parsing the patched text must give exactly the intended content.
        guard let result = try? YAMLSerializer.decodeContent(yaml: patched),
              sameIgnoringIDs(result.matches ?? [], newMatches),
              result.extras == originalContent.extras
        else { return nil }
        return patched
    }

    // MARK: - Layout

    /// The file's lines divided around the `matches:` sequence.
    private struct Layout {
        var header: [String] = []
        /// Comment/blank lines directly above each match.
        var leaders: [[String]] = []
        /// Each match's own lines, starting at its `- `.
        var bodies: [[String]] = []
        var footer: [String] = []
        /// Indentation of the `- ` that starts each match.
        var dashColumn = 0

        init?(lines: [String], items: [Node], keyLine: Int, sectionEnd: Int) {
            let starts = items.compactMap { $0.mark.map { $0.line - 1 } }
            guard starts.count == items.count, let first = starts.first, let last = starts.last,
                  first > keyLine, last < sectionEnd, sectionEnd <= lines.count,
                  zip(starts, starts.dropFirst()).allSatisfy({ $0 < $1 })
            else { return nil }

            // Every match must start on its own `- ` line at one shared indent.
            dashColumn = Self.indent(of: lines[first])
            for s in starts {
                guard Self.indent(of: lines[s]) == dashColumn,
                      lines[s].dropFirst(dashColumn).hasPrefix("-")
                else { return nil }
            }

            // A line that belongs to no match: blank, or a comment at or left of
            // the dash. (A deeper `#` line could be text inside a block scalar.)
            let dash = dashColumn
            func isLoose(_ i: Int) -> Bool {
                let trimmed = lines[i].trimmingCharacters(in: .whitespaces)
                return trimmed.isEmpty || (trimmed.hasPrefix("#") && Self.indent(of: lines[i]) <= dash)
            }

            // Loose lines directly above a match lead that match.
            var chunkStarts: [Int] = []
            for (k, s) in starts.enumerated() {
                let floor = k == 0 ? keyLine + 1 : starts[k - 1] + 1
                var i = s
                while i > floor, isLoose(i - 1) { i -= 1 }
                chunkStarts.append(i)
            }
            // Loose lines after the last match stay in the footer.
            var tail = sectionEnd
            while tail > last + 1, isLoose(tail - 1) { tail -= 1 }

            header = Array(lines[..<chunkStarts[0]])
            footer = Array(lines[tail...])
            for k in starts.indices {
                let end = k + 1 < starts.count ? chunkStarts[k + 1] : tail
                leaders.append(Array(lines[chunkStarts[k]..<starts[k]]))
                bodies.append(Array(lines[starts[k]..<end]))
            }
        }

        private static func indent(of line: String) -> Int {
            line.prefix { $0 == " " }.count
        }
    }

    // MARK: - Helpers

    /// One match as the lines of a block-sequence item, indented to `indent`.
    private static func render(_ match: EspansoMatch, indent: Int) -> [String]? {
        guard let yaml = try? YAMLSerializer.encode([match]) else { return nil }
        var lines = yaml.components(separatedBy: "\n")
        guard lines.first == "matches:" else { return nil }
        lines.removeFirst()
        while lines.last == "" { lines.removeLast() }
        guard lines.first?.hasPrefix("- ") == true else { return nil }
        let pad = String(repeating: " ", count: indent)
        return lines.map { $0.isEmpty ? "" : pad + $0 }
    }

    private static func sameIgnoringIDs(_ a: [EspansoMatch], _ b: [EspansoMatch]) -> Bool {
        a.count == b.count && zip(a, b).allSatisfy { x, y in
            var x = x
            x.id = y.id
            return x == y
        }
    }
}
