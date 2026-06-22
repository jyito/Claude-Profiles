@_exported import Foundation

// Single shared failure sink — there is NO cross-test isolation: the runner
// `reset()`s it before each case and reads `failures` right after. Test bodies
// must therefore finish recording within their own `await` — never spawn a
// detached or un-awaited Task that calls an XCTAssert later, or its failure
// lands in (and is attributed to) whichever case happens to be running then.
public final class _XCTState: @unchecked Sendable {
    public static let shared = _XCTState()
    public private(set) var failures: [String] = []
    public func reset() { failures = [] }
    public func record(_ message: String, _ file: StaticString, _ line: UInt) {
        failures.append("    \(file):\(line): \(message)")
    }
}

open class XCTestCase {
    public required init() {}
    open func setUp() {}
    open func tearDown() {}
}

public func XCTFail(_ message: String = "XCTFail", file: StaticString = #file, line: UInt = #line) {
    _XCTState.shared.record(message, file, line)
}

public func XCTAssertTrue(_ expr: @autoclosure () throws -> Bool, _ message: String = "expected true",
                          file: StaticString = #file, line: UInt = #line) {
    do { if try !expr() { _XCTState.shared.record(message, file, line) } }
    catch { _XCTState.shared.record("threw: \(error)", file, line) }
}

public func XCTAssertFalse(_ expr: @autoclosure () throws -> Bool, _ message: String = "expected false",
                           file: StaticString = #file, line: UInt = #line) {
    do { if try expr() { _XCTState.shared.record(message, file, line) } }
    catch { _XCTState.shared.record("threw: \(error)", file, line) }
}

public func XCTAssertEqual<T: Equatable>(_ a: @autoclosure () throws -> T, _ b: @autoclosure () throws -> T,
                                         _ message: String = "", file: StaticString = #file, line: UInt = #line) {
    do { let av = try a(); let bv = try b()
        if av != bv { _XCTState.shared.record(message.isEmpty ? "(\(av)) != (\(bv))" : message, file, line) } }
    catch { _XCTState.shared.record("threw: \(error)", file, line) }
}

public func XCTAssertEqual(_ a: @autoclosure () -> Double, _ b: @autoclosure () -> Double, accuracy: Double,
                           _ message: String = "", file: StaticString = #file, line: UInt = #line) {
    let av = a(); let bv = b()
    if abs(av - bv) > accuracy { _XCTState.shared.record(message.isEmpty ? "(\(av)) != (\(bv)) ± \(accuracy)" : message, file, line) }
}

public func XCTAssertNil(_ v: @autoclosure () throws -> Any?, _ message: String = "expected nil",
                         file: StaticString = #file, line: UInt = #line) {
    do { if try v() != nil { _XCTState.shared.record(message, file, line) } }
    catch { _XCTState.shared.record("threw: \(error)", file, line) }
}

public func XCTAssertNotNil(_ v: @autoclosure () throws -> Any?, _ message: String = "expected non-nil",
                            file: StaticString = #file, line: UInt = #line) {
    do { if try v() == nil { _XCTState.shared.record(message, file, line) } }
    catch { _XCTState.shared.record("threw: \(error)", file, line) }
}

public func XCTAssertThrowsError<T>(_ expr: @autoclosure () async throws -> T, _ message: String = "expected throw",
                                    file: StaticString = #file, line: UInt = #line) async {
    do { _ = try await expr(); _XCTState.shared.record(message, file, line) }
    catch { /* expected */ }
}

public func XCTAssertNoThrow<T>(_ expr: @autoclosure () async throws -> T, _ message: String = "",
                                file: StaticString = #file, line: UInt = #line) async {
    do { _ = try await expr() }
    catch { _XCTState.shared.record(message.isEmpty ? "unexpected throw: \(error)" : message, file, line) }
}
