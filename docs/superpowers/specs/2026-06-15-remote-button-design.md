# Remote button + in-app Tailscale instructions — design

Date: 2026-06-15

## Goal

Make a profile reachable from another device **without touching the CLI**. Add a
**Remote** button to each profile card that starts/reuses that profile's Claude
Code session and shows copy-paste connect commands, plus **in-app instructions**
for setting up Tailscale (off-network access). Also restyle the drill-down
trigger to look like a real button labeled **"+ Details"**.

Nothing about remote is broken — "fixed" means UI-accessible. This is additive.

## Non-negotiables (unchanged)

- **Zero network I/O.** The app still opens no socket. Remote works by starting a
  local `screen` session; the secure channel is the user's own SSH. The Remote
  modal only *displays* the SSH commands — it never connects.
- **No credentials.** We never read/store logins. Claude Code authenticates
  itself per profile config dir.
- **Zero dependencies / macOS built-ins only.** `screen`, `scutil`, `whoami`,
  `pbcopy` are all built in. `tailscale`/`claude` are optional and detected, not
  required. bash 3.2 compatible.

## Components

### 1. Backend — `engine.sh remoteinfo <slug>`

A new dispatch verb mirroring the CLI's `cmd_remote`, but emitting JSON for the
dashboard instead of human text:

- Resolve `slug → session=claude-<slug>`, `cfg=$HOME/.claude-code-instances/<slug>`.
- If `screen -ls` shows the session, set `alreadyRunning=true`; else start it
  (`screen -dmS "$session" bash -lc "CLAUDE_CONFIG_DIR='$cfg' '$claude_bin'"`).
- Resolve `host="$(scutil --get LocalHostName).local"`, `user="$(whoami)"`.
- If `tailscale` is present, `ts_ip=$(tailscale ip -4 | head -n1)`, else empty.
- Emit one JSON object (use the existing `json_str` helper for escaping):
  ```json
  {"slug":"personal","session":"claude-personal","user":"jane","host":"mac.local",
   "tailscaleIp":"100.x.y.z","alreadyRunning":false}
  ```
- Guard: `screen` missing → emit `{"error":"screen not found"}`. The page shows
  the error in the modal rather than failing silently.

The CLI's text `remote` stays as-is for terminal users. The screen/host/Tailscale
logic is small and duplicated between the two; a shared helper is a fine future
cleanup but out of scope here (the CLI is intentionally standalone, no engine dep).

### 2. Backend — `engine.sh copy` (clipboard bridge)

`navigator.clipboard.writeText` is unreliable under `file://` in WKWebView, so a
**Copy** button routes through the bridge: `engine.sh copy <text>` runs
`printf '%s' "$text" | pbcopy`. Text originates from the page (engine-generated
SSH strings over `[a-z0-9.@-]`), inlined safely. Degrades to a no-op off macOS.

### 3. Bridge — new `cp:remote:<slug>` and `cp:copy:<text>` verbs

In `dashboard.applescript`:
- `cp:remote:<slug>` → `pushRemote(slug)`: `do shell script enginePath & " remoteinfo " & slug`,
  then `evaluateJavaScript("updateRemote(" & json & ")")`. **Excluded from the
  follow-up `pushStats`** in `checkBridge` (per the title-bridge 4Hz-loop lesson —
  any verb that returns data must not re-trigger stats).
- `cp:copy:<text>` → `do shell script enginePath & " copy " & quoted form of text & " &"`
  (fire-and-forget).

### 4. UI — card controls (`dashboard.html`)

Each profile card's secondary controls become a row of two **button-styled**
controls:

- **Remote** — `act('remote', slug)` → sets `cp:remote:<slug>`. Shown on every
  profile card (running *and* stopped — a remote session is independent of whether
  the desktop app is running). Not shown on the default-instance card.
- **+ Details** — the renamed/​restyled expander. Replaces `▾ Terminals (N)` /
  `▾ Cleanup` / `▴ Hide …`. Label is **"+ Details"** collapsed, **"− Details"**
  expanded. The `.expander` CSS changes from a bare text link to the bordered
  secondary-button look (matching `.acts button`: `border:.5px solid #3a382f;
  border-radius:7px; padding:6px 0`). Drill-down **content is unchanged**
  (running → terminals table; stopped → cleanup tiers). The terminal count drops
  from the label — it's already in the card's status line.

`structureSig` already keys on `expanded`/state, so the in-place patch path is
unaffected; these are structural elements rendered in `fullRender`.

### 5. UI — Remote modal (`dashboard.html`)

A new `.scrim`/`.modal` (`id="remotemodal"`), toggled like Settings, populated by
`updateRemote(info)`:

- Title: **Remote access — <Profile>**
- Line: *"Your <Profile> session is ready. Reach it from another device."*
- **Same network** (block, monospace, selectable): `ssh user@host -t "screen -r session"` + **Copy**.
- **Any network**: if `tailscaleIp` → `ssh user@100.x.y.z -t "screen -r session"` + **Copy**;
  else a muted *"To connect from outside your home network, set up Tailscale"* +
  a **Show steps** toggle that reveals the instructions block.
- Note: *Requires Remote Login — System Settings → General → Sharing → Remote Login.*
- Collapsible **"Connect from your iPad / set up Tailscale"** instructions
  (condensed from `docs/REMOTE.md`): install an SSH app; install + sign into
  Tailscale on both devices; paste the line above. A link to `docs/REMOTE.md` for
  depth.
- If `info.error` is set, show it instead of the commands.

### 6. Data flow

```
[Remote button] → document.title="cp:remote:personal"
  → checkBridge (250ms) → handleAction → pushRemote("personal")
    → engine.sh remoteinfo personal   (starts/reuses screen session, prints JSON)
    → evaluateJavaScript updateRemote({...})
      → fill #remotemodal, toggle it open
[Copy button] → document.title="cp:copy:<ssh line>"
  → checkBridge → handleAction → engine.sh copy "<line>"  → pbcopy
```

## Error handling

- `remoteinfo` missing `screen` / not macOS → `{"error":...}` → modal shows it.
- `claude` binary absent → `claude_bin` falls back to `"claude"`; the session
  starts but Claude Code errors on attach. Acceptable (same as CLI today); the
  instructions note Claude Code must be installed.
- Copy off macOS → no-op (no `pbcopy`); the command is still selectable.

## Testing

- **engine `remoteinfo`** (shim `screen`, `scutil`, `whoami`, `tailscale`):
  emits valid JSON; starts a session; `alreadyRunning` true on reuse;
  `tailscaleIp` present/empty with/without the shim.
- **engine `copy`** (shim `pbcopy`): receives the text.
- **dashboard node test**: `updateRemote({...})` fills the modal (ssh lines,
  Tailscale line vs CTA, error path); the card renders a **Remote** button and a
  **"+ Details"** button; `+ Details` toggles `expanded`.
- Full suite + shellcheck + build green; `osacompile` parse-check the applet.

## Out of scope (YAGNI)

- Sharing the desktop profile's *account* with the remote Claude Code session
  (separate auth systems; documented limitation).
- Auto-installing Tailscale or enabling Remote Login (system actions the user
  performs; we only instruct).
- A web/remote-desktop server (violates zero-network).
- Unifying the CLI `remote` and engine `remoteinfo` into one helper (future).
