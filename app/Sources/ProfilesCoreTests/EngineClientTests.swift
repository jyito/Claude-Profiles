import XCTest
import ProfilesCore

final class EngineClientTests: XCTestCase {
    func testRealProcessBridgeDecodes() async throws {
        // Thin proof the real Process boundary runs bash + decodes — uses a fake engine.
        let tmp = FileManager.default.temporaryDirectory.appendingPathComponent("fake-engine-\(UUID().uuidString).sh")
        let script = """
        #!/bin/bash
        [ "$1" = stats ] && printf '%s' '[{"name":"X","slug":"x","running":true,"cpu":1,"mem":2,"procs":1,"ptys":0,"ptmx":7,"ptmxMax":256,"disk":-1,"opens":0,"last":"","color":"#000000","remote":false}]'
        """
        try script.write(to: tmp, atomically: true, encoding: .utf8)
        try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: tmp.path)
        defer { try? FileManager.default.removeItem(at: tmp) }

        let client = EngineClient(enginePath: tmp.path)
        let stats = try await client.stats()
        XCTAssertEqual(stats.count, 1)
        XCTAssertEqual(stats[0].ptmx, 7)
    }

    func testRunThrowsOnEngineErrorToken() async throws {
        // engine.sh action verbs exit 0 even on failure, printing an error token to
        // stdout (e.g. `refused`, `err badindex`). `run` must throw on those, else a
        // failed action (closeterm/setbadge/purge…) silently reports success.
        let tmp = FileManager.default.temporaryDirectory.appendingPathComponent("fake-engine-\(UUID().uuidString).sh")
        let script = """
        #!/bin/bash
        # Mimic a refused action: print the token, exit 0.
        printf '%s' 'refused'
        exit 0
        """
        try script.write(to: tmp, atomically: true, encoding: .utf8)
        try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: tmp.path)
        defer { try? FileManager.default.removeItem(at: tmp) }

        let client = EngineClient(enginePath: tmp.path)
        await XCTAssertThrowsError(try await client.run(["closeterm", "x", "/dev/ttys999"]))

        // And confirm it's the right case (actionFailed carrying the token).
        var thrown: Error?
        do { try await client.run(["closeterm", "x", "/dev/ttys999"]) }
        catch { thrown = error }
        XCTAssertEqual(thrown as? EngineError, EngineError.actionFailed("refused"))
    }

    static let allTests: [(String, (EngineClientTests) -> () async throws -> Void)] = [
        ("testRealProcessBridgeDecodes", testRealProcessBridgeDecodes),
        ("testRunThrowsOnEngineErrorToken", testRunThrowsOnEngineErrorToken),
    ]
}
