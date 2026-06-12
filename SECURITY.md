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
  plists (sanitization in `src/launcher`), `rm -rf` paths in cache cleanup
  (`src/engine.sh`), and the `document.title` action bridge
  (`src/dashboard.applescript`).
