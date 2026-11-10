import XCTest
import Foundation
import ProfilesCore

final class SignInTests: XCTestCase {

    private func stat(_ name: String, slug: String, running: Bool) -> ProfileStat {
        ProfileStat(name: name, slug: slug, running: running, cpu: 0, mem: 0, procs: 0, ptys: 0,
                    ptmx: 0, ptmxMax: 256, disk: 0, opens: 0, last: "", color: "#000000", remote: false)
    }

    // MARK: Store — sign-in mode lifecycle

    func testBeginSignInEntersModeWithClosedInstances() async throws {
        let engine = FixtureEngine(stats: [stat("Business", slug: "business", running: true)])
        engine.signInClosed = ["default", "work"]
        let store = StatsStore(engine: engine, clock: ImmediateClock())
        let ok = await store.beginSignIn("business")
        XCTAssertTrue(ok)
        XCTAssertEqual(engine.signInCalls, ["business"])
        let mode = await MainActor.run { store.signInMode }
        XCTAssertEqual(mode, SignInMode(target: "business", closed: ["default", "work"]))
    }

    func testBeginSignInSkipsModeWhenNothingWasClosed() async throws {
        // Nothing else running → the claude:// callback is already unambiguous:
        // no banner, nothing to restore.
        let engine = FixtureEngine(stats: [stat("Business", slug: "business", running: true)])
        engine.signInClosed = []
        let store = StatsStore(engine: engine, clock: ImmediateClock())
        let ok = await store.beginSignIn("business")
        XCTAssertTrue(ok)
        let mode = await MainActor.run { store.signInMode }
        XCTAssertNil(mode)
    }

    func testRestoreLeavesModeAndDismissClears() async throws {
        let engine = FixtureEngine(stats: [stat("Business", slug: "business", running: true)])
        let store = StatsStore(engine: engine, clock: ImmediateClock())
        await store.beginSignIn("business")
        await store.restoreSignIn()
        XCTAssertEqual(engine.signInRestoreCalls, 1)
        var mode = await MainActor.run { store.signInMode }
        XCTAssertNil(mode)

        // Dismiss path: mode clears + the engine's pending file is dropped.
        await store.beginSignIn("business")
        await store.dismissSignIn()
        XCTAssertEqual(engine.signInClearCalls, 1)
        mode = await MainActor.run { store.signInMode }
        XCTAssertNil(mode)
    }

    func testRestoreFailureKeepsTheModeVisible() async throws {
        // A failed restore must NOT drop the banner — it's the user's way back.
        let engine = FixtureEngine(stats: [stat("Business", slug: "business", running: true)])
        let store = StatsStore(engine: engine, clock: ImmediateClock())
        await store.beginSignIn("business")
        engine.shouldThrow = true
        await store.restoreSignIn()
        let mode = await MainActor.run { store.signInMode }
        XCTAssertNotNil(mode)
        let err = await MainActor.run { store.lastError }
        XCTAssertNotNil(err)
    }

    func testCheckSignInPendingRecoversAfterRelaunch() async throws {
        // The engine still holds a restore list from a previous app run; the
        // startup probe re-enters sign-in mode with an unknown target.
        let engine = FixtureEngine(stats: [stat("Business", slug: "business", running: true)])
        engine.signInPendingList = ["default"]
        let store = StatsStore(engine: engine, clock: ImmediateClock())
        await store.checkSignInPending()
        let mode = await MainActor.run { store.signInMode }
        XCTAssertEqual(mode, SignInMode(target: nil, closed: ["default"]))
    }

    func testCheckSignInPendingNoopsWhenNothingPending() async throws {
        let engine = FixtureEngine(stats: [stat("Business", slug: "business", running: true)])
        let store = StatsStore(engine: engine, clock: ImmediateClock())
        await store.checkSignInPending()
        let mode = await MainActor.run { store.signInMode }
        XCTAssertNil(mode)
    }

    // MARK: EngineClient — real Process boundary decode

    private func fakeEngine(_ body: String) throws -> URL {
        let tmp = FileManager.default.temporaryDirectory
            .appendingPathComponent("fake-engine-\(UUID().uuidString).sh")
        try "#!/bin/bash\n\(body)\n".write(to: tmp, atomically: true, encoding: .utf8)
        try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: tmp.path)
        return tmp
    }

    func testClientDecodesSignInJSON() async throws {
        let tmp = try fakeEngine(
            #"[ "$1" = signin ] && printf '%s' '{"target":"business","closed":["default","work"]}'"#)
        defer { try? FileManager.default.removeItem(at: tmp) }
        let client = EngineClient(enginePath: tmp.path)
        let result = try await client.signIn("business")
        XCTAssertEqual(result, SignInResult(target: "business", closed: ["default", "work"]))
    }

    func testClientThrowsOnSignInErrToken() async throws {
        let tmp = try fakeEngine(#"printf '%s' 'err not found'"#)
        defer { try? FileManager.default.removeItem(at: tmp) }
        let client = EngineClient(enginePath: tmp.path)
        var thrown: Error?
        do { _ = try await client.signIn("nosuch") } catch { thrown = error }
        XCTAssertEqual(thrown as? EngineError, EngineError.actionFailed("err not found"))
    }

    func testClientDecodesRestoreAndState() async throws {
        let tmp = try fakeEngine("""
        [ "$1" = signinrestore ] && printf '%s' '{"restored":["default"]}'
        [ "$1" = signinstate ] && printf '%s' '{"pending":[]}'
        """)
        defer { try? FileManager.default.removeItem(at: tmp) }
        let client = EngineClient(enginePath: tmp.path)
        let restored = try await client.signInRestore()
        XCTAssertEqual(restored, ["default"])
        let pending = try await client.signInState()
        XCTAssertEqual(pending, [])
    }

    func testClientRemoteTtyEmptyMeansNil() async throws {
        let tmp = try fakeEngine("""
        [ "$2" = work ] && printf '%s' '/dev/ttys004'
        exit 0
        """)
        defer { try? FileManager.default.removeItem(at: tmp) }
        let client = EngineClient(enginePath: tmp.path)
        let attached = try await client.remoteTty("work")
        XCTAssertEqual(attached, "/dev/ttys004")
        let none = try await client.remoteTty("idle")
        XCTAssertNil(none)
    }

    static let allTests: [(String, (SignInTests) -> () async throws -> Void)] = [
        ("testBeginSignInEntersModeWithClosedInstances", testBeginSignInEntersModeWithClosedInstances),
        ("testBeginSignInSkipsModeWhenNothingWasClosed", testBeginSignInSkipsModeWhenNothingWasClosed),
        ("testRestoreLeavesModeAndDismissClears", testRestoreLeavesModeAndDismissClears),
        ("testRestoreFailureKeepsTheModeVisible", testRestoreFailureKeepsTheModeVisible),
        ("testCheckSignInPendingRecoversAfterRelaunch", testCheckSignInPendingRecoversAfterRelaunch),
        ("testCheckSignInPendingNoopsWhenNothingPending", testCheckSignInPendingNoopsWhenNothingPending),
        ("testClientDecodesSignInJSON", testClientDecodesSignInJSON),
        ("testClientThrowsOnSignInErrToken", testClientThrowsOnSignInErrToken),
        ("testClientDecodesRestoreAndState", testClientDecodesRestoreAndState),
        ("testClientRemoteTtyEmptyMeansNil", testClientRemoteTtyEmptyMeansNil),
    ]
}
