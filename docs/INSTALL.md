# Claude Profiles — Install & Use (no Terminal needed)

Run two or more Claude accounts (personal + business) side by side on your Mac.
Each profile is its own Claude app in your Dock, permanently signed in.

## Install (once, ~1 minute)

1. **Open what you downloaded** and drag the app into **Applications**:
   - **DMG:** double-click `Claude-Profiles.dmg`, then drag **Claude Profiles**
     onto the **Applications** shortcut in the window.
   - **Zip:** double-click it (Finder unpacks **Claude Profiles.app**), then drag
     **Claude Profiles.app** into your **Applications** folder.
2. **First launch — get past Gatekeeper.** The app is open-source and **unsigned**
   (no paid Apple Developer ID yet), so macOS blocks the very first open. This is
   expected. On current macOS (Sequoia / macOS 15 and later):
   1. Double-click **Claude Profiles**. macOS says it "can't be opened because
      Apple cannot check it for malicious software." Click **Done**.
   2. Open **System Settings → Privacy & Security**, scroll to the **Security**
      section, and next to *"Claude Profiles was blocked…"* click **Open Anyway**.
   3. Confirm **Open Anyway** and authenticate with Touch ID / your password.

   The app opens, and **every launch after this is a normal double-click**.

   *(On macOS 14 (Sonoma) and earlier you can instead right-click the app →
   **Open** → **Open** — but Apple removed that shortcut for unsigned apps in
   macOS 15, so use the System Settings path above.)*

   Why is it unsigned? See [Privacy & security](#privacy--security) — the app
   handles no credentials, opens no network connections, and the profile apps it
   creates are generated locally on your Mac. Signing is on the roadmap and will
   remove this prompt entirely.

## Use

Open **Claude Profiles** (Dock, Spotlight, or Launchpad). It opens a **dashboard
window** — a dark panel with one card per account.

**Add an account.** Click **＋ New Profile** (top right), type a name like
"Business", and click **Create Profile**. A new app called **Claude Business**
appears in your Dock, Spotlight, Launchpad, and ~/Applications. Open it once and
sign in to that account — from then on it stays signed in. Run as many profiles
at once as you like; they never interfere with each other or your regular Claude.

**Each profile is a card** showing its live state — running or stopped, CPU,
memory, process count, terminals, and rolling sparklines (it refreshes every
couple of seconds on its own; there's no Refresh button to press).

- A **running** card has **Show Window** (raise that account's windows),
  **Quit**, and **Force Quit**. A **stopped** card has **Open**.
- **+ Details** expands the card in place: a *running* profile shows a live
  **Terminals** table (device, command, idle time) with a per-row **Close** and a
  **Throttle CPU** button; a *stopped* profile shows **Cleanup** tiers
  (Caches / GPU / Logs / Everything).
- **Remote** opens copy-paste SSH commands to reach that profile's **Claude
  Code** session (the terminal agent) from another device — iPad, phone, laptop.
  This is Claude Code in a terminal, *not* the Desktop chat window; see
  [REMOTE.md](REMOTE.md) for setup (incl. Tailscale for off-network access).

**Remove an account:** on a stopped card, click **Remove profile…**. It's a
two-step confirm — the app is removed, but your saved sign-in is kept unless you
explicitly **type DELETE** to erase it. Removing is always safe by default.

Your regular **Claude (default)** instance also gets a card — **Show Window /
Quit / Force Quit**, plus **Remote** and (while it's running) **+ Details** for
its terminals — but its data folder is left untouched: it can't be cleaned or
deleted from here.

Tip: keep your regular Claude as your personal account and add profiles only for
the extra accounts.

*(Power users: `"Claude Profiles.app/Contents/MacOS/launcher" --classic` opens
the old dialog-menu interface instead — used for scripting, and an automatic
fallback if the window can't open on your macOS version.)*

## One thing to know about signing in

When you sign in, your browser may try to open "Claude" — and macOS sometimes
sends that to the wrong Claude window. If that happens, use the **copy code**
option shown on the login page and paste the code into the profile's window.
You only ever do this once per profile.

## Privacy & security

Claude Profiles never sees, stores, or transmits your passwords or tokens.
Each profile is simply a separate data folder (`~/.claude-instances/…`) that
Claude Desktop itself manages — exactly like two browser profiles. The apps it
creates are plain launchers generated locally on your Mac.

## Cleanup & maintenance

The dashboard already shows live per-instance stats — running state, CPU,
memory, process count, terminals, and disk — refreshing on its own every couple
of seconds. To free space or calm a busy Mac:

- **Per profile:** expand a *stopped* card with **+ Details** and clear a cache
  tier — **Caches / GPU / Logs / Everything**. Only regenerable Electron caches
  are deleted; your sign-in and settings are never touched, and running profiles
  are skipped automatically.
- **In bulk:** the **Cleanup** button (top bar) offers **Quit all profiles**,
  **Clear caches on stopped profiles**, and an **Emergency Stop** that force-quits
  every Claude instance at once. Sign-ins always survive.
- **Automatic (opt-in):** **Settings** can auto-clear caches on stopped profiles
  over a size limit and auto-close terminals idle past a threshold — both off by
  default.

## Telemetry: none

This app collects no telemetry and makes no network connections — ever. The
Activity dashboard computes everything locally on demand, and each profile
keeps a small "last opened" history *inside its own folder on your Mac*
(`.profile-activity`, last 50 launches), shown in the dashboard and deleted
with the profile. Nothing is ever transmitted anywhere.

## Making a DMG (for whoever distributes this)

End users don't need this — the release pipeline builds the DMG automatically on
every version tag. To build it yourself on a Mac, from the repo root run:

```
bash scripts/make-dmg.sh "/path/to/Claude Profiles.app"
```

It produces `Claude-Profiles.dmg`, a compressed drag-to-Applications image. An
unsigned DMG hits the same one-time Gatekeeper prompt as the zip (see **Install**
above); frictionless distribution needs an Apple Developer ID + notarization.

## Your data & "telemetry"

Claude Profiles collects **no telemetry** and makes **no network connections**
— ever. The Activity dashboard's stats (launch counts, last-opened times) come
from a small text file stored inside each profile's own folder on your Mac
(`.profile-activity`, last 50 launches). It never leaves your machine, it's
yours to read, and deleting it is harmless.
