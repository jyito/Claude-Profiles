import XCTest
import ProfilesCore

final class StatsStoreTests: XCTestCase {
    private func stat(_ name: String, running: Bool) -> ProfileStat {
        ProfileStat(name: name, slug: name.lowercased(), running: running, cpu: 1, mem: 1, procs: 1,
                    ptys: 0, ptmx: 0, ptmxMax: 256, disk: 0, opens: 0, last: "", color: "#000000", remote: false)
    }

    func testRefreshPopulatesAndSorts() async throws {
        let engine = FixtureEngine(stats: [stat("Zed", running: false), stat("Able", running: true)])
        let store = StatsStore(engine: engine, clock: ImmediateClock())
        await store.refreshOnce()
        let (count, firstRunning) = await MainActor.run { (store.profiles.count, store.profiles.first?.running ?? false) }
        XCTAssertEqual(count, 2)
        XCTAssertTrue(firstRunning)                 // alive-first sort applied
        let err = await MainActor.run { store.lastError }
        XCTAssertNil(err)
    }

    func testBadTickKeepsLastGoodProfiles() async throws {
        let engine = FixtureEngine(stats: [stat("Able", running: true)])
        let store = StatsStore(engine: engine, clock: ImmediateClock())
        await store.refreshOnce()
        engine.shouldThrow = true
        await store.refreshOnce()
        let (count, err) = await MainActor.run { (store.profiles.count, store.lastError) }
        XCTAssertEqual(count, 1)                     // last-good profiles retained
        XCTAssertNotNil(err)                         // but the error is surfaced
    }

    func testHasLoadedOnceGatesTheLoadingSkeleton() async throws {
        let engine = FixtureEngine(stats: [stat("Able", running: true)])
        let store = StatsStore(engine: engine, clock: ImmediateClock())
        let before = await MainActor.run { store.hasLoadedOnce }
        XCTAssertFalse(before)                       // skeleton shows before the first tick
        await store.refreshOnce()
        let after = await MainActor.run { store.hasLoadedOnce }
        XCTAssertTrue(after)                         // first tick done → grid takes over
        // A later FAILED tick must NOT revert to the skeleton.
        engine.shouldThrow = true
        await store.refreshOnce()
        let stillLoaded = await MainActor.run { store.hasLoadedOnce }
        XCTAssertTrue(stillLoaded)
    }

    static let allTests: [(String, (StatsStoreTests) -> () async throws -> Void)] = [
        ("testRefreshPopulatesAndSorts", testRefreshPopulatesAndSorts),
        ("testBadTickKeepsLastGoodProfiles", testBadTickKeepsLastGoodProfiles),
        ("testHasLoadedOnceGatesTheLoadingSkeleton", testHasLoadedOnceGatesTheLoadingSkeleton),
    ]
}
