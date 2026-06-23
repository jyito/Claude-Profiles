import XCTest
import ProfilesCore

final class PtmxHysteresisTests: XCTestCase {
    /// Feed a series of `(used, terminals)` pairs and return the final state. `max`
    /// (the ptmx ceiling) is fixed high — it no longer gates color, so it's only here
    /// to prove a huge ceiling never matters.
    private func feed(_ samples: [(used: Int, terminals: Int)], max: Int = 512) -> AlertState {
        var h = PtmxHysteresis()
        var state = AlertState.calm
        for s in samples {
            state = h.ingest(PtmxSample(used: s.used, max: max, terminals: s.terminals))
        }
        return state
    }

    // Flat: held handles exactly match live terminals — never a leak, at any level.
    func testFlatEqualsTerminalsIsCalm() async throws {
        XCTAssertEqual(feed([(2, 2), (2, 2), (2, 2)]), .calm)
        // Even a *high* flat count is calm if it equals the terminals (no excess).
        XCTAssertEqual(feed([(40, 40), (40, 40)]), .calm)
    }

    // Opening terminals: `used` rises but tracks `terminals` 1:1 — no excess, so the
    // rising count must NOT trip the gauge (the key false-positive guard).
    func testOpeningTerminalsStaysCalm() async throws {
        XCTAssertEqual(feed([(2, 2), (4, 4), (6, 6), (8, 8)]), .calm)
    }

    // A real leak: terminals are stable/low while held handles climb past them.
    // (The leak condition holds across enough ticks to satisfy the sustain counter.)
    func testExcessAndClimbingIsLeaking() async throws {
        XCTAssertEqual(feed([(2, 2), (4, 2), (6, 2), (8, 2)]), .leaking)
    }

    // Sustain: the leak condition (excess + climbing) must hold for `sustainTicks`
    // CONSECUTIVE ticks before the state flips. One qualifying tick is not enough.
    func testOneLeakTickStaysCalm() async throws {
        // floor 2; (4,2) qualifies (excess + climb 2) but it's only the 1st tick → calm.
        XCTAssertEqual(feed([(2, 2), (4, 2)]), .calm)
    }

    // Two consecutive qualifying ticks still aren't enough (sustain is 3).
    func testTwoLeakTicksStayCalm() async throws {
        // (4,2) = tick 1, (5,2) = tick 2 — both qualify, but counter hasn't hit 3 → calm.
        XCTAssertEqual(feed([(2, 2), (4, 2), (5, 2)]), .calm)
    }

    // The third consecutive qualifying tick flips to leaking.
    func testThirdLeakTickFlipsToLeaking() async throws {
        // (4,2),(5,2),(6,2) = three consecutive qualifying ticks → leaking on the 3rd.
        XCTAssertEqual(feed([(2, 2), (4, 2), (5, 2), (6, 2)]), .leaking)
    }

    // An interrupted run resets the counter: if the condition breaks at tick 2, the
    // streak restarts — three MORE consecutive ticks are then needed.
    func testInterruptedLeakRunResetsCounter() async throws {
        // tick 1 qualifies (4,2); tick 2 breaks it (used==terminals at (4,4) → no excess)
        // — counter resets. Then (6,4),(7,4) is only a fresh 2-tick streak → still calm.
        XCTAssertEqual(feed([(2, 2), (4, 2), (4, 4), (6, 4), (7, 4)]), .calm)
        // ...and one more consecutive qualifying tick after the reset finally flips it.
        XCTAssertEqual(feed([(2, 2), (4, 2), (4, 4), (6, 4), (7, 4), (8, 4)]), .leaking)
    }

    // Excess WITHOUT climbing isn't enough — a flat excess (e.g. one stuck handle that
    // never grows) shouldn't alarm; the leak signal is a *rising* pool.
    func testFlatExcessIsCalm() async throws {
        // used sits 1 above terminals but never climbs by climbDelta → calm.
        XCTAssertEqual(feed([(3, 2), (3, 2), (3, 2)]), .calm)
    }

    // Climbing WITHOUT excess isn't enough either — covered by openingTerminals, but
    // assert the pure "climb but used==terminals" case directly.
    func testClimbingWithoutExcessIsCalm() async throws {
        XCTAssertEqual(feed([(2, 2), (10, 10)]), .calm)
    }

    // Restart drops the held pool back to ~terminals → the gauge clears to calm.
    func testDropAfterRestartIsCalm() async throws {
        // climb into leaking, then a restart frees the masters (used collapses to 2,
        // matching 2 terminals) → calm again.
        XCTAssertEqual(feed([(2, 2), (6, 2), (10, 2), (2, 2)]), .calm)
    }

    // Hysteresis: once leaking, a small wobble down (still well above terminals and
    // above the floor) keeps it leaking — it only clears when handles are actually
    // freed (back to/below the floor margin) or used drops to terminals.
    func testHysteresisHoldsLeakingThroughWobble() async throws {
        // sustain into leaking (3 qualifying ticks), then a 1-handle dip to 7 — still
        // excess, still near the high water → stays leaking (avoids flicker).
        XCTAssertEqual(feed([(2, 2), (6, 2), (7, 2), (8, 2), (7, 2)]), .leaking)
    }

    // The leak clears when the pool falls back toward the floor (handles freed) even
    // without a full restart-to-terminals collapse.
    func testLeakingClearsWhenHandlesFreed() async throws {
        // sustain to leaking (3 qualifying ticks climbing to 12), then drain back to 3
        // (floor was 2; 3 <= floor+margin) → calm.
        XCTAssertEqual(feed([(2, 2), (4, 2), (8, 2), (12, 2), (3, 2)]), .calm)
    }

    // The floor tracks the running minimum: a dip re-bases the floor so a later climb
    // is measured from the NEW low, not the original.
    func testFloorRebasesOnDip() async throws {
        // 2→3 (excess but < climbDelta from floor 2 → calm), drop to 2 (floor still 2),
        // then climb 2→4→5→6 from that floor — three sustained qualifying ticks → leaking.
        XCTAssertEqual(feed([(2, 2), (3, 2), (2, 2), (4, 2), (5, 2), (6, 2)]), .leaking)
    }

    // Zero ceiling (sysctl unreadable) must never crash or alarm by itself — the rule
    // is ceiling-independent now, but assert the divide-by-zero guard still holds.
    func testZeroCeilingDoesNotCrash() async throws {
        // used==terminals → calm regardless of a 0 max.
        XCTAssertEqual(feed([(5, 5)], max: 0), .calm)
        // a genuine sustained leak still reads leaking with an unreadable ceiling.
        XCTAssertEqual(feed([(2, 2), (6, 2), (8, 2), (10, 2)], max: 0), .leaking)
    }

    // climbDelta boundary: a climb of exactly climbDelta above the floor (with excess)
    // qualifies; one less does not. (Sustained over the required ticks to flip.)
    func testClimbDeltaBoundary() async throws {
        // floor 2; each tick is exactly +climbDelta(2)-or-more above floor with excess,
        // sustained for 3 ticks → leaking.
        XCTAssertEqual(feed([(2, 2), (4, 2), (5, 2), (6, 2)]), .leaking)
        // floor 2, climb to 3 (= +1, under climbDelta) with excess, however many ticks
        // → never qualifies → calm.
        XCTAssertEqual(feed([(2, 2), (3, 2), (3, 2), (3, 2)]), .calm)
    }

    static let allTests: [(String, (PtmxHysteresisTests) -> () async throws -> Void)] = [
        ("testFlatEqualsTerminalsIsCalm", testFlatEqualsTerminalsIsCalm),
        ("testOpeningTerminalsStaysCalm", testOpeningTerminalsStaysCalm),
        ("testExcessAndClimbingIsLeaking", testExcessAndClimbingIsLeaking),
        ("testOneLeakTickStaysCalm", testOneLeakTickStaysCalm),
        ("testTwoLeakTicksStayCalm", testTwoLeakTicksStayCalm),
        ("testThirdLeakTickFlipsToLeaking", testThirdLeakTickFlipsToLeaking),
        ("testInterruptedLeakRunResetsCounter", testInterruptedLeakRunResetsCounter),
        ("testFlatExcessIsCalm", testFlatExcessIsCalm),
        ("testClimbingWithoutExcessIsCalm", testClimbingWithoutExcessIsCalm),
        ("testDropAfterRestartIsCalm", testDropAfterRestartIsCalm),
        ("testHysteresisHoldsLeakingThroughWobble", testHysteresisHoldsLeakingThroughWobble),
        ("testLeakingClearsWhenHandlesFreed", testLeakingClearsWhenHandlesFreed),
        ("testFloorRebasesOnDip", testFloorRebasesOnDip),
        ("testZeroCeilingDoesNotCrash", testZeroCeilingDoesNotCrash),
        ("testClimbDeltaBoundary", testClimbDeltaBoundary),
    ]
}
