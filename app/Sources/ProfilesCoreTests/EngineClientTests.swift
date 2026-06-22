import XCTest
@testable import ProfilesCore

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

    static let allTests: [(String, (EngineClientTests) -> () async throws -> Void)] = [
        ("testRealProcessBridgeDecodes", testRealProcessBridgeDecodes),
    ]
}
