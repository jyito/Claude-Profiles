# Launch posts (drafts)

Ready to use once the repo is public. Adjust the name if you adopt
"Profiles for Claude". Don't overclaim; lead with free + honest.

---

## Show HN

**Title:** Show HN: Claude Profiles – run every Claude account at once (free, open source)

**Body:**

I kept logging out of my personal Claude to get into my work one, all day. Claude
Desktop only signs in one account at a time.

Claude Profiles gives each account its own permanently-signed-in app, plus a
native dashboard to manage them all. It's a thin, honest launcher around the
real Claude Desktop app — each "profile" just launches Claude with its own
`--user-data-dir`, exactly like separate browser profiles. It never sees your
credentials, never phones home, and never modifies Claude.app (so auto-updates
keep working). Zero dependencies — plain bash + AppleScriptObjC, macOS built-ins
only.

The `--user-data-dir` trick is well known and there are a couple of bare
wrappers already. What I wanted and couldn't find was a *complete* app around it:
a live dashboard (CPU/mem/terminals/disk with sparklines), per-profile colored
icon badges so a Dock full of Claudes is readable, drill-down to close idle
terminal sessions, tiered cache cleanup, and one-click "raise this specific
instance's windows."

It's free and open source (Apache-2.0). No subscription, no account, no upsell —
you shouldn't have to pay for something this simple, so you don't.

Unofficial and not affiliated with Anthropic; "Claude" is their trademark. macOS
only. Feedback very welcome.

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
to a specific instance).

How it's safe: it's just a launcher around the **real** Claude Desktop app, using
the same `--user-data-dir` mechanism browsers use for profiles. It never touches
your logins, makes zero network connections, and doesn't modify Claude.app —
auto-updates keep working. No dependencies, nothing to trust beyond plain shell
scripts you can read.

It's completely free and open source — no subscription, no catch. Anthropic has
open feature requests for built-in multi-account support; until that ships, this
is the most complete way I've found to do it.

Unofficial / not affiliated with Anthropic. macOS only. Source + build
instructions: https://github.com/jyito/Claude-Profiles — would love your feedback.

---

## X / Bluesky (short)

Run every Claude account at once on your Mac — each permanently signed in, with a
live native dashboard and per-profile icon badges.

Free. Open source. No subscription, no catch. It's a thin launcher around the real
Claude Desktop app — never touches your logins, never phones home.

(Unofficial, not affiliated with Anthropic.)
→ github.com/jyito/Claude-Profiles

---

## Posting notes

- Post the **Show HN in the morning ET** on a weekday; reply to early comments fast.
- Lead with the screenshot/video everywhere — the dashboard is the hook.
- Don't name-and-shame paid alternatives; the comparison table on the site does
  the work without you sounding bitter.
- Have answers ready for the obvious questions: "is this safe?" (credentials/network),
  "official?" (no), "why still 'Claude' in the menu bar?" (link the spike doc).
