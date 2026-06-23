#!/bin/bash
# run-tests.sh — Linux-compatible test suite for Claude Profiles.
# Shims macOS tools (osascript, defaults, ps, lsof) so the bash engine can be
# exercised on any CI runner. The native SwiftUI dashboard (app/) is the UI as
# of v0.7.0 and has its own Swift test runners (`swift run ProfilesCoreTests` /
# `ProfilesSnapshotTests`); this suite covers engine.sh + the CLI.
set -u
cd "$(dirname "$0")"
ROOT="$(cd .. && pwd)"
WORK="$(mktemp -d)"
trap 'rm -rf "$WORK"' EXIT
PASS=0; FAIL=0

ok()   { PASS=$((PASS+1)); printf '  ✓ %s\n' "$1"; }
bad()  { FAIL=$((FAIL+1)); printf '  ✗ %s\n' "$1"; }
check(){ if eval "$2"; then ok "$1"; else bad "$1"; fi; }

# ---- shims ------------------------------------------------------------------
mkdir -p "$WORK/shims" "$WORK/apps" "$WORK/instances" "$WORK/Claude.app/Contents/Resources"
touch "$WORK/Claude.app/Contents/Resources/electron.icns"

cat > "$WORK/shims/defaults" <<'EOF'
#!/bin/bash
plist="$2.plist"; key="$3"
[ -f "$plist" ] || exit 1
val=$(grep -A1 "<key>$key</key>" "$plist" | sed -n 's/.*<string>\(.*\)<\/string>.*/\1/p' | head -1)
[ -n "$val" ] && echo "$val" || exit 1
EOF

cat > "$WORK/shims/osascript" <<EOF
#!/bin/bash
Q="$WORK/queue"; shift
echo "---- \$1" >> "$WORK/dialog.log"
resp=\$(head -n1 "\$Q"); tail -n +2 "\$Q" > "\$Q.t" && mv "\$Q.t" "\$Q"
echo "\$resp"
EOF

cat > "$WORK/shims/ps" <<EOF
#!/bin/bash
T="100 1 12.5 524288 /Applications/Claude.app/Contents/MacOS/Claude --user-data-dir=$WORK/instances/business
101 100 3.2 262144 /Applications/Claude.app/Contents/Frameworks/Claude Helper (Renderer).app
102 100 1.1 131072 /Applications/Claude.app/Contents/Frameworks/Claude Helper (GPU).app
200 1 2.0 393216 /Applications/Claude.app/Contents/MacOS/Claude
201 200 0.5 98304 /Applications/Claude.app/Contents/Frameworks/Claude Helper (Renderer).app"
case "\$*" in
  # The combined snapshot cmd_stats captures once per tick. Must precede the
  # narrower pid=,ppid= case, which is a substring of this query.
  *"pid=,ppid=,command="*) echo "\$T" | awk '{printf "%s %s ", \$1, \$2; for(i=5;i<=NF;i++) printf "%s ", \$i; print ""}' ;;
  *"pid=,command="*) echo "\$T" | awk '{printf "%s ", \$1; for(i=5;i<=NF;i++) printf "%s ", \$i; print ""}' ;;
  *"pid=,ppid="*)    echo "\$T" | awk '{print \$1, \$2}' ;;
  *"-o pcpu=,rss= -p"*) p="\${@: -1}"; echo "\$T" | awk -v p=",\$p," '{ if (index(p, ","\$1",")) print \$3, \$4 }' ;;
esac
EOF

cat > "$WORK/shims/lsof" <<'EOF'
#!/bin/bash
# ttys = the deduped "terminals" metric; ptmx = the leaked masters (NOT deduped).
# pid 100 tree holds 3 ttys + 4 ptmx masters; pid 200 holds 1 tty + 2 ptmx.
case "$*" in
  *100*) printf 'c 100 u 17u CHR /dev/ttys001\nc 101 u 18u CHR /dev/ttys002\nc 102 u 19u CHR /dev/ttys003\nc 100 u 20u CHR /dev/ptmx\nc 100 u 21u CHR /dev/ptmx\nc 101 u 22u CHR /dev/ptmx\nc 102 u 23u CHR /dev/ptmx\n' ;;
  *200*) printf 'c 200 u 17u CHR /dev/ttys004\nc 200 u 24u CHR /dev/ptmx\nc 201 u 25u CHR /dev/ptmx\n' ;;
esac
EOF
cat > "$WORK/shims/sysctl" <<'EOF'
#!/bin/bash
case "$*" in
  *kern.tty.ptmx_max*) printf '511\n' ;;
  *) printf '0\n' ;;
esac
EOF
cat > "$WORK/shims/stat" <<'EOF'
#!/bin/bash
# emulate macOS `stat -f %m <path>` → device mtime epoch (fixed, in the past)
echo 1700000000
EOF
cat > "$WORK/shims/renice" <<EOF
#!/bin/bash
printf '%s\n' "\$*" >> "$WORK/renice.log"
EOF
cat > "$WORK/shims/screen" <<EOF
#!/bin/bash
case "\$*" in
  *-ls*)         cat "$WORK/screen-sessions" 2>/dev/null || echo "No Sockets found." ;;
  *-X*quit*)     printf '%s\n' "\$*" >> "$WORK/screen-quit.log" ;;
  *-dmS*)        printf '%s\n' "\$*" >> "$WORK/screen.log" ;;
esac
EOF
cat > "$WORK/shims/scutil" <<'EOF'
#!/bin/bash
echo "testmac"
EOF
# `open` is shimmed so engine actions that launch instances (opendefault, etc.)
# just log their args instead of spawning real apps. The shim just logs the args.
printf '#!/bin/bash\nprintf "%%s\\\\n" "$*" >> "%s/open.log"\n' "$WORK" > "$WORK/shims/open"
# Stub the Claude Code CLI so remoteinfo's existence guard passes in CI (where it
# isn't installed); a no-op is fine since `screen` is also a shim.
printf '#!/bin/bash\n:\n' > "$WORK/shims/claude"
chmod +x "$WORK/shims/"*

export PATH="$WORK/shims:$PATH"
export CLAUDE_PROFILES_APP="$WORK/Claude.app"
export CLAUDE_PROFILES_APPS_DIR="$WORK/apps"
export CLAUDE_PROFILES_INSTANCES_DIR="$WORK/instances"
ENGINE="$ROOT/src/engine.sh"

echo "== syntax =="
check "engine bash syntax"     "bash -n '$ENGINE'"
check "cli bash syntax"        "bash -n '$ROOT/cli/claude-profiles.sh'"

# The `ps`/`lsof` shims model a running "business" instance whose data dir is
# $WORK/instances/business. Create that wrapper + data dir up front so the stats,
# terminals, throttle, and remote tests downstream have a real profile to target.
echo "== engine headless lifecycle =="
check "engine creates business" "[ \"\$('$ENGINE' create Business)\" = 'ok business' ] && [ -d '$WORK/apps/Claude Business.app' ] && [ -d '$WORK/instances/business' ]"
touch "$WORK/instances/business/marker"
check "engine re-create preserves data" "[ \"\$('$ENGINE' create Business)\" = 'ok business' ] && [ -f '$WORK/instances/business/marker' ]"
check "engine create"          "[ \"\$('$ENGINE' create 'Head Less')\" = 'ok headless' ] && [ -d '$WORK/apps/Claude Head Less.app' ]"
check "engine create sanitizes" "[ \"\$('$ENGINE' create 'Bad\":{Name}')\" = 'ok badname' ]"
check "engine create reserves default" "printf '%s' \"\$('$ENGINE' create Default)\" | grep -qi reserved && [ ! -d '$WORK/instances/default' ]"
check "engine create strips XML chars (valid plist)" "[ \"\$('$ENGINE' create 'Q&A')\" = 'ok qa' ] && python3 -c \"import plistlib; plistlib.load(open('$WORK/apps/Claude QA.app/Contents/Info.plist','rb'))\""
check "engine remove keeps data" "mkdir -p '$WORK/instances/headless'; touch '$WORK/instances/headless/m'; [ \"\$('$ENGINE' remove headless)\" = ok ] && [ ! -d '$WORK/apps/Claude Head Less.app' ] && [ -f '$WORK/instances/headless/m' ]"
check "engine purge erases data" "[ \"\$('$ENGINE' purge headless)\" = ok ] && [ ! -d '$WORK/instances/headless' ]"

echo "== per-profile badge icons =="
check "badge color is deterministic" "[ \"\$(bash -c '. \"\$1\"; badge_color_for work' _ '$ENGINE')\" = \"\$(bash -c '. \"\$1\"; badge_color_for work' _ '$ENGINE')\" ]"
check "badge color is r g b triple"  "bash -c '. \"\$1\"; badge_color_for work' _ '$ENGINE' | grep -qE '^[0-9]+ [0-9]+ [0-9]+\$'"
check "badge falls back to plain copy" "rm -rf '$WORK/bf'; mkdir -p '$WORK/bf'; printf icnsDATA > '$WORK/srcicns'; bash -c '. \"\$1\"; RES_DIR=/nonexistent; badge_icon work \"Claude Work\" \"$WORK/srcicns\" \"$WORK/bf\"' _ '$ENGINE' 2>/dev/null; cmp -s '$WORK/srcicns' '$WORK/bf/app.icns'"
# The real render path (sips -> osascript compositor -> iconutil) can't run here:
# this suite shims osascript, so badge_icon's compositor call would hit the shim.
# The fallback + color tests above cover the bash logic; the actual rendering is
# verified directly with the real osascript (see commit notes), and CI parse-checks
# src/badge-icon.applescript on real macOS.
check "badge compositor present"     "[ -f '$ROOT/src/badge-icon.applescript' ] && grep -q 'badge_icon' '$ROOT/src/engine.sh' && grep -q 'badge-icon.applescript' '$ROOT/scripts/build.sh'"
mkdir -p "$WORK/instances/.runtime"
printf 'ovslug 3\n' > "$WORK/instances/.runtime/badges"
check "badge override changes color"  "[ \"\$(bash -c '. \"\$1\"; badge_color_for ovslug' _ '$ENGINE')\" = '124 92 196' ]"
check "setbadge rejects bad index"    "[ \"\$(bash -c '. \"\$1\"; cmd_setbadge ovslug 9' _ '$ENGINE')\" = 'err badindex' ]"
rm -f "$WORK/instances/.runtime/badges"

echo "== engine stats =="
printf '2026-06-10 08:12\n2026-06-12 09:14\n' > "$WORK/instances/business/.profile-activity"
S=$("$ENGINE" stats)
check "stats is valid JSON"    "printf '%s' '$S' | python3 -m json.tool >/dev/null"
check "cpu summed over tree"   "printf '%s' '$S' | grep -q '\"cpu\":16.8'"
check "mem summed over tree"   "printf '%s' '$S' | grep -q '\"mem\":896'"
check "pty count attributed"   "printf '%s' '$S' | grep -q '\"ptys\":3'"
# /dev/ptmx leak metric: masters are counted (NOT deduped) — business holds 4,
# the default 2 — and the system ceiling is surfaced from kern.tty.ptmx_max.
check "ptmx leak count attributed" "printf '%s' '$S' | grep -q '\"ptmx\":4'"
check "ptmx default counted"       "printf '%s' '$S' | grep -q '\"ptmx\":2'"
check "ptmx ceiling reported"      "printf '%s' '$S' | grep -q '\"ptmxMax\":511'"
check "default instance shown" "printf '%s' '$S' | grep -q 'Claude (default)'"
check "opens counted"          "printf '%s' '$S' | grep -q '\"opens\":2'"
check "mainpid resolves"       "[ \"\$('$ENGINE' mainpid business)\" = 100 ]"
check "defaultpid resolves"    "[ \"\$('$ENGINE' defaultpid)\" = 200 ]"

echo "== remote session status (stats remote field) =="
# With a live claude-business screen session, business is remote:true; default
# (no claude-default session) is remote:false. Token boundary avoids prefix bleed.
printf '\t12345.claude-business\t(Detached)\n' > "$WORK/screen-sessions"
RS=$("$ENGINE" stats)
rm -f "$WORK/screen-sessions"
check "stats: live profile is remote:true"  "printf '%s' '$RS' | python3 -c 'import sys,json; d=json.load(sys.stdin); print([p[\"remote\"] for p in d if p[\"slug\"]==\"business\"][0])' | grep -qx True"
check "stats: default is remote:false"      "printf '%s' '$RS' | python3 -c 'import sys,json; d=json.load(sys.stdin); print([p[\"remote\"] for p in d if p[\"slug\"]==\"\"][0])' | grep -qx False"
check "stats: no screen → all remote:false" "printf '%s' '$S' | python3 -c 'import sys,json; d=json.load(sys.stdin); print(any(p[\"remote\"] for p in d))' | grep -qx False"

echo "== menulist (menu-bar switcher data) =="
# slug<TAB>name<TAB>running(1|0); default sentinel first, business running (pid 100).
check "menulist lists default first"     "[ \"\$('$ENGINE' menulist | head -1 | cut -f1)\" = default ]"
check "menulist marks default running"   "[ \"\$('$ENGINE' menulist | head -1 | cut -f3)\" = 1 ]"
check "menulist default carries name"    "[ \"\$('$ENGINE' menulist | head -1 | cut -f2)\" = 'Claude (default)' ]"
check "menulist marks running profile 1" "'$ENGINE' menulist | awk -F'\t' '\$1==\"business\"{print \$3}' | grep -qx 1"
check "menulist marks a stopped profile" "'$ENGINE' menulist | awk -F'\t' '\$3==0' | grep -q ."

echo "== terminals (drill-down data) =="
T=$("$ENGINE" terminals business)
check "terminals is valid JSON"   "printf '%s' '$T' | python3 -m json.tool >/dev/null"
check "terminals lists 3 devices" "[ \"\$(printf '%s' '$T' | python3 -c 'import sys,json; print(len(json.load(sys.stdin)))')\" = 3 ]"
check "terminals rows carry dev"  "printf '%s' '$T' | grep -q '\"dev\":\"/dev/ttys001\"'"
check "terminals rows carry idle" "printf '%s' '$T' | grep -q '\"idle\":[0-9]'"
check "terminals rows carry cmd"  "printf '%s' '$T' | grep -q '\"cmd\":\"'"
check "terminals empty when stopped" "[ \"\$('$ENGINE' terminals evex)\" = '[]' ]"
# the default instance: terminals/closeterm/throttle resolve PIDs via the default
# detection (cmd_defaultpid), not a profile data dir, scoped to the default's tree
check "terminals default uses default tree" "printf '%s' \"\$('$ENGINE' terminals default)\" | grep -q '\"dev\":\"/dev/ttys004\"'"
# regression: real lsof truncates COMMAND to 9 chars and it may contain a space
# ("Claude He"), shifting columns — the PID must still be read correctly.
cp "$WORK/shims/lsof" "$WORK/shims/lsof.bak"
cat > "$WORK/shims/lsof" <<'LSOFEOF'
#!/bin/bash
printf 'Claude He 100 u 17u CHR 16,5 0t0 999 /dev/ttys001\n'
LSOFEOF
chmod +x "$WORK/shims/lsof"
TS=$("$ENGINE" terminals business)
check "terminals valid JSON w/ spaced lsof cmd" "printf '%s' '$TS' | python3 -m json.tool >/dev/null"
check "terminals reads pid past spaced cmd"     "printf '%s' '$TS' | grep -q '\"pid\":100'"
mv "$WORK/shims/lsof.bak" "$WORK/shims/lsof"

echo "== closeterm (guarded terminal close) =="
# Only devices in THIS instance's own tree may be closed. business owns ttys001-003
# (lsof shim for pid 100 tree); the default's ttys004 and unknown devices are refused.
check "closeterm accepts own device"    "[ \"\$('$ENGINE' closeterm business ttys001)\" = ok ]"
check "closeterm refuses other instance" "[ \"\$('$ENGINE' closeterm business ttys004)\" = refused ]"
check "closeterm refuses unknown device" "[ \"\$('$ENGINE' closeterm business ttys999)\" = refused ]"
check "closeterm refuses when stopped"   "[ \"\$('$ENGINE' closeterm evex ttys001)\" = refused ]"
check "closeterm rejects bad device arg" "[ \"\$('$ENGINE' closeterm business notadev)\" = baddev ]"

echo "== throttle (CPU priority) =="
rm -f "$WORK/renice.log"
check "throttle renices own tree"     "[ \"\$('$ENGINE' throttle business)\" = ok ] && grep -q '^10 100' '$WORK/renice.log'"
check "throttle refuses when stopped" "[ \"\$('$ENGINE' throttle evex)\" = notrunning ]"

echo "== restart (free leaked terminal handles) =="
# A stopped/unknown instance has no tree to cycle, so restart skips straight to
# relaunch and returns ok without blocking. Slug is validated at the boundary.
check "restart relaunches stopped (ok)" "[ \"\$('$ENGINE' restart ghostprof)\" = ok ]"
check "restart rejects spaced slug"     "[ \"\$('$ENGINE' restart 'bad slug')\" = 'err invalid slug' ]"
check "restart rejects traversal slug"  "[ \"\$('$ENGINE' restart '../../evil')\" = 'err invalid slug' ]"

echo "== focus (headless, for global hotkeys) =="
# osascript is shimmed; business (pid 100) is running, so focus resolves + returns ok.
check "focus a running profile (ok)"    "[ \"\$('$ENGINE' focus business)\" = ok ]"
check "focus the default (ok)"          "[ \"\$('$ENGINE' focus default)\" = ok ]"
check "focus rejects bad slug"          "[ \"\$('$ENGINE' focus 'bad slug')\" = 'err invalid slug' ]"
check "focus errors when not running"   "[ \"\$('$ENGINE' focus ghostprof)\" = 'err not running' ]"
check "hotkeys doc ships hammerspoon"   "grep -qi 'hammerspoon' '$ROOT/docs/HOTKEYS.md' && grep -q ' focus ' '$ROOT/docs/HOTKEYS.md'"

echo "== settings & auto-clean =="
check "getconfig defaults to zero"   "[ \"\$('$ENGINE' getconfig)\" = '{\"autoCloseIdleMin\":0,\"autoCleanThresholdMB\":0,\"autoRestartLeakAt\":0}' ]"
check "setconfig persists threshold" "[ \"\$('$ENGINE' setconfig autoCleanThresholdMB 500)\" = ok ]"
check "getconfig reflects setting"   "'$ENGINE' getconfig | grep -q '\"autoCleanThresholdMB\":500'"
check "setconfig persists leak threshold" "[ \"\$('$ENGINE' setconfig autoRestartLeakAt 250)\" = ok ] && '$ENGINE' getconfig | grep -q '\"autoRestartLeakAt\":250'"
"$ENGINE" setconfig autoRestartLeakAt 0 >/dev/null
check "setconfig rejects bad key"    "[ \"\$('$ENGINE' setconfig nope 5)\" = 'err badkey' ]"
check "setconfig rejects bad value"  "[ \"\$('$ENGINE' setconfig autoCloseIdleMin -3)\" = 'err badval' ]"
check "setconfig rejects bad leak value" "[ \"\$('$ENGINE' setconfig autoRestartLeakAt 5x)\" = 'err badval' ]"
"$ENGINE" setconfig autoCleanThresholdMB 0 >/dev/null; "$ENGINE" setconfig autoCloseIdleMin 0 >/dev/null
check "autotick is a no-op when disabled" "[ \"\$('$ENGINE' autotick)\" = ok ]"
check "autotick runs with auto-close on" "'$ENGINE' setconfig autoCloseIdleMin 60 >/dev/null; [ \"\$('$ENGINE' autotick)\" = ok ]"
"$ENGINE" setconfig autoCloseIdleMin 0 >/dev/null
mkdir -p "$WORK/apps/Claude AutoBig.app/Contents" "$WORK/instances/autobig/GPUCache"
printf '<plist><dict>\n<key>CFBundleIdentifier</key>\n<string>local.claude-profiles.autobig</string>\n<key>CFBundleDisplayName</key>\n<string>Claude AutoBig</string>\n</dict></plist>\n' > "$WORK/apps/Claude AutoBig.app/Contents/Info.plist"
dd if=/dev/zero of="$WORK/instances/autobig/GPUCache/big" bs=1024 count=2048 2>/dev/null
rm -f "${TMPDIR:-/tmp}/claude-profiles-disk-cache"
check "autotick cleans over-threshold stopped profile" "'$ENGINE' setconfig autoCleanThresholdMB 1 >/dev/null; '$ENGINE' autotick >/dev/null; [ ! -d '$WORK/instances/autobig/GPUCache' ]"
"$ENGINE" setconfig autoCleanThresholdMB 0 >/dev/null
# auto-restart on leak: business (pid 100 tree) holds 4 leaked /dev/ptmx masters.
# Stub cmd_restart so we observe the dispatch without the real ~5s cycle.
check "autotick restarts a profile over leak threshold" "bash -c '
  . \"$ENGINE\"
  cmd_restart() { printf \"%s\\n\" \"\$1\" >> \"$WORK/autorestart.log\"; }
  rm -f \"$WORK/autorestart.log\"
  cmd_setconfig autoRestartLeakAt 3 >/dev/null
  cmd_autotick >/dev/null
  cmd_setconfig autoRestartLeakAt 0 >/dev/null
  grep -qx business \"$WORK/autorestart.log\"
'"
check "autotick skips a profile under leak threshold" "bash -c '
  . \"$ENGINE\"
  cmd_restart() { printf \"%s\\n\" \"\$1\" >> \"$WORK/autorestart.log\"; }
  rm -f \"$WORK/autorestart.log\"
  cmd_setconfig autoRestartLeakAt 99 >/dev/null
  cmd_autotick >/dev/null
  cmd_setconfig autoRestartLeakAt 0 >/dev/null
  [ ! -s \"$WORK/autorestart.log\" ]
'"

echo "== default instance launch =="
rm -f "$WORK/open.log"   # the `open` shim is set up at the top; isolate this check
check "opendefault launches Claude" "'$ENGINE' opendefault >/dev/null; grep -q -- '-n -a $WORK/Claude.app' '$WORK/open.log'"

echo "== engine cleanup safety =="
mkdir -p "$WORK/instances/evex/GPUCache"
dd if=/dev/zero of="$WORK/instances/evex/GPUCache/b" bs=1024 count=256 2>/dev/null
dd if=/dev/zero of="$WORK/instances/evex/Cookies" bs=1024 count=4 2>/dev/null
check "clean frees caches"     "[ \"\$('$ENGINE' clean evex)\" = ok ] && [ ! -d '$WORK/instances/evex/GPUCache' ]"
check "clean preserves login"  "[ -f '$WORK/instances/evex/Cookies' ]"
check "clean refuses if running" "[ \"\$('$ENGINE' clean business)\" = running ]"

echo "== per-instance clean tiers =="
mkdir -p "$WORK/instances/tierx/Cache" "$WORK/instances/tierx/GPUCache" "$WORK/instances/tierx/logs"
touch "$WORK/instances/tierx/Cache/c" "$WORK/instances/tierx/GPUCache/g" "$WORK/instances/tierx/logs/l" "$WORK/instances/tierx/Cookies"
check "gpu tier removes only GPU"   "[ \"\$('$ENGINE' clean tierx gpu)\" = ok ] && [ ! -d '$WORK/instances/tierx/GPUCache' ] && [ -d '$WORK/instances/tierx/Cache' ]"
check "caches tier removes caches"  "[ \"\$('$ENGINE' clean tierx caches)\" = ok ] && [ ! -d '$WORK/instances/tierx/Cache' ]"
check "logs tier removes logs"      "[ \"\$('$ENGINE' clean tierx logs)\" = ok ] && [ ! -d '$WORK/instances/tierx/logs' ]"
check "clean tier preserves login"  "[ -f '$WORK/instances/tierx/Cookies' ]"
check "clean default (no tier) works" "mkdir -p '$WORK/instances/tierx/ShaderCache'; [ \"\$('$ENGINE' clean tierx)\" = ok ] && [ ! -d '$WORK/instances/tierx/ShaderCache' ]"

echo "== cli clean =="
mkdir -p "$WORK/apps/Claude Cleanme.app/Contents" "$WORK/instances/cleanme/GPUCache"
printf '<plist><dict>\n<key>CFBundleIdentifier</key>\n<string>local.claude-profiles.cleanme</string>\n<key>CFBundleDisplayName</key>\n<string>Claude Cleanme</string>\n</dict></plist>\n' > "$WORK/apps/Claude Cleanme.app/Contents/Info.plist"
dd if=/dev/zero of="$WORK/instances/cleanme/GPUCache/b" bs=1024 count=64 2>/dev/null
touch "$WORK/instances/cleanme/Cookies"
CLI="$ROOT/cli/claude-profiles.sh"
check "cli clean clears caches"      "bash '$CLI' clean Cleanme >/dev/null 2>&1; [ ! -d '$WORK/instances/cleanme/GPUCache' ]"
check "cli clean keeps login"        "[ -f '$WORK/instances/cleanme/Cookies' ]"
check "cli clean refuses if running" "bash '$CLI' clean Business 2>&1 | grep -qi running"
check "cli clean rejects unknown"    "bash '$CLI' clean Nope 2>&1 | grep -qi 'no profile'"

echo "== cli remote (ssh-able Claude Code session) =="
rm -f "$WORK/screen.log" "$WORK/screen-sessions"
RR=$(bash "$CLI" remote Work 2>&1)
check "cli remote starts a screen session" "[ -f '$WORK/screen.log' ] && grep -q 'claude-work' '$WORK/screen.log'"
check "cli remote shows ssh attach line"   "printf '%s' \"\$RR\" | grep -qE 'ssh .*-t .*screen -r claude-work'"
check "cli remote shows local attach line" "printf '%s' \"\$RR\" | grep -q 'screen -r claude-work'"
check "cli remote needs a name"            "bash '$CLI' remote 2>&1 | grep -qi usage"
printf '\t12345.claude-work\t(Detached)\n' > "$WORK/screen-sessions"
check "cli remote reuses running session"  "bash '$CLI' remote Work 2>&1 | grep -qi 'already running'"
rm -f "$WORK/screen-sessions"
# When Tailscale is present, remote prints an any-network attach line using the
# Tailscale IP; when absent, it prints the install hint instead.
cat > "$WORK/shims/tailscale" <<'TS'
#!/bin/bash
[ "$*" = "ip -4" ] && echo "100.64.1.2"
TS
chmod +x "$WORK/shims/tailscale"
check "cli remote shows tailscale any-network line" "bash '$CLI' remote Work 2>&1 | grep -qE 'ssh .*@100[.]64[.]1[.]2 -t .*screen -r claude-work'"
rm -f "$WORK/shims/tailscale"
# Restricted PATH so a real (system-installed) tailscale can't shadow the "absent"
# case — the dashboard dev's Mac may well have Tailscale installed.
check "cli remote hints tailscale when absent"      "PATH=\"$WORK/shims:/usr/bin:/bin\" bash '$CLI' remote Work 2>&1 | grep -qi 'install Tailscale'"

echo "== engine remoteinfo (UI JSON) =="
rm -f "$WORK/screen.log" "$WORK/screen-sessions"
# Restricted PATH so a system-installed tailscale can't make the "absent" case flaky.
RI=$(PATH="$WORK/shims:/usr/bin:/bin" "$ENGINE" remoteinfo work)
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
# Security: a slug arrives over the title bridge (untrusted); remoteinfo must
# reject anything that isn't [a-z0-9] before it reaches the nested bash -lc / paths.
rm -f "$WORK/PWNED"
check "remoteinfo rejects injection slug" "\"\$ENGINE\" remoteinfo \"x'; touch '$WORK/PWNED'; echo '\" 2>/dev/null | grep -q 'invalid profile id'; [ ! -f '$WORK/PWNED' ]"
check "remoteinfo rejects traversal slug" "\"\$ENGINE\" remoteinfo '../../escape/evil' 2>/dev/null | grep -q 'invalid profile id'; [ ! -d '$WORK/escape' ]"

echo "== engine remotestop (turn Remote OFF) =="
rm -f "$WORK/screen-quit.log"
"$ENGINE" remotestop work
check "remotestop quits the exact session"  "[ -f '$WORK/screen-quit.log' ] && grep -qF -- '-S claude-work -X quit' '$WORK/screen-quit.log'"
check "remotestop does NOT touch claude-work2" "! grep -qF -- 'claude-work2' '$WORK/screen-quit.log'"
check "remotestop emits ok"                 "[ \"\$('$ENGINE' remotestop work)\" = ok ]"
# default → claude-default (engine.sh contract: Remote works for the default too)
rm -f "$WORK/screen-quit.log"
"$ENGINE" remotestop default
check "remotestop default quits claude-default" "grep -qF -- '-S claude-default -X quit' '$WORK/screen-quit.log'"
# Idempotent: a second stop with no live session is a harmless no-op that still emits ok.
check "remotestop is idempotent (still ok)" "[ \"\$('$ENGINE' remotestop work)\" = ok ]"
# Same untrusted-slug boundary as remoteinfo: an injection slug never reaches `screen`.
rm -f "$WORK/screen-quit.log" "$WORK/PWNED"
check "remotestop rejects injection slug"   "\"\$ENGINE\" remotestop \"x'; touch '$WORK/PWNED'; echo '\" >/dev/null 2>&1; [ ! -f '$WORK/PWNED' ] && [ ! -f '$WORK/screen-quit.log' ]"
rm -f "$WORK/screen-quit.log"

echo "== engine copy (clipboard bridge) =="
cat > "$WORK/shims/pbcopy" <<PB
#!/bin/bash
cat > "$WORK/pbcopy.out"
PB
chmod +x "$WORK/shims/pbcopy"
"$ENGINE" copy 'ssh me@mac.local -t "screen -r claude-work"'
check "copy pipes text to pbcopy" "[ -f '$WORK/pbcopy.out' ] && grep -q 'screen -r claude-work' '$WORK/pbcopy.out'"
rm -f "$WORK/shims/pbcopy" "$WORK/pbcopy.out"

echo "== bulk cleanup =="
mkdir -p "$WORK/instances/bulkstopped/GPUCache"; dd if=/dev/zero of="$WORK/instances/bulkstopped/GPUCache/b" bs=1024 count=64 2>/dev/null
mkdir -p "$WORK/apps/Claude BulkStopped.app/Contents"
printf '<plist><dict>\n<key>CFBundleIdentifier</key>\n<string>local.claude-profiles.bulkstopped</string>\n<key>CFBundleDisplayName</key>\n<string>Claude BulkStopped</string>\n</dict></plist>\n' > "$WORK/apps/Claude BulkStopped.app/Contents/Info.plist"
R=$("$ENGINE" cleanall)
check "cleanall cleans stopped"  "case \"\$R\" in ok*bulkstopped*) [ ! -d '$WORK/instances/bulkstopped/GPUCache' ] ;; *) false ;; esac"
check "cleanall skips running"   "case \"\$R\" in *business*) false ;; *) true ;; esac"

echo "== attribution isolation (no cross-app bleed) =="
# Two profiles whose data dirs are prefix-colliding: .../work is a substring of
# .../work2. The old substring match folded work2's process into work's metrics.
mkdir -p "$WORK/instances/work" "$WORK/instances/work2"
cp "$WORK/shims/ps" "$WORK/shims/ps.bak"
cat > "$WORK/shims/ps" <<PSEOF
#!/bin/bash
T="300 1 5.0 100000 /Applications/Claude.app/Contents/MacOS/Claude --user-data-dir=$WORK/instances/work
301 1 5.0 100000 /Applications/Claude.app/Contents/MacOS/Claude --user-data-dir=$WORK/instances/work2"
case "\$*" in
  *"pid=,command="*) echo "\$T" | awk '{printf "%s ", \$1; for(i=5;i<=NF;i++) printf "%s ", \$i; print ""}' ;;
  *"pid=,ppid="*)    echo "\$T" | awk '{print \$1, \$2}' ;;
esac
PSEOF
chmod +x "$WORK/shims/ps"
check "prefix slug matches exactly one pid" "[ \"\$(bash -c '. \"\$1\"; main_pids_for_dir \"\$2\"' _ '$ENGINE' '$WORK/instances/work' | tr -d '[:space:]')\" = 300 ]"
check "longer slug resolves to its own pid" "[ \"\$(bash -c '. \"\$1\"; main_pids_for_dir \"\$2\"' _ '$ENGINE' '$WORK/instances/work2' | tr -d '[:space:]')\" = 301 ]"
mv "$WORK/shims/ps.bak" "$WORK/shims/ps"
# terminal dedup: one /dev/ttys held by main + helper must count once, not twice
cp "$WORK/shims/lsof" "$WORK/shims/lsof.bak"
cat > "$WORK/shims/lsof" <<'LSOFEOF'
#!/bin/bash
printf 'c 400 u 17u CHR /dev/ttys009\nc 401 u 18u CHR /dev/ttys009\n'
LSOFEOF
chmod +x "$WORK/shims/lsof"
check "shared terminal counted once" "[ \"\$(bash -c '. \"\$1\"; pty_count_for_pids \$2 \$3' _ '$ENGINE' 400 401)\" = 1 ]"
mv "$WORK/shims/lsof.bak" "$WORK/shims/lsof"

echo
printf '%d passed, %d failed\n' "$PASS" "$FAIL"
[ "$FAIL" -eq 0 ]
