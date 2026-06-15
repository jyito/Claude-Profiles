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
2. On your device, install an SSH terminal app (Blink Shell, Termius, a-Shell).
3. **To reach your Mac from outside your home network,** set up Tailscale — see
   [From anywhere: Tailscale](#from-anywhere-tailscale-optional-recommended)
   below. On the same Wi-Fi you can skip it.

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

Same network (e.g. an SSH app on your iPad):
  ssh you@your-mac.local -t "screen -r claude-work"

Any network (via Tailscale):
  ssh you@100.x.y.z -t "screen -r claude-work"
```

If Tailscale is running on your Mac, `remote` automatically prints the
works-from-anywhere line too (using your Tailscale address); otherwise it points
you at installing it. From your device's SSH app, run the line that fits where
you are — you're in the live session — type, get responses, detach with **Ctrl-A
then D** (it keeps running on your Mac), reattach later from anywhere.

- Each profile gets its own session (`claude-<slug>`) using that profile's
  `CLAUDE_CONFIG_DIR` (`~/.claude-code-instances/<slug>`), so accounts stay
  separate. Sign Claude Code into the matching account once.
- List sessions: `screen -ls`. Quit one: `screen -X -S claude-work quit`.

## From anywhere: Tailscale (optional, recommended)

On the **same Wi-Fi**, the `you@your-mac.local` line above is all you need. To
reach your Mac from a *different* network — cellular, a café, the office — your
home router's NAT blocks the incoming connection. [Tailscale](https://tailscale.com)
is the clean fix: a free, encrypted peer-to-peer network that traverses NAT with
**no port-forwarding and nothing exposed to the public internet**. (The
alternative — opening port 22 on your router — puts SSH on the open internet and
fails entirely behind carrier-grade NAT, which most home ISPs now use.)

Tailscale is **not** a dependency of Claude Profiles — the app opens no socket
and works without it. It's simply the SSH transport you choose for off-network
access; the secure channel stays yours.

1. **Mac:** install Tailscale (download from [tailscale.com](https://tailscale.com),
   or `brew install --cask tailscale`), open it, and sign in (Google / GitHub /
   email — no separate password to manage).
2. **Device (iPad/phone/laptop):** install Tailscale and sign in with the **same**
   account. Both devices now share one private network.
3. On the Mac, run `cli/claude-profiles.sh remote <Profile>`. With Tailscale up,
   it automatically prints an **"Any network (via Tailscale)"** attach line using
   your Mac's stable Tailscale address (`100.x.y.z`). Use that line from your SSH
   app — from anywhere.

The router never needs touching, and the address stays stable across networks.

## What this does and doesn't cover

- ✅ **Claude Code** (the CLI/agent) — fully remote, this is the sweet spot.
- ❌ **Claude Desktop chats / Cowork** (the GUI) — there's no clean programmatic
  way to drive the Electron UI remotely, and faking it would mean scripting
  Claude's interface (fragile, privacy-adjacent, against the project's rules).
  For chat on the go, use the Claude app on your device directly.
