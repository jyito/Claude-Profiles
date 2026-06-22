# SwiftUI Dashboard — Phase 2 (Shell + Live Data) Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: superpowers:subagent-driven-development. Steps use `- [ ]`. Verification for views is **visual**: render to PNG via the snapshot harness, and the controller compares against the approved mockup (`docs/superpowers/specs/2026-06-22-swiftui-dashboard-design.md` + the "Calm Instrument" mockup).

**Goal:** Turn the tested `ProfilesCore` foundation into a running native window that matches the "Calm Instrument" mockup — `NavigationSplitView` with a vibrant sidebar, the KPI instrument strip, and the running/stopped/default card grid with live CPU/Mem Swift Charts sparklines and the handle-pool gauge — plus the golden-PNG snapshot harness on real views.

**Architecture:** A new `ProfilesUI` **library** target (importable by the snapshot runner) holds all views; the `Profiles` executable becomes the real `@main` scene wiring `StatsStore` (2s poll) into `NavigationSplitView`. A `Theme` enum centralizes tokens. Views are deterministic (fixture model + frozen data as init params, no `@Environment`/`Date.now`/materials) so `ImageRenderer` snapshots are stable.

**Tech Stack:** SwiftUI, Swift Charts, AppKit (`NSVisualEffectView` bridge for sidebar vibrancy), Observation. CLT build, no Xcode. Tests: `swift run ProfilesCoreTests` (logic) + `swift run ProfilesSnapshotTests` (golden PNGs).

**Spec tokens (authoritative — use exactly):** canvas `#16150F` · surface1 `#1F1E17` · surface2 `#262419` · surface3 `#2E2C1F` · hairline white 6%/11% · text `#F1EFE8`→62%→40%→28% · mint `#5DCAA5` (live only) · coral `#D85A30` (brand/focus/critical) · amber `#E0A333` (warning) · CPU line `#E08A5E` · MEM line `#4FA8A0` · leak-hot `#F0997B`. Badge palette (engine `badge_rgb`): blue 59,125,216 · mint 93,202,165 · amber 224,165,94 · purple 124,92,196 · pink 210,95,140 · teal 76,169,178. Spacing 4·8·12·16·20·24·32; radii pill 6 / button 8 / disc 10 / card 14 / modal 16. SF Pro semantic styles + `.monospacedDigit()` on every live number; SF Mono for device/PID/slug. No drop shadows (depth = surface ladder + hairline). No materials on resting cards.

---

## File structure (this phase)

```
app/Sources/
  ProfilesUI/                          (NEW library target; imports ProfilesCore + SwiftUI/Charts)
    Theme.swift                        color/spacing/radii/type tokens + Color(hex:) + badge palette
    VisualEffectView.swift             NSViewRepresentable for sidebar vibrancy
    BadgeDisc.swift                    rounded-square avatar (color + initial)
    StatusDot.swift                    running(mint, breathing-OFF in snapshotMode)/stopped(hollow) dot
    Sparkline.swift                    Swift Charts line+area+live-point, pinned Y, hidden chrome
    HandleGauge.swift                  ptmx capacity bar (calm/amber/coral per AlertState)
    ProfileCardView.swift              running / stopped / default card (drives off ProfileStat + AlertState)
    KPIStripView.swift                 instrument cells (memory/running/cpu/terminals/handle pool)
    SidebarView.swift                  List(selection:) Profiles + System sections
    DashboardView.swift                KPI strip + LazyVGrid of cards (the content column)
    SnapshotMode.swift                 EnvironmentKey that freezes animation/numericText for snapshots
  Profiles/
    ProfilesApp.swift                  REWRITE: NavigationSplitView + MenuBarExtra stub + store wiring
    EnginePath.swift                   resolveEnginePath() (SPIKE_ENGINE env → bundled fallback)
  ProfilesSnapshotTests/
    SnapshotRunner.swift               REWRITE: golden-PNG harness + per-view cases
    Fixtures.swift                     deterministic ProfileStat fixtures + frozen sparkline series
tests/snapshot/
  pngdiff.py                           python3-stdlib PNG tolerance diff (NEW)
app/Tests/__Snapshots__/               committed golden PNGs (NEW)
```

Inspector drill-down, real modals, the live MenuBarExtra menu, and Show Window are **Phase 3+** — a `MenuBarExtra` stub + non-functional Details chevron are fine here.

---

### Task 1: `ProfilesUI` target + `Theme` tokens

**Files:** `app/Package.swift` (add `ProfilesUI` library target + add it as a dep of `Profiles` and `ProfilesSnapshotTests`); Create `app/Sources/ProfilesUI/Theme.swift`, `app/Sources/ProfilesUI/SnapshotMode.swift`.

- [ ] **Step 1** — In `Package.swift` add `.target(name: "ProfilesUI", dependencies: ["ProfilesCore"])`, add `"ProfilesUI"` to the `Profiles` exe deps, and to `ProfilesSnapshotTests` deps.
- [ ] **Step 2** — `Theme.swift`: a `Theme` enum exposing the spec tokens as `Color` constants (via a `Color(hex:)` initializer and an opacity ramp for text), spacing constants, corner radii, and `badgeColor(for index: Int) -> Color` + `badgeColor(forHex: String) -> Color` (parse `ProfileStat.color`; **first read `src/engine.sh`'s `profile_json` to confirm the `color` field format — hex `#RRGGBB` vs `"R G B"` — and parse whatever it actually emits**, falling back to a slug-hash into the 6-palette). All colors are explicit constants (the app is always dark; no system semantic colors here except where the spec says system orange/red for severity).
- [ ] **Step 3** — `SnapshotMode.swift`: `struct SnapshotModeKey: EnvironmentKey { static let defaultValue = false }` + `EnvironmentValues.snapshotMode` accessor. Views read it to disable `.animation`/breathing/`contentTransition` and render numbers as plain text.
- [ ] **Step 4** — `cd app && swift build` succeeds. Commit `feat(ui): ProfilesUI target + Theme tokens + snapshotMode`.

### Task 2: Golden-PNG snapshot harness + `pngdiff.py`

**Files:** Create `tests/snapshot/pngdiff.py`; Rewrite `app/Sources/ProfilesSnapshotTests/SnapshotRunner.swift`; Create `app/Sources/ProfilesSnapshotTests/Fixtures.swift`; Create `app/Tests/__Snapshots__/` (goldens committed as views land).

- [ ] **Step 1** — `pngdiff.py` (python3 stdlib only — `zlib`/`struct`; no Pillow; degrade-or-skip if python3 absent): decode both PNGs, error clearly if dimensions differ, compute the fraction of pixels differing by more than a small per-channel delta, exit non-zero if it exceeds a tolerance arg (default ~0.2%); on mismatch write a side-by-side diff PNG next to the actual.
- [ ] **Step 2** — `Fixtures.swift`: deterministic `ProfileStat` fixtures (a running "Business" blue, a leak-warning "Research" purple at high ptmx, a stopped "Client X" pink, the default instance) + a fixed 30-point CPU and Mem `[Double]` series. No `Date.now`, no randomness.
- [ ] **Step 3** — `SnapshotRunner.swift`: a `@MainActor` harness that, for each registered case `(name, AnyView, size)`, renders via `ImageRenderer` (`scale=2`, `isOpaque=true`, `.environment(\.snapshotMode, true)`), writes `Tests/__Snapshots__/<name>@2x.png`; in default mode it renders to a temp file and shells `python3 tests/snapshot/pngdiff.py <golden> <temp>`; in `SNAPSHOT_RECORD=1` mode it (re)writes goldens. Prints `Test Case 'Snapshot.<name>' passed.`/`FAILED` and the standard `Executed N tests, with M failures` + nonzero exit on any fail. Cases are registered per view in later tasks.
- [ ] **Step 4** — `cd app && swift build` succeeds (no cases yet). Commit `test(ui): golden-PNG snapshot harness + pngdiff.py`.

### Task 3: `BadgeDisc` + `StatusDot` (+ snapshots)

**Files:** Create `BadgeDisc.swift`, `StatusDot.swift`; register snapshot cases.

- [ ] **Step 1** — `BadgeDisc(name:colorHex:size:)`: a `RoundedRectangle(cornerRadius: 10)` filled with the badge color, the profile's initial (first letter of name, "Claude "-stripped, uppercased) in SF Pro semibold near-black (`Color.black.opacity(0.8)`), centered. The default instance shows a `lock` SF Symbol instead of an initial.
- [ ] **Step 2** — `StatusDot(running:)`: 8pt circle — mint with a canvas-colored 1.5px ring + breathing pulse (opacity 1↔0.55, 1.6s) when running and **not** in `snapshotMode`; hollow gray ring when stopped.
- [ ] **Step 3** — Register snapshot cases: `badge-business`, `badge-default-lock`, `dot-running`, `dot-stopped`. Run `SNAPSHOT_RECORD=1 swift run ProfilesSnapshotTests` to record, then `swift run ProfilesSnapshotTests` to confirm they pass.
- [ ] **Step 4** — Commit `feat(ui): BadgeDisc + StatusDot (+ goldens)`.

### Task 4: `Sparkline` (Swift Charts) + snapshot

**Files:** Create `Sparkline.swift`; register snapshot.

- [ ] **Step 1** — `Sparkline(values:[Double], tint:Color, filled:Bool)`: Swift Charts `LineMark`(1.5pt, `.interpolationMethod(.monotone)`) + gradient `AreaMark` to clear + a single filled `PointMark` on the last sample (the live edge). `.chartYScale` pinned to `0...max(values)` (so per-core CPU >100% doesn't flatten), all axes/legend/gridlines hidden, `.chartLegend(.hidden)`, frame height 34. A `ghosted` variant (gray ~25%, no point, no fill) for stopped cards.
- [ ] **Step 2** — Register `spark-cpu`, `spark-mem`, `spark-ghost` snapshots (fixed series). Record + verify.
- [ ] **Step 3** — Commit `feat(ui): Swift Charts sparkline (+ goldens)`.

### Task 5: `HandleGauge` + `ProfileCardView` (running) + snapshot

**Files:** Create `HandleGauge.swift`, `ProfileCardView.swift`; register snapshots.

- [ ] **Step 1** — `HandleGauge(used:max:state:AlertState)`: a 4px capacity bar `used/max` + a terminal glyph + `formatHandles(used:max:)`; calm gray under warning, amber bar + `exclamationmark.triangle` + "N leaked" + (if `.warning(climbing:true)`) "▲ climbing", coral bar at `.critical`. Three channels always (color+glyph+number).
- [ ] **Step 2** — `ProfileCardView(stat:ProfileStat, cpu:[Double], mem:[Double], state:AlertState, selected:Bool)` for the **running** layout per the mockup: surface1 card, 14 radius, hairline + (selected → coral inset ring); identity row (BadgeDisc 34 + name `.title3`/semibold + trailing `ellipsis.circle` Menu placeholder); status line (StatusDot + "Running · N Procs · M Terminals", "Running" in mint, counts monospacedDigit); a two-column metric row (each: eyebrow "CPU"/"MEMORY" + big `.title2` monospacedDigit value + `Sparkline` tinted CPU `#E08A5E`/MEM `#4FA8A0`); the `HandleGauge`; a primary action row (Show Window mint-tinted `.bordered` + Remote with mint live-dot + "Details ›" chevron). Title Case. Every control gets a stable `.accessibilityIdentifier` (e.g. `card-<slug>-showwindow`).
- [ ] **Step 3** — Register `card-running-business` (calm) and `card-running-research-warning` (amber gauge) snapshots. Record + verify.
- [ ] **Step 4** — Commit `feat(ui): HandleGauge + running ProfileCard (+ goldens)`.

### Task 6: `ProfileCardView` stopped + default variants + snapshots

- [ ] **Step 1** — Stopped variant: whole card dimmed to 0.6, hollow dot + "Stopped · opened N× · last <date>", a "Disk X" `LabeledContent`, the **ghosted** last sparkline, single "Open" primary (mint-tinted border), "Details ›". Default variant: a faint `lock`/"System" tag, Show Window/Remote/terminals-Details only — **structurally** no disk/clean/badge/leak (gate by `stat.isDefault`).
- [ ] **Step 2** — Register `card-stopped-clientx`, `card-default` snapshots. Record + verify.
- [ ] **Step 3** — Commit `feat(ui): stopped + default ProfileCard variants (+ goldens)`.

### Task 7: `KPIStripView` + snapshot

- [ ] **Step 1** — `KPIStripView(profiles:[ProfileStat])`: a surface1 band (14 radius) of hairline-divided cells computed from the profiles — Memory in use (sum mem, big value + a 3px mem-teal micro-bar + "across N running" with N in mint), Running N/M, Total CPU (sum), Terminals (sum ptys), Handle pool (worst used/ceiling + a micro-bar neutral<75/amber 75–90/coral≥90). All numbers monospacedDigit.
- [ ] **Step 2** — Register `kpi-strip` snapshot. Record + verify.
- [ ] **Step 3** — Commit `feat(ui): KPI instrument strip (+ golden)`.

### Task 8: `SidebarView` + `VisualEffectView` + snapshot

- [ ] **Step 1** — `VisualEffectView`: `NSViewRepresentable` wrapping `NSVisualEffectView` (`.underWindowBackground`, `.behindWindow`, active) for sidebar vibrancy.
- [ ] **Step 2** — `SidebarView(profiles:, selection:Binding)`: a `List(selection:)`, `.listStyle(.sidebar)`, sections "Profiles" (non-default, alive-first) + "System" (the default row with a faint lock). Each row: StatusDot + BadgeDisc(18) + name + trailing muted MEM (monospacedDigit) when running. Footer area note: the pinned New Profile button is added with the scene in Task 9.
- [ ] **Step 3** — Register `sidebar` snapshot (rendered over a solid canvas color, since live vibrancy is non-deterministic — snapshot the row CONTENT, not the material). Record + verify.
- [ ] **Step 4** — Commit `feat(ui): vibrant sidebar (+ golden)`.

### Task 9: The real scene — `NavigationSplitView` wiring live data

**Files:** Rewrite `ProfilesApp.swift`; Create `EnginePath.swift`, `DashboardView.swift`.

- [ ] **Step 1** — `EnginePath.swift`: `resolveEnginePath()` → `ProcessInfo…environment["SPIKE_ENGINE"]` if set, else `Bundle.main.resourcePath + "/engine.sh"`, else `"engine.sh"` (dev uses the env var pointing at the repo `src/engine.sh`; bundling is Phase 6).
- [ ] **Step 2** — `DashboardView(store:)`: the content column — `KPIStripView(profiles:)` + a `LazyVGrid(.adaptive(minimum:300, maximum:380), spacing:16)` of `ProfileCardView`s built from `store.profiles` (sorted alive-first; each card computes its `AlertState` by feeding a per-slug `PtmxHysteresis` — keep the hysteresis instances in an `@State` dictionary keyed by slug so they persist across ticks; CPU/Mem sparkline series come from a rolling 30-point history kept in the store/view). For Phase 2, a simple rolling history in the view is acceptable.
- [ ] **Step 3** — `ProfilesApp.swift`: `@main` with `@State var store = StatsStore(engine: EngineClient(enginePath: resolveEnginePath()), clock: RealClock())`, a `NavigationSplitView { SidebarView(...) } detail: { DashboardView(store: store) }`, `.toolbar` (window-stack glyph + "Profiles" + a New Profile button — non-functional placeholder OK), `.onAppear { store.start() }`, `.frame(minWidth:840, minHeight:560)`. Add a `MenuBarExtra("Claude Profiles", systemImage: "square.on.square")` listing `store.profiles` names (focus wiring is Phase 5 — a static menu is fine).
- [ ] **Step 4** — Build + run against the real engine: `cd app && SPIKE_ENGINE="$(git -C .. rev-parse --show-toplevel)/src/engine.sh" swift run Profiles`. Confirm the window shows your real profiles with live-updating CPU/Mem sparklines and the KPI strip. (Controller will also visually QA this.)
- [ ] **Step 5** — Register a `window-full` snapshot at a fixed size built from `Fixtures` (looser tolerance ~1%). Record + verify. Commit `feat(ui): NavigationSplitView scene + live data wiring (+ golden)`.

### Task 10: Full visual QA pass

- [ ] **Step 1** — Run `swift run ProfilesCoreTests` (still 18+/0) and `swift run ProfilesSnapshotTests` (all goldens pass). Build the release: `swift build -c release`.
- [ ] **Step 2** — Render every view golden and confirm against the mockup (controller reads the PNGs). Fix any token/layout drift.
- [ ] **Step 3** — Commit any fixes. The macOS CI already runs both runners — open the Phase 2 PR and confirm green.

---

## Self-review notes (author)
- **Spec coverage:** window/split-view + sidebar (T8, T9), KPI strip (T7), running/stopped/default cards (T5, T6), sparklines (T4), handle gauge (T5), live data loop (T9), Theme tokens (T1), snapshot harness (T2). Inspector/modals/menu-bar/Show Window correctly deferred to Phase 3+.
- **Type consistency:** views consume `ProfileStat`/`AlertState`/`PtmxHysteresis`/formatters/`sortProfiles` from `ProfilesCore` (Phase 1); `Theme` tokens used everywhere; `snapshotMode` env flag threaded through animated views; snapshot cases reference `Fixtures`.
- **Visual acceptance is the gate** for views (PNG vs mockup), not code assertions — by design for UI.
