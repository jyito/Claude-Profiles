import XCTest
import Foundation
import ProfilesCore

final class RouteTests: XCTestCase {

    // MARK: decideRoute (pure policy)

    func testTargetRunningForwardsToItsPid() async throws {
        let d = decideRoute(target: "business", running: ["default": 10, "business": 20])
        XCTAssertEqual(d, .forward(slug: "business", pid: 20))
    }

    func testTargetNotRunningLaunchesThenForwards() async throws {
        let d = decideRoute(target: "business", running: ["default": 10])
        XCTAssertEqual(d, .launchThenForward(slug: "business"))
        // Even with nothing running at all.
        XCTAssertEqual(decideRoute(target: "business", running: [:]),
                       .launchThenForward(slug: "business"))
    }

    func testNoTargetSingleInstanceForwardsSilently() async throws {
        let d = decideRoute(target: nil, running: ["work": 33])
        XCTAssertEqual(d, .forward(slug: "work", pid: 33))
    }

    func testNoTargetSeveralInstancesAsksDefaultFirst() async throws {
        let d = decideRoute(target: nil, running: ["work": 3, "default": 1, "alpha": 2])
        XCTAssertEqual(d, .choose(["default", "alpha", "work"]))
    }

    func testNothingRunningNoTarget() async throws {
        XCTAssertEqual(decideRoute(target: nil, running: [:]), .noInstances)
    }

    // MARK: Store + client

    func testStoreRouteSignInRecordsAndClears() async throws {
        let engine = FixtureEngine(stats: [])
        let store = StatsStore(engine: engine, clock: ImmediateClock())
        let ok = await store.routeSignIn("business")
        XCTAssertTrue(ok)
        XCTAssertEqual(engine.signInRouteCalls, ["business"])
        let target = await store.signInTarget()
        XCTAssertEqual(target, "business")
        await store.clearSignInTarget()
        XCTAssertEqual(engine.signInTargetClearCalls, 1)
        let after = await store.signInTarget()
        XCTAssertNil(after)
    }

    func testStoreRouteSignInSurfacesFailure() async throws {
        let engine = FixtureEngine(stats: [])
        engine.shouldThrow = true
        let store = StatsStore(engine: engine, clock: ImmediateClock())
        let ok = await store.routeSignIn("business")
        XCTAssertFalse(ok)
        let err = await MainActor.run { store.lastError }
        XCTAssertNotNil(err)
    }

    private func fakeEngine(_ body: String) throws -> URL {
        let tmp = FileManager.default.temporaryDirectory
            .appendingPathComponent("fake-engine-\(UUID().uuidString).sh")
        try "#!/bin/bash\n\(body)\n".write(to: tmp, atomically: true, encoding: .utf8)
        try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: tmp.path)
        return tmp
    }

    func testClientDecodesTargetAndNull() async throws {
        let some = try fakeEngine(#"printf '%s' '{"target":"business"}'"#)
        let none = try fakeEngine(#"printf '%s' '{"target":null}'"#)
        defer { try? FileManager.default.removeItem(at: some); try? FileManager.default.removeItem(at: none) }
        let a = try await EngineClient(enginePath: some.path).signInTarget()
        XCTAssertEqual(a, "business")
        let b = try await EngineClient(enginePath: none.path).signInTarget()
        XCTAssertNil(b)
    }

    func testClientRouteSurfacesErrToken() async throws {
        let tmp = try fakeEngine(#"printf '%s' 'err not found'"#)
        defer { try? FileManager.default.removeItem(at: tmp) }
        var thrown: Error?
        do { try await EngineClient(enginePath: tmp.path).signInRoute("nosuch") } catch { thrown = error }
        XCTAssertEqual(thrown as? EngineError, EngineError.actionFailed("err not found"))
    }

    static let allTests: [(String, (RouteTests) -> () async throws -> Void)] = [
        ("testTargetRunningForwardsToItsPid", testTargetRunningForwardsToItsPid),
        ("testTargetNotRunningLaunchesThenForwards", testTargetNotRunningLaunchesThenForwards),
        ("testNoTargetSingleInstanceForwardsSilently", testNoTargetSingleInstanceForwardsSilently),
        ("testNoTargetSeveralInstancesAsksDefaultFirst", testNoTargetSeveralInstancesAsksDefaultFirst),
        ("testNothingRunningNoTarget", testNothingRunningNoTarget),
        ("testStoreRouteSignInRecordsAndClears", testStoreRouteSignInRecordsAndClears),
        ("testStoreRouteSignInSurfacesFailure", testStoreRouteSignInSurfacesFailure),
        ("testClientDecodesTargetAndNull", testClientDecodesTargetAndNull),
        ("testClientRouteSurfacesErrToken", testClientRouteSurfacesErrToken),
    ]
}
