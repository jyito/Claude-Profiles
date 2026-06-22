import XCTest
@testable import ProfilesCore

final class ProfileStatTests: XCTestCase {
    func testDecodesAllFieldsAndDefaultInstance() async throws {
        let json = """
        [
          {"name":"Business","slug":"business","running":true,"cpu":61.1,"mem":2230,"procs":7,"ptys":3,"ptmx":12,"ptmxMax":256,"disk":1400,"opens":42,"last":"2026-06-20 08:00","color":"#3B7DD8","remote":false},
          {"name":"Claude (default)","slug":"","running":true,"cpu":18,"mem":2230,"procs":5,"ptys":2,"ptmx":39,"ptmxMax":256,"disk":-1,"opens":0,"last":"","color":"#6E6A62","remote":true}
        ]
        """.data(using: .utf8)!
        let stats = try ProfileStat.decodeList(from: json)
        XCTAssertEqual(stats.count, 2)
        XCTAssertEqual(stats[0].name, "Business")
        XCTAssertEqual(stats[0].cpu, 61.1, accuracy: 0.001)
        XCTAssertEqual(stats[0].ptmx, 12)
        XCTAssertFalse(stats[0].isDefault)
        XCTAssertEqual(stats[0].id, "business")
        XCTAssertEqual(stats[1].slug, "")
        XCTAssertTrue(stats[1].isDefault)
        XCTAssertEqual(stats[1].id, "default")
        XCTAssertEqual(stats[1].disk, -1)
        XCTAssertTrue(stats[1].remote)
    }

    func testMalformedThrowsAndEmptyDecodes() async throws {
        await XCTAssertThrowsError(try ProfileStat.decodeList(from: Data("{not json".utf8)))
        let empty = try ProfileStat.decodeList(from: Data("[]".utf8))
        XCTAssertEqual(empty.count, 0)
    }

    static let allTests: [(String, (ProfileStatTests) -> () async throws -> Void)] = [
        ("testDecodesAllFieldsAndDefaultInstance", testDecodesAllFieldsAndDefaultInstance),
        ("testMalformedThrowsAndEmptyDecodes", testMalformedThrowsAndEmptyDecodes),
    ]
}
