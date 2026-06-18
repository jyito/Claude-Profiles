# Remote polish — design

Two ideas were scoped: (a) show whether a profile's Claude Code `screen` session
is live, and (b) a QR of the SSH attach line in the Remote modal.

## (a) Live session status — BUILT
At a glance, know which accounts are remotely reachable right now.

- **engine**: `cmd_stats` captures one `screen -ls` per tick (`SCREEN_SNAP`, dynamic
  scope like `PS_SNAP`). A new `remote_live <slug>` matches the `claude-<slug>`
  session as a whole token (`[.]claude-<slug>[[:space:]]` — the same boundary
  `remoteinfo` uses, so `claude-work` ≠ `claude-work2`). Each instance's stats
  JSON gains a `remote` boolean (default included → `claude-default`).
- **dashboard**: the **Remote** button shows a mint live-dot (`.rdot`) when
  `p.remote`, with a "Claude Code session is live" tooltip. `remote` is folded into
  `structureSig` so the dot appears/clears on a full render.
- Independent of the Desktop app's running state — a stopped profile can still have
  a live remote session, and the dot reflects that.

## (b) QR of the SSH line — DEFERRED (recommend skipping)
A scannable QR needs a from-scratch encoder (byte mode + Reed-Solomon over GF(256)
+ masking/format) — ~300 lines whose **scannability can't be verified in CI** (no
QR decoder available to the suite). Value is marginal: the modal already has the
command + a Copy button, and scanning a raw `ssh … screen -r …` string with an
iPad camera yields plain text you'd still paste, not an auto-connect. Recommend
leaving it out unless the maintainer specifically wants it; if so it ships behind a
"scan to verify on a real device" flag.

## Testing (for (a))
- engine: with a live `claude-business` session, `business` is `remote:true` and the
  default is `remote:false`; with no sessions, all `remote:false`.
- render: a `remote:true` profile renders `.rdot` + the tooltip on its Remote button.

## Non-negotiables
Zero deps, zero network, built-ins only (`screen`), bash 3.2. Read-only — never
starts a session (that stays the explicit Remote click), no credentials, no
Claude.app or data-dir access.
