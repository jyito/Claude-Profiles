# SwiftUI Dashboard Spike — Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Build a throwaway SwiftUI spike that validates 5 risky unknowns before committing to the full native dashboard rewrite (see `docs/superpowers/specs/2026-06-21-swiftui-dashboard-spike-design.md`).

**Architecture:** A Swift Package (built with the CLT `swift` toolchain — verified to compile SwiftUI + `MenuBarExtra` + `@Observable` without full Xcode) producing a `.app` that is hand-assembled and `codesign`ed with Developer ID + hardened runtime. The app shells out to the repo's existing `src/engine.sh` via `Process` and decodes its JSON; the engine is never reimplemented in Swift. All spike code lives in a **gitignored `spike/` dir** and is discarded — only a findings note is committed.

**Tech Stack:** Swift 5.10 (Command Line Tools), Swift Package Manager (`swift build`/`swift test`/XCTest), SwiftUI, AppKit (`NSRunningApplication`), `codesign`. macOS 14+, non-sandboxed.

**Validation gate (from the spec):** (1) hardened-runtime process spawn, (2) live 2s stats loop, (3) `MenuBarExtra`, (4) Spaces-aware focus-by-PID, (5) action round-trip. Pass all → green-light the full design.

---

### Task 1: Scaffold the gitignored Swift package

**Files:**
- Modify: `.gitignore` (append `/spike/`)
- Create: `spike/Package.swift`
- Create: `spike/Sources/SpikeCore/Placeholder.swift`
- Create: `spike/Sources/Spike/main.swift` (temporary; replaced in Task 6)
- Create: `spike/Tests/SpikeCoreTests/SmokeTest.swift`

- [ ] **Step 1: Ignore the spike dir**

Append to `.gitignore`:

```
# Throwaway SwiftUI de-risking spike (never committed; see docs/superpowers/specs/2026-06-21-swiftui-dashboard-spike-design.md)
/spike/
```

- [ ] **Step 2: Create `spike/Package.swift`**

```swift
// swift-tools-version:5.10
import PackageDescription

let package = Package(
    name: "Spike",
    platforms: [.macOS(.v14)],
    targets: [
        .target(name: "SpikeCore"),
        .executableTarget(name: "Spike", dependencies: ["SpikeCore"]),
        .testTarget(name: "SpikeCoreTests", dependencies: ["SpikeCore"]),
    ]
)
```

- [ ] **Step 3: Create placeholder sources so the package builds**

`spike/Sources/SpikeCore/Placeholder.swift`:

```swift
public enum SpikeCore {
    public static let ok = true
}
```

`spike/Sources/Spike/main.swift`:

```swift
import SpikeCore
print("spike scaffold ok: \(SpikeCore.ok)")
```

`spike/Tests/SpikeCoreTests/SmokeTest.swift`:

```swift
import XCTest
@testable import SpikeCore

final class SmokeTest: XCTestCase {
    func testScaffoldBuilds() {
        XCTAssertTrue(SpikeCore.ok)
    }
}
```

- [ ] **Step 4: Verify the package builds and tests run**

Run: `cd spike && swift build && swift test`
Expected: build succeeds; `Executed 1 test, with 0 failures`.

- [ ] **Step 5: Commit the .gitignore change only (spike code is ignored)**

```bash
cd "$(git rev-parse --show-toplevel)"
git add .gitignore
git commit -m "chore: ignore the throwaway SwiftUI spike dir"
```

---

### Task 2: Decode `engine.sh stats` JSON (TDD)

**Files:**
- Create: `spike/Sources/SpikeCore/Models.swift`
- Create: `spike/Tests/SpikeCoreTests/ModelsTest.swift`

The engine emits an array of objects shaped like (from `src/engine.sh` `profile_json`):
`{"name","slug","running","cpu","mem","procs","ptys","ptmx","ptmxMax","disk","opens","last","color","remote"}`.

- [ ] **Step 1: Write the failing test**

`spike/Tests/SpikeCoreTests/ModelsTest.swift`:

```swift
import XCTest
@testable import SpikeCore

final class ModelsTest: XCTestCase {
    func testDecodesEngineStats() throws {
        let json = """
        [
          {"name":"Claude (default)","slug":"","running":true,"cpu":12.5,"mem":896,"procs":3,"ptys":1,"ptmx":39,"ptmxMax":511,"disk":-1,"opens":0,"last":"","color":"#6E6A62","remote":false},
          {"name":"Claude Personal","slug":"personal","running":false,"cpu":0,"mem":0,"procs":0,"ptys":0,"ptmx":0,"ptmxMax":511,"disk":1024,"opens":4,"last":"2026-06-21 08:00","color":"#5DCAA5","remote":true}
        ]
        """.data(using: .utf8)!
        let stats = try ProfileStat.decodeList(from: json)
        XCTAssertEqual(stats.count, 2)
        XCTAssertEqual(stats[0].name, "Claude (default)")
        XCTAssertEqual(stats[0].slug, "")
        XCTAssertTrue(stats[0].running)
        XCTAssertEqual(stats[0].cpu, 12.5, accuracy: 0.001)
        XCTAssertEqual(stats[0].ptmx, 39)
        XCTAssertEqual(stats[1].slug, "personal")
        XCTAssertFalse(stats[1].running)
        XCTAssertTrue(stats[1].remote)
        XCTAssertEqual(stats[0].effSlug, "default")   // empty slug => the default instance
        XCTAssertEqual(stats[1].effSlug, "personal")
    }
}
```

- [ ] **Step 2: Run the test to verify it fails**

Run: `cd spike && swift test --filter ModelsTest`
Expected: FAIL — "cannot find 'ProfileStat' in scope".

- [ ] **Step 3: Write the model**

`spike/Sources/SpikeCore/Models.swift`:

```swift
import Foundation

public struct ProfileStat: Codable, Identifiable, Sendable {
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

    /// Stable identity + the slug used by the engine for actions ("default" for the empty-slug default instance).
    public var id: String { slug.isEmpty ? "default" : slug }
    public var effSlug: String { slug.isEmpty ? "default" : slug }

    public static func decodeList(from data: Data) throws -> [ProfileStat] {
        try JSONDecoder().decode([ProfileStat].self, from: data)
    }
}
```

- [ ] **Step 4: Run the test to verify it passes**

Run: `cd spike && swift test --filter ModelsTest`
Expected: PASS — `Executed 1 test, with 0 failures`.

- [ ] **Step 5: Commit (spike is gitignored — this is a no-op commit-wise; just run the build to checkpoint)**

Run: `cd spike && swift build`
Expected: build succeeds. (No git commit — `spike/` is ignored. Use `swift build`/`swift test` green as the checkpoint throughout.)

---

### Task 3: EngineClient — spawn `engine.sh` and decode (TDD with a stub)

**Files:**
- Create: `spike/Sources/SpikeCore/EngineClient.swift`
- Create: `spike/Tests/SpikeCoreTests/EngineClientTest.swift`

- [ ] **Step 1: Write the failing test (drives the engine via a stub script so it's hermetic)**

`spike/Tests/SpikeCoreTests/EngineClientTest.swift`:

```swift
import XCTest
@testable import SpikeCore

final class EngineClientTest: XCTestCase {
    /// Write a fake "engine" script that prints a known stats array, then verify EngineClient runs + decodes it.
    func testRunsAndDecodesStats() throws {
        let tmp = FileManager.default.temporaryDirectory.appendingPathComponent("fake-engine-\(UUID().uuidString).sh")
        let script = """
        #!/bin/bash
        if [ "$1" = "stats" ]; then
          printf '%s' '[{"name":"X","slug":"x","running":true,"cpu":1.0,"mem":2,"procs":1,"ptys":0,"ptmx":7,"ptmxMax":511,"disk":-1,"opens":0,"last":"","color":"#000000","remote":false}]'
        fi
        """
        try script.write(to: tmp, atomically: true, encoding: .utf8)
        try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: tmp.path)
        defer { try? FileManager.default.removeItem(at: tmp) }

        let client = EngineClient(enginePath: tmp.path)
        let stats = try client.stats()
        XCTAssertEqual(stats.count, 1)
        XCTAssertEqual(stats[0].slug, "x")
        XCTAssertEqual(stats[0].ptmx, 7)
    }

    func testRunReturnsExitCode() throws {
        let tmp = FileManager.default.temporaryDirectory.appendingPathComponent("fake-engine-\(UUID().uuidString).sh")
        try "#!/bin/bash\nexit 0\n".write(to: tmp, atomically: true, encoding: .utf8)
        try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: tmp.path)
        defer { try? FileManager.default.removeItem(at: tmp) }
        let client = EngineClient(enginePath: tmp.path)
        XCTAssertNoThrow(try client.run("focus", "x"))   // fire-and-forget action, no throw on exit 0
    }
}
```

- [ ] **Step 2: Run to verify it fails**

Run: `cd spike && swift test --filter EngineClientTest`
Expected: FAIL — "cannot find 'EngineClient' in scope".

- [ ] **Step 3: Implement EngineClient**

`spike/Sources/SpikeCore/EngineClient.swift`:

```swift
import Foundation

public struct EngineClient: Sendable {
    public let enginePath: String
    public init(enginePath: String) { self.enginePath = enginePath }

    public enum EngineError: Error { case nonZeroExit(Int32, String) }

    /// Run `bash <enginePath> <args...>` and return (stdout, exitCode).
    @discardableResult
    private func invoke(_ args: [String]) throws -> (out: Data, code: Int32) {
        let p = Process()
        p.executableURL = URL(fileURLWithPath: "/bin/bash")
        p.arguments = [enginePath] + args
        let outPipe = Pipe()
        p.standardOutput = outPipe
        p.standardError = Pipe()
        try p.run()
        let out = outPipe.fileHandleForReading.readDataToEndOfFile()
        p.waitUntilExit()
        return (out, p.terminationStatus)
    }

    /// `engine.sh stats` -> decoded profiles.
    public func stats() throws -> [ProfileStat] {
        let (out, code) = try invoke(["stats"])
        if code != 0 { throw EngineError.nonZeroExit(code, "stats") }
        return try ProfileStat.decodeList(from: out)
    }

    /// Fire a mutating verb, e.g. run("restart","personal"). Throws on non-zero exit.
    public func run(_ verb: String, _ slug: String) throws {
        let (_, code) = try invoke([verb, slug])
        if code != 0 { throw EngineError.nonZeroExit(code, "\(verb) \(slug)") }
    }
}
```

- [ ] **Step 4: Run to verify it passes**

Run: `cd spike && swift test --filter EngineClientTest`
Expected: PASS — `Executed 2 tests, with 0 failures`.

- [ ] **Step 5: Checkpoint**

Run: `cd spike && swift test`
Expected: all tests pass.

---

### Task 4: StatsStore — `@Observable` 2s poll off the main thread

**Files:**
- Create: `spike/Sources/SpikeCore/StatsStore.swift`
- Create: `spike/Tests/SpikeCoreTests/StatsStoreTest.swift`

- [ ] **Step 1: Write the failing test (one refresh, against a stub engine)**

`spike/Tests/SpikeCoreTests/StatsStoreTest.swift`:

```swift
import XCTest
@testable import SpikeCore

final class StatsStoreTest: XCTestCase {
    func testRefreshPopulatesProfiles() async throws {
        let tmp = FileManager.default.temporaryDirectory.appendingPathComponent("fake-engine-\(UUID().uuidString).sh")
        try "#!/bin/bash\n[ \"$1\" = stats ] && printf '%s' '[{\"name\":\"A\",\"slug\":\"a\",\"running\":true,\"cpu\":3.0,\"mem\":5,\"procs\":1,\"ptys\":0,\"ptmx\":2,\"ptmxMax\":511,\"disk\":-1,\"opens\":0,\"last\":\"\",\"color\":\"#111111\",\"remote\":false}]'\n"
            .write(to: tmp, atomically: true, encoding: .utf8)
        try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: tmp.path)
        defer { try? FileManager.default.removeItem(at: tmp) }

        let store = StatsStore(engine: EngineClient(enginePath: tmp.path))
        await store.refreshOnce()
        XCTAssertEqual(store.profiles.count, 1)
        XCTAssertEqual(store.profiles[0].slug, "a")
        XCTAssertNil(store.lastError)
    }
}
```

- [ ] **Step 2: Run to verify it fails**

Run: `cd spike && swift test --filter StatsStoreTest`
Expected: FAIL — "cannot find 'StatsStore' in scope".

- [ ] **Step 3: Implement StatsStore**

`spike/Sources/SpikeCore/StatsStore.swift`:

```swift
import Foundation
import Observation

@MainActor
@Observable
public final class StatsStore {
    public private(set) var profiles: [ProfileStat] = []
    public private(set) var lastError: String?

    private let engine: EngineClient
    private var task: Task<Void, Never>?

    public init(engine: EngineClient) { self.engine = engine }

    /// Run the (blocking) engine call off the main actor, then publish on the main actor.
    public func refreshOnce() async {
        let engine = self.engine
        do {
            let stats = try await Task.detached(priority: .utility) { try engine.stats() }.value
            self.profiles = stats
            self.lastError = nil
        } catch {
            self.lastError = String(describing: error)
        }
    }

    /// Start a 2s polling loop. Idempotent.
    public func start() {
        guard task == nil else { return }
        task = Task { [weak self] in
            while !Task.isCancelled {
                await self?.refreshOnce()
                try? await Task.sleep(nanoseconds: 2_000_000_000)
            }
        }
    }

    public func stop() { task?.cancel(); task = nil }
}
```

- [ ] **Step 4: Run to verify it passes**

Run: `cd spike && swift test --filter StatsStoreTest`
Expected: PASS — `Executed 1 test, with 0 failures`.

- [ ] **Step 5: Checkpoint**

Run: `cd spike && swift test`
Expected: all pass.

---

### Task 5: Focus-by-PID helper

**Files:**
- Create: `spike/Sources/SpikeCore/Focus.swift`

No unit test (it manipulates live app activation — validated manually in Task 10, criterion #4).

- [ ] **Step 1: Implement Focus**

`spike/Sources/SpikeCore/Focus.swift`:

```swift
import AppKit

public enum Focus {
    /// Raise an instance's windows by PID: NSRunningApplication first; if cooperative
    /// activation declines (macOS 14+, esp. across Spaces), fall back to System Events
    /// frontmost (one-time Automation prompt). Mirrors the AppleScriptObjC focusInstance.
    @MainActor
    public static func show(pid: Int32) {
        guard let app = NSRunningApplication(processIdentifier: pid_t(pid)) else { return }
        NSApp?.yieldActivation(to: app)
        app.activate(options: [.activateAllWindows])
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
            if !app.isActive { systemEventsFrontmost(pid: pid) }
        }
    }

    private static func systemEventsFrontmost(pid: Int32) {
        let src = "tell application \"System Events\" to set frontmost of (first application process whose unix id is \(pid)) to true"
        let p = Process()
        p.executableURL = URL(fileURLWithPath: "/usr/bin/osascript")
        p.arguments = ["-e", src]
        try? p.run()
    }
}
```

> Note: `NSApp?.yieldActivation(to:)` is macOS 14+. Build will confirm availability.

- [ ] **Step 2: Verify it compiles**

Run: `cd spike && swift build`
Expected: build succeeds (no availability errors). If `yieldActivation` errors, wrap it in `if #available(macOS 14, *)`.

- [ ] **Step 3: Checkpoint**

Run: `cd spike && swift test`
Expected: all pass (Focus has no tests; nothing regressed).

---

### Task 6: App + window UI (cards with live CPU/mem), plus a Show Window button and an action

**Files:**
- Delete: `spike/Sources/Spike/main.swift`
- Create: `spike/Sources/Spike/SpikeApp.swift`
- Create: `spike/Sources/Spike/ContentView.swift`

We need the engine path. The spike resolves it from an env var `SPIKE_ENGINE` (so we can point at the repo's `src/engine.sh` while developing) and falls back to the app bundle's `Resources/engine.sh` (Task 9).

- [ ] **Step 1: Remove the placeholder entrypoint**

```bash
rm spike/Sources/Spike/main.swift
```

- [ ] **Step 2: Create the App entrypoint with the mutating action wired in**

`spike/Sources/Spike/SpikeApp.swift`:

```swift
import SwiftUI
import SpikeCore

func resolveEnginePath() -> String {
    if let p = ProcessInfo.processInfo.environment["SPIKE_ENGINE"], !p.isEmpty { return p }
    // Bundled fallback (Task 9 copies engine.sh into Resources)
    if let r = Bundle.main.resourcePath { return r + "/engine.sh" }
    return "engine.sh"
}

@main
struct SpikeApp: App {
    @State private var store = StatsStore(engine: EngineClient(enginePath: resolveEnginePath()))

    var body: some Scene {
        WindowGroup("Claude Profiles (spike)") {
            ContentView(store: store)
                .frame(minWidth: 480, minHeight: 320)
                .onAppear { store.start() }
        }
    }
}
```

- [ ] **Step 3: Create ContentView with cards + Show Window + a Restart action**

`spike/Sources/Spike/ContentView.swift`:

```swift
import SwiftUI
import SpikeCore

struct ContentView: View {
    let store: StatsStore

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Spike — live from engine.sh")
                .font(.headline)
            if let err = store.lastError {
                Text("engine error: \(err)").foregroundStyle(.red).font(.caption)
            }
            ScrollView {
                LazyVStack(spacing: 8) {
                    ForEach(store.profiles) { p in CardView(p: p, store: store) }
                }
            }
        }
        .padding(16)
    }
}

struct CardView: View {
    let p: ProfileStat
    let store: StatsStore

    var body: some View {
        HStack(spacing: 12) {
            Circle().fill(p.running ? .green : .gray).frame(width: 8, height: 8)
            VStack(alignment: .leading) {
                Text(p.name).bold()
                Text(p.running
                     ? "CPU \(String(format: "%.1f", p.cpu))%  ·  Mem \(Int(p.mem)) MB  ·  \(p.ptmx) leaked"
                     : "Stopped")
                    .font(.caption).foregroundStyle(.secondary)
            }
            Spacer()
            if p.running {
                Button("Show Window") { showWindow(p) }
                Button("Restart") { runAction("restart", p) }
            }
        }
        .padding(10)
        .background(RoundedRectangle(cornerRadius: 8).fill(Color.gray.opacity(0.12)))
    }

    private func showWindow(_ p: ProfileStat) {
        // Resolve PID via the engine, then focus by PID.
        Task.detached {
            let engine = EngineClient(enginePath: resolveEnginePath())
            let verb = p.slug.isEmpty ? "defaultpid" : "mainpid"
            // mainpid <slug> / defaultpid -> a PID on stdout. Reuse run via a tiny inline call:
            if let pid = try? pidFor(engine: engine, verb: verb, slug: p.slug), let n = Int32(pid) {
                await MainActor.run { Focus.show(pid: n) }
            }
        }
    }

    private func runAction(_ verb: String, _ p: ProfileStat) {
        Task.detached {
            try? EngineClient(enginePath: resolveEnginePath()).run(verb, p.effSlug)
        }
    }
}

/// Helper: read a single PID line from `engine.sh mainpid <slug>` / `defaultpid`.
func pidFor(engine: EngineClient, verb: String, slug: String) throws -> String {
    let proc = Process()
    proc.executableURL = URL(fileURLWithPath: "/bin/bash")
    proc.arguments = slug.isEmpty ? [engine.enginePath, "defaultpid"] : [engine.enginePath, "mainpid", slug]
    let pipe = Pipe(); proc.standardOutput = pipe; proc.standardError = Pipe()
    try proc.run()
    let out = pipe.fileHandleForReading.readDataToEndOfFile()
    proc.waitUntilExit()
    return String(data: out, encoding: .utf8)?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
}
```

- [ ] **Step 4: Build the executable against the repo engine and smoke-run it (windowed)**

Run (from repo root):
```bash
cd spike && swift build -c release
SPIKE_ENGINE="$(git -C .. rev-parse --show-toplevel)/src/engine.sh" ./.build/release/Spike
```
Expected: a window opens listing your profiles with live CPU/Mem/leaked updating every 2s. (This is the **unsigned** dev run — criterion #2. Quit the app to continue.)

> If the window doesn't appear because a bare SPM executable isn't treated as a GUI app, that's expected — proceed to Task 9 (the assembled `.app` is the real run surface) and treat this step as "build succeeds."

- [ ] **Step 5: Checkpoint**

Run: `cd spike && swift build -c release && swift test`
Expected: build + tests succeed.

---

### Task 7: Add the MenuBarExtra switcher

**Files:**
- Modify: `spike/Sources/Spike/SpikeApp.swift`

- [ ] **Step 1: Add `MenuBarExtra` to the App scene**

In `spike/Sources/Spike/SpikeApp.swift`, add a second scene inside `body` after the `WindowGroup { ... }` closure:

```swift
        MenuBarExtra("CP", systemImage: "square.on.square") {
            ForEach(store.profiles) { p in
                Button((p.running ? "● " : "  ") + p.name) {
                    Task.detached {
                        let engine = EngineClient(enginePath: resolveEnginePath())
                        let verb = p.slug.isEmpty ? "defaultpid" : "mainpid"
                        if let pid = try? pidFor(engine: engine, verb: verb, slug: p.slug), let n = Int32(pid) {
                            await MainActor.run { Focus.show(pid: n) }
                        }
                    }
                }
            }
            Divider()
            Button("Quit") { NSApplication.shared.terminate(nil) }
        }
```

Add `import AppKit` to the top of the file if not present.

- [ ] **Step 2: Build**

Run: `cd spike && swift build -c release`
Expected: build succeeds.

- [ ] **Step 3: Checkpoint**

Run: `cd spike && swift test`
Expected: all pass.

---

### Task 8: `build.sh` — assemble + sign the `.app`

**Files:**
- Create: `spike/build.sh`
- Create: `spike/Info.plist`

- [ ] **Step 1: Create the bundle Info.plist**

`spike/Info.plist`:

```xml
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
  <key>CFBundleName</key><string>Claude Profiles Spike</string>
  <key>CFBundleDisplayName</key><string>Claude Profiles Spike</string>
  <key>CFBundleIdentifier</key><string>local.claude-profiles.spike</string>
  <key>CFBundleExecutable</key><string>Spike</string>
  <key>CFBundlePackageType</key><string>APPL</string>
  <key>CFBundleVersion</key><string>0.0.1</string>
  <key>CFBundleShortVersionString</key><string>0.0.1</string>
  <key>LSMinimumSystemVersion</key><string>14.0</string>
</dict>
</plist>
```

- [ ] **Step 2: Create the assemble+sign script**

`spike/build.sh`:

```bash
#!/bin/bash
# Assemble + sign the throwaway spike .app (no Xcode; swift build + hand-assembly + codesign).
set -euo pipefail
cd "$(dirname "$0")"
REPO="$(git rev-parse --show-toplevel)"

swift build -c release

APP="dist/Claude Profiles Spike.app"
rm -rf dist; mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
cp Info.plist "$APP/Contents/Info.plist"
cp ".build/release/Spike" "$APP/Contents/MacOS/Spike"
cp "$REPO/src/engine.sh" "$APP/Contents/Resources/engine.sh"   # bundled engine (the real one)
chmod +x "$APP/Contents/Resources/engine.sh"

# Sign with the maintainer's Developer ID + hardened runtime (the real shipping config).
ID="${SIGN_IDENTITY:-Developer ID Application: Justin Ito (VL65UNJU87)}"
codesign --deep --force --options runtime --timestamp --sign "$ID" "$APP"
codesign --verify --strict --verbose=2 "$APP"
echo "built + signed: $APP"
```

- [ ] **Step 3: Make it executable and run it**

```bash
chmod +x spike/build.sh
spike/build.sh
```
Expected: `built + signed: dist/Claude Profiles Spike.app` and `valid on disk / satisfies its Designated Requirement`.

> If `codesign` fails because the bundled `engine.sh` needs its own signature, the `--deep` flag handles it; if not, add `codesign --force --sign "$ID" "$APP/Contents/Resources/engine.sh"` before signing the app.

- [ ] **Step 4: Checkpoint**

Run: `cd spike && swift test`
Expected: all pass.

---

### Task 9: Validation run + findings note + go/no-go (the actual point of the spike)

**Files:**
- Create: `docs/swiftui-spike-findings.md` (committed — the one artifact we keep)

> Steps 1–5 require the **maintainer on a real Mac** (GUI + Automation prompt). The agent assembles/signs; the maintainer clicks through and reports.

- [ ] **Step 1: Launch the SIGNED app (criterion #1 — hardened-runtime spawn)**

```bash
open "spike/dist/Claude Profiles Spike.app"
```
Expected: it launches and the window lists profiles with live stats — proving a **signed, hardened-runtime** app can spawn `engine.sh`. (If it launches but shows "engine error", the spawn/exec was denied — record that.)

- [ ] **Step 2: Watch the live loop (criterion #2)**

Expected: CPU / Mem / leaked-count update ~every 2s with no beachball / stutter.

- [ ] **Step 3: Menu bar (criterion #3)**

Expected: a `square.on.square` item appears top-right; clicking it lists the profiles (running ones marked ●).

- [ ] **Step 4: Show Window (criterion #4)**

Click a card's **Show Window** (and a menu-bar profile row). Expected: that instance's windows come forward; first time, the one-time Automation prompt → Allow; then it jumps even across Spaces.

- [ ] **Step 5: Action round-trip (criterion #5)**

Click **Restart** on a running profile. Expected: that instance cycles (quits + relaunches) and its stats reflect it within a couple ticks.

- [ ] **Step 6: Write the findings note (the kept deliverable)**

Create `docs/swiftui-spike-findings.md` with the verified results. Template — fill each with the real pass/fail + any quirk:

```markdown
# SwiftUI dashboard spike — findings (2026-06-21)

Toolchain: Swift 5.10 via Command Line Tools (no full Xcode). SwiftUI, MenuBarExtra,
and @Observable all compile; app built with `swift build` + hand-assembled `.app` +
`codesign` (Developer ID, hardened runtime).

| # | Criterion | Result | Notes |
|---|-----------|--------|-------|
| 1 | Hardened-runtime process spawn | PASS/FAIL | … |
| 2 | Live 2s stats loop (smooth) | PASS/FAIL | … |
| 3 | MenuBarExtra switcher | PASS/FAIL | … |
| 4 | Spaces-aware focus-by-PID | PASS/FAIL | … |
| 5 | Action round-trip (restart) | PASS/FAIL | … |

**Decision:** GO / NO-GO for the full-parity SwiftUI rewrite.
**Build approach that works:** swiftc/SPM (CLT) + hand-assembled .app + codesign — no Xcode IDE.
**Gotchas for the full design:** …
```

- [ ] **Step 7: Commit the findings note (only this; spike code stays ignored)**

```bash
cd "$(git rev-parse --show-toplevel)"
git add docs/swiftui-spike-findings.md
git commit -m "docs: SwiftUI dashboard spike findings + go/no-go"
```

---

## Self-review notes (author)

- **Spec coverage:** all 5 validation criteria map to Task 9 steps 1–5; the "engine stays the backend / shell out" commitment is Tasks 3+8; "non-sandboxed + Developer ID + hardened runtime" is Task 8; "gitignored/throwaway, only findings kept" is Tasks 1 + 9. ✓
- **Type consistency:** `ProfileStat` (Task 2) → used by `EngineClient.stats()` (Task 3) → `StatsStore.profiles` (Task 4) → `ContentView`/`MenuBarExtra` (Tasks 6–7). `EngineClient.run(_:_:)` and `pidFor(...)` signatures are stable across Tasks 3/6/7. `effSlug` defined in Task 2, used in Task 6. ✓
- **No placeholders:** every code step shows complete code; commands have expected output. The Info.plist, Package.swift, and build.sh are complete. ✓
- **Known soft spots flagged inline:** bare-SPM-exe GUI behavior (Task 6 step 4), `yieldActivation` availability (Task 5), `--deep` signing of the bundled engine (Task 8) — each has a fallback noted.
