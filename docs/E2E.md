# End-to-end smoke harness (Layer 3)

The SwiftUI app is tested in three layers:

| Layer | What | Where | Runs in CI? |
|------|------|-------|-------------|
| 1 — logic | `ProfilesCore` (parsing, sorting, hysteresis, badge math) | `app` · `swift run ProfilesCoreTests` | yes (Linux + macOS) |
| 2 — render | `ImageRenderer` snapshot proofs of the views | `app` · `swift run ProfilesSnapshotTests` | yes (macOS) |
| 3 — e2e | drive the **running** app through the macOS Accessibility API | `scripts/e2e.sh` | **no — maintainer gate** |

This doc covers Layer 3.

## Why it's a maintainer gate, not hosted CI

Driving the live GUI means reading and pressing real `AXUIElement`s, which requires
an **Accessibility (TCC) grant** for the process running the driver. Hosted GitHub
runners can't grant TCC — SIP blocks it and there's no logged-in window session —
so Layer 3 can't run there. It's a thing the **maintainer runs on their own Mac**
before the Phase 6b cutover (and whenever the UI changes shape). Layers 1 and 2
carry the automated load; Layer 3 is the final "does the real app actually wire
up" check.

It is deliberately **minimal** — a handful of smoke flows, not a full UI suite.
e2e is the flakiest layer; the value is "the app launches, renders cards from the
engine, and the New Profile sheet opens", not exhaustive coverage.

## What's in `scripts/e2e/`

- **`axdrive.swift`** — a ~150-line `AXUIElement` driver compiled with `swiftc`
  (no Xcode). Finds elements by `AXIdentifier` (a DFS over the AX tree — these map
  1:1 to the SwiftUI `.accessibilityIdentifier(...)` the views already set), and
  can `wait` for one to appear, `press` it (`kAXPressAction`), read its `value`
  (`AXValue`/`AXDescription`/`AXTitle`), or `dump` every identifier in the tree.
- **`engine-stub.sh`** — a fixture engine. Pointed at by `SPIKE_ENGINE`, it emits
  the same JSON shapes `src/engine.sh` does (two profiles + the default instance
  for `stats`, canned `getconfig`/`terminals`/`remoteinfo`/`create`), so **no real
  Claude is touched** and the data is deterministic. Every call is appended to
  `$E2E_STUB_LOG` so flows can assert a button press actually reached the engine.
- **`flows.sh`** — the smoke flows (sourced by the runner): launch → first render
  shows the profile cards (and `stats` was called); the New Profile sheet opens; the
  stopped profile's card is present (the whole grid built). Each assertion prints
  `ok`/`FAIL`; the run exits non-zero on the first failure.
- **`scripts/e2e.sh`** — the runner: builds the bundle (unless `--no-build`),
  compiles `axdrive`, launches the app's binary directly with `SPIKE_ENGINE` →
  the stub (running the binary, not `open`, is what lets the env vars land in the
  app), runs the flows, and quits the app on exit.

## One-time setup: grant Accessibility to your terminal

The driver process (i.e. the **terminal** you run `scripts/e2e.sh` from) must be
Accessibility-trusted:

1. **System Settings → Privacy & Security → Accessibility**
2. Add (and enable) your terminal app — Terminal.app, iTerm, etc.
3. If you switch terminals, grant the new one too.

`axdrive` checks `AXIsProcessTrusted()` and exits with a clear message (code 5) if
the grant is missing, so a forgotten grant fails loud rather than silently passing.

## Running it

```bash
bash scripts/e2e.sh             # build the bundle, then run the flows
bash scripts/e2e.sh --no-build  # reuse the existing dist/ bundle as-is
```

Expected tail on success:

```
flow: launch -> first render
  ok   present: card-work-showwindow
  ok   present: card-default-showwindow
  ok   engine called: ^stats$
flow: New Profile sheet opens
  ok   present: newprofile-field
flow: instance grid present
  ok   present: card-personal-details

e2e: all flows passed
```

A window will briefly appear and the runner quits the app when it finishes. The
fixture engine never touches the real `~/.claude-instances` data or any Claude
process.

## Extending the flows

Add an identifier to a SwiftUI view with `.accessibilityIdentifier("my-id")`, then
in `flows.sh` use `expect_present my-id`, `press my-id`, or
`expect_logged '^verb arg$'` (against the stub log). Run `axdrive dump "Claude
Profiles"` while the app is up to list every identifier currently in the tree.
