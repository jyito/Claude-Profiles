import XCTest
import ProfilesCore

final class EngineSeamTests: XCTestCase {
    private func stat(_ name: String, running: Bool) -> ProfileStat {
        ProfileStat(name: name, slug: name.lowercased(), running: running, cpu: 1, mem: 1, procs: 1,
                    ptys: 0, ptmx: 0, ptmxMax: 256, disk: 0, opens: 0, last: "", color: "#000000", remote: false)
    }

    func testRunRecordsMultiArgVerb() async throws {
        let engine = FixtureEngine(stats: [])
        try await engine.run(["clean", "x", "gpu"])
        XCTAssertEqual(engine.ranArgs, [["clean", "x", "gpu"]])
        // The convenience run(verb,slug) delegates to run([verb,slug]).
        try await engine.run("focus", "x")
        XCTAssertEqual(engine.ranArgs.last ?? [], ["focus", "x"])
    }

    func testTerminalsReturnsCannedList() async throws {
        let engine = FixtureEngine(stats: [])
        engine.terminalsList = [
            TerminalInfo(dev: "/dev/ttys001", pid: 10, cmd: "node", idle: 5),
            TerminalInfo(dev: "/dev/ttys002", pid: 11, cmd: "-zsh", idle: -1),
        ]
        let terms = try await engine.terminals("x")
        XCTAssertEqual(terms.count, 2)
        XCTAssertEqual(terms[0].dev, "/dev/ttys001")
        XCTAssertEqual(terms[1].idle, -1)
    }

    func testStoreLoadTerminalsPopulates() async throws {
        let engine = FixtureEngine(stats: [stat("Able", running: true)])
        engine.terminalsList = [TerminalInfo(dev: "/dev/ttys009", pid: 99, cmd: "claude", idle: 0)]
        let store = StatsStore(engine: engine, clock: ImmediateClock())
        await store.loadTerminals(for: "able")
        let (count, dev) = await MainActor.run { (store.terminals.count, store.terminals.first?.dev ?? "") }
        XCTAssertEqual(count, 1)
        XCTAssertEqual(dev, "/dev/ttys009")
    }

    func testStoreLoadTerminalsClearsOnError() async throws {
        let engine = FixtureEngine(stats: [])
        engine.terminalsList = [TerminalInfo(dev: "/dev/ttys009", pid: 99, cmd: "claude", idle: 0)]
        let store = StatsStore(engine: engine, clock: ImmediateClock())
        await store.loadTerminals(for: "able")
        engine.shouldThrow = true
        await store.loadTerminals(for: "able")
        let count = await MainActor.run { store.terminals.count }
        XCTAssertEqual(count, 0)   // a failed load empties rather than showing stale terminals
    }

    static let allTests: [(String, (EngineSeamTests) -> () async throws -> Void)] = [
        ("testRunRecordsMultiArgVerb", testRunRecordsMultiArgVerb),
        ("testTerminalsReturnsCannedList", testTerminalsReturnsCannedList),
        ("testStoreLoadTerminalsPopulates", testStoreLoadTerminalsPopulates),
        ("testStoreLoadTerminalsClearsOnError", testStoreLoadTerminalsClearsOnError),
    ]
}
