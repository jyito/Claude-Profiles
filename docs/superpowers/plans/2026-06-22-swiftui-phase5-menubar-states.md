# SwiftUI Dashboard — Phase 5 (Menu-bar, Focus, List view, States) Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: superpowers:subagent-driven-development. Logic TDD (`swift run ProfilesCoreTests`); views via golden snapshots + controller visual-QA. **Live focus/menu-bar behavior (window raising, the Automation prompt) is maintainer-verified** (the Phase-0 spike already proved the mechanism; the implementer builds + compiles + snapshots the static views).

**Goal:** The remaining interaction + polish: a **functional `MenuBarExtra`** switcher (focus an instance by PID), **Show Window across Spaces** (the spike-proven `NSRunningApplication` + System Events path), a **dense List-view toggle**, and the **empty / loading / inactive-window states**.

**Architecture:** Add a `mainPid` seam (resolve a profile's main PID). A `Focus` AppKit helper performs in-process activation (not `engine focus`). The shared `@Observable StatsStore` already backs both the window and `MenuBarExtra`, so dots stay consistent. The Grid/List toggle (Phase-2 toolbar control) drives a dense `Table`/list over the same models. States are view-level.

**Tech Stack:** SwiftUI `MenuBarExtra`, `Table`, AppKit `NSRunningApplication` + `osascript` (System Events fallback). ProfilesCore (PID parse). CLT build, no Xcode.

---

### Task 1: `mainPid` seam (TDD)

**Files:** Modify `EngineRunning.swift`/`EngineClient.swift`/`FixtureEngine.swift`; Create `app/Sources/ProfilesCoreTests/MainPidTests.swift`; register.

The engine resolves PIDs via `mainpid <slug>` and `defaultpid` (stdout = a PID, or empty). **Read `src/engine.sh` `cmd_mainpid`/`cmd_defaultpid` to confirm output.**

- [ ] **Step 1** — Failing test: a stub engine printing `"54321\n"` for `mainpid x` → `mainPid("x")` returns `54321`; empty stdout → `nil`. For the default instance (`slug == "default"` or empty) it must call `defaultpid`.
- [ ] **Step 2** — Register `MainPidTests`. Run → fails.
- [ ] **Step 3** — Implement `func mainPid(_ slug: String) async throws -> Int32?` on `EngineRunning`: run `["mainpid", slug]` (or `["defaultpid"]` when `slug == "default"`), trim stdout, `Int32(...)` or `nil`. `EngineClient` real impl; `FixtureEngine` returns a canned pid. (No error-token handling needed — empty = nil.)
- [ ] **Step 4** — Run → passes (count grows). Commit `feat(core): mainPid seam`.

### Task 2: `Focus` helper (in-process activation)

**Files:** Create `app/Sources/ProfilesUI/Focus.swift`.

No unit test (manipulates live app activation — maintainer-verified; the spike proved it). Port the spike/spec approach.

- [ ] **Step 1** — `enum Focus { @MainActor static func show(pid: Int32) }`: `NSRunningApplication(processIdentifier:)` → `app.activate(options: [.activateAllWindows])`; after 0.3s, if `!app.isActive`, fall back to System Events frontmost via `osascript -e 'tell application "System Events" to set frontmost of (first application process whose unix id is <pid>) to true'` (the one-time Automation prompt). Target the PID, never the bundle id (all instances share Claude's bundle). Guard `if #available(macOS 14, *)` for `yieldActivation` if used.
- [ ] **Step 2** — Wire it: the scene's "Show Window" / "Open"-then-focus action becomes `Task { if let pid = try? await store.mainPid(slug) { await MainActor.run { Focus.show(pid: pid) } } }`. Wire the card's existing **Show Window** button (running) to this. **Open** (stopped) → `run(["open", slug])` (Phase-2 behavior, unchanged).
- [ ] **Step 3** — `swift build` compiles. Commit `feat(ui): in-process focus-by-PID + Show Window wiring`.

### Task 3: Functional `MenuBarExtra` switcher

**Files:** Modify `ProfilesApp.swift` (the `MenuBarExtra` block).

- [ ] **Step 1** — Replace the Phase-2 stub menu: rebuild each open from the shared `store.profiles` (alive-first). One row per instance — a small badge-color swatch + name + a trailing mint dot when running — that on tap focuses by PID (`Task { if let pid = try? await store.mainPid(p.id) { await MainActor.run { Focus.show(pid: pid) } } }`). A `Divider()`, then "New Profile" (opens the New Profile sheet / ⌘N) and "Quit" (⌘Q, `NSApplication.shared.terminate(nil)`). Template `square.on.square` SF Symbol. The window and menu share the store, so dots match by construction.
- [ ] **Step 2** — `swift build` compiles. (Snapshot the menu CONTENT as a plain view if practical — `inspector`/menu chrome isn't a renderable leaf; a `menu-content` golden of the row list over a solid surface is optional but nice.)
- [ ] **Step 3** — Commit `feat(ui): functional MenuBarExtra switcher (focus by PID)`.

### Task 4: Dense List-view toggle

**Files:** Create `app/Sources/ProfilesUI/ProfileListView.swift`; wire the toolbar Grid/List control.

- [ ] **Step 1** — `ProfileListView(profiles:, selection:Binding, ...)`: a dense `Table` (live app) over the same `ProfileStat` models — columns: dot+badge+name, status, CPU% (monospacedDigit), MEM, terminals, handle-pool (used/ceiling) — with the same selection→inspector wiring as the grid. Snapshot uses a hand-built row stand-in (native `Table` renders empty headless — reuse the established pattern).
- [ ] **Step 2** — Wire the toolbar Grid/List segmented control (`@State viewMode`) to switch `DashboardContent` between the grid and `ProfileListView`. Both share `store.profiles` + `selection`, so the inspector works in either.
- [ ] **Step 3** — Snapshot `list-view` (fixture rows, stand-in). Record + verify.
- [ ] **Step 4** — Commit `feat(ui): dense List-view toggle (+ golden)`.

### Task 5: Empty / loading / inactive states (snapshots)

**Files:** Create `app/Sources/ProfilesUI/States.swift`; wire into `DashboardContent`.

- [ ] **Step 1** — `EmptyStateView`: centered muted window-stack glyph + one sentence-case line ("No profiles yet — create one to run a second Claude account.") + the single coral New Profile CTA. Shown when `store.profiles` is empty (excluding the always-present default — decide: show empty state only when there are zero NON-default profiles AND the default isn't running, else show the grid; keep it simple — empty when `profiles.isEmpty`).
- [ ] **Step 2** — `LoadingSkeletonView`: card-shaped `surface2` rectangles with a left→right shimmer, shown until the first stats render (track a `hasLoadedOnce` flag on the store — set true after the first `refreshOnce`). Replaces the grid on first load so it fills in rather than popping.
- [ ] **Step 3** — Inactive-window dim: apply `.opacity(appearsActive ? 1 : 0.85)` to the content via the `\.appearsActive` environment value.
- [ ] **Step 4** — Snapshots `state-empty`, `state-loading`. Record + verify.
- [ ] **Step 5** — Commit `feat(ui): empty / loading / inactive states (+ goldens)`.

### Task 6: Full verify + visual QA + CI + merge

- [ ] **Step 1** — `swift build -c release`; `swift run ProfilesCoreTests` (all green); `swift run ProfilesSnapshotTests` (all goldens). Live run (maintainer): the menu-bar item lists instances + focuses on click; Show Window raises the instance (Automation prompt first time, across Spaces); the List toggle works; empty/loading states render.
- [ ] **Step 2** — Controller opens new goldens (`list-view`, `state-empty`, `state-loading`, optional `menu-content`) vs the spec; fix drift.
- [ ] **Step 3** — Open the Phase 5 PR; CI green; merge.

---

## Self-review notes (author)
- **Spec coverage:** menu-bar switcher (T3), Show-Window/focus (T1, T2), List-view toggle (T4), empty/loading/inactive states (T5). After this, only Phase 6 (e2e + cutover) remains.
- **Type consistency:** `mainPid` seam (T1) → `Focus.show` (T2) ← used by the card Show Window (T2) AND the menu-bar (T3). `viewMode` toggles grid vs `ProfileListView` over the same `store.profiles`/`selection`. States read `store.profiles`/`hasLoadedOnce`.
- **Verification boundary (honest):** the live focus/menu-bar/Show-Window *behavior* (window raising, the one-time Automation prompt, cross-Spaces) is **maintainer-verified** — unit tests + snapshots can't exercise it, but the Phase-0 spike already proved the exact mechanism (criteria #3/#4 PASS). Built + compiled here; behavior confirmed on the Mac in Task 6 / Phase 6 e2e.
