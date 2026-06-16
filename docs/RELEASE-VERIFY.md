# Pre-release Mac verification (~5–10 min)

The test suite covers the bash/JS layers. It **cannot** exercise the
applet/WebView layer (osacompile, NSWindow, WKWebView, the title bridge, real
process signals). Run this once on a real Mac before any public release. Build
fresh first:

```
bash scripts/build.sh
rm -rf ~/.claude-instances/.runtime
open "dist/Claude Profiles.app"
```

(The `rm -rf …/.runtime` forces a clean applet recompile — do it whenever you
rebuild or move the app.)

| # | Do this | Expect |
|---|---------|--------|
| 1 | Launch the manager app | Dark dashboard renders (not a blank white pane). Loading splash → cards. |
| 2 | Look at the Dock | The manager shows the window-stack icon; each profile shows the real Claude icon with a distinct colored badge. |
| 3 | Have ≥2 profiles, both running. Click **Show Window** on one | That instance's windows come forward. **First time:** a one-time Automation prompt — click **Allow**. After allowing, repeat — it should jump every time, even across Spaces. |
| 4 | Expand a running card (**+ Details**) | The terminals table populates with the instance's live sessions (device, command, idle). |
| 5 | Click **Close** on a terminal (confirm) | That terminal disappears within ~2s. |
| 6 | Click **Throttle CPU** | No crash; the instance keeps running (priority drops — visible in Activity Monitor as a higher "nice" value). |
| 7 | Quit a profile, expand its (stopped) card | Clean tiers appear (Caches / GPU / Logs / Everything). Click one → caches clear (card disk shrinks). |
| 8 | Open **Settings**, change auto-clean to a value, reopen | The selection persisted. |
| 9 | In a card's drill-down, click a **badge color swatch** | The toast shows "Updating badge…"; within a moment the Dock icon recolors. |
| 10 | On the stopped **default** card, click **Open** | The base Claude (default account) launches. |
| 11 | Click **Remote** on a profile card | The Remote modal opens titled "Remote access — <name>" with copy-paste SSH lines; **Copy** lands the command in the clipboard; the modal is clearly labeled Claude Code (terminal), not the Desktop window. |
| 12 | Quit the dashboard (close its window) | The applet exits cleanly (no lingering process). |

If Show Window does nothing **and** no Automation prompt appears:
`tccutil reset AppleEvents local.claude-profiles.dashboard`, then relaunch and
try again.

If the dashboard is a blank white window: `rm -rf ~/.claude-instances/.runtime`
and relaunch (a stale compiled applet — now self-healed automatically, but this
is the manual recovery).

Note anything that fails here in an issue before going public — this layer is
where the real-Mac surprises live.
