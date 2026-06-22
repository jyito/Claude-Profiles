import XCTest
import ProfilesCore

final class ConfigTests: XCTestCase {
    private func stat(_ name: String, running: Bool) -> ProfileStat {
        ProfileStat(name: name, slug: name.lowercased(), running: running, cpu: 1, mem: 1, procs: 1,
                    ptys: 0, ptmx: 0, ptmxMax: 256, disk: 0, opens: 0, last: "", color: "#000000", remote: false)
    }

    // MARK: getconfig decode

    func testDecodeGetConfigJSON() throws {
        // Exact `cmd_getconfig` shape (keys in the engine's emitted order).
        let json = #"{"autoCloseIdleMin":30,"autoCleanThresholdMB":1024,"autoRestartLeakAt":250}"#
        let cfg = try ProfileConfig.decode(from: Data(json.utf8))
        XCTAssertEqual(cfg.autoCloseIdleMin, 30)
        XCTAssertEqual(cfg.autoCleanThresholdMB, 1024)
        XCTAssertEqual(cfg.autoRestartLeakAt, 250)
    }

    func testDecodeAllZeroDefaults() throws {
        let json = #"{"autoCloseIdleMin":0,"autoCleanThresholdMB":0,"autoRestartLeakAt":0}"#
        let cfg = try ProfileConfig.decode(from: Data(json.utf8))
        XCTAssertEqual(cfg, ProfileConfig())
    }

    func testValueForKeyReadsRightField() {
        let cfg = ProfileConfig(autoCleanThresholdMB: 500, autoCloseIdleMin: 60, autoRestartLeakAt: 150)
        XCTAssertEqual(cfg.value(for: .autoCleanThresholdMB), 500)
        XCTAssertEqual(cfg.value(for: .autoCloseIdleMin), 60)
        XCTAssertEqual(cfg.value(for: .autoRestartLeakAt), 150)
    }

    // MARK: store loadConfig

    func testStoreLoadConfigPopulates() async throws {
        let engine = FixtureEngine(stats: [])
        engine.config = ProfileConfig(autoCleanThresholdMB: 2048, autoCloseIdleMin: 120, autoRestartLeakAt: 350)
        let store = StatsStore(engine: engine, clock: ImmediateClock())
        await store.loadConfig()
        let cfg = await MainActor.run { store.config }
        XCTAssertEqual(cfg.autoCleanThresholdMB, 2048)
        XCTAssertEqual(cfg.autoCloseIdleMin, 120)
        XCTAssertEqual(cfg.autoRestartLeakAt, 350)
    }

    func testStoreSetConfigRoutesKeyAndMirrors() async throws {
        let engine = FixtureEngine(stats: [])
        let store = StatsStore(engine: engine, clock: ImmediateClock())
        let ok = await store.setConfig("autoRestartLeakAt", 250)
        XCTAssertTrue(ok)
        let (calls, mirrored) = await MainActor.run {
            (engine.setConfigCalls, store.config.autoRestartLeakAt)
        }
        XCTAssertEqual(calls.count, 1)
        XCTAssertEqual(calls.first?.0, "autoRestartLeakAt")
        XCTAssertEqual(calls.first?.1, 250)
        XCTAssertEqual(mirrored, 250)            // optimistically mirrored into the live config
    }

    func testStoreSetConfigSurfacesError() async throws {
        let engine = FixtureEngine(stats: [])
        engine.shouldThrow = true
        let store = StatsStore(engine: engine, clock: ImmediateClock())
        let ok = await store.setConfig("autoCloseIdleMin", 30)
        XCTAssertFalse(ok)
        let (mirrored, err) = await MainActor.run { (store.config.autoCloseIdleMin, store.lastError) }
        XCTAssertEqual(mirrored, 0)              // not mirrored on failure
        XCTAssertNotNil(err)
    }

    // MARK: create

    func testCreateParsesSlugFromStub() async throws {
        let engine = FixtureEngine(stats: [])
        engine.createSlug = "work2"
        let slug = try await engine.create("Work 2")
        XCTAssertEqual(slug, "work2")
        XCTAssertEqual(engine.createNames, ["Work 2"])
    }

    func testStoreEngineCreateReturnsSlugAndRefreshes() async throws {
        let engine = FixtureEngine(stats: [stat("Able", running: true)])
        engine.createSlug = "marketing"
        let store = StatsStore(engine: engine, clock: ImmediateClock())
        let slug = await store.engineCreate("Marketing")
        XCTAssertEqual(slug, "marketing")
        let count = await MainActor.run { store.profiles.count }
        XCTAssertEqual(count, 1)                 // refreshOnce ran after create
    }

    func testStoreEngineCreateNilOnError() async throws {
        let engine = FixtureEngine(stats: [])
        engine.shouldThrow = true
        let store = StatsStore(engine: engine, clock: ImmediateClock())
        let slug = await store.engineCreate("Bad")
        XCTAssertNil(slug)
        let err = await MainActor.run { store.lastError }
        XCTAssertNotNil(err)
    }

    static let allTests: [(String, (ConfigTests) -> () async throws -> Void)] = [
        ("testDecodeGetConfigJSON", testDecodeGetConfigJSON),
        ("testDecodeAllZeroDefaults", testDecodeAllZeroDefaults),
        ("testValueForKeyReadsRightField", testValueForKeyReadsRightField),
        ("testStoreLoadConfigPopulates", testStoreLoadConfigPopulates),
        ("testStoreSetConfigRoutesKeyAndMirrors", testStoreSetConfigRoutesKeyAndMirrors),
        ("testStoreSetConfigSurfacesError", testStoreSetConfigSurfacesError),
        ("testCreateParsesSlugFromStub", testCreateParsesSlugFromStub),
        ("testStoreEngineCreateReturnsSlugAndRefreshes", testStoreEngineCreateReturnsSlugAndRefreshes),
        ("testStoreEngineCreateNilOnError", testStoreEngineCreateNilOnError),
    ]
}
