# Launch posts (drafts)

The repo is public and v0.5.0 is downloadable — these are ready to post. Lead
with **free + honest**. Before a big push: add a dashboard screenshot/GIF (the
hook is visual) and run docs/RELEASE-VERIFY.md on the shipped DMG.

---

## Show HN

**Title:** Show HN: Claude Profiles – run every Claude account at once on a Mac (free, open source)

**Body:**

I kept logging out of my personal Claude to get into my work one, all day. Claude
Desktop only signs in one account at a time.

Claude Profiles gives each account its own permanently-signed-in app, plus a
native dashboard to manage them all. It's a thin, honest launcher around the real
Claude Desktop app — each "profile" just launches Claude with its own
`--user-data-dir`, exactly like separate browser profiles. It never sees your
credentials, never phones home, and never modifies Claude.app (so auto-updates
keep working). Zero dependencies — plain bash + AppleScriptObjC, macOS built-ins
only (that's also why the download is ~100 KB).

The `--user-data-dir` trick is well known and there are a couple of bare wrappers
already. What I wanted and couldn't find was a *complete* app around it: a live
dashboard (CPU/mem/terminals/disk with sparklines), per-profile colored icon
badges so a Dock full of Claudes is readable, drill-down to close idle terminal
sessions, tiered cache cleanup, and one-click "raise this specific instance's
windows."

The newest piece I'm proud of: a **Remote** button. Each profile also gets an
isolated Claude Code (CLI) session, and Remote hands you a copy-paste SSH command
to reach any profile's session from another device — your iPad, phone, laptop —
over *your own* SSH. The app still runs no server and opens no socket; it just
starts the session in `screen` and tells you how to attach. Separate accounts
stay separate (per-profile `CLAUDE_CONFIG_DIR`).

It's free and open source (Apache-2.0). No subscription, no account, no upsell —
you shouldn't have to pay for something this simple, so you don't.

Honest heads-up: the download is **unsigned** (no paid Apple Developer cert yet),
so macOS blocks the first launch — clear it once via System Settings → Privacy &
Security → Open Anyway. It's open source; read every line, and the release ships
SHA-256 sums. Signing/notarization is the top roadmap item.

Unofficial and not affiliated with Anthropic; "Claude" is their trademark. macOS
14+. Feedback very welcome.

GitHub: https://github.com/jyito/Claude-Profiles

---

## r/ClaudeAI (or r/macapps)

**Title:** I built a free, open-source app to run multiple Claude accounts at once on macOS

**Body:**

If you juggle a personal and a work Claude account (or client accounts), you know
the pain: Claude Desktop signs in one at a time, so you're constantly logging out
and back in.

**Claude Profiles** fixes that. Each account gets its own app — `Claude Personal`,
`Claude Work` — permanently signed in, each with a distinct colored badge so you
can tell them apart in the Dock. Run as many at once as you like. There's a native
dashboard to monitor and manage them (live stats, cleanup, "Show Window" to jump
to a specific instance), and a **Remote** button that lets you SSH into any
profile's Claude Code session from your iPad or phone — terminal Claude, reachable
from anywhere, with no server running on your Mac.

How it's safe: it's just a launcher around the **real** Claude Desktop app, using
the same `--user-data-dir` mechanism browsers use for profiles. It never touches
your logins, makes zero network connections, and doesn't modify Claude.app —
auto-updates keep working. No dependencies, nothing to trust beyond plain shell
scripts you can read.

It's completely free and open source — no subscription, no catch. Anthropic has
open feature requests for built-in multi-account support; until that ships, this
is the most complete way I've found to do it.

Unofficial / not affiliated with Anthropic. macOS 14+. The downloaded app is
unsigned, so the first launch needs a one-time System Settings → Privacy &
Security → Open Anyway (it's open source — full steps in the install guide).
Source + downloads: https://github.com/jyito/Claude-Profiles — would love your
feedback.

---

## X / Bluesky (short)

Run every Claude account at once on your Mac — each permanently signed in, with a
live native dashboard and per-profile icon badges. Plus a Remote button to SSH
into any account's Claude Code session from your iPad.

Free. Open source. No subscription, no catch. A thin launcher around the real
Claude Desktop app — never touches your logins, never phones home.

(Unofficial, not affiliated with Anthropic.)
→ github.com/jyito/Claude-Profiles

---

## Posting notes

- Post the **Show HN in the morning ET** on a weekday; reply to early comments fast.
- **Lead with the screenshot/video everywhere** — the dashboard is the hook, and
  the page currently has none. Capture it first.
- Don't name-and-shame paid alternatives; the comparison table on the site does
  the work without you sounding bitter.
- Have answers ready for the obvious questions:
  - *"Is this safe?"* → never sees credentials, zero network, doesn't modify
    Claude.app; it's all readable shell.
  - *"Official?"* → no, unofficial; nominative use of the name.
  - *"Why is it unsigned / how do I open it?"* → no paid Apple cert yet (free
    tool); System Settings → Privacy & Security → Open Anyway, once. SHA-256 sums
    are published; signing is on the roadmap.
  - *"Why does the menu bar still say Claude?"* → link the branded-apps spike doc.
  - *"Can I get the Desktop app on my iPad via Remote?"* → no — Remote is Claude
    Code (terminal), not the Desktop GUI; be upfront about that.
