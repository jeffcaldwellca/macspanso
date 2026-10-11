// macspansoTests/EspansoProcessManagerTests.swift
import XCTest
@testable import macspanso

@MainActor
final class EspansoProcessManagerTests: XCTestCase {

    /// Writes an executable stand-in for the espanso binary.
    private func makeFakeEspanso(script: String) throws -> String {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("fake-espanso-\(UUID().uuidString).sh")
        try "#!/bin/bash\n\(script)\n".write(to: url, atomically: true, encoding: .utf8)
        try FileManager.default.setAttributes(
            [.posixPermissions: 0o755], ofItemAtPath: url.path)
        addTeardownBlock { try? FileManager.default.removeItem(at: url) }
        return url.path
    }

    /// Races `body` against a deadline. Async XCTest bodies that never return
    /// hang the whole suite (XCTest waits without timeout), so every test that
    /// exercises a potentially-hanging path must go through this.
    private func withDeadline<T: Sendable>(
        seconds: UInt64,
        _ body: @escaping @Sendable () async -> T
    ) async -> T? {
        await withTaskGroup(of: T?.self) { group in
            group.addTask { await body() }
            group.addTask {
                try? await Task.sleep(nanoseconds: seconds * 1_000_000_000)
                return nil
            }
            let first = await group.next()!
            group.cancelAll()
            return first
        }
    }

    func testRunReadsOutputLargerThanPipeBuffer() async throws {
        // ~1 MB of output — far beyond the ~64 KB pipe buffer. If run() waits
        // for exit before draining the pipe, the child blocks on a full pipe
        // and run() never returns. The output comes from bash itself (no
        // grandchildren) and a watchdog bounds the child's life so a deadlocked
        // child can't hold the test host's inherited pipes open forever.
        // The watchdog must NOT inherit our stdout pipe (>/dev/null), or its
        // orphaned sleep would hold the write end open and delay EOF to 15s.
        let script = """
        ( sleep 15; kill -9 $$ ) >/dev/null 2>&1 &
        watchdog=$!
        line=$(printf 'x%.0s' {1..999})
        for i in {1..1000}; do echo "$line"; done
        kill -9 $watchdog 2>/dev/null
        exit 0
        """
        let path = try makeFakeEspanso(script: script)
        let manager = EspansoProcessManager(espansoPath: path)

        let output = await withDeadline(seconds: 10) { await manager.run("log") }
        let result = try XCTUnwrap(output, "run() deadlocked on output > pipe buffer")
        XCTAssertGreaterThan(result.utf8.count, 900_000)
    }

    func testRunReturnsEmptyWhenBinaryCannotLaunch() async throws {
        // A failed launch must not leave run() blocked reading a pipe whose
        // write end our own process still holds (EOF never arrives).
        let manager = EspansoProcessManager(
            espansoPath: "/nonexistent/path/to/espanso")
        let output = await withDeadline(seconds: 5) { await manager.run("status") }
        let result = try XCTUnwrap(output, "run() hung forever on launch failure")
        XCTAssertEqual(result, "")
    }
}

// MARK: - Snooze expiry & path resolution

extension EspansoProcessManagerTests {

    func testRefreshClearsExpiredSnooze() async throws {
        let path = try makeFakeEspanso(script: "echo 'espanso is running'")
        let manager = EspansoProcessManager(espansoPath: path, defaults: try makeDefaults())

        // A snooze that elapses without its timer firing — as after a Mac
        // sleeps through the end date (Timer doesn't fire during system sleep).
        // It must start in the future: beginSnooze ends with a refresh, which
        // would clear an already-past snooze before we could observe it.
        await manager.beginSnooze(until: Date(timeIntervalSinceNow: 0.3))
        XCTAssertNotNil(manager.snoozeUntil)
        try await Task.sleep(nanoseconds: 400_000_000)

        await manager.refresh()
        XCTAssertNil(manager.snoozeUntil,
            "refresh() must clear a snooze whose end date has passed")
    }

    func testResolveMatchDirectoryTimesOutOnHungBinary() async throws {
        // exec → single process, so the deadline SIGKILL closes the pipe's
        // only write end and the reader sees EOF immediately.
        let path = try makeFakeEspanso(script: "exec sleep 8")
        let started = Date()
        let dir = await EspansoProcessManager.resolveMatchDirectory(
            espansoPath: path, timeout: 2)
        let elapsed = Date().timeIntervalSince(started)

        XCTAssertLessThan(elapsed, 6,
            "a hung espanso binary must not block match-directory resolution")
        XCTAssertTrue(dir.path.hasSuffix("Library/Application Support/espanso/match"),
            "timeout must fall back to the default directory, got \(dir.path)")
    }
}

// MARK: - Enabled / disabled tracking

extension EspansoProcessManagerTests {

    /// Isolated defaults so tests never touch (or depend on) the real app's state.
    private func makeDefaults() throws -> UserDefaults {
        let name = "macspanso-tests-\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: name))
        addTeardownBlock { defaults.removePersistentDomain(forName: name) }
        return defaults
    }

    /// A stand-in that behaves like real espanso: `status` says "running"
    /// whether or not expansion is enabled, and every invocation is logged.
    private func makeRecordingEspanso() throws -> (path: String, log: URL) {
        let log = FileManager.default.temporaryDirectory
            .appendingPathComponent("fake-espanso-log-\(UUID().uuidString)")
        addTeardownBlock { try? FileManager.default.removeItem(at: log) }
        let path = try makeFakeEspanso(script: """
        echo "$*" >> '\(log.path)'
        if [ "$1" = status ]; then echo 'espanso is running'; fi
        """)
        return (path, log)
    }

    private func commands(in log: URL) -> [String] {
        ((try? String(contentsOf: log, encoding: .utf8)) ?? "")
            .split(separator: "\n").map(String.init).filter { $0 != "status" }
    }

    func testDisabledStateIsTrackedEvenThoughStatusCannotReportIt() async throws {
        let (path, log) = try makeRecordingEspanso()
        let manager = EspansoProcessManager(espansoPath: path, defaults: try makeDefaults())

        await manager.refresh()
        XCTAssertEqual(manager.state, .running)

        await manager.setExpansionEnabled(false)
        XCTAssertEqual(manager.state, .disabled)
        await manager.refresh()
        XCTAssertEqual(manager.state, .disabled, "a later poll must not flip it back to running")

        await manager.setExpansionEnabled(true)
        XCTAssertEqual(manager.state, .running)
        XCTAssertEqual(commands(in: log), ["cmd disable", "cmd enable"])
    }

    func testDisabledStateSurvivesRelaunch() async throws {
        let (path, _) = try makeRecordingEspanso()
        let defaults = try makeDefaults()
        await EspansoProcessManager(espansoPath: path, defaults: defaults).setExpansionEnabled(false)

        let relaunched = EspansoProcessManager(espansoPath: path, defaults: defaults)
        await relaunched.refresh()
        XCTAssertEqual(relaunched.state, .disabled)
    }

    func testEndingSnoozeReenablesExpansion() async throws {
        let (path, log) = try makeRecordingEspanso()
        let manager = EspansoProcessManager(espansoPath: path, defaults: try makeDefaults())
        await manager.beginSnooze(until: Date(timeIntervalSinceNow: 3600))
        XCTAssertEqual(manager.state, .disabled)
        XCTAssertEqual(commands(in: log).last, "cmd disable")

        await manager.endSnooze(reenable: true)
        XCTAssertNil(manager.snoozeUntil)
        XCTAssertEqual(manager.state, .running)
        XCTAssertEqual(commands(in: log).last, "cmd enable",
                       "an expired snooze must turn expansion back on")
    }

    func testDaemonStopClearsDisabledRecord() async throws {
        let defaults = try makeDefaults()
        let running = try makeRecordingEspanso().path
        await EspansoProcessManager(espansoPath: running, defaults: defaults).setExpansionEnabled(false)

        // The daemon went away; when it comes back it is enabled again.
        let stopped = try makeFakeEspanso(script: "echo 'espanso is not running'")
        let afterStop = EspansoProcessManager(espansoPath: stopped, defaults: defaults)
        await afterStop.refresh()
        XCTAssertEqual(afterStop.state, .stopped)

        let back = EspansoProcessManager(espansoPath: running, defaults: defaults)
        await back.refresh()
        XCTAssertEqual(back.state, .running)
    }

    func testRunTerminatesCommandThatHangs() async throws {
        let path = try makeFakeEspanso(script: "exec sleep 30")
        let manager = EspansoProcessManager(espansoPath: path, defaults: try makeDefaults())
        let started = Date()
        _ = await manager.run("status", timeout: 1)
        XCTAssertLessThan(Date().timeIntervalSince(started), 10)
    }

    func testFailedEnableIsNotRecordedAsEnabled() async throws {
        // `cmd enable` fails; everything else behaves.
        let path = try makeFakeEspanso(script: """
        if [ "$1" = status ]; then echo 'espanso is running'; exit 0; fi
        if [ "$2" = enable ]; then exit 1; fi
        exit 0
        """)
        let manager = EspansoProcessManager(espansoPath: path, defaults: try makeDefaults())
        await manager.beginSnooze(until: Date(timeIntervalSinceNow: 3600))
        XCTAssertEqual(manager.state, .disabled)

        await manager.endSnooze(reenable: true)
        XCTAssertEqual(manager.state, .disabled, "espanso is still off, so the app must say so")
        XCTAssertNotNil(manager.snoozeUntil, "the snooze stays so a later poll retries")
    }

    func testSnoozeIsNotShownWhenDisableFails() async throws {
        let path = try makeFakeEspanso(script: """
        if [ "$1" = status ]; then echo 'espanso is running'; exit 0; fi
        exit 1
        """)
        let manager = EspansoProcessManager(espansoPath: path, defaults: try makeDefaults())
        await manager.beginSnooze(until: Date(timeIntervalSinceNow: 3600))
        XCTAssertNil(manager.snoozeUntil)
        XCTAssertEqual(manager.state, .running)
    }

    func testEnablingByAnyRouteEndsTheSnooze() async throws {
        let (path, _) = try makeRecordingEspanso()
        let manager = EspansoProcessManager(espansoPath: path, defaults: try makeDefaults())
        await manager.beginSnooze(until: Date(timeIntervalSinceNow: 3600))
        XCTAssertNotNil(manager.snoozeUntil)

        await manager.setExpansionEnabled(true)   // what the "Espanso Enabled" menu item does
        XCTAssertNil(manager.snoozeUntil)
        XCTAssertEqual(manager.state, .running)
    }
}
