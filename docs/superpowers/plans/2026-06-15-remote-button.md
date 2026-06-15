# Remote Button + In-App Tailscale Instructions — Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Let a user make any profile reachable from another device entirely from the dashboard UI — a Remote button per card opening a modal of copy-paste connect commands and in-app Tailscale instructions — with the drill-down trigger restyled to a "+ Details" button.

**Architecture:** A new `engine.sh remoteinfo <slug>` action starts/reuses the profile's Claude Code `screen` session and emits JSON; a `copy` action pipes text to `pbcopy`. The dashboard's title-bridge gains `cp:remote` / `cp:copy` verbs; `pushRemote` runs `remoteinfo` and pushes the JSON to `updateRemote`, which fills and opens a new modal. The per-card expander becomes a button-styled "+ Details" alongside the new Remote button.

**Tech Stack:** bash 3.2 (engine.sh), AppleScriptObjC applet (dashboard.applescript), vanilla JS in a WKWebView (dashboard.html). Tests: `tests/run-tests.sh` (shimmed macOS tools, node for JS render).

---

### Task 1: `engine.sh remoteinfo <slug>` — start/reuse session, emit JSON

**Files:**
- Modify: `src/engine.sh` (add `cmd_remoteinfo`, add dispatch case)
- Test: `tests/run-tests.sh` (new "engine remoteinfo" block)

- [ ] **Step 1: Write the failing tests.** Add after the `== cli remote ==` block in `tests/run-tests.sh`. The suite already shims `screen` (logs to `$WORK/screen.log`, lists from `$WORK/screen-sessions`), `scutil`, `whoami`. Add a `tailscale` shim per-case.

```bash
echo "== engine remoteinfo (UI JSON) =="
rm -f "$WORK/screen.log" "$WORK/screen-sessions"
RI=$("$ENGINE" remoteinfo work)
check "remoteinfo is valid JSON"        "printf '%s' '$RI' | python3 -m json.tool >/dev/null"
check "remoteinfo starts the session"   "grep -q 'claude-work' '$WORK/screen.log'"
check "remoteinfo emits session+host"   "printf '%s' '$RI' | grep -q '\"session\":\"claude-work\"' && printf '%s' '$RI' | grep -q '\"host\":'"
check "remoteinfo tailscaleIp empty when absent" "printf '%s' '$RI' | grep -q '\"tailscaleIp\":\"\"'"
printf '\t9.claude-work\t(Detached)\n' > "$WORK/screen-sessions"
check "remoteinfo alreadyRunning on reuse" "printf '%s' \"\$('$ENGINE' remoteinfo work)\" | grep -q '\"alreadyRunning\":true'"
rm -f "$WORK/screen-sessions"
cat > "$WORK/shims/tailscale" <<'TS'
#!/bin/bash
[ "$*" = "ip -4" ] && echo "100.64.1.2"
TS
chmod +x "$WORK/shims/tailscale"
check "remoteinfo includes tailscale ip" "printf '%s' \"\$('$ENGINE' remoteinfo work)\" | grep -q '\"tailscaleIp\":\"100.64.1.2\"'"
rm -f "$WORK/shims/tailscale"
```

- [ ] **Step 2: Run, verify they fail.** `bash tests/run-tests.sh 2>&1 | grep -i remoteinfo` → FAIL (unknown command / no output).

- [ ] **Step 3: Implement `cmd_remoteinfo`.** Add to `src/engine.sh` near the other `cmd_*` actions (after `cmd_throttle`, before the dispatch). Uses the existing `json_str` helper.

```bash
cmd_remoteinfo() {  # start/reuse a profile's Claude Code screen session; emit JSON for the dashboard
    local slug="${1:?}" session cfg claude_bin host user ts_ip already=false
    command -v screen >/dev/null 2>&1 || { printf '{"error":"screen not found (it ships with macOS)"}'; return 0; }
    session="claude-$slug"
    cfg="$HOME/.claude-code-instances/$slug"
    claude_bin=$(command -v claude 2>/dev/null) || claude_bin="claude"
    mkdir -p "$cfg"
    if screen -ls 2>/dev/null | grep -qE "[.]${session}[[:space:]]"; then
        already=true
    else
        screen -dmS "$session" bash -lc "CLAUDE_CONFIG_DIR='$cfg' '$claude_bin'"
    fi
    host="$(scutil --get LocalHostName 2>/dev/null).local"
    user=$(whoami)
    ts_ip=""
    command -v tailscale >/dev/null 2>&1 && ts_ip=$(tailscale ip -4 2>/dev/null | head -n1)
    printf '{"slug":"%s","session":"%s","user":"%s","host":"%s","tailscaleIp":"%s","alreadyRunning":%s}' \
        "$(json_str "$slug")" "$(json_str "$session")" "$(json_str "$user")" "$(json_str "$host")" "$(json_str "$ts_ip")" "$already"
}
```

Add the dispatch case alongside the others (near `terminals)`):

```bash
    remoteinfo) cmd_remoteinfo "${2:?}" ;;
```

- [ ] **Step 4: Run, verify pass.** `bash tests/run-tests.sh 2>&1 | grep -i remoteinfo` → all PASS.

- [ ] **Step 5: Commit.**

```bash
git add src/engine.sh tests/run-tests.sh
git commit -m "feat(engine): remoteinfo action — start/reuse a profile's Claude Code session, emit JSON"
```

---

### Task 2: `engine.sh copy <text>` — clipboard bridge

**Files:**
- Modify: `src/engine.sh` (add `cmd_copy`, dispatch case)
- Test: `tests/run-tests.sh`

- [ ] **Step 1: Write the failing test.** Add a `pbcopy` shim that records its stdin, then assert.

```bash
echo "== engine copy (clipboard bridge) =="
cat > "$WORK/shims/pbcopy" <<PB
#!/bin/bash
cat > "$WORK/pbcopy.out"
PB
chmod +x "$WORK/shims/pbcopy"
"$ENGINE" copy 'ssh me@mac.local -t "screen -r claude-work"'
check "copy pipes text to pbcopy" "[ -f '$WORK/pbcopy.out' ] && grep -q 'screen -r claude-work' '$WORK/pbcopy.out'"
rm -f "$WORK/shims/pbcopy" "$WORK/pbcopy.out"
```

- [ ] **Step 2: Run, verify it fails.** `bash tests/run-tests.sh 2>&1 | grep -i 'copy pipes'` → FAIL.

- [ ] **Step 3: Implement `cmd_copy`** in `src/engine.sh` (near `cmd_remoteinfo`):

```bash
cmd_copy() {  # put text on the clipboard for the dashboard's Copy buttons (macOS only)
    command -v pbcopy >/dev/null 2>&1 || return 0
    printf '%s' "${1:-}" | pbcopy
}
```

Dispatch case:

```bash
    copy) cmd_copy "${2:-}" ;;
```

- [ ] **Step 4: Run, verify pass.** `bash tests/run-tests.sh 2>&1 | grep -i 'copy pipes'` → PASS.

- [ ] **Step 5: Commit.**

```bash
git add src/engine.sh tests/run-tests.sh
git commit -m "feat(engine): copy action — pbcopy bridge for the dashboard's Copy buttons"
```

---

### Task 3: Applet bridge — `cp:remote` / `cp:copy` verbs + `pushRemote`

**Files:**
- Modify: `src/dashboard.applescript` (add `pushRemote`; two `handleAction` branches; extend the `checkBridge` pushStats exclusion)

No automated test (applet layer); verified by `osacompile` parse-check + real-Mac run.

- [ ] **Step 1: Add the `pushRemote` handler.** After the existing `on pushConfig()` handler:

```applescript
on pushRemote(slug)
	-- slug is page-originated [a-z0-9]; rjson is engine's remoteinfo JSON object.
	try
		set rjson to do shell script quoted form of enginePath & " remoteinfo " & quoted form of slug
		theWebView's evaluateJavaScript:("updateRemote(" & rjson & ")") completionHandler:(missing value)
	end try
end pushRemote
```

- [ ] **Step 2: Add the `handleAction` branches.** Inside `on handleAction(raw)`, alongside the other `else if verb is …` branches (e.g. after the `terminals` branch):

```applescript
			else if verb is "remote" then
				my pushRemote(slug)
			else if verb is "copy" then
				set ctext to my joinFrom(parts, 3, ":")
				do shell script quoted form of enginePath & " copy " & quoted form of ctext & " >/dev/null 2>&1 &"
```

- [ ] **Step 3: Extend the `checkBridge` pushStats exclusion.** Find the line added by the 4Hz-loop fix and broaden it so the data-returning/utility verbs never trigger a stats re-push:

Replace:
```applescript
			if rawTitle does not start with "cp:terminals" then my pushStats()
```
with:
```applescript
			if rawTitle does not start with "cp:terminals" and rawTitle does not start with "cp:remote" and rawTitle does not start with "cp:copy" then my pushStats()
```

- [ ] **Step 4: Parse-check.**

Run:
```bash
sed 's|__RESOURCES__|/tmp/fake-resources|g' src/dashboard.applescript > /tmp/d.applescript && osacompile -o /tmp/d.app /tmp/d.applescript && echo OK
```
Expected: `OK` (compiles clean).

- [ ] **Step 5: Commit.**

```bash
git add src/dashboard.applescript
git commit -m "feat(applet): cp:remote and cp:copy bridge verbs; pushRemote"
```

---

### Task 4: Dashboard card — Remote button + "+ Details" restyle

**Files:**
- Modify: `src/dashboard.html` (CSS `.expander`→button row; `expLabel`; `fullRender` controls block; trim `livePatch`)
- Test: `tests/run-tests.sh` (extend the existing node render block)

- [ ] **Step 1: Write the failing assertions.** In the node render test (the `R=$(node -e " … ")` block), add two checks to the `console.log(...)` outputs and two `check` lines. After the existing `swatches` computation add:

```javascript
let remotebtn=0, detailsbtn=0;
try { const g6=(E['grid']||{}).innerHTML||''; if(g6.indexOf("act('remote'")>-1) remotebtn=1; if(g6.indexOf('+ Details')>-1 || g6.indexOf('− Details')>-1) detailsbtn=1; } catch(e){}
```
Append `remotebtn, detailsbtn` to the `console.log(...)` list, then add after the existing checks:
```bash
    check "card shows Remote button"   "[ \"\$(echo '$R' | awk '{print \$11}')\" = 1 ]"
    check "card shows + Details button" "[ \"\$(echo '$R' | awk '{print \$12}')\" = 1 ]"
```

- [ ] **Step 2: Run, verify they fail.** `bash tests/run-tests.sh 2>&1 | grep -iE 'Remote button|Details button'` → FAIL.

- [ ] **Step 3a: Change `expLabel`** in `src/dashboard.html` to a generic toggle label:

```javascript
function expLabel(p) { return expanded === p.slug ? "− Details" : "+ Details"; }
```

- [ ] **Step 3b: Replace the expander render** in `fullRender` (the block guarded by `if (p.slug && (p.running || !confirmStep[p.slug]))`):

```javascript
    if (p.slug && (p.running || !confirmStep[p.slug])) {
      html += '<div class="cardrow">' +
        '<button class="cardbtn" onclick="act(\'remote\',\'' + p.slug + '\')">Remote</button>' +
        '<button class="cardbtn" id="exp-' + key + '" onclick="toggleExpand(\'' + p.slug + '\')">' + expLabel(p) + '</button>' +
        '</div>';
      if (expanded === p.slug) html += drillPanel(p);
    }
```

- [ ] **Step 3c: Trim `livePatch`** — `expLabel` no longer depends on live data, so remove its per-tick update. Delete this line from `livePatch`:

```javascript
    var ex = document.getElementById("exp-" + key); if (ex) ex.innerHTML = expLabel(p);
```

- [ ] **Step 3d: Restyle CSS.** Replace the `.expander` rules (`.expander { … }`, `.expander:hover`, `.expander:active`) with a shared card-button row:

```css
  .cardrow { display:flex; gap:8px; margin-top:8px; }
  .cardbtn { flex:1; background:transparent; border:.5px solid #3a382f; color:#D3D1C7;
             border-radius:7px; padding:6px 0; font-size:12px; cursor:pointer; font-family:inherit;
             transition: background-color .12s ease, border-color .12s ease, color .12s ease, transform .06s ease; }
  .cardbtn:hover { border-color:#5F5E5A; color:#F1EFE8; }
  .cardbtn:active { transform:scale(.99); }
```

- [ ] **Step 4: Run, verify pass.** `bash tests/run-tests.sh 2>&1 | grep -iE 'Remote button|Details button|passed,'` → PASS, count up by 2.

- [ ] **Step 5: Commit.**

```bash
git add src/dashboard.html tests/run-tests.sh
git commit -m "feat(ui): Remote button per card; restyle expander to a + Details button"
```

---

### Task 5: Dashboard — Remote modal + `updateRemote` + copy

**Files:**
- Modify: `src/dashboard.html` (modal markup, CSS, `updateRemote`/`toggleRemote`/`toggleSteps`/`copyText`, Escape handler)
- Test: `tests/run-tests.sh` (node render block)

- [ ] **Step 1: Write the failing assertions.** In the node render block, after a successful `updateRemote(...)` call, assert the modal filled. Add:

```javascript
let rm=0;
try {
  updateRemote({slug:'work',session:'claude-work',user:'me',host:'mac.local',tailscaleIp:'100.64.1.2',alreadyRunning:false});
  const loc=(E['rm-local']||{}).textContent||'', ts=(E['rm-ts']||{}).textContent||'';
  if(loc.indexOf('screen -r claude-work')>-1 && ts.indexOf('100.64.1.2')>-1) rm=1;
} catch(e){}
let rmcta=0;
try {
  updateRemote({slug:'work',session:'claude-work',user:'me',host:'mac.local',tailscaleIp:'',alreadyRunning:false});
  const cta=(E['rm-ts-cta']||{}).style||{}, cmd=(E['rm-ts-cmd']||{}).style||{};
  if(cta.display!=='none' && cmd.display==='none') rmcta=1;
} catch(e){}
```
Append `rm, rmcta` to `console.log(...)`, and add:
```bash
    check "remote modal fills ssh lines"     "[ \"\$(echo '$R' | awk '{print \$13}')\" = 1 ]"
    check "remote modal shows tailscale CTA"  "[ \"\$(echo '$R' | awk '{print \$14}')\" = 1 ]"
```

Note: the node DOM stub must support `.style`. Confirm the `getElementById` stub returns an object with a `style` property — if not, extend the stub: `if(!E[id]) E[id]={innerHTML:'',textContent:'',className:'',value:'',style:{},focus(){}};`

- [ ] **Step 2: Run, verify they fail.** `bash tests/run-tests.sh 2>&1 | grep -iE 'remote modal'` → FAIL.

- [ ] **Step 3a: Add the modal markup** in `src/dashboard.html` after the `setmodal` `</div>` (the Settings modal close):

```html
<div class="scrim" id="remotemodal" onclick="if(event.target===this)toggleRemote(false)">
  <div class="modal">
    <h2 id="rm-title">Remote access</h2>
    <p id="rm-intro">Reach this profile's session from another device — no app server, your own SSH.</p>
    <div id="rm-err" class="rm-err" style="display:none"></div>
    <div id="rm-body">
      <div class="rm-label">Same network (e.g. an SSH app on your iPad)</div>
      <div class="rm-cmd"><code id="rm-local"></code><button class="rm-copy" onclick="copyText((document.getElementById('rm-local').textContent))">Copy</button></div>
      <div class="rm-label">Any network</div>
      <div class="rm-cmd" id="rm-ts-cmd"><code id="rm-ts"></code><button class="rm-copy" onclick="copyText((document.getElementById('rm-ts').textContent))">Copy</button></div>
      <div class="rm-cta" id="rm-ts-cta">To connect from outside your home network, set up Tailscale (free, no router config).</div>
      <div class="rm-note">Requires Remote Login: System Settings → General → Sharing → Remote Login.</div>
      <button class="linkbtn" id="rm-steps-toggle" onclick="toggleSteps()">Show iPad / Tailscale setup ▾</button>
      <div id="rm-steps" class="rm-steps" style="display:none">
        <ol>
          <li>On the Mac: turn on <b>Remote Login</b> (System Settings → General → Sharing).</li>
          <li>On your device: install an SSH app (Blink Shell, Termius).</li>
          <li>To reach it from <b>any</b> network: install <b>Tailscale</b> on the Mac and the device, sign into both with the same account, then use the "Any network" line above.</li>
          <li>Paste the line into your SSH app — you're in the session. Detach with Ctrl-A then D.</li>
        </ol>
        <div class="rm-note">Full guide: docs/REMOTE.md in the repo.</div>
      </div>
    </div>
    <div class="row"><button class="ghost" onclick="toggleRemote(false)">Close</button></div>
  </div>
</div>
```

- [ ] **Step 3b: Add CSS** (near the other modal styles):

```css
  .rm-label { font-size:11px; color:#888780; margin:12px 0 4px; }
  .rm-cmd { display:flex; gap:8px; align-items:center; background:#1A1915; border:.5px solid #3a382f;
            border-radius:8px; padding:8px 10px; }
  .rm-cmd code { flex:1; font-family:"SF Mono", ui-monospace, monospace; font-size:11px; color:#9FE1CB;
                 word-break:break-all; -webkit-user-select:text; user-select:text; }
  .rm-copy { flex:none; background:#2A4A3E; border:none; color:#9FE1CB; border-radius:6px;
             padding:4px 10px; font-size:11px; cursor:pointer; font-family:inherit; }
  .rm-copy:hover { background:#335C4D; }
  .rm-cta { font-size:12px; color:#888780; margin-top:6px; }
  .rm-note { font-size:11px; color:#6b6a64; margin-top:10px; }
  .rm-err { color:#F0997B; font-size:12px; margin:8px 0; }
  .rm-steps { margin-top:10px; font-size:12px; color:#D3D1C7; line-height:1.5; }
  .rm-steps ol { margin:0 0 0 18px; }
```

- [ ] **Step 3c: Add the JS** (near `toggleSet`):

```javascript
function toggleRemote(show) {
  document.getElementById("remotemodal").className = show ? "scrim show" : "scrim";
}
function toggleSteps() {
  var s = document.getElementById("rm-steps");
  s.style.display = s.style.display === "none" ? "" : "none";
}
function copyText(t) {
  document.title = "cp:copy:" + t;   // host pipes it to pbcopy
  var el = document.getElementById("toast"); el.textContent = "Copied";
  setTimeout(function () { el.textContent = ""; }, 1500);
}
function updateRemote(info) {   // pushed by the host after `engine remoteinfo <slug>`
  if (info.error) {
    document.getElementById("rm-err").style.display = "block";
    document.getElementById("rm-err").textContent = info.error;
    document.getElementById("rm-body").style.display = "none";
  } else {
    document.getElementById("rm-err").style.display = "none";
    document.getElementById("rm-body").style.display = "";
    var p = profileBySlug(info.slug), name = (p ? p.name : info.slug).replace(/^Claude /, "");
    document.getElementById("rm-title").textContent = "Remote access — " + name;
    document.getElementById("rm-local").textContent =
      'ssh ' + info.user + '@' + info.host + ' -t "screen -r ' + info.session + '"';
    if (info.tailscaleIp) {
      document.getElementById("rm-ts").textContent =
        'ssh ' + info.user + '@' + info.tailscaleIp + ' -t "screen -r ' + info.session + '"';
      document.getElementById("rm-ts-cmd").style.display = "";
      document.getElementById("rm-ts-cta").style.display = "none";
    } else {
      document.getElementById("rm-ts-cmd").style.display = "none";
      document.getElementById("rm-ts-cta").style.display = "";
    }
  }
  toggleRemote(true);
}
```

- [ ] **Step 3d: Add Escape handling.** In the `keydown` listener's Escape chain, add a branch (before the `else if (expanded)` branch):

```javascript
    else if (document.getElementById("remotemodal").className.indexOf("show") > -1) toggleRemote(false);
```

- [ ] **Step 4: Run, verify pass.** `bash tests/run-tests.sh 2>&1 | grep -iE 'remote modal|passed,'` → PASS.

- [ ] **Step 5: Commit.**

```bash
git add src/dashboard.html tests/run-tests.sh
git commit -m "feat(ui): Remote modal — copy-paste connect commands + in-app Tailscale steps"
```

---

### Task 6: Docs, full verification, changelog

**Files:**
- Modify: `CHANGELOG.md`, `CLAUDE.md`

- [ ] **Step 1: CHANGELOG.** Add under `## [Unreleased]`:

```markdown
- **Remote button on every profile card.** Make a profile reachable from another
  device without the CLI: the button starts/reuses its Claude Code session and
  opens a modal with copy-paste SSH commands (same-network and, when Tailscale is
  up, any-network) plus in-app iPad/Tailscale setup steps. Copy buttons use a
  `pbcopy` bridge. Still zero-network — the app opens no socket.
- The drill-down trigger is now a button-styled **+ Details** control (was a
  text-link "Terminals/Cleanup"); the terminal count stays in the status line.
```

- [ ] **Step 2: CLAUDE.md.** In the `dashboard.html` and `engine.sh` descriptions, note the new `remoteinfo`/`copy` actions, the `cp:remote`/`cp:copy` bridge verbs (added to the pushStats exclusion list), the Remote modal, and the "+ Details" control.

- [ ] **Step 3: Full verification.**

Run:
```bash
bash tests/run-tests.sh 2>&1 | tail -1
shellcheck -S error src/engine.sh cli/claude-profiles.sh src/launcher scripts/*.sh   # if installed
bash scripts/build.sh >/dev/null && echo BUILD_OK
sed 's|__RESOURCES__|/tmp/fake-resources|g' src/dashboard.applescript > /tmp/d.applescript && osacompile -o /tmp/d.app /tmp/d.applescript && echo APPLET_OK
```
Expected: all tests pass, `BUILD_OK`, `APPLET_OK`.

- [ ] **Step 4: Commit + push.**

```bash
git add CHANGELOG.md CLAUDE.md
git commit -m "docs: Remote button + Tailscale instructions; + Details control"
git push
```

- [ ] **Step 5: Verify CI green** on `main` after push.

---

## Notes for the implementer

- **bash 3.2**: no `declare -A`, no `mapfile`, no `${var,,}`. `json_str` already exists in `engine.sh` — reuse it.
- **The 4Hz-loop trap** (see CLAUDE.md): any `cp:` verb that returns data must be excluded from the `checkBridge` `pushStats` follow-up. Task 3 step 3 does this for `cp:remote`/`cp:copy`.
- **Real-Mac verification** (CI can't run the applet/WebView): after merge, confirm on macOS that the Remote button opens the modal, the commands are correct, Copy lands in the clipboard, and "+ Details" expands the drill-down.
- **Manual round-trip**: `bash src/engine.sh remoteinfo <existing-slug>` should print valid JSON and (off the test shims) start a real `screen` session.
