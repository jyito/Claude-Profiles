# Claude Profiles — Install & Use (no Terminal needed)

Run two or more Claude accounts (personal + business) side by side on your Mac.
Each profile is its own Claude app in your Dock, permanently signed in.

## Install (once, ~30 seconds)

1. Double-click the downloaded zip — Finder unpacks **Claude Profiles.app**.
2. Drag **Claude Profiles.app** into your **Applications** folder.
3. **First open only:** right-click the app → **Open** → **Open**.
   (macOS asks this once because the app isn't from the App Store. If you
   instead see "Open Anyway" in System Settings → Privacy & Security, click
   that.) Every launch after this is a normal double-click.

## Use

Open **Claude Profiles** (Dock, Spotlight, or Launchpad). A simple menu appears:

- **＋ Add a profile…** — type a name like "Business". A new app called
  **Claude Business** instantly appears in Spotlight, Launchpad, and
  ~/Applications. Open it and sign in to that account — one time only.
  From then on it's always signed in.
- **▶ Open <profile>** — launch any profile. Run several at once; they never
  interfere with each other or with your regular Claude app.
- **✕ Remove a profile…** — removes the app. Your saved sign-in is kept unless
  you explicitly type DELETE when asked, so removing is always safe.

Tip: keep your regular **Claude.app** as your personal account and add
profiles only for the extra accounts.

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

## Activity & Cleanup

Pick **📊 Activity & Cleanup…** from the menu to see, per profile (and the
default Claude app): running state, CPU %, memory, process count, open PTYs
(terminal handles), and disk used — with a **Refresh** button for an updated
snapshot. **Clean Up…** offers:

- **Quit / Force Quit** a profile — releases all of its processes and PTYs.
- **Clear caches** (per profile, or all stopped profiles at once) — frees disk
  by deleting only regenerable Electron caches. Your sign-in and settings are
  never touched, and running profiles are skipped automatically.

## Telemetry: none

This app collects no telemetry and makes no network connections — ever. The
Activity dashboard computes everything locally on demand, and each profile
keeps a small "last opened" history *inside its own folder on your Mac*
(`.profile-activity`, last 50 launches), shown in the dashboard and deleted
with the profile. Nothing is ever transmitted anywhere.

## Making a DMG (for whoever distributes this)

End users don't need this. If you want to hand the app out as a classic
drag-to-Applications disk image: on a Mac, put **Make DMG.command** next to
**Claude Profiles.app** and double-click it. It produces
`Claude-Profiles.dmg`. Note that an unsigned DMG meets the same one-time
right-click→Open prompt as the zip — proper frictionless distribution
requires an Apple Developer ID + notarization.

## Installing from the DMG

Double-click **Claude-Profiles.dmg** → a window opens → drag **Claude
Profiles** onto the **Applications** shortcut → eject. First open is the same
one-time right-click → Open as with the zip.

## Your data & "telemetry"

Claude Profiles collects **no telemetry** and makes **no network connections**
— ever. The Activity dashboard's stats (launch counts, last-opened times) come
from a small text file stored inside each profile's own folder on your Mac
(`.profile-activity`, last 50 launches). It never leaves your machine, it's
yours to read, and deleting it is harmless.
