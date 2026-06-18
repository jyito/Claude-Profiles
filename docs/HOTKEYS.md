# Profile-switch hotkeys

Two ways to jump straight to a Claude account by keystroke.

## In-app: ⌘⌥1–9 (built in, nothing to install)

When the **Claude Profiles** dashboard window is focused, press **⌘⌥** + a number
to focus that instance's windows — in card order, so **⌘⌥1** is *Claude (default)*,
**⌘⌥2** the first profile, and so on.

This only works while the dashboard window itself is frontmost (it's a normal
in-window shortcut). For a key that works from *anywhere*, use the global recipe
below.

## Global: ⌘⌥1–9 from any app (optional, via Hammerspoon)

True global hotkeys need a system-wide key listener, which Claude Profiles
deliberately does **not** ship — the app stays zero-dependency and opens no such
hooks. Instead, point your own hotkey tool at the headless `engine focus <slug>`
command. [Hammerspoon](https://www.hammerspoon.org) (free, open source) is the
easy option.

1. Install Hammerspoon (download from hammerspoon.org, or `brew install --cask hammerspoon`).
2. List your slugs to pick the slot order:

   ```sh
   "$HOME/Applications/Claude Profiles.app/Contents/Resources/engine.sh" menulist
   ```

   Each line is `slug⇥name⇥running`. The default instance's slug is `default`.

3. Put this in `~/.hammerspoon/init.lua` (edit the `slots` list to taste — slot N
   is the slug bound to ⌘⌥N):

   ```lua
   -- Global ⌘⌥1..9 → focus a Claude Profiles instance
   local engine = os.getenv("HOME") ..
     "/Applications/Claude Profiles.app/Contents/Resources/engine.sh"

   local slots = { "default", "work", "personal" }  -- ⌘⌥1, ⌘⌥2, ⌘⌥3, …

   for i, slug in ipairs(slots) do
     hs.hotkey.bind({ "cmd", "alt" }, tostring(i), function()
       hs.execute('"' .. engine .. '" focus ' .. slug, true)
     end)
   end
   ```

4. Reload the config (Hammerspoon menu-bar icon → **Reload Config**). The first
   time a hotkey fires, macOS asks Hammerspoon for Automation permission to focus
   apps — allow it once.

`engine focus <slug>` raises that instance's windows by PID via System Events
(reliable across Spaces). It touches no credentials, never reads a data dir, and
opens no network — it just brings an already-running account forward. If the
instance isn't running it prints `err not running` and does nothing.
