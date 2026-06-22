# SwiftUI Dashboard — Phase 1 (Foundation) Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Stand up the real Swift package, a working no-Xcode test harness + green macOS CI, the four testability seams, and a fully unit-tested `ProfilesCore` (the `PtmxHysteresis` state machine, stats decode, formatters, sort) — the tested foundation every later phase builds on.

**Architecture:** A committed SPM package at `app/`. A SwiftUI-free `ProfilesCore` library holds the pure logic + the `EngineRunning`/`PollClock` seams + `EngineClient` (real `Process`) + the `@Observable StatsStore`, so all of it is importable and unit-testable. A thin `Profiles` executable is the SwiftUI app shell (a stub this phase). Tests run via the spike-proven executable-runner pattern (a vendored `XCTest` shim target + `swift run`), because `swift test`/XCTest does not work under Command Line Tools.

**Tech Stack:** Swift 5.10 (Command Line Tools, no Xcode), SwiftUI, Observation, Foundation, Swift Charts (later phases). Tests: hand-rolled `XCTest` shim + executable runners. CI: GitHub Actions macOS runner. Zero third-party dependencies.

**Spec:** `docs/superpowers/specs/2026-06-22-swiftui-dashboard-design.md` + `docs/superpowers/specs/2026-06-22-swiftui-testing-strategy.md`.

---

## File structure (locked here)

```
app/
  Package.swift
  .gitignore                                  (.build/)
  Sources/
    ProfilesCore/                             (library — no SwiftUI; testable)
      ProfileStat.swift                       Codable model + decodeList
      Formatters.swift                        formatMemoryMB / formatCPU / formatDiskMB / formatHandles
      Sort.swift                              sortProfiles (alive-first)
      PtmxHysteresis.swift                    severity state machine (prime test target)
      EngineRunning.swift                     protocol + EngineError
      PollClock.swift                         protocol + RealClock + ImmediateClock
      EngineClient.swift                      real Process impl of EngineRunning
      FixtureEngine.swift                     test double impl of EngineRunning
      StatsStore.swift                        @MainActor @Observable store
    Profiles/                                 (executable — SwiftUI app shell; stub this phase)
      ProfilesApp.swift                       @main, minimal WindowGroup
    XCTest/                                   (library — vendored shim so `import XCTest` resolves)
      XCTest.swift
    ProfilesCoreTests/                        (executable test runner)
      TestRunner.swift                        @main + runSuite
      ProfileStatTests.swift
      FormatterTests.swift
      SortTests.swift
      PtmxHysteresisTests.swift
      StatsStoreTests.swift
      EngineClientTests.swift
    ProfilesSnapshotTests/                    (executable — proves ImageRenderer headless)
      SnapshotRunner.swift
```

Later phases add `ProfilesUI` (library, the views), real snapshot goldens, and `scripts/build.sh`/cutover wiring. Not this phase.

---

### Task 1: Scaffold the `app/` package

**Files:**
- Create: `app/Package.swift`
- Create: `app/.gitignore`
- Create: `app/Sources/ProfilesCore/Placeholder.swift`
- Create: `app/Sources/Profiles/ProfilesApp.swift`
- Modify: `.gitignore` (repo root — keep `app/.build/` out even if the nested ignore is missed)

- [ ] **Step 1: Create `app/Package.swift`**

```swift
// swift-tools-version:5.10
import PackageDescription

let package = Package(
    name: "Profiles",
    platforms: [.macOS(.v14)],
    targets: [
        .target(name: "ProfilesCore"),
        .target(name: "XCTest"),
        .executableTarget(name: "Profiles", dependencies: ["ProfilesCore"]),
        .executableTarget(name: "ProfilesCoreTests", dependencies: ["ProfilesCore", "XCTest"]),
        .executableTarget(name: "ProfilesSnapshotTests", dependencies: ["XCTest"]),
    ]
)
```

- [ ] **Step 2: Create `app/.gitignore`**

```
.build/
*.xcodeproj
.DS_Store
```

- [ ] **Step 3: Add a repo-root ignore line (belt and suspenders)**

Append to the repo-root `.gitignore`:

```
# SwiftUI app build artifacts
app/.build/
```

- [ ] **Step 4: Create a ProfilesCore placeholder so the library builds**

`app/Sources/ProfilesCore/Placeholder.swift`:

```swift
public enum ProfilesCore {
    public static let version = "0.0.1"
}
```

- [ ] **Step 5: Create the minimal SwiftUI app shell**

`app/Sources/Profiles/ProfilesApp.swift`:

```swift
import SwiftUI
import ProfilesCore

@main
struct ProfilesApp: App {
    var body: some Scene {
        WindowGroup("Claude Profiles") {
            Text("Claude Profiles \(ProfilesCore.version)")
                .frame(minWidth: 480, minHeight: 320)
        }
    }
}
```

- [ ] **Step 6: Verify the package builds**

Run: `cd app && swift build`
Expected: `Build complete!` (compiles ProfilesCore, Profiles, XCTest stub-less for now will warn that XCTest/test targets have no sources — that's fine until Task 2; if `swift build` errors on the empty `XCTest`/test targets, proceed to Task 2 which fills them, then build).

> Note: SPM requires every declared target to have at least one source file. If Step 6 errors with "Source files for target XCTest should be located under …", that's expected — Task 2 adds those sources. You may temporarily verify just the library with `swift build --target ProfilesCore`.

- [ ] **Step 7: Commit**

```bash
cd "$(git rev-parse --show-toplevel)"
git add .gitignore app/Package.swift app/.gitignore app/Sources/ProfilesCore/Placeholder.swift app/Sources/Profiles/ProfilesApp.swift
git commit -m "feat(app): scaffold the SwiftUI Package (ProfilesCore + app shell)"
```

---

### Task 2: Vendored `XCTest` shim + the test runner (empty registry)

**Files:**
- Create: `app/Sources/XCTest/XCTest.swift`
- Create: `app/Sources/ProfilesCoreTests/TestRunner.swift`

- [ ] **Step 1: Create the XCTest shim**

`app/Sources/XCTest/XCTest.swift`:

```swift
@_exported import Foundation

public final class _XCTState: @unchecked Sendable {
    public static let shared = _XCTState()
    public private(set) var failures: [String] = []
    public func reset() { failures = [] }
    public func record(_ message: String, _ file: StaticString, _ line: UInt) {
        failures.append("    \(file):\(line): \(message)")
    }
}

open class XCTestCase {
    public init() {}
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
```

- [ ] **Step 2: Create the runner with an empty registry**

`app/Sources/ProfilesCoreTests/TestRunner.swift`:

```swift
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
        // Suites are registered here as each is added (Tasks 3–7).
        print("Executed \(tally.passed + tally.failed) tests, with \(tally.failed) failures")
        exit(tally.failed == 0 ? 0 : 1)
    }
}
```

- [ ] **Step 3: Create a placeholder so the snapshot target compiles (filled in Task 8)**

`app/Sources/ProfilesSnapshotTests/SnapshotRunner.swift`:

```swift
@main
struct ProfilesSnapshotTestsMain {
    static func main() {
        print("snapshot runner: no cases yet")
    }
}
```

- [ ] **Step 4: Build everything and run the (empty) suite**

Run: `cd app && swift build && swift run ProfilesCoreTests`
Expected: build succeeds; output ends with `Executed 0 tests, with 0 failures`; exit code 0.
(A harmless `warning: could not determine XCTest paths` may print — ignore it; only the exit code matters.)

- [ ] **Step 5: Commit**

```bash
cd "$(git rev-parse --show-toplevel)"
git add app/Sources/XCTest app/Sources/ProfilesCoreTests app/Sources/ProfilesSnapshotTests
git commit -m "test(app): vendored XCTest shim + executable test runner (no-Xcode)"
```

---

### Task 3: `ProfileStat` + `decodeList` (TDD)

**Files:**
- Create: `app/Sources/ProfilesCoreTests/ProfileStatTests.swift`
- Create: `app/Sources/ProfilesCore/ProfileStat.swift`
- Modify: `app/Sources/ProfilesCoreTests/TestRunner.swift` (register the suite)

- [ ] **Step 1: Write the failing test**

`app/Sources/ProfilesCoreTests/ProfileStatTests.swift`:

```swift
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
```

- [ ] **Step 2: Register the suite in the runner**

In `app/Sources/ProfilesCoreTests/TestRunner.swift`, inside `main()`, replace the
`// Suites are registered here…` comment with:

```swift
        await runSuite("ProfileStatTests", ProfileStatTests.allTests, &tally)
```

- [ ] **Step 3: Run to verify it fails**

Run: `cd app && swift run ProfilesCoreTests`
Expected: build FAILS — "cannot find 'ProfileStat' in scope".

- [ ] **Step 4: Implement `ProfileStat`**

`app/Sources/ProfilesCore/ProfileStat.swift`:

```swift
import Foundation

public struct ProfileStat: Codable, Identifiable, Sendable, Equatable {
    public let name: String
    public let slug: String
    public let running: Bool
    public let cpu: Double
    public let mem: Double
    public let procs: Int
    public let ptys: Int
    public let ptmx: Int
    public let ptmxMax: Int
    public let disk: Int
    public let opens: Int
    public let last: String
    public let color: String
    public let remote: Bool

    public var isDefault: Bool { slug.isEmpty }
    /// The slug the engine expects for actions ("default" for the empty-slug default instance).
    public var effSlug: String { slug.isEmpty ? "default" : slug }
    public var id: String { effSlug }

    public static func decodeList(from data: Data) throws -> [ProfileStat] {
        try JSONDecoder().decode([ProfileStat].self, from: data)
    }
}
```

- [ ] **Step 5: Run to verify it passes**

Run: `cd app && swift run ProfilesCoreTests`
Expected: `Test Case 'ProfileStatTests.testDecodesAllFieldsAndDefaultInstance' passed.`, the second passes too, and `Executed 2 tests, with 0 failures`, exit 0.

- [ ] **Step 6: Commit**

```bash
cd "$(git rev-parse --show-toplevel)"
git add app/Sources/ProfilesCore/ProfileStat.swift app/Sources/ProfilesCoreTests/ProfileStatTests.swift app/Sources/ProfilesCoreTests/TestRunner.swift
git commit -m "feat(core): ProfileStat Codable model + decodeList"
```

---

### Task 4: Formatters (TDD)

**Files:**
- Create: `app/Sources/ProfilesCoreTests/FormatterTests.swift`
- Create: `app/Sources/ProfilesCore/Formatters.swift`
- Modify: `app/Sources/ProfilesCoreTests/TestRunner.swift`

- [ ] **Step 1: Write the failing test**

`app/Sources/ProfilesCoreTests/FormatterTests.swift`:

```swift
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
```

- [ ] **Step 2: Register the suite**

Add inside `main()` after the ProfileStat line:

```swift
        await runSuite("FormatterTests", FormatterTests.allTests, &tally)
```

- [ ] **Step 3: Run to verify it fails**

Run: `cd app && swift run ProfilesCoreTests`
Expected: build FAILS — "cannot find 'formatMemoryMB' in scope".

- [ ] **Step 4: Implement the formatters**

`app/Sources/ProfilesCore/Formatters.swift`:

```swift
import Foundation

private let grouping: NumberFormatter = {
    let f = NumberFormatter(); f.numberStyle = .decimal; f.locale = Locale(identifier: "en_US_POSIX")
    f.maximumFractionDigits = 0; return f
}()

private func grouped(_ n: Int) -> String { grouping.string(from: NSNumber(value: n)) ?? "\(n)" }

/// Memory is MB from the engine. < 1 GB → "N MB" (grouped); ≥ 1 GB → "X.Y GB".
public func formatMemoryMB(_ mb: Double) -> String {
    let m = Int(mb.rounded())
    if m < 1024 { return "\(grouped(m)) MB" }
    return String(format: "%.1f GB", mb / 1024.0)
}

/// CPU is a summed percentage that can exceed 100 (per-core). Never clamp.
public func formatCPU(_ pct: Double) -> String {
    if pct == pct.rounded() { return "\(Int(pct))%" }
    return String(format: "%.1f%%", pct)
}

/// Disk is MB; -1 is the default-instance sentinel (off-limits → not shown).
public func formatDiskMB(_ mb: Int) -> String {
    if mb < 0 { return "—" }
    if mb < 1024 { return "\(grouped(mb)) MB" }
    return String(format: "%.1f GB", Double(mb) / 1024.0)
}

public func formatHandles(used: Int, max: Int) -> String {
    "\(used) / \(max) handles"
}
```

- [ ] **Step 5: Run to verify it passes**

Run: `cd app && swift run ProfilesCoreTests`
Expected: all FormatterTests pass; `Executed 6 tests, with 0 failures`.

- [ ] **Step 6: Commit**

```bash
cd "$(git rev-parse --show-toplevel)"
git add app/Sources/ProfilesCore/Formatters.swift app/Sources/ProfilesCoreTests/FormatterTests.swift app/Sources/ProfilesCoreTests/TestRunner.swift
git commit -m "feat(core): display formatters (memory/cpu/disk/handles)"
```

---

### Task 5: `sortProfiles` — alive-first ordering (TDD)

**Files:**
- Create: `app/Sources/ProfilesCoreTests/SortTests.swift`
- Create: `app/Sources/ProfilesCore/Sort.swift`
- Modify: `app/Sources/ProfilesCoreTests/TestRunner.swift`

- [ ] **Step 1: Write the failing test**

`app/Sources/ProfilesCoreTests/SortTests.swift`:

```swift
import XCTest
@testable import ProfilesCore

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
```

- [ ] **Step 2: Register the suite**

Add inside `main()`:

```swift
        await runSuite("SortTests", SortTests.allTests, &tally)
```

- [ ] **Step 3: Run to verify it fails**

Run: `cd app && swift run ProfilesCoreTests`
Expected: build FAILS — "cannot find 'sortProfiles' in scope".

- [ ] **Step 4: Implement the sort**

`app/Sources/ProfilesCore/Sort.swift`:

```swift
import Foundation

/// Alive-first ordering: the default instance pinned first, then running profiles,
/// then stopped — each group ordered case-insensitively by name (stable).
public func sortProfiles(_ profiles: [ProfileStat]) -> [ProfileStat] {
    func rank(_ p: ProfileStat) -> Int {
        if p.isDefault { return 0 }
        return p.running ? 1 : 2
    }
    return profiles.sorted { a, b in
        let ra = rank(a), rb = rank(b)
        if ra != rb { return ra < rb }
        return a.name.localizedCaseInsensitiveCompare(b.name) == .orderedAscending
    }
}
```

- [ ] **Step 5: Run to verify it passes**

Run: `cd app && swift run ProfilesCoreTests`
Expected: SortTests passes; `Executed 7 tests, with 0 failures`.

- [ ] **Step 6: Commit**

```bash
cd "$(git rev-parse --show-toplevel)"
git add app/Sources/ProfilesCore/Sort.swift app/Sources/ProfilesCoreTests/SortTests.swift app/Sources/ProfilesCoreTests/TestRunner.swift
git commit -m "feat(core): alive-first profile sort"
```

---

### Task 6: `PtmxHysteresis` severity state machine (TDD — the prime target)

The handle-pool leak indicator. Anti-cry-wolf: escalate to `.critical` only at ≥90%
of the ceiling **and** only after N consecutive breach ticks; de-escalate from
critical only below the 80% low-water band; `.warning` at ≥75%; a `climbing` flag
when the ratio is rising in the warn band.

**Files:**
- Create: `app/Sources/ProfilesCoreTests/PtmxHysteresisTests.swift`
- Create: `app/Sources/ProfilesCore/PtmxHysteresis.swift`
- Modify: `app/Sources/ProfilesCoreTests/TestRunner.swift`

- [ ] **Step 1: Write the failing test**

`app/Sources/ProfilesCoreTests/PtmxHysteresisTests.swift`:

```swift
import XCTest
@testable import ProfilesCore

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
```

- [ ] **Step 2: Register the suite**

Add inside `main()`:

```swift
        await runSuite("PtmxHysteresisTests", PtmxHysteresisTests.allTests, &tally)
```

- [ ] **Step 3: Run to verify it fails**

Run: `cd app && swift run ProfilesCoreTests`
Expected: build FAILS — "cannot find 'PtmxHysteresis' / 'AlertState' / 'PtmxSample' in scope".

- [ ] **Step 4: Implement the state machine**

`app/Sources/ProfilesCore/PtmxHysteresis.swift`:

```swift
import Foundation

public enum AlertState: Equatable, Sendable {
    case calm
    case warning(climbing: Bool)
    case critical
}

public struct PtmxSample: Sendable {
    public let used: Int
    public let max: Int
    public init(used: Int, max: Int) { self.used = used; self.max = max }
    public var ratio: Double { max > 0 ? Double(used) / Double(max) : 0 }
}

/// Sustained-breach + hysteresis severity. Thresholds:
/// warn ≥ 0.75 · critical-enter ≥ 0.90 sustained for `sustain` ticks · critical-exit < 0.80.
public struct PtmxHysteresis: Sendable {
    public static let warn = 0.75
    public static let high = 0.90
    public static let low  = 0.80
    public static let sustain = 3

    private var breachStreak = 0
    private var prevRatio = 0.0
    private var isCritical = false

    public init() {}

    public mutating func ingest(_ sample: PtmxSample) -> AlertState {
        let r = sample.ratio
        let climbing = r > prevRatio
        defer { prevRatio = r }

        breachStreak = (r >= Self.high) ? breachStreak + 1 : 0

        if isCritical {
            if r < Self.low { isCritical = false } else { return .critical }
        } else if breachStreak >= Self.sustain {
            isCritical = true
            return .critical
        }

        if r >= Self.warn { return .warning(climbing: climbing) }
        return .calm
    }
}
```

- [ ] **Step 5: Run to verify it passes**

Run: `cd app && swift run ProfilesCoreTests`
Expected: all 8 PtmxHysteresisTests pass; `Executed 15 tests, with 0 failures`.

- [ ] **Step 6: Commit**

```bash
cd "$(git rev-parse --show-toplevel)"
git add app/Sources/ProfilesCore/PtmxHysteresis.swift app/Sources/ProfilesCoreTests/PtmxHysteresisTests.swift app/Sources/ProfilesCoreTests/TestRunner.swift
git commit -m "feat(core): PtmxHysteresis anti-cry-wolf severity state machine"
```

---

### Task 7: The seams — `EngineRunning`, `PollClock`, `EngineClient`, `FixtureEngine`, `StatsStore` (TDD)

**Files:**
- Create: `app/Sources/ProfilesCore/EngineRunning.swift`
- Create: `app/Sources/ProfilesCore/PollClock.swift`
- Create: `app/Sources/ProfilesCore/EngineClient.swift`
- Create: `app/Sources/ProfilesCore/FixtureEngine.swift`
- Create: `app/Sources/ProfilesCore/StatsStore.swift`
- Create: `app/Sources/ProfilesCoreTests/StatsStoreTests.swift`
- Create: `app/Sources/ProfilesCoreTests/EngineClientTests.swift`
- Modify: `app/Sources/ProfilesCoreTests/TestRunner.swift`

- [ ] **Step 1: Write the failing tests**

`app/Sources/ProfilesCoreTests/StatsStoreTests.swift`:

```swift
import XCTest
@testable import ProfilesCore

final class StatsStoreTests: XCTestCase {
    private func stat(_ name: String, running: Bool) -> ProfileStat {
        ProfileStat(name: name, slug: name.lowercased(), running: running, cpu: 1, mem: 1, procs: 1,
                    ptys: 0, ptmx: 0, ptmxMax: 256, disk: 0, opens: 0, last: "", color: "#000000", remote: false)
    }

    func testRefreshPopulatesAndSorts() async throws {
        let engine = FixtureEngine(stats: [stat("Zed", running: false), stat("Able", running: true)])
        let store = StatsStore(engine: engine, clock: ImmediateClock())
        await store.refreshOnce()
        let (count, firstRunning) = await MainActor.run { (store.profiles.count, store.profiles.first?.running ?? false) }
        XCTAssertEqual(count, 2)
        XCTAssertTrue(firstRunning)                 // alive-first sort applied
        let err = await MainActor.run { store.lastError }
        XCTAssertNil(err)
    }

    func testBadTickKeepsLastGoodProfiles() async throws {
        let engine = FixtureEngine(stats: [stat("Able", running: true)])
        let store = StatsStore(engine: engine, clock: ImmediateClock())
        await store.refreshOnce()
        engine.shouldThrow = true
        await store.refreshOnce()
        let (count, err) = await MainActor.run { (store.profiles.count, store.lastError) }
        XCTAssertEqual(count, 1)                     // last-good profiles retained
        XCTAssertNotNil(err)                         // but the error is surfaced
    }

    static let allTests: [(String, (StatsStoreTests) -> () async throws -> Void)] = [
        ("testRefreshPopulatesAndSorts", testRefreshPopulatesAndSorts),
        ("testBadTickKeepsLastGoodProfiles", testBadTickKeepsLastGoodProfiles),
    ]
}
```

`app/Sources/ProfilesCoreTests/EngineClientTests.swift`:

```swift
import XCTest
@testable import ProfilesCore

final class EngineClientTests: XCTestCase {
    func testRealProcessBridgeDecodes() async throws {
        // Thin proof the real Process boundary runs bash + decodes — uses a fake engine.
        let tmp = FileManager.default.temporaryDirectory.appendingPathComponent("fake-engine-\(UUID().uuidString).sh")
        let script = """
        #!/bin/bash
        [ "$1" = stats ] && printf '%s' '[{"name":"X","slug":"x","running":true,"cpu":1,"mem":2,"procs":1,"ptys":0,"ptmx":7,"ptmxMax":256,"disk":-1,"opens":0,"last":"","color":"#000000","remote":false}]'
        """
        try script.write(to: tmp, atomically: true, encoding: .utf8)
        try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: tmp.path)
        defer { try? FileManager.default.removeItem(at: tmp) }

        let client = EngineClient(enginePath: tmp.path)
        let stats = try await client.stats()
        XCTAssertEqual(stats.count, 1)
        XCTAssertEqual(stats[0].ptmx, 7)
    }

    static let allTests: [(String, (EngineClientTests) -> () async throws -> Void)] = [
        ("testRealProcessBridgeDecodes", testRealProcessBridgeDecodes),
    ]
}
```

- [ ] **Step 2: Register both suites**

Add inside `main()`:

```swift
        await runSuite("StatsStoreTests", StatsStoreTests.allTests, &tally)
        await runSuite("EngineClientTests", EngineClientTests.allTests, &tally)
```

- [ ] **Step 3: Run to verify it fails**

Run: `cd app && swift run ProfilesCoreTests`
Expected: build FAILS — "cannot find 'FixtureEngine' / 'StatsStore' / 'EngineClient' / 'ImmediateClock' in scope".

- [ ] **Step 4: Implement the protocols, clocks, engines, and store**

`app/Sources/ProfilesCore/EngineRunning.swift`:

```swift
import Foundation

public enum EngineError: Error, Equatable { case nonZeroExit(Int32) }

/// The seam between the app and engine.sh. EngineClient is the real impl; FixtureEngine is the test double.
public protocol EngineRunning: Sendable {
    func stats() async throws -> [ProfileStat]
    func run(_ verb: String, _ slug: String) async throws
}
```

`app/Sources/ProfilesCore/PollClock.swift`:

```swift
import Foundation

/// The 2s poll interval, injectable so tests run instantly and deterministically.
public protocol PollClock: Sendable { func sleepTick() async }

public struct RealClock: PollClock {
    public init() {}
    public func sleepTick() async { try? await Task.sleep(nanoseconds: 2_000_000_000) }
}

public struct ImmediateClock: PollClock {
    public init() {}
    public func sleepTick() async {}
}
```

`app/Sources/ProfilesCore/EngineClient.swift`:

```swift
import Foundation

public struct EngineClient: EngineRunning {
    public let enginePath: String
    public init(enginePath: String) { self.enginePath = enginePath }

    private static func invoke(_ path: String, _ args: [String]) throws -> (Data, Int32) {
        let p = Process()
        p.executableURL = URL(fileURLWithPath: "/bin/bash")
        p.arguments = [path] + args
        let outPipe = Pipe()
        p.standardOutput = outPipe
        p.standardError = Pipe()
        try p.run()
        let out = outPipe.fileHandleForReading.readDataToEndOfFile()
        p.waitUntilExit()
        return (out, p.terminationStatus)
    }

    public func stats() async throws -> [ProfileStat] {
        let path = enginePath
        return try await Task.detached(priority: .utility) {
            let (out, code) = try Self.invoke(path, ["stats"])
            if code != 0 { throw EngineError.nonZeroExit(code) }
            return try ProfileStat.decodeList(from: out)
        }.value
    }

    public func run(_ verb: String, _ slug: String) async throws {
        let path = enginePath
        try await Task.detached(priority: .utility) {
            let (_, code) = try Self.invoke(path, [verb, slug])
            if code != 0 { throw EngineError.nonZeroExit(code) }
        }.value
    }
}
```

`app/Sources/ProfilesCore/FixtureEngine.swift`:

```swift
import Foundation

/// Test double for EngineRunning — returns canned stats, or throws when `shouldThrow`.
public final class FixtureEngine: EngineRunning, @unchecked Sendable {
    public var stats: [ProfileStat]
    public var shouldThrow = false
    public private(set) var ranVerbs: [(String, String)] = []
    public init(stats: [ProfileStat]) { self.stats = stats }

    public func stats() async throws -> [ProfileStat] {
        if shouldThrow { throw EngineError.nonZeroExit(1) }
        return stats
    }
    public func run(_ verb: String, _ slug: String) async throws {
        if shouldThrow { throw EngineError.nonZeroExit(1) }
        ranVerbs.append((verb, slug))
    }
}
```

`app/Sources/ProfilesCore/StatsStore.swift`:

```swift
import Foundation
import Observation

@MainActor
@Observable
public final class StatsStore {
    public private(set) var profiles: [ProfileStat] = []
    public private(set) var lastError: String?

    private let engine: any EngineRunning
    private let clock: any PollClock
    private var task: Task<Void, Never>?

    public nonisolated init(engine: any EngineRunning, clock: any PollClock) {
        self.engine = engine
        self.clock = clock
    }

    public func refreshOnce() async {
        do {
            let fresh = try await engine.stats()
            profiles = sortProfiles(fresh)
            lastError = nil
        } catch {
            lastError = String(describing: error)   // keep last-good profiles — don't blank the UI on one bad tick
        }
    }

    public func start() {
        guard task == nil else { return }
        task = Task { [weak self] in
            while !Task.isCancelled {
                await self?.refreshOnce()
                await self?.clock.sleepTick()
            }
        }
    }

    public func stop() { task?.cancel(); task = nil }
}
```

- [ ] **Step 5: Run to verify it passes**

Run: `cd app && swift run ProfilesCoreTests`
Expected: StatsStoreTests + EngineClientTests pass; `Executed 18 tests, with 0 failures`.

- [ ] **Step 6: Commit**

```bash
cd "$(git rev-parse --show-toplevel)"
git add app/Sources/ProfilesCore/EngineRunning.swift app/Sources/ProfilesCore/PollClock.swift app/Sources/ProfilesCore/EngineClient.swift app/Sources/ProfilesCore/FixtureEngine.swift app/Sources/ProfilesCore/StatsStore.swift app/Sources/ProfilesCoreTests/StatsStoreTests.swift app/Sources/ProfilesCoreTests/EngineClientTests.swift app/Sources/ProfilesCoreTests/TestRunner.swift
git commit -m "feat(core): EngineRunning/PollClock seams + EngineClient + StatsStore"
```

---

### Task 8: Prove the snapshot path — `ImageRenderer` headless under CLT

Phase 1 only proves SwiftUI's `ImageRenderer` renders headlessly (no window server, no
Xcode) and yields a valid bitmap at the pinned scale. The golden-PNG diff harness +
real view goldens arrive in Phase 2 with the first real views.

**Files:**
- Modify: `app/Sources/ProfilesSnapshotTests/SnapshotRunner.swift`

- [ ] **Step 1: Implement the headless-render proof**

Replace `app/Sources/ProfilesSnapshotTests/SnapshotRunner.swift` with:

```swift
import SwiftUI
import AppKit

@MainActor
func renderPNG<V: View>(_ view: V, scale: CGFloat = 2) -> NSBitmapImageRep? {
    let renderer = ImageRenderer(content: view)
    renderer.scale = scale
    renderer.isOpaque = true
    guard let cg = renderer.cgImage else { return nil }
    return NSBitmapImageRep(cgImage: cg)
}

struct ProbeView: View {
    var body: some View {
        Text("snap")
            .font(.system(size: 20, weight: .medium))
            .frame(width: 120, height: 60)
            .background(Color(red: 0.12, green: 0.118, blue: 0.094))
    }
}

@main
struct ProfilesSnapshotTestsMain {
    @MainActor static func main() {
        var failed = 0
        if let rep = renderPNG(ProbeView(), scale: 2) {
            // 120×60 @2x → 240×120 device pixels
            if rep.pixelsWide == 240 && rep.pixelsHigh == 120 && (rep.representation(using: .png, properties: [:])?.count ?? 0) > 0 {
                print("Test Case 'SnapshotProbe.rendersHeadless' passed.")
            } else {
                failed += 1
                print("Test Case 'SnapshotProbe.rendersHeadless' FAILED. got \(rep.pixelsWide)x\(rep.pixelsHigh)")
            }
        } else {
            failed += 1
            print("Test Case 'SnapshotProbe.rendersHeadless' FAILED. ImageRenderer.cgImage was nil")
        }
        print("Executed 1 tests, with \(failed) failures")
        exit(failed == 0 ? 0 : 1)
    }
}
```

- [ ] **Step 2: Run to verify it passes**

Run: `cd app && swift run ProfilesSnapshotTests`
Expected: `Test Case 'SnapshotProbe.rendersHeadless' passed.` then `Executed 1 tests, with 0 failures`, exit 0. This confirms `ImageRenderer` works with no Xcode and no window server.

- [ ] **Step 3: Commit**

```bash
cd "$(git rev-parse --show-toplevel)"
git add app/Sources/ProfilesSnapshotTests/SnapshotRunner.swift
git commit -m "test(app): prove ImageRenderer renders headlessly under CLT"
```

---

### Task 9: macOS CI + build/test docs

Add Swift build + both test runners to the existing macOS CI job, and document the
local commands. (CI behavior can only be verified by pushing — the final step opens a
PR and confirms the macOS job is green.)

**Files:**
- Modify: `.github/workflows/ci-macos.yml`
- Modify: `CLAUDE.md` (the Build / test / release section)

- [ ] **Step 1: Add Swift steps to the macOS job**

In `.github/workflows/ci-macos.yml`, in the `macos` job's `steps:`, insert after the
`actions/checkout@…` step and before `- name: test suite`:

```yaml
      - name: pin Command Line Tools toolchain
        run: |
          # Mirror the maintainer's no-Xcode setup so CI fails the way a CLT-only
          # contributor would. Best-effort: if standalone CLT isn't present, fall
          # back to the runner's default toolchain (the source is identical).
          sudo xcode-select -s /Library/Developer/CommandLineTools 2>/dev/null \
            || echo "standalone CLT not present; using default toolchain"
          swift --version
      - name: cache SwiftPM build
        uses: actions/cache@v4   # pin to a full SHA per repo convention before merge
        with:
          path: |
            app/.build
            ~/Library/Caches/org.swift.swiftpm
          key: ${{ runner.os }}-${{ matrix.os }}-spm-${{ hashFiles('app/Package.swift') }}
          restore-keys: ${{ runner.os }}-${{ matrix.os }}-spm-
      - name: swift build (app + core, no Xcode)
        run: cd app && swift build
      - name: layer 1 — logic tests
        run: cd app && swift run ProfilesCoreTests
      - name: layer 2 — snapshot render proof
        run: cd app && swift run ProfilesSnapshotTests
```

> The `actions/cache@v4` line uses a tag for readability; pin it to a full commit SHA
> (matching `checkout`/`harden-runner` in these workflows) in the same PR. Tests need
> no signing — the 6 Developer-ID secrets stay exclusively in `release.yml`.

- [ ] **Step 2: Document the local commands in CLAUDE.md**

In `CLAUDE.md`, under the "Build / test / release" section, add after the existing
`bash tests/run-tests.sh` line:

```markdown
# SwiftUI app (Command Line Tools — no Xcode needed):
cd app && swift build                  # build ProfilesCore + the app shell
cd app && swift run ProfilesCoreTests  # Layer-1 logic tests (executable runner; XCTest doesn't run under CLT)
cd app && swift run ProfilesSnapshotTests  # Layer-2 ImageRenderer render proof
```

- [ ] **Step 3: Open the PR and verify CI**

```bash
cd "$(git rev-parse --show-toplevel)"
git add .github/workflows/ci-macos.yml CLAUDE.md
git commit -m "ci(macos): build + run the SwiftUI logic and snapshot test runners"
git push -u origin <phase1-branch>
gh pr create --title "Phase 1: SwiftUI foundation (package + tests + CI)" --body "ProfilesCore + no-Xcode test harness + macOS CI. All logic unit-tested (PtmxHysteresis, decode, formatters, sort, store)."
```

Expected: the macOS CI job runs `swift build`, `swift run ProfilesCoreTests`
(`Executed 18 tests, with 0 failures`), and `swift run ProfilesSnapshotTests`
(`Executed 1 tests, with 0 failures`) — all green. The Linux bash job is unchanged.

---

## Self-review notes (author)

- **Spec coverage:** Phase-1 spec bullets all map — real `Package.swift` (Task 1);
  test harness + macOS CI green (Tasks 2, 9); the four seams: `EngineRunning` +
  `PollClock` + SwiftUI-free `ProfilesCore` + (snapshot fixture-init deferred to Phase
  2 views, with the headless-render path proven in Task 8) (Tasks 7, 8); `ProfilesCore`
  fully unit-tested — `PtmxHysteresis` (Task 6), decode (Task 3), formatters (Task 4),
  sort (Task 5), store (Task 7).
- **Type consistency:** `ProfileStat` (Task 3) fields are reused verbatim by `SortTests`/
  `StatsStoreTests` initializers and `decodeList`; `AlertState`/`PtmxSample`/
  `PtmxHysteresis` names match across Task 6; `EngineRunning`/`PollClock`/`ImmediateClock`/
  `FixtureEngine`/`StatsStore`/`EngineClient` names are consistent across Task 7 and its
  tests; `runSuite`'s `(String, (T) -> () async throws -> Void)` signature matches every
  suite's `allTests` (all test methods are `async throws`).
- **No placeholders:** every code step is complete; commands have expected output. The
  one deliberate deferral (golden-PNG diff harness → Phase 2) is stated, not a TODO.
- **Known CI caveat flagged:** the CLT-pin and `actions/cache` SHA-pin are best-effort/
  noted because they can only be validated on a GitHub macOS runner (Task 9 Step 3).
