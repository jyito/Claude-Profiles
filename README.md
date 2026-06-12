# Claude Profiles

Run multiple Claude accounts side by side on one Mac — each in its own Claude Desktop instance, permanently signed in, with a native dashboard for live resource monitoring and one-click management.

> **Unofficial.** This is a community tool, not an Anthropic product, and is not affiliated with or endorsed by Anthropic. "Claude" is a trademark of Anthropic, PBC. The tool is a thin launcher around the official Claude Desktop app; it never modifies it.

## Why

Claude Desktop signs in one account at a time. If you have a personal Max plan and a business Max plan (or client accounts), switching means logging out and back in, constantly. Claude Profiles gives every account its own app icon — `Claude Business`, `Claude Personal`, `Claude Client X` — in your Dock, Spotlight, and Launchpad. Open as many as you like, simultaneously. Each stays signed in forever.

## How it works (and why it's safe)

Claude Desktop is an Electron app. Launched with `--user-data-dir=<path>`, it keeps **all** of its session state — auth tokens, cookies, local storage, MCP config — inside that directory. Claude Profiles simply gives each account its own directory under `~/.claude-instances/` and generates a tiny native `.app` wrapper that launches the real Claude.app pointed at it.

That means:

- **No credential handling, ever.** The launcher never sees, stores, or transmits passwords or tokens. Claude Desktop manages its own session inside each profile's folder, exactly like two browser profiles.
- **No telemetry, no network connections.** The only stats are a small local text file per profile (launch history, last 50 entries) shown in the dashboard. Delete it any time.
- **No modification of Claude.app.** The official app's code signature stays intact; auto-updates keep working.
- **No dependencies.** Plain bash + AppleScriptObjC, all macOS built-ins. No Node, no Python, no Homebrew, no compilation.

## Features

- **One-click profiles** — create a profile from a dialog; a native app appears instantly with the real Claude icon. Sign in once; it's permanent.
- **Live dashboard** — a native window (NSWindow + WKWebView, spun up by `osascript`) showing each instance's CPU, memory, process count, PTY handles, and disk, with rolling sparklines, refreshed every 2 seconds.
- **Show Window** — with many instances and many windows, one click raises every window of a *specific* instance. It targets the process by PID via `NSRunningApplication`, which works even though all instances share Claude's bundle identifier — and needs no Accessibility permissions.
- **Cleanup utilities** — graceful quit, force-quit of a full process tree (releases stuck PTYs), and per-profile cache clearing that only ever deletes regenerable Electron caches. It refuses to run against a live instance and never touches sign-ins.
- **Safe removal** — deleting a profile's app takes one confirmation; deleting its saved login requires literally typing `DELETE`.
- **Graceful degradation** — if the dashboard window can't open on a given macOS version, the app automatically falls back to a native-dialog interface with the same capabilities.
- **CLI for power users** — `cli/claude-profiles.sh` mirrors everything for scripting, plus a `code-alias` command for per-account [Claude Code](https://docs.claude.com/en/docs/claude-code/overview) config dirs (`CLAUDE_CONFIG_DIR`).

## Install (users)

Grab the latest release (`Claude-Profiles.zip` or `.dmg`), then see [docs/INSTALL.md](docs/INSTALL.md). Short version: drag **Claude Profiles.app** to Applications; first launch is right-click → Open (the app is currently unsigned — see [Roadmap](#roadmap)).

## Build from source

```bash
git clone https://github.com/jyito/Claude-Profiles.git
cd Claude-Profiles
bash scripts/build.sh        # assembles dist/Claude Profiles.app (+ DMG on macOS)
bash tests/run-tests.sh      # 22-test suite, runs on macOS or Linux
```

There is no compile step — `build.sh` just assembles the bundle from `src/`.

## Repository layout

```
src/        the app: launcher (GUI manager), engine.sh (stats/actions),
            dashboard.html (window UI), dashboard.applescript (window host)
cli/        standalone CLI with the same engine
scripts/    build.sh (assemble bundle), make-dmg.sh (native DMG, macOS)
docs/       INSTALL.md (end users), ARCHITECTURE.md (how it all works)
tests/      Linux-compatible suite with shimmed macOS tools
```

## Architecture in one paragraph

A profile is a generated `.app` bundle whose entire executable is a short bash script: `open -n -a Claude.app --args --user-data-dir=~/.claude-instances/<slug>`. The manager app is the same kind of bundle, with a menu. The dashboard is a WKWebView in an NSWindow created by AppleScriptObjC through plain `osascript`; the page's buttons communicate to native code by setting `document.title` (polled every 0.5 s — a block-free, subclass-free bridge), and native pushes JSON stats back with `evaluateJavaScript`. Stats come from `engine.sh`, which attributes processes to instances by their `--user-data-dir` argument and walks the child tree for helpers. Full detail in [docs/ARCHITECTURE.md](docs/ARCHITECTURE.md).

## Known limitations

- **Gatekeeper**: releases are unsigned, so the first launch needs right-click → Open. Apps the manager generates locally carry no quarantine and open normally.
- **Deep-link logins**: macOS routes `claude://` callbacks to one instance. If a browser login lands in the wrong window, use the login page's copy-code option. Once per profile.
- **Spaces**: "Assign to Desktop" is unreliable across instances sharing a bundle ID; drag windows to Spaces manually and macOS remembers per session.
- **Memory**: every instance is a full Electron app. The dashboard exists partly so you can see exactly what that costs.
- **Show Window** raises all of an instance's windows (not one specific window); per-window control would require Accessibility permissions.

## Roadmap

- [ ] Developer ID signing + notarization for friction-free public distribution
- [ ] Compiled SwiftUI dashboard (current window host is AppleScriptObjC by design — zero deps — but a signed Swift app unlocks richer UI)
- [ ] Menu-bar quick switcher
- [ ] Per-profile icon tinting/badging

## Contributing

See [CONTRIBUTING.md](CONTRIBUTING.md). Run `tests/run-tests.sh` before sending a PR — it runs anywhere, no Mac required for the bash/JS layers.

## License

[MIT](LICENSE)
