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

    /// Non-nil while a snooze is active; the user has temporarily disabled expansion
    /// and we'll re-enable at this date. Persists across app launches via UserDefaults.
    @Published private(set) var snoozeUntil: Date?

    private var pollTimer: Timer?
    private var snoozeTimer: Timer?
    private var isRefreshing = false
    let espansoPath: String
    private let defaults: UserDefaults

    private static let snoozeDefaultsKey = "macspanso.snoozeUntil"
    private static let disabledDefaultsKey = "macspanso.expansionDisabled"

    /// How often to re-check the daemon in the background. Each check spawns a
    /// process, so keep it slow; the menu also refreshes whenever it opens.
    private static let pollInterval: TimeInterval = 30

    /// Whether macspanso last told the daemon to disable expansion.
    ///
    /// espanso can't be asked: `espanso status` prints "espanso is running"
    /// whether expansion is on or off (checked against 2.4.1). So this is our
    /// own record of the last `cmd enable`/`cmd disable` we sent, persisted so
    /// it survives a relaunch. It can't see a toggle made with espanso's own
    /// hotkey or menu; a daemon (re)start always comes up enabled and clears it.
    private var expansionDisabled: Bool {
        didSet {
            defaults.set(expansionDisabled, forKey: Self.disabledDefaultsKey)
            defaults.set(Self.bootTime, forKey: Self.disabledBootDefaultsKey)
        }
    }

    private static let disabledBootDefaultsKey = "macspanso.expansionDisabledBootTime"

    /// When this Mac last booted, in seconds since 1970 (0 if unavailable).
    /// From the kernel rather than `systemUptime`, which stops during sleep.
    private static var bootTime: Double {
        var time = timeval()
        var size = MemoryLayout<timeval>.stride
        var mib: [Int32] = [CTL_KERN, KERN_BOOTTIME]
        guard sysctl(&mib, 2, &time, &size, nil, 0) == 0 else { return 0 }
        return Double(time.tv_sec)
    }

    /// The persisted record, unless the Mac has rebooted since it was written —
    /// espanso starts enabled after a reboot, whatever we last told it.
    private static func persistedDisabled(in defaults: UserDefaults) -> Bool {
        guard defaults.bool(forKey: disabledDefaultsKey) else { return false }
        let recordedBoot = defaults.double(forKey: disabledBootDefaultsKey)
        return abs(recordedBoot - bootTime) < 120
    }

    /// Pass a custom `espansoPath` / `defaults` for testing; leave the path nil
    /// to auto-locate via Homebrew / PATH.
    init(espansoPath: String? = nil, defaults: UserDefaults = .standard) {
        let path = espansoPath ?? EspansoProcessManager.locateEspanso() ?? ""
        self.espansoPath = path
        self.defaults = defaults
        self.expansionDisabled = Self.persistedDisabled(in: defaults)
        if path.isEmpty { state = .notInstalled }
        restorePersistedSnooze()
    }

    // MARK: - Lifecycle

    func startPolling() {
        guard !espansoPath.isEmpty else { return }
        Task { await refresh() }
        pollTimer = Timer.scheduledTimer(withTimeInterval: Self.pollInterval, repeats: true) { [weak self] _ in
            Task { @MainActor [weak self] in await self?.refresh() }
        }
    }

    func stopPolling() {
        pollTimer?.invalidate()
        pollTimer = nil
    }

    // MARK: - Commands

    /// Refreshes daemon state, first ending a snooze whose time has passed.
    func refresh() async {
        // Timers don't fire during system sleep, so a snooze can outlive its end
        // date — the poll is the reliable place to notice and re-enable. If the
        // re-enable fails the snooze is kept, so the next poll tries again.
        if let end = snoozeUntil, end <= Date() {
            await endSnooze(reenable: true)
        }
        await refreshState()
    }

    /// Reads daemon state by running `espanso status` off the main thread.
    // Verified against espanso v2.4.x output. Check if output strings change on upgrade.
    private func refreshState() async {
        // A slow `espanso status` must not stack up overlapping checks.
        guard !isRefreshing else { return }
        isRefreshing = true
        defer { isRefreshing = false }

        let lower = (await run("status")).lowercased()
        if lower.contains("not running") || lower.contains("stopped") {
            // The daemon starts enabled, so a stop invalidates our record and
            // leaves nothing for a snooze to undo.
            if expansionDisabled { expansionDisabled = false }
            clearSnooze()
            state = .stopped
        } else if lower.contains("running") {
            // "not running" checked above, so this is safe
            state = expansionDisabled ? .disabled : .running
        } else {
            state = .unknown
        }
    }

    /// Enable or disable expansion (daemon keeps running) and record it —
    /// see `expansionDisabled` for why the record is ours to keep. The record
    /// only changes if espanso accepted the command; returns whether it did.
    @discardableResult
    func setExpansionEnabled(_ enabled: Bool) async -> Bool {
        let succeeded = await execute(["cmd", enabled ? "enable" : "disable"]).succeeded
        if succeeded {
            expansionDisabled = !enabled
            // Enabled again by any route means the snooze is over.
            if enabled { clearSnooze() }
        }
        await refreshState()
        return succeeded
    }

    /// Toggle text expansion on/off (daemon keeps running).
    func toggleEnabled() {
        Task { @MainActor [weak self] in
            guard let self else { return }
            switch state {
            case .running:  await setExpansionEnabled(false)
            case .disabled: await setExpansionEnabled(true)
            default:        await refresh()
            }
        }
    }

    // MARK: - Snooze

    enum SnoozeDuration {
        case minutes(Int)
        case hours(Int)
        case untilTomorrow

        var endDate: Date {
            switch self {
            case .minutes(let n):
                return Date().addingTimeInterval(TimeInterval(n) * 60)
            case .hours(let n):
                return Date().addingTimeInterval(TimeInterval(n) * 3600)
            case .untilTomorrow:
                let cal = Calendar.current
                let tomorrowStart = cal.startOfDay(for: Date().addingTimeInterval(86400))
                // Default to 8 AM tomorrow rather than midnight so the user wakes up
                // with espanso ready, not active overnight.
                return cal.date(byAdding: .hour, value: 8, to: tomorrowStart) ?? tomorrowStart
            }
        }

        var label: String {
            switch self {
            case .minutes(let n):  return "\(n) minutes"
            case .hours(let n):    return n == 1 ? "1 hour" : "\(n) hours"
            case .untilTomorrow:   return "Until tomorrow"
            }
        }
    }

    func snooze(for duration: SnoozeDuration) {
        snooze(until: duration.endDate)
    }

    func snooze(until end: Date) {
        Task { @MainActor [weak self] in await self?.beginSnooze(until: end) }
    }

    func beginSnooze(until end: Date) async {
        snoozeUntil = end
        defaults.set(end, forKey: Self.snoozeDefaultsKey)
        scheduleSnoozeTimer()
        // Don't claim a snooze that espanso didn't accept.
        if !(await setExpansionEnabled(false)) { clearSnooze() }
    }

    func cancelSnooze(reenable: Bool = true) {
        Task { @MainActor [weak self] in await self?.endSnooze(reenable: reenable) }
    }

    /// End the snooze and, if asked, turn expansion back on. When re-enabling
    /// fails the snooze stays in place — clearing it would show "enabled"
    /// while espanso is still off — and `refresh()` retries once it's overdue.
    func endSnooze(reenable: Bool) async {
        if reenable {
            await setExpansionEnabled(true)   // clears the snooze on success
        } else {
            clearSnooze()
        }
    }

    private func clearSnooze() {
        guard snoozeUntil != nil || snoozeTimer != nil else { return }
        snoozeUntil = nil
        defaults.removeObject(forKey: Self.snoozeDefaultsKey)
        snoozeTimer?.invalidate()
        snoozeTimer = nil
    }

    private func scheduleSnoozeTimer() {
        snoozeTimer?.invalidate()
        guard let end = snoozeUntil else { return }
        let delay = max(1, end.timeIntervalSinceNow)
        snoozeTimer = Timer.scheduledTimer(withTimeInterval: delay, repeats: false) { [weak self] _ in
            Task { @MainActor [weak self] in await self?.endSnooze(reenable: true) }
        }
    }

    private func restorePersistedSnooze() {
        guard let stored = defaults.object(forKey: Self.snoozeDefaultsKey) as? Date
        else { return }
        if stored > Date(), expansionDisabled {
            snoozeUntil = stored
            scheduleSnoozeTimer()
        } else if stored > Date() {
            // Expansion is no longer off (the Mac rebooted), so there is nothing to snooze.
            defaults.removeObject(forKey: Self.snoozeDefaultsKey)
        } else {
            // Snooze elapsed while the app was closed. Clear it; if expansion is
            // still off because of it, the first refresh() can't tell — so turn
            // it back on here.
            defaults.removeObject(forKey: Self.snoozeDefaultsKey)
            if expansionDisabled {
                Task { @MainActor [weak self] in await self?.setExpansionEnabled(true) }
            }
        }
    }

    func restart() {
        Task { @MainActor [weak self] in
            guard let self else { return }
            await run("restart")
            expansionDisabled = false   // a fresh daemon comes up enabled…
            clearSnooze()               // …so any snooze is over too
            try? await Task.sleep(nanoseconds: 1_000_000_000)
            await refresh()
        }
    }

    // MARK: - Helpers

    /// Runs an espanso command off the main thread and returns its combined stdout+stderr.
    /// A command that hasn't finished after `timeout` seconds is terminated, so a
    /// hung espanso can't pile up processes behind the status poll.
    @discardableResult
    nonisolated func run(_ args: String..., timeout: TimeInterval = 15) async -> String {
        await execute(args, timeout: timeout).output
    }

    /// As `run`, also reporting whether the command launched and exited with status 0.
    nonisolated func execute(
        _ args: [String], timeout: TimeInterval = 15
    ) async -> (output: String, succeeded: Bool) {
        let path = espansoPath
        return await Task.detached(priority: .userInitiated) {
            let proc = Process()
            proc.executableURL = URL(fileURLWithPath: path)
            proc.arguments = args
            let pipe = Pipe()
            proc.standardOutput = pipe
            proc.standardError = pipe
            do {
                try proc.run()
            } catch {
                // Launch failed: return before touching the pipe. Our process
                // still holds its write end, so a read would never see EOF.
                return ("", false)
            }
            let pid = proc.processIdentifier
            // Ask nicely, then insist: a child that ignores SIGTERM would leave
            // the read below — and every later status check — blocked forever.
            let watchdog = DispatchWorkItem {
                guard proc.isRunning else { return }
                proc.terminate()
                DispatchQueue.global().asyncAfter(deadline: .now() + 2) {
                    if proc.isRunning { kill(pid, SIGKILL) }
                }
            }
            DispatchQueue.global().asyncAfter(deadline: .now() + timeout, execute: watchdog)
            // Drain to EOF *before* waiting: output beyond the ~64 KB pipe
            // buffer would otherwise block the child and deadlock both sides.
            let data = pipe.fileHandleForReading.readDataToEndOfFile()
            proc.waitUntilExit()
            watchdog.cancel()
            let succeeded = proc.terminationReason == .exit && proc.terminationStatus == 0
            return (String(data: data, encoding: .utf8) ?? "", succeeded)
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
        do {
            try proc.run()
        } catch {
            return nil
        }
        // Read before waiting — see run(_:) for why this order matters.
        let data = pipe.fileHandleForReading.readDataToEndOfFile()
        proc.waitUntilExit()
        let path = String(data: data, encoding: .utf8)?
            .trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        return path.isEmpty ? nil : path
    }

    /// Discover espanso's match directory by running `espanso path`.
    /// Falls back to the known macOS default if the binary is absent, the
    /// output is unparseable, or the binary doesn't answer within `timeout`.
    static func resolveMatchDirectory(
        espansoPath: String? = nil,
        timeout: TimeInterval = 3
    ) async -> URL {
        let defaultPath = FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent("Library/Application Support/espanso/match")

        guard let espanso = espansoPath ?? locateEspanso() else { return defaultPath }

        let proc = Process()
        proc.executableURL = URL(fileURLWithPath: espanso)
        proc.arguments = ["path"]
        let pipe = Pipe()
        proc.standardOutput = pipe
        do {
            try proc.run()
        } catch {
            return defaultPath
        }
        let pid = proc.processIdentifier

        // Race the read against the deadline. On timeout, kill the child so the
        // reader sees EOF and the group can finish — a task group cannot return
        // while a child is still blocked in read().
        let output: String = await withTaskGroup(of: String?.self) { group in
            group.addTask {
                let data = pipe.fileHandleForReading.readDataToEndOfFile()
                proc.waitUntilExit()
                return String(data: data, encoding: .utf8) ?? ""
            }
            group.addTask {
                try? await Task.sleep(nanoseconds: UInt64(timeout * 1_000_000_000))
                guard !Task.isCancelled else { return nil }
                kill(pid, SIGKILL)
                return nil
            }
            var result = ""
            for await value in group {
                if let value { result = value }
                group.cancelAll()   // reader won → stop the sleeper promptly
            }
            return result
        }

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
