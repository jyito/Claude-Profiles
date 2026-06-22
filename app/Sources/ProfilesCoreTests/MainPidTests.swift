import XCTest
import ProfilesCore

/// Writes a throwaway bash "engine" that echoes a canned PID for `mainpid`/
/// `defaultpid` — proves the REAL EngineClient Process boundary parses stdout into
/// an Int32?, including the slug→verb routing and the empty→nil case.
private func makePidEngine(mainpid: String, defaultpid: String) throws -> (EngineClient, URL) {
    let tmp = FileManager.default.temporaryDirectory
        .appendingPathComponent("fake-pid-engine-\(UUID().uuidString).sh")
    let script = """
    #!/bin/bash
    case "$1" in
      mainpid)    printf '%s' '\(mainpid)' ;;
      defaultpid) printf '%s' '\(defaultpid)' ;;
    esac
    """
    try script.write(to: tmp, atomically: true, encoding: .utf8)
    try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: tmp.path)
    return (EngineClient(enginePath: tmp.path), tmp)
}

final class MainPidTests: XCTestCase {
    /// A profile slug routes to `mainpid <slug>`; a numeric stdout (trailing newline)
    /// → the parsed pid.
    func testProfileSlugParsesPid() async throws {
        let (engine, tmp) = try makePidEngine(mainpid: "54321\n", defaultpid: "")
        defer { try? FileManager.default.removeItem(at: tmp) }
        let pid = try await engine.mainPid("x")
        XCTAssertEqual(pid, 54321)
    }

    /// Empty stdout (instance not running) → nil, never 0.
    func testEmptyStdoutIsNil() async throws {
        let (engine, tmp) = try makePidEngine(mainpid: "", defaultpid: "")
        defer { try? FileManager.default.removeItem(at: tmp) }
        let pid = try await engine.mainPid("x")
        XCTAssertNil(pid)
    }

    /// The default instance (`slug == "default"`) routes to `defaultpid`, not `mainpid`.
    func testDefaultRoutesToDefaultpid() async throws {
        // mainpid would print 111; defaultpid prints 999. A correct route returns 999.
        let (engine, tmp) = try makePidEngine(mainpid: "111\n", defaultpid: "999\n")
        defer { try? FileManager.default.removeItem(at: tmp) }
        let pid = try await engine.mainPid("default")
        XCTAssertEqual(pid, 999)
    }

    /// The FixtureEngine (used across the suite) returns a canned pid so view/store
    /// wiring can be exercised without a live engine.
    func testFixtureEngineReturnsCannedPid() async throws {
        let engine = FixtureEngine(stats: [])
        engine.mainPidValue = 4242
        let pid = try await engine.mainPid("work")
        XCTAssertEqual(pid, 4242)
        XCTAssertEqual(engine.mainPidSlugs, ["work"])
    }

    /// The store's `mainPid` returns the pid on success and nil on a transport error
    /// (surfacing the failure via `lastError` rather than focusing a bogus pid).
    func testStoreMainPidReturnsNilOnError() async throws {
        let engine = FixtureEngine(stats: [])
        engine.mainPidValue = 77
        let store = StatsStore(engine: engine, clock: ImmediateClock())
        let ok = await store.mainPid("work")
        XCTAssertEqual(ok, 77)
        engine.shouldThrow = true
        let bad = await store.mainPid("work")
        XCTAssertNil(bad)
        let err = await MainActor.run { store.lastError }
        XCTAssertNotNil(err)
    }

    static let allTests: [(String, (MainPidTests) -> () async throws -> Void)] = [
        ("testProfileSlugParsesPid", testProfileSlugParsesPid),
        ("testEmptyStdoutIsNil", testEmptyStdoutIsNil),
        ("testDefaultRoutesToDefaultpid", testDefaultRoutesToDefaultpid),
        ("testFixtureEngineReturnsCannedPid", testFixtureEngineReturnsCannedPid),
        ("testStoreMainPidReturnsNilOnError", testStoreMainPidReturnsNilOnError),
    ]
}
