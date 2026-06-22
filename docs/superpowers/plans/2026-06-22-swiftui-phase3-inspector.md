# SwiftUI Dashboard — Phase 3 (Inspector Drill-Down) Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: superpowers:subagent-driven-development. Steps use `- [ ]`. Logic tasks are TDD (`swift run ProfilesCoreTests`); view tasks are snapshot + controller visual-QA against `docs/superpowers/specs/2026-06-22-swiftui-dashboard-design.md`.

**Goal:** Add the native right-side `.inspector` drill-down that the design's biggest usability bet depends on — selecting a card opens an inspector (the grid never reflows) showing, for a running profile, the **terminals table** (per-row Close) + **Throttle** + the **leak-restart block**; for a stopped profile, the **clean tiers** + **badge picker** + **Remove**; the default instance is terminals-only.

**Architecture:** Extend the `EngineRunning` seam with `terminals(slug)` (typed JSON decode) and a general `run([args])` for multi-arg verbs (closeterm/clean/setbadge/restart/remove/purge). The store gains terminals loading. New `ProfilesUI` inspector views switch body by `ProfileStat` state. The scene attaches `.inspector(isPresented:)` driven by selection + the card "Details ›".

**Tech Stack:** SwiftUI `.inspector`, `Table`, `Form`/`GroupBox`, `confirmationDialog`; ProfilesCore (Codable, no SwiftUI). CLT build, no Xcode. Tests: logic via the executable runner, views via golden PNGs.

**Reuses Phase 2:** `Theme`, `BadgeDisc`, `StatusDot`, `PillButtonStyle`, the snapshot harness + `Fixtures`, the `@Observable StatsStore`. Mockup reference: the "inspector + modal" widget already shown.

---

### Task 1: `TerminalInfo` model + decode (TDD)

**Files:** Create `app/Sources/ProfilesCore/TerminalInfo.swift`; Create `app/Sources/ProfilesCoreTests/TerminalInfoTests.swift`; register in `TestRunner.swift`.

The engine `terminals <slug>` emits `[{"dev","pid","cmd","idle"}]` (dev like `/dev/ttys003`; idle = seconds since the tty's mtime, `-1` if unknown). **First read `src/engine.sh`'s `cmd_terminals` to confirm the exact JSON keys/types before writing the model.**

- [ ] **Step 1** — Failing test: decode a 2-row terminals JSON; assert `dev`/`pid`/`cmd`/`idle`, `id == dev`, and an idle `-1` round-trips. Add a `decodeList(from:)` like `ProfileStat`.
- [ ] **Step 2** — Register `TerminalInfoTests` in the runner. Run → fails (no `TerminalInfo`).
- [ ] **Step 3** — Implement `public struct TerminalInfo: Codable, Identifiable, Sendable, Equatable { dev:String; pid:Int; cmd:String; idle:Int; var id:String { dev }; static func decodeList(from:) }`.
- [ ] **Step 4** — Run → passes (count grows to 20). Commit `feat(core): TerminalInfo model + decode`.

### Task 2: Extend the `EngineRunning` seam (TDD)

**Files:** Modify `EngineRunning.swift`, `EngineClient.swift`, `FixtureEngine.swift`; Modify `StatsStore.swift`; Create `app/Sources/ProfilesCoreTests/EngineSeamTests.swift`; register.

- [ ] **Step 1** — Failing tests (in `EngineSeamTests`): (a) `FixtureEngine` records `run(["clean","x","gpu"])` in `ranArgs`; (b) `FixtureEngine.terminals("x")` returns the canned list; (c) `StatsStore.loadTerminals(for:)` populates `store.terminals` via the fixture (use `await MainActor.run` to read).
- [ ] **Step 2** — Register `EngineSeamTests`. Run → fails.
- [ ] **Step 3** — Implement:
  - `EngineRunning`: make the requirement `func run(_ args: [String]) async throws` + `func terminals(_ slug: String) async throws -> [TerminalInfo]`; keep a convenience `extension EngineRunning { func run(_ verb: String, _ slug: String) async throws { try await run([verb, slug]) } }` so Phase-2 callers are unchanged.
  - `EngineClient`: implement `run([args])` (bash + args, `FileHandle.nullDevice` stderr) and `terminals(slug)` (run `["terminals", slug]`, decode `TerminalInfo.decodeList`).
  - `FixtureEngine`: `var terminalsList: [TerminalInfo]`, `private(set) var ranArgs: [[String]]`; implement both; `run` appends to `ranArgs` (and keep `ranVerbs` working or migrate its uses).
  - `StatsStore`: add `private(set) var terminals: [TerminalInfo] = []` + `func loadTerminals(for slug: String) async { do { terminals = try await engine.terminals(slug) } catch { terminals = [] } }`.
- [ ] **Step 4** — Run → passes (count ~23). Commit `feat(core): EngineRunning terminals + run([args]) seam + store.loadTerminals`.

### Task 3: Inspector shell + scene wiring + header (snapshot)

**Files:** Create `app/Sources/ProfilesUI/InspectorView.swift`; Modify the scene (`ProfilesApp.swift` / `DashboardView.swift`); register a snapshot.

- [ ] **Step 1** — `InspectorView(stat: ProfileStat, terminals: [TerminalInfo], state: AlertState, onAction: (InspectorAction) -> Void)` — a header (BadgeDisc 34 + name `.title3` + status line echoing the card) over a body that switches on state (filled in Tasks 4–7). Define `enum InspectorAction { case closeTerminal(String), throttle, restart, clean(String), setBadge(Int), remove }` so the view stays pure and the scene performs the engine calls.
- [ ] **Step 2** — Scene wiring: add `@State var inspectorShown = false` and reuse `selection` (slug). Attach `.inspector(isPresented: $inspectorShown) { InspectorView(...) }` (`.inspectorColumnWidth(min:300, ideal:340, max:420)`) to the detail column. The card's **"Details ›"** sets `selection = stat.id; inspectorShown = true`; selecting a sidebar row also opens it. `onAction` maps to `Task { try? await engine.run([...]) }` then refreshes (stats/terminals). Load terminals when selection changes to a running profile (`.task(id: selection)`).
- [ ] **Step 3** — Snapshot `inspector-header` (running fixture). Record + verify. Run the live app to confirm Details opens the inspector without the grid reflowing (controller QA).
- [ ] **Step 4** — Commit `feat(ui): inspector shell + scene wiring + header (+ golden)`.

### Task 4: Terminals table + per-row Close (snapshot)

**Files:** Create `app/Sources/ProfilesUI/TerminalsTable.swift`; register snapshot.

- [ ] **Step 1** — `TerminalsTable(terminals:, onClose:(String)->Void)`: eyebrow "TERMINALS · N", then a `Table`/`List` — Device (SF Mono, mint-tinted) · Command (SF Mono, dimmed, truncating) · Idle (right-aligned, monospacedDigit, formatted "active"/"Nm idle"/"—" from the idle seconds) · a per-row "Close" `PillButton` that **arms→confirms in place** (unarmed "Close" → 3s armed "Confirm" → calls `onClose(dev)`). Wire into `InspectorView`'s running body.
- [ ] **Step 2** — Snapshot `inspector-terminals` (fixture with 3 terminals, one armed). Record + verify.
- [ ] **Step 3** — Commit `feat(ui): terminals table + per-row close (+ golden)`.

### Task 5: Throttle + leak-restart block (snapshots)

**Files:** Create `app/Sources/ProfilesUI/LeakBlock.swift`; extend `InspectorView` running body.

- [ ] **Step 1** — Below the table: a "Throttle CPU" `PillButton` (`onAction(.throttle)`) + a one-line subtle hint ("lowers priority until restart"). Then `LeakBlock(stat:state:onRestart:)` — an amber-framed tile shown when `ptmx > 0`: "{ptmx} leaked terminal handles macOS can't reclaim (a Claude Desktop bug). Restart frees them." + a **2-step** "Restart to Free Handles" → "Confirm Restart" whose confirm copy reads "This quits and reopens Claude — windows and terminals close; login and chats are kept." (`onAction(.restart)`). Tile framing amber at `.warning`, coral at `.critical`.
- [ ] **Step 2** — Snapshots `inspector-leakblock-warning`, `inspector-leakblock-armed`. Record + verify.
- [ ] **Step 3** — Commit `feat(ui): throttle + leak-restart block (+ goldens)`.

### Task 6: Clean tiers (stopped body) + snapshot

**Files:** Create `app/Sources/ProfilesUI/CleanTiers.swift`; extend `InspectorView` stopped body.

- [ ] **Step 1** — `CleanTiers(onClean:(String)->Void)`: eyebrow "STORAGE" + "Using {formatDiskMB} on disk", then a `LazyVGrid` of 4 bordered tiles — Caches / GPU / Logs / Everything — each title + sub-desc + (static) reclaimable hint, tapping `onAction(.clean("caches"|"gpu"|"logs"|"all"))`. **No confirmation** (regenerable). Shown only when `!stat.running` and `!stat.isDefault`.
- [ ] **Step 2** — Snapshot `inspector-cleantiers`. Record + verify.
- [ ] **Step 3** — Commit `feat(ui): clean tiers (+ golden)`.

### Task 7: Badge picker + Remove (snapshots)

**Files:** Create `app/Sources/ProfilesUI/BadgePicker.swift`, `app/Sources/ProfilesUI/RemoveProfile.swift`; extend `InspectorView`.

- [ ] **Step 1** — `BadgePicker(currentHex:, onPick:(Int)->Void)`: a row of 6 disc swatches in the engine palette order (blue/mint/amber/purple/pink/teal), the active one ringed in primary text, tapping `onAction(.setBadge(index))`. **Absent on default.**
- [ ] **Step 2** — `RemoveProfile(name:, onRemove:()->Void)`: a quiet muted text button at the very bottom that expands to a `TextField` where the user types the **account's own name** (`name`); the armed "Remove Permanently" button is disabled until the typed text matches `name`, then renders desaturated-red (never coral) with a one-line irreversibility note; `onAction(.remove)`. **Absent on default.** (The scene maps `.remove` to `engine.run(["remove", slug])` then `engine.run(["purge", slug])`.)
- [ ] **Step 3** — Snapshots `inspector-badgepicker`, `inspector-remove-armed`. Record + verify.
- [ ] **Step 4** — Commit `feat(ui): badge picker + typed-name remove (+ goldens)`.

### Task 8: Assemble inspector bodies + full snapshots + default gating

**Files:** finalize `InspectorView.swift`.

- [ ] **Step 1** — Compose the body by state: **running** → TerminalsTable + Throttle + LeakBlock; **stopped** → CleanTiers + BadgePicker + RemoveProfile; **default** → TerminalsTable ONLY (gate out clean/badge/remove/leak-restart structurally via `stat.isDefault` so the restricted contract can't be violated).
- [ ] **Step 2** — Snapshots `inspector-running-full`, `inspector-stopped-full`, `inspector-default` (terminals-only). Record + verify.
- [ ] **Step 3** — Commit `feat(ui): assemble inspector bodies + default gating (+ goldens)`.

### Task 9: Full verify + visual QA + CI + merge

- [ ] **Step 1** — `swift build -c release`; `swift run ProfilesCoreTests` (all green); `swift run ProfilesSnapshotTests` (all goldens). Run the live app: select cards, confirm the inspector opens with the right body per state, the grid never reflows, Close/Throttle/Clean/Restart/Badge call the engine (controller QA against real engine).
- [ ] **Step 2** — Controller opens every new inspector golden and confirms against the mockup; fix drift.
- [ ] **Step 3** — Open the Phase 3 PR; CI green; merge.

---

## Self-review notes (author)
- **Spec coverage:** `.inspector` drill-down (T3), terminals table + Close (T4), Throttle + leak-restart (T5), clean tiers (T6), badge picker + typed-name Remove (T7), default terminals-only gating (T8), the seam + terminals data (T1–T2). Modals/menu-bar/Show-Window are Phase 4–5.
- **Type consistency:** `TerminalInfo` (T1) flows into the seam (T2) → store.terminals → `TerminalsTable` (T4). `InspectorAction` enum defined T3, used by every sub-view and mapped in the scene. `EngineRunning.run([args])` + the `run(verb,slug)` convenience keep Phase-2 callers compiling.
- **Safety:** destructive actions (restart, remove) are 2-step; clean tiers (regenerable) are not; default-instance restrictions are structural (`isDefault` gating), honoring CLAUDE.md §5.
