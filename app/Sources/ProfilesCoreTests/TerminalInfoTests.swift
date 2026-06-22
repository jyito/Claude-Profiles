import XCTest
import ProfilesCore

final class TerminalInfoTests: XCTestCase {
    func testDecodesAllFieldsAndIdleSentinel() async throws {
        // Mirrors `engine.sh cmd_terminals`: [{dev,pid,cmd,idle}], idle = -1 if unknown.
        let json = """
        [
          {"dev":"/dev/ttys003","pid":4821,"cmd":"node /opt/claude/pty.js","idle":92},
          {"dev":"/dev/ttys011","pid":4822,"cmd":"-zsh","idle":-1}
        ]
        """.data(using: .utf8)!
        let terms = try TerminalInfo.decodeList(from: json)
        XCTAssertEqual(terms.count, 2)
        XCTAssertEqual(terms[0].dev, "/dev/ttys003")
        XCTAssertEqual(terms[0].pid, 4821)
        XCTAssertEqual(terms[0].cmd, "node /opt/claude/pty.js")
        XCTAssertEqual(terms[0].idle, 92)
        XCTAssertEqual(terms[0].id, "/dev/ttys003")        // id == dev (Identifiable by device)
        XCTAssertEqual(terms[1].idle, -1)                  // unknown-idle sentinel round-trips
        XCTAssertEqual(terms[1].id, terms[1].dev)
    }

    func testMalformedThrowsAndEmptyDecodes() async throws {
        await XCTAssertThrowsError(try TerminalInfo.decodeList(from: Data("{not json".utf8)))
        let empty = try TerminalInfo.decodeList(from: Data("[]".utf8))
        XCTAssertEqual(empty.count, 0)
    }

    static let allTests: [(String, (TerminalInfoTests) -> () async throws -> Void)] = [
        ("testDecodesAllFieldsAndIdleSentinel", testDecodesAllFieldsAndIdleSentinel),
        ("testMalformedThrowsAndEmptyDecodes", testMalformedThrowsAndEmptyDecodes),
    ]
}
