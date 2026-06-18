# Menu-bar switcher — design

## Goal
Focus/launch any profile from a macOS menu-bar item without raising the dashboard
window — the feature you touch dozens of times a day.

## Approach
Add an `NSStatusItem` to the existing dashboard applet (it's already a stay-open
NSApplication on the main thread, with a proven `focusInstance` focus-by-PID
helper). The status item's menu is rebuilt on open (menu delegate) from a new
lightweight engine command, and each profile row reuses `focusInstance`.

### Engine — `menulist` (new, testable)
One tab-separated line per instance: `slug<TAB>display-name<TAB>running(1|0)`.
The default instance is the sentinel slug `default`, listed first. Lighter than
`stats` (no metrics) — cheap to call on every menu open. Pure projection of data
the engine already derives; no new state.

### Applet
- `NSStatusItem` with a template SF Symbol (`square.on.square`, matching the
  window-stack app icon) and a title fallback for < macOS 11.
- Menu `delegate = me`; `menuNeedsUpdate:` rebuilds items from `engine menulist`
  (parsed with `paragraphs of` + `tab`). Running instances get a `●` marker.
- Each row: `target = me`, `action = menuClicked:`, `representedObject = slug`.
  `menuClicked:` calls `focusInstance("focus", slug)` (or `"focusdefault"` for the
  default). Plus **Show Dashboard** and **Quit Claude Profiles** (⌘Q) items.

### Behavior change (flagged)
For the status item to persist, the app must survive closing the dashboard window.
- `on idle` no longer quits when the window is closed; it just skips the stats
  sweep while hidden (autotick still runs, so auto-rules work from the menu bar).
- Closing the window hides it (`setReleasedWhenClosed:false` already set); **Quit**
  (menu or ⌘Q) terminates. `on reopen` re-shows the window (Dock-icon click or the
  manager re-launching).

## Testing
- Engine: `menulist` lists `default` first with its running flag; a running
  profile is `1`; a stopped one is `0`; output is tab-separated.
- Applet: `osacompile -s` parses/compiles clean; grep asserts the status item,
  menu delegate, and `menulist` wiring are present.
- **FLAG — needs real-Mac verification** (suite can't drive AppKit): the item
  appears; the menu lists profiles; clicking one focuses it; close→hide,
  Quit→exit, Dock-click→reopen.

## Non-negotiables
Zero deps, zero network, built-ins only, bash 3.2. Focus is by PID
(NSRunningApplication / System Events) — no credentials, no Claude.app or data-dir
access. Docs (RELEASE-VERIFY, CLAUDE.md) updated for the close-vs-quit change.
