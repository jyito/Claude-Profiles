# Site screenshots

Drop the landing-page images here (referenced by `docs/index.html` as
`assets/<name>`, which resolves correctly under GitHub Pages served from `/docs`):

- `hero-dashboard.png` — the dashboard window with 2+ running profiles and live
  sparklines (≥1400px wide; crop to the window with ⌘⇧5).
- `drilldown.png` — a running profile card expanded to its terminals table.
- `dock.png` — several badged Claude profiles in the Dock at once.

Until they exist, the page shows styled placeholder boxes (not broken images).
Replace each `<div class="ph">…</div>` in `docs/index.html` with
`<img src="assets/<name>.png" alt="…">` as captures land.
