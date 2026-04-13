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
    let espansoPath: String

    /// Pass a custom `espansoPath` for testing; leave nil to auto-locate via Homebrew / PATH.
    init(espansoPath: String? = nil) {
        let path = espansoPath ?? EspansoProcessManager.locateEspanso() ?? ""
        self.espansoPath = path
        if path.isEmpty { state = .notInstalled }
    }

    // MARK: - Lifecycle

    func startPolling() {
        guard !espansoPath.isEmpty else { return }
        Task { await refresh() }
        pollTimer = Timer.scheduledTimer(withTimeInterval: 5, repeats: true) { [weak self] _ in
            Task { @MainActor [weak self] in await self?.refresh() }
        }
    }

    func stopPolling() {
        pollTimer?.invalidate()
        pollTimer = nil
    }

    // MARK: - Commands

    /// Refreshes daemon state by running `espanso status` off the main thread.
    // Verified against espanso v2.2.x output. Check if output strings change on upgrade.
    func refresh() async {
        let output = await run("status")
        let lower = output.lowercased()
        if lower.contains("not running") || lower.contains("stopped") {
            state = .stopped
        } else if lower.contains("disabled") {
            state = .disabled
        } else if lower.contains("running") {
            // "not running" checked above, so this is safe
            state = .running
        } else {
            state = .unknown
        }
    }

    /// Toggle text expansion on/off (daemon keeps running).
    func toggleEnabled() {
        Task { @MainActor [weak self] in
            guard let self else { return }
            switch state {
            case .running:  await run("cmd", "disable")
            case .disabled: await run("cmd", "enable")
            default:        break
            }
            await refresh()
        }
    }

    func restart() {
        Task { @MainActor [weak self] in
            guard let self else { return }
            await run("restart")
            try? await Task.sleep(nanoseconds: 1_000_000_000)
            await refresh()
        }
    }

    // MARK: - Helpers

    /// Runs an espanso command off the main thread and returns its combined stdout+stderr.
    @discardableResult
    nonisolated func run(_ args: String...) async -> String {
        let path = espansoPath
        return await Task.detached(priority: .userInitiated) {
            let proc = Process()
            proc.executableURL = URL(fileURLWithPath: path)
            proc.arguments = args
            let pipe = Pipe()
            proc.standardOutput = pipe
            proc.standardError = pipe
            try? proc.run()
            proc.waitUntilExit()
            return String(data: pipe.fileHandleForReading.readDataToEndOfFile(),
                          encoding: .utf8) ?? ""
        }.value
    }

    nonisolated private static func locateEspanso() -> String? {
        let candidates = [
            "/opt/homebrew/bin/espanso",
            "/usr/local/bin/espanso",
            "/usr/bin/espanso",
        ]
        if let found = candidates.first(where: { FileManager.default.fileExists(atPath: $0) }) {
            return found
        }
        // Uncommon install paths: fall back to `which` (synchronous, but only
        // runs once at launch, only if no Homebrew path is found).
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
    /// Falls back to the known macOS default if binary is absent or output is unparseable.
    static func resolveMatchDirectory() async -> URL {
        let defaultPath = FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent("Library/Application Support/espanso/match")

        guard let espanso = locateEspanso() else { return defaultPath }

        let output = await Task.detached(priority: .userInitiated) {
            let proc = Process()
            proc.executableURL = URL(fileURLWithPath: espanso)
            proc.arguments = ["path"]
            let pipe = Pipe()
            proc.standardOutput = pipe
            try? proc.run()
            proc.waitUntilExit()
            return String(data: pipe.fileHandleForReading.readDataToEndOfFile(),
                          encoding: .utf8) ?? ""
        }.value

        // espanso path output (v2.x):
        //   Config:   /Users/jeff/Library/Application Support/espanso
        //   Packages: ...
        //   Runtime:  ...
        //   Data:     ...
        // Prefer a "Match:" line if espanso ever emits one; fall back to Config: + /match.
        for line in output.components(separatedBy: "\n") {
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            if trimmed.hasPrefix("Match:") {
                let p = trimmed.dropFirst("Match:".count).trimmingCharacters(in: .whitespaces)
                if !p.isEmpty { return URL(fileURLWithPath: p) }
            }
        }
        for line in output.components(separatedBy: "\n") {
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            if trimmed.hasPrefix("Config:") {
                let configPath = trimmed.dropFirst("Config:".count).trimmingCharacters(in: .whitespaces)
                if !configPath.isEmpty {
                    return URL(fileURLWithPath: configPath).appendingPathComponent("match")
                }
            }
        }
        return defaultPath
    }
}
