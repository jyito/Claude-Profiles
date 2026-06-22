import Foundation
import XCTest

struct TestTally { var passed = 0; var failed = 0 }

func runSuite<T: XCTestCase>(_ suite: String,
                             _ tests: [(String, (T) -> () async throws -> Void)],
                             _ tally: inout TestTally) async {
    for (name, fn) in tests {
        let instance = T()
        instance.setUp()
        _XCTState.shared.reset()
        do { try await fn(instance)() }
        catch { _XCTState.shared.record("unexpected throw: \(error)", #file, #line) }
        instance.tearDown()
        if _XCTState.shared.failures.isEmpty {
            tally.passed += 1
            print("Test Case '\(suite).\(name)' passed.")
        } else {
            tally.failed += 1
            print("Test Case '\(suite).\(name)' FAILED.")
            for f in _XCTState.shared.failures { print(f) }
        }
    }
}

@main
struct ProfilesCoreTestsMain {
    static func main() async {
        var tally = TestTally()
        await runSuite("ProfileStatTests", ProfileStatTests.allTests, &tally)
        await runSuite("FormatterTests", FormatterTests.allTests, &tally)
        await runSuite("SortTests", SortTests.allTests, &tally)
        await runSuite("PtmxHysteresisTests", PtmxHysteresisTests.allTests, &tally)
        await runSuite("StatsStoreTests", StatsStoreTests.allTests, &tally)
        await runSuite("EngineClientTests", EngineClientTests.allTests, &tally)
        print("Executed \(tally.passed + tally.failed) tests, with \(tally.failed) failures")
        exit(tally.failed == 0 ? 0 : 1)
    }
}
