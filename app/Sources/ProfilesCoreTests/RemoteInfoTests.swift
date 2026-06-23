import XCTest
import ProfilesCore

final class RemoteInfoTests: XCTestCase {

    // MARK: decode — success shape (exact cmd_remoteinfo JSON)

    func testDecodeSuccessJSON() throws {
        let json = #"{"slug":"work","session":"claude-work","user":"me","host":"mac.local","tailscaleIp":"100.64.0.1","alreadyRunning":true}"#
        let info = try RemoteInfo.decode(from: Data(json.utf8))
        XCTAssertEqual(info.slug, "work")
        XCTAssertEqual(info.session, "claude-work")
        XCTAssertEqual(info.user, "me")
        XCTAssertEqual(info.host, "mac.local")
        XCTAssertEqual(info.tailscaleIp, "100.64.0.1")
        XCTAssertTrue(info.alreadyRunning)
        XCTAssertNil(info.error)
    }

    // MARK: decode — error-only shape

    func testDecodeErrorOnlyJSON() throws {
        let json = #"{"error":"Claude Code CLI not found on PATH — install it, then click Remote again."}"#
        let info = try RemoteInfo.decode(from: Data(json.utf8))
        XCTAssertNotNil(info.error)
        XCTAssertEqual(info.host, "")            // missing success fields default cleanly
        XCTAssertFalse(info.alreadyRunning)
    }

    func testDecodeEmptyTailscaleIp() throws {
        let json = #"{"slug":"work","session":"claude-work","user":"me","host":"mac.local","tailscaleIp":"","alreadyRunning":false}"#
        let info = try RemoteInfo.decode(from: Data(json.utf8))
        XCTAssertEqual(info.tailscaleIp, "")
        XCTAssertNil(info.tailscaleCommand)      // no Tailscale row when IP is empty
    }

    // MARK: derived commands

    func testDerivedCommands() {
        let info = RemoteInfo(slug: "work", session: "claude-work", user: "me",
                              host: "mac.local", tailscaleIp: "100.64.0.1", alreadyRunning: false)
        XCTAssertEqual(info.localCommand, #"ssh me@mac.local -t "screen -r claude-work""#)
        XCTAssertEqual(info.tailscaleCommand, #"ssh me@100.64.0.1 -t "screen -r claude-work""#)
    }

    // MARK: seam + store

    func testEngineRemoteInfoReturnsCanned() async throws {
        let engine = FixtureEngine(stats: [])
        engine.remote = RemoteInfo(slug: "x", session: "claude-x", user: "u",
                                   host: "h.local", tailscaleIp: "", alreadyRunning: true)
        let info = try await engine.remoteInfo("x")
        XCTAssertEqual(info.session, "claude-x")
        XCTAssertTrue(info.alreadyRunning)
    }

    func testStoreRemoteInfoPassesThrough() async throws {
        let engine = FixtureEngine(stats: [])
        engine.remote = RemoteInfo(slug: "x", session: "claude-x", user: "u",
                                   host: "h.local", tailscaleIp: "100.64.0.9", alreadyRunning: false)
        let store = StatsStore(engine: engine, clock: ImmediateClock())
        let info = await store.remoteInfo(for: "x")
        XCTAssertEqual(info.host, "h.local")
        XCTAssertEqual(info.tailscaleIp, "100.64.0.9")
    }

    func testStoreRemoteInfoSurfacesTransportError() async throws {
        let engine = FixtureEngine(stats: [])
        engine.shouldThrow = true
        let store = StatsStore(engine: engine, clock: ImmediateClock())
        let info = await store.remoteInfo(for: "x")
        XCTAssertNotNil(info.error)              // wrapped into the returned RemoteInfo
        let err = await MainActor.run { store.lastError }
        XCTAssertNotNil(err)
    }

    func testStoreCopyRecordsText() async throws {
        let engine = FixtureEngine(stats: [])
        let store = StatsStore(engine: engine, clock: ImmediateClock())
        await store.copy("ssh me@mac.local")
        XCTAssertEqual(engine.copied, ["ssh me@mac.local"])
    }

    // MARK: remoteStop — turn Remote OFF

    func testEngineRemoteStopRecordsSlug() async throws {
        let engine = FixtureEngine(stats: [])
        try await engine.remoteStop("work")
        XCTAssertEqual(engine.remoteStopped, ["work"])
    }

    func testStoreRemoteStopPassesThrough() async throws {
        let engine = FixtureEngine(stats: [])
        let store = StatsStore(engine: engine, clock: ImmediateClock())
        await store.remoteStop("work")
        XCTAssertEqual(engine.remoteStopped, ["work"])
        let err = await MainActor.run { store.lastError }
        XCTAssertNil(err)                       // a clean stop clears lastError
    }

    func testStoreRemoteStopSurfacesTransportError() async throws {
        let engine = FixtureEngine(stats: [])
        engine.shouldThrow = true
        let store = StatsStore(engine: engine, clock: ImmediateClock())
        await store.remoteStop("work")
        let err = await MainActor.run { store.lastError }
        XCTAssertNotNil(err)                     // a failed stop is visible, not silent
    }

    static let allTests: [(String, (RemoteInfoTests) -> () async throws -> Void)] = [
        ("testDecodeSuccessJSON", testDecodeSuccessJSON),
        ("testDecodeErrorOnlyJSON", testDecodeErrorOnlyJSON),
        ("testDecodeEmptyTailscaleIp", testDecodeEmptyTailscaleIp),
        ("testDerivedCommands", testDerivedCommands),
        ("testEngineRemoteInfoReturnsCanned", testEngineRemoteInfoReturnsCanned),
        ("testStoreRemoteInfoPassesThrough", testStoreRemoteInfoPassesThrough),
        ("testStoreRemoteInfoSurfacesTransportError", testStoreRemoteInfoSurfacesTransportError),
        ("testStoreCopyRecordsText", testStoreCopyRecordsText),
        ("testEngineRemoteStopRecordsSlug", testEngineRemoteStopRecordsSlug),
        ("testStoreRemoteStopPassesThrough", testStoreRemoteStopPassesThrough),
        ("testStoreRemoteStopSurfacesTransportError", testStoreRemoteStopSurfacesTransportError),
    ]
}
