# Changelog

## [0.3.0] — 2026-06-12
- Cleanup button in the dashboard header: a modal with graceful quit-all,
  cache-clear for all stopped profiles, and Emergency Stop — a killswitch
  that force-quits every Claude instance (default included) for when the
  machine is overloaded. Arm-then-confirm, 3-second disarm. All sign-ins
  and data survive every option.
- Engine: quitall / cleanall / killswitch subcommands.


## [0.2.0] — 2026-06-12
Consistent UI: the dashboard is now the app.
- Launching opens the dashboard window directly; the dialog menu is demoted
  to an automatic fallback (or `--classic` for scripting).
- New Profile is an in-window form; Remove is an in-card two-step flow with
  the typed-DELETE safeguard, all in the dashboard aesthetic.
- Engine gains headless `create` / `remove` / `purge` subcommands.
- UI edits pause live re-rendering so confirmation steps can't be interrupted.


## [0.1.0] — 2026-06-12
Initial release (Apache-2.0).
- Multi-account profiles: generated native wrapper apps, one per account,
  each permanently signed in via its own `--user-data-dir`.
- GUI manager app (native dialogs, no terminal): add / open / remove with
  typed-DELETE protection for saved logins.
- Native dashboard window (osascript + WKWebView): live CPU / memory /
  process / PTY / disk per instance with rolling sparklines, 2 s refresh.
- Show Window: raise all windows of a specific instance by PID
  (NSRunningApplication; works across shared bundle IDs, no permissions).
- Cleanup utilities: graceful quit, force-quit (full tree), cache clearing
  with running-instance refusal and login preservation.
- Local-only usage stats (`.profile-activity`, last 50 launches). No
  telemetry, no network I/O.
- Automatic fallback to dialog UI if the dashboard window can't open.
- CLI (`cli/claude-profiles.sh`) incl. Claude Code `CLAUDE_CONFIG_DIR` aliases.
- 22-test Linux-compatible suite; CI via GitHub Actions.
