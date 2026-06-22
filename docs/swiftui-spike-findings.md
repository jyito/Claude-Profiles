# SwiftUI dashboard spike — findings (2026-06-21)

**Verdict: GO.** All five de-risking criteria passed on the maintainer's Mac
(macOS 26.5.1, Apple Silicon). Green-light the full-parity SwiftUI rewrite. See
the spec at `docs/superpowers/specs/2026-06-21-swiftui-dashboard-spike-design.md`
and the plan at `docs/superpowers/plans/2026-06-21-swiftui-dashboard-spike.md`.

## Toolchain (validated)

- **No full Xcode is needed to build or sign a SwiftUI app.** Swift 5.10 via
  Command Line Tools compiles SwiftUI, `MenuBarExtra`, `@Observable`, and AppKit
  (`NSRunningApplication`, `yieldActivation`). The `.app` is **hand-assembled**
  (`Contents/MacOS/<exe>` + `Resources/engine.sh` + `Info.plist`) and
  `codesign`ed — Developer ID Application (Team VL65UNJU87), hardened runtime
  (`flags=0x10000(runtime)`), secure timestamp — the same hand-assembly pattern
  `scripts/build.sh` already uses for the manager bundle. No `xcodebuild`, no IDE.
- **One real toolchain gap — `swift test` does NOT work under pure CLT.** CLT
  ships only the private `XCTestSupport` stub, not `XCTest.framework`, and
  `xcrun --show-sdk-platform-path` hard-fails; `swift-testing` is also absent in
  5.10. The spike worked around it with a ~150-line vendored `XCTest` shim plus an
  executable test-runner target (`swift run SpikeCoreTests` → standard
  `Executed N tests, with M failures` output, non-zero exit on failure).
  **Decision for the full app:** either require full Xcode for the test suite, or
  adopt the executable-runner pattern. (The de-risking pre-flight verified SwiftUI
  *compiles* under CLT but never verified XCTest *links/runs* — this gap was the
  spike's main surprise.)

## Results

| # | Criterion | Result | Evidence |
|---|-----------|--------|----------|
| 1 | Process spawn under hardened runtime | **PASS** | The signed, hardened, non-sandboxed app ran `engine.sh stats` and rendered real data with no spawn/exec denial (default: 61.1% CPU / 2,230 MB / 145 leaked; Personal: 5.7% / 1,622 MB / 40 leaked). No special entitlements required. |
| 2 | Live 2s stats loop (smooth) | **PASS** | Cards refresh every 2s off the main thread (`Task.detached` → `Codable` decode → `@MainActor @Observable` publish); no stalls/beachball. |
| 3 | `MenuBarExtra` switcher | **PASS** | Status item (`square.on.square`) lists both profiles with running ● dots + Quit. |
| 4 | Spaces-aware focus-by-PID | **PASS** | Show Window raised the target Claude instance; the one-time Automation prompt appeared → Allow; focus worked across Spaces. Same mechanism as today's AppleScriptObjC `focusInstance` (`NSRunningApplication.activate` + System Events frontmost fallback). |
| 5 | Action round-trip (restart) | **PASS** | Restart cycled the instance (`engine.sh restart <slug>`); stats reflected it within a couple ticks. |

## Gotchas to carry into the full design

- **Swift Concurrency / actor isolation:** the stats store is `@MainActor`, so its
  `init` must be `nonisolated` for the SwiftUI `App`'s `@State` property
  initializer to construct it; test methods that read main-actor state need
  `@MainActor`. Trivial but will recur across every `@MainActor` store.
- **`@main` SwiftUI executable** builds under SPM with no manual
  `-parse-as-library` flag (SPM supplies it).
- **`--deep` codesign** seals the bundled `engine.sh` as a resource; no separate
  inner-binary signature needed.
- **`yieldActivation`/`activate(options:)`** compiled without an `#available`
  guard because the package targets macOS 14 — keep the deployment floor at 14.
- A persistent `warning: could not determine XCTest paths` prints on every
  `swift` invocation under CLT — harmless noise from the same missing-platform
  probe; ignore.

## Architecture validated

Native SwiftUI shell → `Process`-spawn the existing `src/engine.sh` → `Codable`
decode → `@Observable` model → SwiftUI views, with actions as one-shot
`engine.sh <verb> <slug>` calls. This cleanly replaces the `document.title`
JS↔native title-bridge. The bash engine remains the single source of truth; no
stats/actions logic moved into Swift.

## Decision

**GO** for the full-parity SwiftUI rewrite. Recommended build approach:
`swift build` (CLT, no Xcode) → hand-assembled `.app` → Developer-ID +
hardened-runtime `codesign`, wired into `scripts/build.sh`/CI; tests via the
executable-runner pattern (or full Xcode if the test suite grows). Next step is a
dedicated full-design brainstorm → spec → plan (feature parity: leaked-handle
stat + restart, terminals drill-down, settings, Remote modal + QR, badge picker,
hotkeys, sparklines, cleanup, new-profile flow). The throwaway spike app is
discarded; this note is the kept artifact.
