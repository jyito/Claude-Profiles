# Changelog

## [0.1.0] — 2026-06-12
Initial release.
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
