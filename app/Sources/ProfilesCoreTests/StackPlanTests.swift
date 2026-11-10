import XCTest
import CoreGraphics
import ProfilesCore

final class StackPlanTests: XCTestCase {

    private let screen = CGRect(x: 0, y: 25, width: 1440, height: 875)   // a typical visibleFrame

    func testCountsAndGridShape() async throws {
        XCTAssertEqual(stackFrames(in: screen, count: 0).count, 0)
        XCTAssertEqual(stackFrames(in: screen, count: 1).count, 1)
        // 1 fills the whole frame
        XCTAssertEqual(stackFrames(in: screen, count: 1)[0], screen)
        // 2 and 3 stay a single side-by-side row (every frame full height)
        for n in [2, 3] {
            let frames = stackFrames(in: screen, count: n)
            XCTAssertEqual(frames.count, n)
            for f in frames { XCTAssertEqual(f.height, screen.height, accuracy: 0.5) }
        }
        // 4 → 2×2: two distinct y rows, two distinct x columns
        let four = stackFrames(in: screen, count: 4)
        XCTAssertEqual(Set(four.map { Int($0.minY.rounded()) }).count, 2)
        XCTAssertEqual(Set(four.map { Int($0.minX.rounded()) }).count, 2)
        // 5 → 2 rows × 3 columns (columns preferred over rows)
        let five = stackFrames(in: screen, count: 5)
        XCTAssertEqual(Set(five.map { Int($0.minY.rounded()) }).count, 2)
        XCTAssertEqual(Set(five.map { Int($0.minX.rounded()) }).count, 3)
    }

    func testFramesStayWithinBoundsAndNeverOverlap() async throws {
        for n in 1...6 {
            let frames = stackFrames(in: screen, count: n)
            for f in frames {
                XCTAssertTrue(screen.insetBy(dx: -0.5, dy: -0.5).contains(f),
                              "n=\(n): \(f) escapes \(screen)")
            }
            for i in 0..<frames.count {
                for j in (i + 1)..<frames.count {
                    XCTAssertFalse(frames[i].intersects(frames[j]),
                                   "n=\(n): frames \(i)/\(j) overlap")
                }
            }
        }
    }

    func testRowMajorFromVisualTopLeft() async throws {
        // Cocoa y-up: the first frame is the visual top-left — leftmost x, topmost
        // (largest) y. Within a row, x strictly increases.
        let frames = stackFrames(in: screen, count: 4)
        XCTAssertEqual(frames[0].minX, screen.minX, accuracy: 0.5)
        XCTAssertEqual(frames[0].maxY, screen.maxY, accuracy: 0.5)
        XCTAssertLessThan(frames[0].minX, frames[1].minX)          // row 0: left → right
        XCTAssertGreaterThan(frames[0].minY, frames[2].minY)       // row 1 sits below row 0
    }

    func testEqualTileSizesPerLayout() async throws {
        for n in 2...6 {
            let frames = stackFrames(in: screen, count: n)
            let w0 = frames[0].width, h0 = frames[0].height
            for f in frames {
                XCTAssertEqual(f.width, w0, accuracy: 0.5)
                XCTAssertEqual(f.height, h0, accuracy: 0.5)
            }
        }
    }

    func testDegenerateBoundsReturnEmpty() async throws {
        XCTAssertTrue(stackFrames(in: .zero, count: 2).isEmpty)
        XCTAssertTrue(stackFrames(in: CGRect(x: 0, y: 0, width: -10, height: 100), count: 2).isEmpty)
    }

    static let allTests: [(String, (StackPlanTests) -> () async throws -> Void)] = [
        ("testCountsAndGridShape", testCountsAndGridShape),
        ("testFramesStayWithinBoundsAndNeverOverlap", testFramesStayWithinBoundsAndNeverOverlap),
        ("testRowMajorFromVisualTopLeft", testRowMajorFromVisualTopLeft),
        ("testEqualTileSizesPerLayout", testEqualTileSizesPerLayout),
        ("testDegenerateBoundsReturnEmpty", testDegenerateBoundsReturnEmpty),
    ]
}
