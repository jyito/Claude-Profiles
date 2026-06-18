# Auto-restart on leak threshold — design

## Problem
The `/dev/ptmx` leak (shipped detection in PR #4) still needs a manual click to
clear. For instances you leave running for days, the wedge can arrive while you're
away. Make the remedy automatic, opt-in, and conservative.

## Approach
A new opt-in setting `autoRestartLeakAt` (non-negative integer, default `0` = off).
When set to N, the existing `autotick` sweep restarts any **profile** instance
holding ≥ N leaked `/dev/ptmx` masters, reusing the `restart` action shipped in #4.

Scoped to **profiles only**, never the default instance — consistent with the
existing `autotick` invariant (auto-clean / auto-close already iterate
`all_profile_slugs` and never touch the default). Auto-cycling the user's primary
Claude unprompted is too intrusive; the default still has its manual Restart.

## Changes
- **engine `getconfig`** — emit `autoRestartLeakAt` (defaults 0).
- **engine `setconfig`** — accept/validate the key (non-negative int).
- **engine `autotick`** — add a third enforced rule: for each running profile,
  if `ptmx_count_for_pids(tree) >= autoRestartLeakAt` and the threshold > 0,
  `cmd_restart <slug>`. The whole sweep stays a no-op while all three knobs are 0.
  `autotick` is already invoked detached (`… &`) by the applet, so `restart`'s
  ~5s wait can't block the UI.
- **dashboard Settings modal** — a third control to set the threshold (0 = off),
  driven by the existing `getconfig`/`setconfig` plumbing, with a caveat that an
  auto-restart closes that instance's windows.

## Testing
- `setconfig autoRestartLeakAt N` persists; `getconfig` reflects it.
- `setconfig` rejects a non-integer for the new key.
- `autotick` with the threshold below a running profile's leak count invokes
  `restart` for that slug (stub `cmd_restart`, assert it's called); above the
  count, it does not.
- Render: the Settings modal exposes the new control wired to `setconfig`.

## Non-negotiables
Zero deps, zero network, built-ins only, bash 3.2. Only signals processes (via the
existing guarded `restart`); never touches credentials, Claude.app, or any data dir.
Default instance is never auto-restarted.
