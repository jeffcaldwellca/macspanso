// macspanso/Store/EspansoProcessManager.swift
import Foundation
import Combine

@MainActor
final class EspansoProcessManager: ObservableObject {
    enum DaemonState: Equatable {
        case running        // espanso is running and expansion is enabled
        case disabled       // espanso is running but expansion is disabled
        case stopped        // espanso daemon is not running
        case notInstalled   // espanso binary not found in PATH
        case unknown
    }

    @Published var state: DaemonState = .unknown

    private var pollTimer: Timer?
    let espansoPath: String  // internal(set) for testing

    init() {
        self.espansoPath = Self.locateEspanso() ?? ""
        if espansoPath.isEmpty { state = .notInstalled }
    }

    // MARK: - Lifecycle

    func startPolling() {
        guard !espansoPath.isEmpty else { return }
        refresh()
        pollTimer = Timer.scheduledTimer(withTimeInterval: 5, repeats: true) { [weak self] _ in
            Task { @MainActor in self?.refresh() }
        }
    }

    func stopPolling() {
        pollTimer?.invalidate()
        pollTimer = nil
    }

    // MARK: - Commands

    func refresh() {
        let output = run("status")
        if output.contains("not running") || output.contains("stopped") {
            state = .stopped
        } else if output.contains("disabled") {
            state = .disabled
        } else if output.contains("running") {
            state = .running
        } else {
            state = .unknown
        }
    }

    /// Toggle text expansion on/off (daemon keeps running).
    func toggleEnabled() {
        switch state {
        case .running:
            run("cmd", "disable")
        case .disabled:
            run("cmd", "enable")
        default:
            break
        }
        refresh()
    }

    func restart() {
        run("restart")
        DispatchQueue.main.asyncAfter(deadline: .now() + 1) { self.refresh() }
    }

    // MARK: - Helpers

    @discardableResult
    func run(_ args: String...) -> String {
        let proc = Process()
        proc.executableURL = URL(fileURLWithPath: espansoPath)
        proc.arguments = args
        let pipe = Pipe()
        proc.standardOutput = pipe
        proc.standardError = pipe
        try? proc.run()
        proc.waitUntilExit()
        return String(data: pipe.fileHandleForReading.readDataToEndOfFile(),
                      encoding: .utf8) ?? ""
    }

    private static func locateEspanso() -> String? {
        let candidates = [
            "/opt/homebrew/bin/espanso",
            "/usr/local/bin/espanso",
            "/usr/bin/espanso",
        ]
        if let found = candidates.first(where: { FileManager.default.fileExists(atPath: $0) }) {
            return found
        }
        // Also try PATH via `which`
        let proc = Process()
        proc.executableURL = URL(fileURLWithPath: "/usr/bin/which")
        proc.arguments = ["espanso"]
        let pipe = Pipe()
        proc.standardOutput = pipe
        try? proc.run()
        proc.waitUntilExit()
        let path = String(data: pipe.fileHandleForReading.readDataToEndOfFile(),
                          encoding: .utf8)?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        return path.isEmpty ? nil : path
    }

    /// Discover espanso's match directory by running `espanso path`.
    /// Falls back to the known macOS default.
    static func resolveMatchDirectory() -> URL {
        let defaultPath = FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent("Library/Application Support/espanso/match")

        guard let espanso = locateEspanso() else { return defaultPath }

        let proc = Process()
        proc.executableURL = URL(fileURLWithPath: espanso)
        proc.arguments = ["path"]
        let pipe = Pipe()
        proc.standardOutput = pipe
        try? proc.run()
        proc.waitUntilExit()

        let output = String(data: pipe.fileHandleForReading.readDataToEndOfFile(),
                            encoding: .utf8) ?? ""
        // Output line format: "Config: /Users/jeff/Library/Application Support/espanso"
        for line in output.components(separatedBy: "\n") {
            if line.hasPrefix("Config:") {
                let configPath = line
                    .dropFirst("Config:".count)
                    .trimmingCharacters(in: .whitespaces)
                return URL(fileURLWithPath: configPath).appendingPathComponent("match")
            }
        }
        return defaultPath
    }
}
