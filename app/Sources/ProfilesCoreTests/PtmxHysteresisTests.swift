import XCTest
import ProfilesCore

final class PtmxHysteresisTests: XCTestCase {
    private func feed(_ ratios: [Double], max: Int = 100) -> AlertState {
        var h = PtmxHysteresis()
        var state = AlertState.calm
        for r in ratios { state = h.ingest(PtmxSample(used: Int((r * Double(max)).rounded()), max: max)) }
        return state
    }

    func testCalmBelowWarn() async throws {
        XCTAssertEqual(feed([0.10, 0.50, 0.74]), .calm)
    }
    func testWarnAtSeventyFive() async throws {
        XCTAssertEqual(feed([0.50, 0.76]), .warning(climbing: true))     // rising into warn band
    }
    func testNoCriticalUntilSustained() async throws {
        // one tick at 92% must NOT be critical yet (needs 3 consecutive)
        XCTAssertEqual(feed([0.50, 0.92]), .warning(climbing: true))
        XCTAssertEqual(feed([0.92, 0.92]), .warning(climbing: false))   // 2 ticks: still not critical
    }
    func testCriticalAfterThreeConsecutive() async throws {
        XCTAssertEqual(feed([0.92, 0.92, 0.92]), .critical)
    }
    func testBreachStreakResetsOnDip() async throws {
        // 2 breach ticks, a dip resets the streak, so the next single breach isn't critical
        XCTAssertEqual(feed([0.92, 0.92, 0.50, 0.92]), .warning(climbing: true))
    }
    func testHysteresisHoldsCriticalUntilBelowEighty() async throws {
        // escalate, then sit at 85% — must STAY critical (de-escalates only < 80%)
        XCTAssertEqual(feed([0.92, 0.92, 0.92, 0.85]), .critical)
        // drop below the 80% low-water → leaves critical (still ≥75% → warning)
        XCTAssertEqual(feed([0.92, 0.92, 0.92, 0.79]), .warning(climbing: false))
    }
    func testBoundaryArithmetic() async throws {
        XCTAssertEqual(feed([0.90, 0.90, 0.90]), .critical)             // exactly 90% counts as breach
        XCTAssertEqual(feed([0.75]), .warning(climbing: true))         // exactly 75% is warning
        XCTAssertEqual(feed([0.74]), .calm)                            // just under
    }
    func testZeroCeilingIsCalm() async throws {
        var h = PtmxHysteresis()
        XCTAssertEqual(h.ingest(PtmxSample(used: 9, max: 0)), .calm)    // ptmxMax unreadable → no divide-by-zero, no alarm
    }
    static let allTests: [(String, (PtmxHysteresisTests) -> () async throws -> Void)] = [
        ("testCalmBelowWarn", testCalmBelowWarn),
        ("testWarnAtSeventyFive", testWarnAtSeventyFive),
        ("testNoCriticalUntilSustained", testNoCriticalUntilSustained),
        ("testCriticalAfterThreeConsecutive", testCriticalAfterThreeConsecutive),
        ("testBreachStreakResetsOnDip", testBreachStreakResetsOnDip),
        ("testHysteresisHoldsCriticalUntilBelowEighty", testHysteresisHoldsCriticalUntilBelowEighty),
        ("testBoundaryArithmetic", testBoundaryArithmetic),
        ("testZeroCeilingIsCalm", testZeroCeilingIsCalm),
    ]
}
