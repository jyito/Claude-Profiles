# Claude Profiles v0.3.0 — Granular Controls, Cleanup & Polish

**Status:** approved design (2026-06-12) · **Target release:** v0.3.0
**Author:** brainstormed with the maintainer (jyito)

This spec covers the v0.3.0 feature batch: per-instance drill-down with terminal
detail, attribution hardening, terminal/cache cleanup automation, UI polish, and
a distinctive app icon. It honors every CLAUDE.md non-negotiable — no credentials,
no network, no dependencies, default data dir off-limits, bash 3.2.

## Goals

1. **Trustworthy metrics.** No per-instance stat (CPU/MEM/terminals/disk) may ever
   include another instance's processes. This is the foundation; everything else
   surfaces these numbers in more detail, so they must be exact.
2. **Drill into an instance** to see its process tree and individual terminals, and
   act on them (close an idle terminal, clean that profile's caches) without
   leaving the dashboard.
3. **Reduce idle waste** — manual and opt-in-automatic cleanup of idle terminals
   and regenerable caches, with conservative, clearly-labeled defaults.
4. **Feel polished** — button hover/press reactivity and a startup loading screen.
5. **Look distinctive** — an icon that reads as "many Claudes, managed" at Dock size.

Non-goals (deferred): the inter-Claude message bus (its own v0.4.0 spec); SwiftUI
dashboard; per-profile icon tinting.

---

## 1. Attribution hardening (foundation) — DONE

The user's recurring concern: "ensure the usage metrics aren't getting confused
between apps." Audit of `engine.sh` found two real bleed paths, both now fixed and
covered by regression tests (suite at 40/40).

### Bug A — substring prefix collision (`main_pids_for_dir`)
`index($0, "--user-data-dir=$1")` was a substring match. With two profiles whose
data dirs are prefix-colliding (`…/work` is a substring of `…/work2`), querying
`work` also matched `work2`'s process, so `work`'s CPU/MEM/terminal totals silently
absorbed `work2`. Fixed: the matched `--user-data-dir=<dir>` must be a **complete
argv value** — the character immediately after must be a space (next token) or end
of line. Space-tolerant within the path; rejects any longer dir.

### Bug B — terminal double-counting (`pty_count_for_pids`)
`grep -c ' /dev/ttys'` counted lsof **lines**. A single `/dev/ttysNN` held by the
Electron main process and inherited by a helper counted twice. Fixed: dedup by
device — `awk '$NF ~ /^\/dev\/ttys/ {print $NF}' | sort -u | wc -l`.

This dedup also answers *"which terminal goes to which Claude?"*: every terminal is
reached by walking that instance's own `tree_pids`, so each `/dev/ttysNN` is
attributed to exactly one instance by construction. The default instance stays
isolated — it is matched by the *absence* of `--user-data-dir`, so no profile can
leak into it or vice-versa.

### Testability change
`engine.sh`'s dispatch is now guarded by `if [ "${BASH_SOURCE[0]:-$0}" = "$0" ]`,
so the suite can source the file and unit-test `main_pids_for_dir` /
`pty_count_for_pids` directly. New section `== attribution isolation ==` proves both
fixes (they fail on the old code).

---

## 2. Drill-down UI — full-width expand-in-place

**Decision (research-backed):** expand the card in place to a full grid-width panel,
one open at a time, Escape collapses. NN/G and master-detail pattern guidance favor
expand/drill for "act on one item" workflows over a persistent side panel (which is
for rapidly flipping between items and would be cramped at the 620px window min).
Modal was rejected — it hides the live data the user came to watch.

### Layout
- Clicking a card's header (or a chevron affordance) expands it to span the full grid
  row; the rest of the grid reflows below.
- Expanded content, two columns:
  - **Terminals** — a table, one row per `/dev/ttysNN`: device, owning PID, the
    command running in it (from `ps -o command=` for that PID), and idle time.
  - **Controls** — per-instance clean tiers (caches / GPU / logs — the cleanup
    modal's granular actions, scoped to this profile) and the existing
    Quit/Force/Remove, plus Resource priority (see §4) and Launch options (§4).
- `uiLock` extends to the expanded state so the 2s tick never eats a click; live
  numbers still update in place while expanded.
- Exactly one card expanded at a time. Escape or re-click collapses.

### Engine support
New `terminals <slug>` verb emits a JSON array of `{dev, pid, cmd, idle}` for the
instance's tree. Idle time derives from the controlling process's CPU state / last
activity heuristic available without extra dependencies (`ps -o lstart=,state=`); if
a precise idle metric isn't cheaply available, the column shows the process's elapsed
time and we label it honestly ("running for", not "idle for") rather than guessing.

> Open implementation question to resolve in the plan: the cheapest dependency-free
> idle signal. Candidates: tty atime via `stat -f %a /dev/ttysNN` (may be permission/
> semantics-limited), or process CPU-time delta across two ticks. Pick in the plan;
> never kill on a guessed-idle signal (see §3).

---

## 3. Terminal & cache cleanup

### Terminals (live Claude Code sessions — handle with care)
Killing a terminal kills whatever runs in it, so the trigger must be precise.

- **Manual (v0.3.0):** the drill-down lists each terminal with its idle/elapsed time
  and a per-row "Close" action (sends SIGHUP/TERM to the terminal's owning PID).
  Confirmation on click; never a bulk silent kill.
- **Automatic (opt-in, off by default):** a setting "auto-close terminals idle >
  N minutes" enforced on the 2s tick, with a conservative default (e.g. 120 min) and
  a clear warning that a long-running build emitting no output can look idle. Disabled
  unless the user explicitly turns it on and accepts the warning.

### Caches (regenerable only — already safe)
- **Manual:** per-instance clean tiers in the drill-down (reuses `cmd_clean`, which
  refuses to run on a live instance and never touches logins).
- **Automatic (opt-in):** settings panel rule "auto-clean stopped profiles when
  caches exceed N MB," checked on the 2s tick using the existing 30s-cached `du` (so
  it's cheap). Only ever touches **stopped** instances and regenerable Electron
  caches — never logins, never the default instance.

### Settings storage
A single JSON file at `$INSTANCES_DIR/.runtime/settings.json` (local-only, honors
zero-network). Read by `engine.sh` on the tick; written by the dashboard via a new
`setconfig <json>` verb. Schema: `{autoCloseIdleMin: 0|N, autoCleanThresholdMB:
0|N}` where `0` = disabled. Defaults: both `0`. The default instance is never a
target of any automatic rule.

---

## 4. Granular per-instance controls (drill-down panel)

Per the user's multi-select, the panel includes all four:
- **Per-instance drill-down** — the process tree + terminals (§2).
- **Per-instance clean tiers** — caches / GPU / logs scoped to one profile (§3).
- **Resource limits** — `renice` the instance tree to lower CPU priority ("Throttle"
  toggle → `renice +10`; "Normal" → `renice 0`). Memory ceilings are not available
  dependency-free on macOS, so they are **out of scope** — surfaced as "not
  supported" rather than faked.
- **Launch options** — per-profile flags stored alongside the wrapper: "open
  minimized" and "auto-launch at login" (via a LaunchAgent plist the wrapper writes
  to `~/Library/LaunchAgents`, user-toggled, removable). "Launch a Claude Code
  workspace alongside" is deferred to the message-bus milestone.

> Scope guard: Resource limits and Launch options are the most invasive. If the plan
> shows either bloating v0.3.0, they split to v0.3.1 — drill-down + cleanup + polish
> + icon are the committed core.

---

## 5. Polish

- **Button reactivity:** hover (subtle lift/tint), active/press (depress), and
  focus-visible outlines for every button class in `dashboard.html`. Pure CSS;
  respects the existing coral/mint palette. Verified by the node-based render test
  (class presence) and visual check.
- **Startup loading screen:** the applet shows a branded splash (dark bg, app mark,
  "Starting Claude Profiles…") immediately on launch, replaced when the first
  `updateStats` arrives. Lives in `dashboard.html` as the initial DOM state; the
  WebView loads it instantly while the first engine `stats` call runs.

---

## 6. Icon (maintainer chose to delegate)

**Direction:** refine the existing "stacked window cards" mark into a distinctive
deck-of-profiles: three overlapping rounded squares fanned with a slight offset, in
the profile tints (coral `#D85A30`, mint `#5DCAA5`, and a neutral warm gray) on the
dark `#1A1915` background. Reads as "multiple identities, managed" at Dock size and
is **trademark-safe** — no Anthropic Claude artwork is committed to the repo (a hard
constraint, as the repo is going public). The asterisk/starburst idea the user liked
is Anthropic's mark and cannot ship in-repo; the fanned-deck metaphor conveys the
same "many Claudes" idea originally.

Deliverable: an SVG master in `assets/`, baked to the `.iconset` PNG ladder and
`app.icns` via `build.sh`'s existing `iconutil` flow. Rasterization approach (no new
runtime dependency) is an implementation detail for the plan.

---

## Testing strategy

- **Suite-verifiable (I own these):** attribution isolation (done), `terminals` verb
  JSON shape, `setconfig`/settings round-trip, auto-clean threshold logic, `renice`
  command construction, launch-option plist generation, dashboard JS render
  (cards/terminals table/buttons), button-class presence.
- **Maintainer-Mac-only (queued, never claimed working unverified):** anything
  touching `dashboard.applescript` / the applet (drill-down rendering in the real
  WebView, loading-splash timing, Show Window), the actual icon in the Dock, and any
  `renice`/LaunchAgent behavior that needs a real process. Each lands with an
  explicit "verify on your Mac" checkpoint.

## Rollout order (for the implementation plan)

1. Attribution hardening ✅ (done, tested, ready to commit)
2. `terminals` verb + drill-down panel (engine + HTML + applet routing)
3. Manual terminal close + per-instance clean tiers
4. Settings storage + auto-clean threshold + opt-in auto-close
5. Polish (buttons + loading screen)
6. Resource limits + launch options (split to v0.3.1 if heavy)
7. Icon master + bake
