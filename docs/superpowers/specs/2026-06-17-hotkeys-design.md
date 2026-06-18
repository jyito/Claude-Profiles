# Profile-switch hotkeys — design

## Constraint
True global hotkeys (fire when the app isn't focused) need Carbon
`RegisterEventHotKey` (C callbacks) or an `NSEvent` global monitor (ObjC blocks) —
neither possible in AppleScriptObjC, and a compiled helper / Hammerspoon dependency
would break zero-deps. So we split it:

## Two layers (both ⌘⌥1..9)
1. **In-app (shipped, zero-dep):** when the dashboard window is focused, ⌘⌥N
   focuses the Nth instance (card order: default = 1, then profiles). The page
   already owns a `keydown` listener; add `hotkeyFocus(n)` that fires the existing
   `cp:focus` / `cp:focusdefault` bridge verb.
2. **Global (optional, user's own tool):** a new headless **`engine focus <slug>`**
   raises an instance's windows by PID via System Events `set frontmost` (the
   proven cross-Space method; `osascript` is a built-in). Documented with a
   copy-paste **Hammerspoon** recipe that binds ⌘⌥1..9 to `engine focus <slug>`.
   The app ships nothing new for this — Hammerspoon is the user's optional tool, so
   zero-deps holds.

## Changes
- **engine `focus <slug|default>`** — validate slug (`[a-z0-9]` or `default`),
  resolve the main PID (`resolve_mains`), `osascript` System-Events frontmost;
  `ok` / `err invalid slug` / `err not running`.
- **dashboard.html** — `hotkeyFocus(n)` (maps to `lastData[n-1]`), wired into the
  `keydown` handler for `metaKey && altKey && /[1-9]/`.
- **docs/HOTKEYS.md** — the Hammerspoon recipe + setup, clearly optional.

## Testing
- engine: `focus` returns `ok` for a running instance, `err invalid slug` for a
  bad slug, `err not running` for a stopped one (osascript is shimmed in CI).
- render: `hotkeyFocus(1)` → `cp:focusdefault`; `hotkeyFocus(2)` → `cp:focus:<slug>`
  of the first profile; the keydown handler references the ⌘⌥ chord.

## Non-negotiables
Zero deps (Hammerspoon is the user's own optional tool, nothing shipped/bundled),
zero network, built-ins only (`osascript`), bash 3.2. Focus is by PID — no
credentials, no Claude.app or data-dir access.
