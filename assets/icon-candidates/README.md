# App icon candidates

Three trademark-safe directions for the Claude Profiles app icon, in the
dashboard palette (coral `#D85A30`, mint `#5DCAA5`, warm gray, on the dark
`#1A1915` squircle). **None reproduce Anthropic's Claude mark** — the asterisk
is Anthropic's trademark and must never ship in this repo.

| File | Idea | Reads as |
|------|------|----------|
| `A-fanned-deck.svg` | Three profile cards fanned from a common pivot, coral upright in front | "a hand of accounts" |
| `B-window-stack.svg` | Three app windows cascading up-right, coral on top with title-bar dots | "multiple Claude windows" |
| `C-profile-grid.svg` | A 2×2 grid of four tinted profile tiles | "a grid of instances" |

All three are resolution-independent vectors (viewBox 160×160).

## Picking and baking

Pick one, then bake it into the iconset the build consumes:

```bash
# Requires a rasterizer that reads SVG. Options on macOS:
#   - rsvg-convert (brew install librsvg) — cleanest, recommended; or
#   - resvg; or
#   - qlmanage -t (built in, zero-dep) — verified to rasterize these SVGs
#     faithfully (correct colors/shapes), but it pads the icon into the canvas,
#     so the output needs cropping to the squircle bounds before scaling.
SVG=assets/icon-candidates/A-fanned-deck.svg
for s in 16 32 64 128 256 512 1024; do
  rsvg-convert -w $s -h $s "$SVG" -o "assets/icon.iconset/icon_${s}x${s}.png"
done
# (also produce the @2x variants: 16→32, 32→64, … per Apple's iconset naming)
iconutil -c icns assets/icon.iconset -o assets/app.icns
```

A clean **zero-dependency** bake (no Homebrew) is possible with `qlmanage` +
`sips`, but qlmanage centres/pads the render, so it needs a crop-to-content
step. That refinement is worth doing once a candidate is chosen — no point
perfecting it for all three.

The build (`scripts/build.sh`) bakes `assets/icon.iconset` → `app.icns`, which
becomes both the manager app's icon and the source for `applet.icns`. After
baking, delete `~/.claude-instances/.runtime` once so the dashboard applet is
recompiled and picks up the new icon (the baked `applet.icns` goes stale if
only the icon changes — see CLAUDE.md).
