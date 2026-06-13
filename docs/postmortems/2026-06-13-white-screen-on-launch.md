# Postmortem — Dashboard launches to a blank white window

- **Date:** 2026-06-13
- **Author:** jyito (with Claude)
- **Status:** Resolved — immediate fix applied; **hardening (action #1) now landed**
- **Severity:** High — the manager app was unusable (no dashboard rendered)

## Summary

The Claude Profiles manager opened its window, but the dashboard area rendered
as a blank white pane instead of the dark UI. The window chrome (titlebar,
traffic lights) appeared normally; only the WebView content was missing.

Root cause: the compiled dashboard applet cached in
`~/.claude-instances/.runtime/` had a manager **Resources path baked in from a
previous install location** (`~/Applications/Claude Profiles.app`). The app had
since moved to `/Applications/Claude Profiles.app`, so the applet's
`loadFileURL:` pointed at a `dashboard.html` that no longer existed, and the
WebView painted nothing.

## Impact

- The dashboard window was non-functional — no profile cards, no stats, no
  controls. The app was effectively dead on launch.
- No data loss. Profile data dirs, credentials, and settings were untouched.
- Scope: the maintainer's Mac. Not shipped to any other users.

## Timeline (2026-06-13)

| Time | Event |
|------|-------|
| — | App previously installed and launched from `~/Applications/Claude Profiles.app`; this compiled the runtime applet, baking that path. |
| — | App moved/reinstalled to `/Applications/Claude Profiles.app`; `~/Applications` copy removed. The stale runtime applet was left in place. |
| T0 | User launches the app → blank white window. Reports it as critical. |
| T0+ | Investigation: worktree `dashboard.html`/JS both parse cleanly (ruled out a syntax/render error). |
| T0+ | Found the cached applet's substituted source bakes `resourcesDir = "/Users/<you>/Applications/Claude Profiles.app/Contents/Resources"`; that path no longer exists (app is at `/Applications/...`). Root cause confirmed. |
| T1 | Recovery: `rm -rf ~/.claude-instances/.runtime` + relaunch from `/Applications`, forcing a recompile with the correct path. |
| T2 | Dashboard renders correctly. Resolved. |
| T3 | Hardening landed: `launch_dashboard` now self-heals a moved app (see Resolution). |

## Root cause

`launch_dashboard` (in `src/launcher`) substitutes `__RESOURCES__` with the
manager's current `Contents/Resources` path, compiles the result into a
stay-open applet under `~/.claude-instances/.runtime/`, and — by design —
**reuses that compiled applet on subsequent launches** so the ad-hoc signature
stays stable (which keeps the one-time Automation grant alive).

That reuse did not account for the compiled applet having been built against a
manager location that no longer exists. Worse, the single-instance guard
re-`open`ed a *running* stale applet before any path check. When the app moved,
the cached applet kept pointing `loadFileURL:` at the dead
`~/Applications/.../dashboard.html`. A failed file load in WKWebView renders as
a blank white pane with no error surfaced to the user.

The blank-*white* (rather than the dark `#1A1915` startup splash) was the key
diagnostic signal: a JavaScript error would still paint the static HTML/CSS
splash, so white meant the document never loaded at all.

## Detection

User-reported. There is no automated check for "WebView failed to load" — the
applet/WebView layer is the one layer the test suite cannot exercise.

## Resolution

Immediate recovery (already documented in CLAUDE.md for stale runtime):

```
rm -rf ~/.claude-instances/.runtime
open "/Applications/Claude Profiles.app"
```

Permanent fix (action item #1): `launch_dashboard` now calls
`runtime_applet_stale`, which **exact-matches** the baked `resourcesDir` against
the manager's current Resources path. On a mismatch it quits any stale instance
and drops the cached build so it recompiles against the live path. The
exact-match is deliberate: `/Applications/…` is a *substring* of
`/Users/x/Applications/…`, so a substring test would have missed this very case.
Covered by regression tests in `tests/run-tests.sh` (`== dashboard self-heal ==`).

## What went well

- Systematic, layer-by-layer diagnosis (HTML/JS validity → load mechanism →
  baked path → filesystem reality) found the true root cause rather than
  guessing at the UI code, which had just changed.
- The "white vs. dark splash" distinction quickly ruled out the most tempting
  suspect (the recent badge-color edits to `dashboard.html`).

## What went poorly

- The cached applet could silently outlive the install location it was built
  for, with no self-healing and no user-visible error — just a blank window.
- First recovery instructions bundled inline `#` comments and a Unicode `→`
  into pasteable shell, which zsh mis-parsed; and a suggested broad
  `pkill -f "Claude Profiles Dashboard.app"` matched too widely. Recovery steps
  handed to a user should be plain, comment-free, one command per line, and
  avoid broad `pkill -f`. The landed fix uses a `ps`/`kill` on the full
  `.runtime` applet path, not a broad pattern.

## Action items

1. **Harden `launch_dashboard` against a moved app.** ✅ **Done** — exact-match
   `runtime_applet_stale` + self-heal + regression tests.
2. **Surface load failures in the applet.** Have the WebView detect a failed
   `dashboard.html` load and show a visible error (path + "delete
   ~/.claude-instances/.runtime to rebuild") instead of a blank pane.
   *(Open; requires real-Mac testing.)*
3. **Recovery-doc hygiene.** Plain one-command-per-line snippets, no inline
   comments, no Unicode, no broad `pkill -f`. *(Done.)*
4. **Rebuild/reinstall** so the running app matches current source.
   *(Maintainer — open.)*
