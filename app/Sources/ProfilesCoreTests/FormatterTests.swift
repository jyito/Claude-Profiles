import XCTest
@testable import ProfilesCore

final class FormatterTests: XCTestCase {
    func testMemory() async throws {
        XCTAssertEqual(formatMemoryMB(0), "0 MB")
        XCTAssertEqual(formatMemoryMB(2230), "2,230 MB")
        XCTAssertEqual(formatMemoryMB(8400), "8.2 GB")     // 8400/1024 = 8.20
    }
    func testCPUNotClamped() async throws {
        XCTAssertEqual(formatCPU(0), "0%")
        XCTAssertEqual(formatCPU(61.1), "61.1%")
        XCTAssertEqual(formatCPU(240), "240%")             // per-core > 100% must NOT clamp
    }
    func testDiskSentinel() async throws {
        XCTAssertEqual(formatDiskMB(-1), "—")              // default instance: hidden
        XCTAssertEqual(formatDiskMB(512), "512 MB")
        XCTAssertEqual(formatDiskMB(1400), "1.4 GB")
    }
    func testHandles() async throws {
        XCTAssertEqual(formatHandles(used: 12, max: 256), "12 / 256 handles")
    }
    static let allTests: [(String, (FormatterTests) -> () async throws -> Void)] = [
        ("testMemory", testMemory), ("testCPUNotClamped", testCPUNotClamped),
        ("testDiskSentinel", testDiskSentinel), ("testHandles", testHandles),
    ]
}
