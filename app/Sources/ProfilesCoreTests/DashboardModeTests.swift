import XCTest
import ProfilesCore

final class DashboardModeTests: XCTestCase {
    private func profile(_ name: String, isDefault: Bool = false) -> ProfileStat {
        ProfileStat(name: name, slug: isDefault ? "" : name.lowercased(), running: true,
                    cpu: 1, mem: 1, procs: 1, ptys: 0, ptmx: 0, ptmxMax: 256, disk: 0,
                    opens: 0, last: "", color: "#000000", remote: false)
    }

    /// Before the first stats tick → loading, regardless of roster.
    func testNotLoadedIsLoading() {
        XCTAssertEqual(dashboardMode(profiles: [], hasLoadedOnce: false), .loading)
        XCTAssertEqual(dashboardMode(profiles: [profile("Work")], hasLoadedOnce: false), .loading)
    }

    /// Loaded with ONLY the always-present default instance → empty (onboarding).
    /// This is the regression guard: the engine always emits the default, so a
    /// fresh-install user with zero user profiles must still reach the empty state.
    func testLoadedWithOnlyDefaultIsEmpty() {
        let only = [profile("Claude (default)", isDefault: true)]
        XCTAssertEqual(dashboardMode(profiles: only, hasLoadedOnce: true), .empty)
    }

    /// Loaded with at least one user (non-default) profile → content.
    func testLoadedWithUserProfileIsContent() {
        let roster = [profile("Claude (default)", isDefault: true), profile("Work")]
        XCTAssertEqual(dashboardMode(profiles: roster, hasLoadedOnce: true), .content)
    }

    /// Loaded with a truly empty array → empty (vacuously: allSatisfy is true for []).
    func testLoadedEmptyArrayIsEmpty() {
        XCTAssertEqual(dashboardMode(profiles: [], hasLoadedOnce: true), .empty)
    }

    static let allTests: [(String, (DashboardModeTests) -> () async throws -> Void)] = [
        ("testNotLoadedIsLoading", testNotLoadedIsLoading),
        ("testLoadedWithOnlyDefaultIsEmpty", testLoadedWithOnlyDefaultIsEmpty),
        ("testLoadedWithUserProfileIsContent", testLoadedWithUserProfileIsContent),
        ("testLoadedEmptyArrayIsEmpty", testLoadedEmptyArrayIsEmpty),
    ]
}
