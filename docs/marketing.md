# Positioning & launch notes

Working notes for taking Claude Profiles public as a free tool. Not marketing
copy — the thinking behind it.

## One-line positioning

> **The complete, genuinely-free way to run all your Claude accounts at once —
> no subscription, no catch, open source.**

The wedge is *complete + free*. The bare `--user-data-dir` trick and basic
wrappers already exist and are free; what doesn't exist is a polished native app
around it (live dashboard, per-profile badges, drill-down, cleanup, Show
Window). We're not "a thing that exists but costs money made free" — we're "the
best version of this, and it happens to be free, because it should be."

## Who it's for

- People with **2+ Claude accounts** (personal + work, agencies/consultants with
  client accounts, families) tired of logging out and back in.
- People who've found the `--user-data-dir` hack and want something nicer than
  an Automator droplet.
- The privacy-minded: zero network, zero telemetry, never touches credentials.

## Key messages (in priority order)

1. **Free and open source — and it should be.** Lead with this. The tone is
   confident, not preachy: "you shouldn't have to pay for this, so you don't."
   Don't attack other tools by name; let the comparison table speak.
2. **Complete, not a script.** The native dashboard is the screenshot that sells
   it. Most alternatives are CLI/Automator.
3. **Safe.** No credentials, no network, never modifies Claude.app, auto-updates
   keep working. This matters a lot to the target user.
4. **Honest.** Prominent UNOFFICIAL disclaimer; we don't pretend to be Anthropic.

## Proof points / differentiation

- vs `weidwonder/claude-desktop-multi-instance` and other wrappers: we add the
  whole management layer (dashboard, badges, cleanup, Show Window).
- vs Automator/manual: we're a real app with safety rails.
- Anthropic feature requests (#18435, #32783) are social proof that demand is
  real and unmet — link them, don't lean on them.

## Channels (when the repo is public)

- The `r/ClaudeAI` subreddit and the Anthropic Discord — the exact audience.
- A "Show HN" once screenshots + a short demo video exist.
- A reply in the open Anthropic feature-request threads ("until this ships
  officially, here's a free tool").
- X/Twitter with the dashboard screenshot + 15s screen recording.
- Product Hunt is optional and can wait; organic + the subreddit are higher-fit.

Tone everywhere: helpful, not salesy. The product is the pitch.

## Pre-launch checklist (gating)

- [ ] **Screenshots/video** into `docs/assets/` (hero-dashboard.png,
      drilldown.png, dock.png) — the page and README have placeholders ready.
- [ ] **Name decision.** CLAUDE.md notes the agreed safer public name
      *"Profiles for Claude"* (trademark convention). Decide before launch and
      update `src/Info.plist`, the site, and the README in one pass.
- [ ] **Make the repo public**, enable **GitHub Pages → Settings → Pages →
      source: `main` / `/docs`** (serves `docs/index.html`).
- [ ] **Signing/notarization** (`scripts/sign.sh` is ready) so a downloaded DMG
      opens without the right-click→Open friction. Friction kills first impressions.
- [ ] Real contact on the `jyito` GitHub org (NOTICE points there).

## The landing page

`docs/index.html` — static, dependency-free, on-brand. Screenshots live in
`docs/assets/` (relative to the page, so they work under GitHub Pages from
`/docs`). The placeholders are styled text boxes, not `<img>` tags, so the page
looks intentional before any screenshot exists. Swap each `.ph` div for an
`<img src="assets/…">` as captures land.
