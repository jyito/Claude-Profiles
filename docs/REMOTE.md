# Remote into a profile's Claude Code session

Drive a profile's **Claude Code** session from another device — your iPad, a
laptop, your phone — and get real responses back. It's the better, more powerful
alternative to a mobile remote-control for coding work.

## How it stays safe

Claude Profiles **never opens a network connection** — that's a founding rule
(zero network I/O). This feature doesn't change that. It just runs your Claude
Code session inside `screen` (a terminal multiplexer that ships with macOS), and
**you** reach it over your own SSH connection. The app is local; the secure
channel is yours.

## One-time setup

1. **Turn on Remote Login** (SSH) on your Mac:
   System Settings → General → Sharing → **Remote Login** → on.
2. **(To reach it from anywhere, not just your home Wi-Fi)** install
   [Tailscale](https://tailscale.com) on your Mac and your iPad — it gives your
   Mac a stable name you can SSH to from any network, with no port-forwarding.
   On a trusted local network you can skip this.
3. On your iPad, install an SSH terminal app (Blink Shell, Termius, a-Shell).

## Use it

On your Mac, start (or re-attach to) a profile's Claude Code session:

```
cli/claude-profiles.sh remote Work
```

It prints exactly how to attach, e.g.:

```
Started a Claude Code session for profile 'Work' (screen: claude-work).

Attach on this Mac:
  screen -r claude-work          (detach without quitting: Ctrl-A then D)

Attach from another device (e.g. an SSH app on your iPad):
  ssh you@your-mac.local -t "screen -r claude-work"
```

From your iPad's SSH app, run that `ssh … screen -r claude-work` line and you're
in the live session — type, get responses, detach with **Ctrl-A then D** (it
keeps running on your Mac), reattach later from anywhere.

- Each profile gets its own session (`claude-<slug>`) using that profile's
  `CLAUDE_CONFIG_DIR` (`~/.claude-code-instances/<slug>`), so accounts stay
  separate. Sign Claude Code into the matching account once.
- List sessions: `screen -ls`. Quit one: `screen -X -S claude-work quit`.

## What this does and doesn't cover

- ✅ **Claude Code** (the CLI/agent) — fully remote, this is the sweet spot.
- ❌ **Claude Desktop chats / Cowork** (the GUI) — there's no clean programmatic
  way to drive the Electron UI remotely, and faking it would mean scripting
  Claude's interface (fragile, privacy-adjacent, against the project's rules).
  For chat on the go, use the Claude app on your device directly.
