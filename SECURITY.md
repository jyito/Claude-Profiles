# Security Policy

## Reporting a vulnerability
Please use GitHub's private vulnerability reporting ("Report a vulnerability"
under the Security tab) rather than a public issue. We'll acknowledge within
72 hours.

## Scope notes for researchers
- This tool intentionally handles **no credentials**: it never reads or
  stores tokens, passwords, cookies, or Keychain items. Session state lives
  in per-profile directories owned and managed by Claude Desktop itself.
- The tool makes **no network connections**. Anything observed phoning home
  is a critical finding.
- Interesting attack surface: profile-name templating into bash/AppleScript/
  plists and `rm -rf` paths in cache cleanup (`src/engine.sh`, every one
  `${var:?}`-guarded). The SwiftUI app invokes the engine via
  `Foundation.Process` with an explicit argument array (no shell-string
  interpolation, so no command-injection seam); `engine.sh`'s own input
  handling is the relevant boundary. The engine's typed `Process` + `Codable`
  boundary in the app (`EngineClient`) replaces the old `document.title` action
  bridge.
- Process-signal / cache-deletion paths (`closeterm`, `throttle`, `clean`,
  `autotick`) are guarded to each instance's **own** process tree / data dir —
  they can never target an arbitrary PID or another instance. The `remote`
  command opens no socket; it relies on the user's own SSH (Remote Login).
