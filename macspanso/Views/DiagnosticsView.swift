// macspanso/Views/DiagnosticsView.swift
import SwiftUI

struct DiagnosticsView: View {
    let store: EspansoConfigStore
    let processManager: EspansoProcessManager

    @State private var report: String = "Collecting diagnostics…"
    @State private var copied = false
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        VStack(spacing: 0) {
            // Title bar
            HStack {
                Text("Diagnostics")
                    .font(.headline)
                Spacer()
                Button("Done") { dismiss() }
                    .buttonStyle(.bordered)
                    .controlSize(.small)
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 12)
            .background(Color(nsColor: .windowBackgroundColor))

            Divider()

            // Report
            ScrollView {
                Text(report)
                    .font(.system(.caption, design: .monospaced))
                    .foregroundStyle(.primary)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(16)
                    .textSelection(.enabled)
            }

            Divider()

            // Copy button
            HStack {
                Spacer()
                Button {
                    NSPasteboard.general.clearContents()
                    NSPasteboard.general.setString(report, forType: .string)
                    copied = true
                    DispatchQueue.main.asyncAfter(deadline: .now() + 2) { copied = false }
                } label: {
                    Label(copied ? "Copied!" : "Copy to Clipboard",
                          systemImage: copied ? "checkmark" : "doc.on.doc")
                        .font(.callout)
                }
                .buttonStyle(.bordered)
                .padding(12)
            }
            .background(Color(nsColor: .windowBackgroundColor))
        }
        .frame(width: 560, height: 480)
        .task { report = await buildReport() }
    }

    // MARK: - Report builder

    private func buildReport() async -> String {
        var lines: [String] = []

        let fm = FileManager.default
        let version = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "?"
        let build   = Bundle.main.infoDictionary?["CFBundleVersion"] as? String ?? "?"

        lines += section("macspanso", [
            "Version: \(version) (\(build))",
            "macOS:   \(ProcessInfo.processInfo.operatingSystemVersionString)",
        ])

        // espanso binary
        let espansoPath = processManager.espansoPath
        let binaryExists = !espansoPath.isEmpty && fm.fileExists(atPath: espansoPath)
        lines += section("espanso Binary", [
            "Path:   \(espansoPath.isEmpty ? "(not found)" : espansoPath)",
            "Exists: \(binaryExists ? "✓ yes" : "✗ no")",
        ])

        // espanso path raw output
        let pathOutput = await processManager.run("path")
        lines += section("espanso path (raw output)", [
            pathOutput.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                ? "(no output)"
                : pathOutput.trimmingCharacters(in: .whitespacesAndNewlines),
        ])

        // espanso status
        let statusOutput = await processManager.run("status")
        lines += section("espanso status", [
            statusOutput.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                ? "(no output)"
                : statusOutput.trimmingCharacters(in: .whitespacesAndNewlines),
        ])

        // Match directory
        let matchDir = store.matchDirectory
        let dirExists   = fm.fileExists(atPath: matchDir.path)
        var dirReadable = false
        if dirExists {
            dirReadable = fm.isReadableFile(atPath: matchDir.path)
        }
        lines += section("Match Directory", [
            "Path:     \(matchDir.path)",
            "Exists:   \(dirExists  ? "✓ yes" : "✗ no")",
            "Readable: \(dirReadable ? "✓ yes" : "✗ no")",
        ])

        // Raw directory listing
        var dirListLines: [String] = []
        if dirExists, let enumerator = fm.enumerator(at: matchDir, includingPropertiesForKeys: [.isRegularFileKey]) {
            let allFiles = enumerator.compactMap { $0 as? URL }.sorted { $0.path < $1.path }
            if allFiles.isEmpty {
                dirListLines.append("(directory is empty)")
            } else {
                for url in allFiles {
                    let rel = url.path.replacingOccurrences(of: matchDir.path + "/", with: "")
                    let isYML = url.pathExtension == "yml"
                    let readable = fm.isReadableFile(atPath: url.path)
                    dirListLines.append("\(isYML ? "●" : "○") \(rel)\(readable ? "" : "  [not readable]")")
                }
            }
        } else {
            dirListLines.append("(could not enumerate directory)")
        }
        lines += section("Directory Contents  (● = .yml, ○ = other)", dirListLines)

        // Loaded files
        let matchFiles = await MainActor.run { store.matchFiles }
        if matchFiles.isEmpty {
            lines += section("Loaded Files", ["(none loaded)"])
        } else {
            var fileLines: [String] = []
            for file in matchFiles {
                let rel = file.url.path.replacingOccurrences(of: matchDir.path + "/", with: "")
                if let err = file.parseError {
                    fileLines.append("✗ \(rel)  — parse error: \(err)")
                } else {
                    fileLines.append("✓ \(rel)  — \(file.matches.count) match(es)\(file.isPackage ? "  [package]" : "")")
                }
            }
            lines += section("Loaded Files (\(matchFiles.count) total)", fileLines)
        }

        return lines.joined(separator: "\n")
    }

    // MARK: - Helpers

    private func section(_ title: String, _ body: [String]) -> [String] {
        let bar = String(repeating: "─", count: 52)
        return ["", "┌ \(title)", "│ \(bar)"] + body.map { "│ \($0)" } + ["└ \(bar)", ""]
    }
}
