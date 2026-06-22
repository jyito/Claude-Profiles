# SwiftUI dashboard — full design (native rewrite)

The native SwiftUI replacement for the AppleScriptObjC + WKWebView dashboard host.
The bash `engine.sh` backend and the profile `.app` wrappers stay unchanged; only
the **manager window** is rewritten. Grounded by the Phase-0 spike (GO —
`docs/swiftui-spike-findings.md`), the design exploration (winning direction "Calm
Instrument"), and the testing strategy (`docs/superpowers/specs/2026-06-22-swiftui-testing-strategy.md`).

## Locked decisions

- **Full replacement** of the WebView/AppleScriptObjC host. `dashboard.html` +
  `dashboard.applescript` retire at cutover.
- **`engine.sh` stays the single source of truth.** The app shells out to it via
  `Process` and `Codable`-decodes the stats JSON — replacing the `document.title`
  title-bridge. No stats/actions logic moves into Swift.
- **Build with Command Line Tools `swift` — no full Xcode.** Hand-assemble the `.app`
  (as `scripts/build.sh` already does) + `codesign` (Developer ID, hardened runtime).
- **macOS 14+**, **non-sandboxed** (Developer ID direct distribution; the App Store is
  out — it would forbid the spawning/`lsof`/`ps` the engine needs).
- **Zero runtime dependencies**, **zero third-party test dependencies** (all hand-rolled).
- **UI direction: "Calm Instrument."** Native split view + right-side inspector (no
  fragile in-place card-morph), instrument-style KPI strip, calm severity ladder.
- **e2e tests: maintainer pre-merge gate** for now (self-hosted Mac later if earned).

## Architecture

```
┌─ Claude Profiles.app (SwiftUI, non-sandboxed, Developer-ID signed) ─┐
│  App target "Profiles"  ──imports──▶  ProfilesCore (no SwiftUI)     │
│    • SwiftUI scene: NavigationSplitView + .inspector + MenuBarExtra  │
│    • @Observable StatsStore(engine: any EngineRunning, clock:)       │
│        └─ 2s poll ─▶ EngineClient.stats() ─▶ [ProfileStat]           │
│    • Views: sidebar, KPI strip, cards, inspector, sheets            │
│  ProfilesCore (pure, SwiftUI-free, even Linux-runnable):            │
│    • ProfileStat (Codable) · decodeList                              │
│    • PtmxHysteresis (severity state machine)                        │
│    • formatBytes/Percent/Ptmx · sortProfiles (alive-first)          │
│  Resources/engine.sh  (bundled copy of the real backend)            │
└──────────────┬──────────────────────────────────────────────────────┘
               │ Process: /bin/bash <engine.sh> <verb> [args]
               ▼
        engine.sh (unchanged) ──▶ ps / lsof / sysctl / screen / du …
```

**Data flow (replaces the title-bridge):** a `@MainActor @Observable StatsStore`
runs `engine.sh stats` off the main actor every 2s (`Task.detached` → `Codable`
decode), publishes `[ProfileStat]`; SwiftUI re-renders. Actions are one-shot
`engine.sh <verb> <slug>` calls. The same store backs the window **and** the
`MenuBarExtra` (running dots consistent by construction). `StatsStore.init` is
`nonisolated` (spike gotcha) so the scene's `@State` initializer can build it.

**Seams (extracted first — see testing strategy):** `protocol EngineRunning`
(real `EngineClient` vs `FixtureEngine`), `protocol PollClock` (real 2s vs
`ImmediateClock`), the SwiftUI-free `ProfilesCore` module, fixture-init snapshot
views, and a stable `.accessibilityIdentifier()` on every control.

## Module / file structure

- **`ProfilesCore/`** (library target, no SwiftUI): `ProfileStat.swift` (Codable +
  `decodeList`, empty-slug→`"default"`, `disk==-1` sentinel), `PtmxHysteresis.swift`,
  `Formatters.swift`, `Sort.swift`, `EngineRunning.swift` (protocol), `PollClock.swift`.
- **`Profiles/`** (executable app target, imports ProfilesCore): `ProfilesApp.swift`
  (`@main`, `WindowGroup` + `MenuBarExtra`), `EngineClient.swift` (real `Process`),
  `StatsStore.swift` (`@Observable`), `Theme.swift` (tokens), and a `Views/` group:
  `SidebarView`, `KPIStrip`, `ProfileGrid`/`ProfileList`, `ProfileCard`,
  `Sparkline`, `BadgeDisc`, `InspectorView` (+ `TerminalsTable`, `CleanTiers`,
  `BadgePicker`, `RemoveProfile`, `LeakBlock`), and `Sheets/` (`NewProfileSheet`,
  `SettingsSheet`, `CleanupSheet`, `RemoteSheet`).
- **Test targets** (executables, not `testTarget`): `ProfilesCoreTests`,
  `ProfilesSnapshotTests`; the in-repo `XCTest` shim target; `tests/snapshot/pngdiff.py`.
- **Build:** `scripts/build.sh` extended to `swift build -c release` → hand-assemble
  the bundle → copy `src/engine.sh` into Resources → `codesign`. CI in
  `.github/workflows/ci-macos.yml`.

## UI design — "Calm Instrument"

Faithful to the approved mockup. The tokens below plus this section are the canonical
design; the load-bearing decisions:

**Window & layout.** `NavigationSplitView` (two-column), `.windowToolbarStyle(.unified)`,
real traffic lights, no custom-drawn title bar. Toolbar: leading window-stack glyph
(coral) + "Profiles"; trailing Grid/List segmented toggle, Settings (⌘,), Cleanup,
and the one coral **New Profile** (`.borderedProminent`, ⌘N). Default ~1080×720,
min ~840×560.

**Sidebar (~240pt).** Vibrant `List(selection:)`, `.listStyle(.sidebar)`. Sections
"Profiles" (accounts) + "System" (the Default row, `lock` glyph). Each row: 8pt
running(mint)/stopped(hollow) dot + 18pt badge-disc + name + trailing MEM when running.
Footer pins the coral New Profile button. Selection drives the inspector.

**KPI strip.** A full-width instrument band (surface1, 14pt radius) of hairline-divided
cells: Memory in use + teal micro-bar + "across N running", Running N/M, Total CPU,
Terminals, **Handle pool** N/ceiling + a micro-bar that is neutral <75% / amber 75–90%
/ coral ≥90% and taps to flash the worst-offending card. The **only** place fleet
aggregates live; cards carry per-instance only.

**Grid.** `LazyVGrid(.adaptive(minimum:300, maximum:380))`. **Alive-first sort:**
Default pinned → running (mint) → stopped (recessed). A **List view** toggle (dense
`Table`, same `@Observable` models) is the power-user escape hatch.

**Card anatomy.** surface1, 14pt radius, hairline + rim-light stroke, no drop shadow
(depth = surface ladder). Selected = 1.5px coral inset ring. Dim grid to ~0.85 when
window inactive (`\.appearsActive`).
- *Running:* identity row (34pt badge-disc + name + `ellipsis` overflow `Menu` →
  Quit/Force/Restart, mirrored by `.contextMenu`); status line (breathing mint dot +
  "Running · N Procs · M Terminals"); a two-column metric row, each = eyebrow + big
  `.monospacedDigit` value with `.contentTransition(.numericText())` + a **Swift Charts**
  sparkline (`LineMark`+`AreaMark`+ live-edge `PointMark`, hidden axes, pinned
  `.chartYScale`); a **handle-pool gauge** (4px bar + "N / ceiling handles", calm under
  75%, escalating per the severity ladder); a primary action row — **Show Window**
  (mint-tinted) + **Remote** (mint live-dot when up) + a **Details ›** chevron opening
  the inspector.
- *Stopped:* whole card dimmed ~0.6, zero accent; "Stopped · opened N× · last <date>",
  a "Disk X" line, the last sparkline **ghosted** (gray ~25%), single **Open** (mint
  border). Details → clean tiers.
- *Default:* "System" treatment (faint `lock`); Show Window/Quit/Force/Open + Remote +
  terminals-only Details. **Structurally** has no disk, clean tiers, badge picker,
  Remove, or leak-restart — the restricted contract is unbreakable by construction.

**Inspector (`.inspector(isPresented:)`, ~340pt).** The drill-down — toggled by
⌘⌃I / "Details ›" / selection. **The grid never reflows; sparklines never jump**
(the in-place-morph hazard designed out). Header echoes the account's avatar + name +
status. *Running:* `Table` of terminals (Device SF-Mono mint · Command dimmed · Idle ·
per-row Close arm→confirm), Throttle CPU, then the **leak block** (amber tile: "N
leaked terminal handles macOS can't reclaim (a Claude Desktop bug). Restart frees
them." → 2-step Restart whose confirm copy explains the quit/reopen). *Stopped:*
"Using X on disk" + four clean tiers (Caches/GPU/Logs/Everything, no confirm — they're
regenerable) + a 6-swatch badge picker (absent on default). **Remove** at the bottom:
a quiet button expanding to a typed-confirmation field where the user types the
**account's own name** (guards the work/work2 prefix hazard); armed button desaturated
red, never coral.

**Modals (`.sheet`).** New Profile (single `TextField` + **live identity-disc preview**
— type a name, see the deterministic color+initial), Settings (native `Form` + three
`Picker`s: auto-clean / auto-close-idle / auto-restart-on-leak, amber ⚠ on the two
footguns), Cleanup (Quit All / Clear Caches / Emergency Stop — last desaturated-red),
Remote (SF-Mono SSH blocks + Copy → `engine copy`, a `CIQRCodeGenerator` QR, collapsible
Tailscale/iPad steps).

**MenuBarExtra** (`square.on.square`): rebuilds from `engine menulist`; one row per
instance (badge-color swatch + name + mint dot if running) focusing by PID; divider →
New Profile + Quit. Shares the store, so dots match the sidebar.

**Tokens.** Surfaces: canvas `#16150F` · surface1 `#1F1E17` · surface2 `#262419` ·
surface3 `#2E2C1F`; hairline white 6%/11%. Text: `#F1EFE8` → 62% → 40% → 28%.
**Semantic (disciplined):** mint `#5DCAA5` = live/running ONLY; coral `#D85A30` =
brand + the one focus ring + critical ≥90%; **new amber `#E0A333`** = warning.
**Metric identity (separate from severity):** CPU `#E08A5E`, Memory `#4FA8A0` — so a
*busy* card never reads as *broken*; leak tail brightens to hot-orange `#F0997B` past
threshold. Materials/vibrancy only on sidebar + sheets, never on resting data cards.
Type: SF Pro semantic styles + `.monospacedDigit()` on every live number; SF Mono only
for device names/PIDs/slugs/SSH. 4px spacing scale; radii 6/8/10/14/16. Motion:
`.snappy` (interaction), `.smooth(0.4)` (the 2s re-render, no overshoot), `.bouncy`
(sparingly). Single `Theme` enum.

**States.** Empty (centered window-stack mark + one line + the coral CTA), loading
(card-shaped shimmer skeletons), inactive-window dim. Friction tiers: Quit/Force =
one-step `confirmationDialog`; Restart = one-step confirm whose copy explains
disappear/reappear; Remove = typed-own-name two-step.

## Severity / leak model (`PtmxHysteresis`, pure logic)

Per-instance handle pool = `ptmx / ptmxMax`. A sustained-breach state machine with
hysteresis (in `ProfilesCore`, no view/clock/engine): enter **warning** at ≥75% of the
ceiling, and **escalate to critical** only at ≥90% **and** only after **N consecutive**
breach ticks; **de-escalate** from critical only below the 80% low-water band; the
breach counter resets on any sub-threshold tick;
slope sign drives the "▲ climbing" tell (only when rising in the warn band). Three
always-on channels — color **+** glyph **+** number — so it survives grayscale /
colorblindness. This is the **prime unit-test target** (crafted tick sequences,
boundary arithmetic at 90%/80%, off-by-one on the ceiling).

## Feature-parity scope (must match the current dashboard)

Stats fields: name, slug, running, cpu, mem, procs, ptys, ptmx, ptmxMax, disk, opens,
last, color, remote (+ default-instance special-casing). Actions consumed: open, quit,
force, restart, focus, clean(tier), mainpid, defaultpid, terminals, closeterm, throttle,
create, remove, purge, rebadge, setbadge, getconfig, setconfig, remoteinfo, copy,
menulist, and the default/bulk verbs (opendefault/quitdefault/forcedefault, quitall,
cleanall, killswitch). UI parity: KPI summary, card grid (running/stopped/default), live
CPU/MEM sparklines, the leaked-handle stat + restart, terminals drill-down with per-row
close + Throttle, clean tiers, badge picker, New Profile, Settings, Cleanup, Remote
(SSH + QR + copy), the typed-DELETE remove, menu-bar switcher, Show Window across
Spaces, hover/press/focus states, loading splash. Default-instance restrictions per
CLAUDE.md §5 enforced structurally.

## Testing (TDD-first — full doc: 2026-06-22-swiftui-testing-strategy.md)

Three layers on top of the existing bash suite: **Layer 1** logic (executable-runner,
gates PRs) — hysteresis, decode, formatting, sort, store-with-FixtureEngine+ImmediateClock;
**Layer 2** visual snapshots (`ImageRenderer`→golden PNG, `pngdiff.py`, gates PRs) of
deterministic leaf views; **Layer 3** e2e (AXUIElement driver by `accessibilityIdentifier`,
stubbed engine.sh, assert engine side-effects) as the maintainer pre-merge gate. Harness
+ CI stood up **before** features; every new `engine.sh` verb still gets a bash test.

## Build & CI & cutover

- `scripts/build.sh`: `swift build -c release` → hand-assembled `.app` → bundle
  `engine.sh` → `codesign`. No Xcode. `release.yml` (the 6 signing secrets) unchanged.
- `ci-macos.yml`: `xcode-select` to CLT, cache `.build` per-OS, `swift build`, the two
  `swift run` test suites (snapshot diffs uploaded on mismatch). Linux bash job kept.
- **Cutover:** ship behind the existing manager until parity is verified, then delete
  `dashboard.html` + `dashboard.applescript` and repoint `launcher` at the SwiftUI
  app. Update CLAUDE.md (the title-bridge / applet lessons become historical;
  the SwiftUI architecture replaces them).

## Phasing (each phase ships something testable)

1. **Foundation:** real `Package.swift`, the test harness + macOS CI green on a near-
   empty package, the four seams, `ProfilesCore` with `PtmxHysteresis`/decode/format/sort
   fully unit-tested.
2. **Shell + live data:** window, sidebar, KPI strip, the running/stopped/default card
   grid with live stats + sparklines (the spike's data loop, productionized) + snapshots.
3. **Inspector:** terminals table + Throttle + leak block; clean tiers; badge picker;
   Remove.
4. **Modals:** New Profile (live preview), Settings, Cleanup, Remote (+ QR).
5. **MenuBarExtra**, Show Window/focus, alive-first sort, List-view toggle, states.
6. **e2e** pass + cutover (retire the WebView host, repoint the launcher, docs).

## Out of scope / deferred

No new features beyond parity. Per-profile icon tinting beyond today's badges, the
SwiftUI-only "richer tier" extras, and any Remote/iPad upgrades are a **separate**
effort (the user's "then 2" — level up Remote — comes after this lands).
