import XCTest
import ProfilesCore

final class SortTests: XCTestCase {
    private func stat(_ name: String, slug: String, running: Bool) -> ProfileStat {
        ProfileStat(name: name, slug: slug, running: running, cpu: 0, mem: 0, procs: 0, ptys: 0,
                    ptmx: 0, ptmxMax: 256, disk: 0, opens: 0, last: "", color: "#000000", remote: false)
    }
    func testAliveFirstThenStableByName() async throws {
        let input = [
            stat("Zed", slug: "zed", running: false),
            stat("Business", slug: "business", running: true),
            stat("Claude (default)", slug: "", running: true),
            stat("Apple", slug: "apple", running: false),
            stat("Research", slug: "research", running: true),
        ]
        let out = sortProfiles(input).map(\.effSlug)
        // default pinned first → running (by name) → stopped (by name)
        XCTAssertEqual(out, ["default", "business", "research", "apple", "zed"])
    }
    static let allTests: [(String, (SortTests) -> () async throws -> Void)] = [
        ("testAliveFirstThenStableByName", testAliveFirstThenStableByName),
    ]
}
