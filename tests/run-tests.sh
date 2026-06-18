#!/bin/bash
# run-tests.sh — Linux-compatible test suite for Claude Profiles.
# Shims macOS tools (osascript, defaults, ps, lsof) so the bash engine and
# dialog flows can be exercised on any CI runner. The AppleScript window host
# is macOS-only and is validated by review + the launcher's runtime fallback.
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
  *-ls*)  cat "$WORK/screen-sessions" 2>/dev/null || echo "No Sockets found." ;;
  *-dmS*) printf '%s\n' "\$*" >> "$WORK/screen.log" ;;
esac
EOF
cat > "$WORK/shims/scutil" <<'EOF'
#!/bin/bash
echo "testmac"
EOF
# `open` MUST be shimmed before any launcher run: on a dev Mac, launch_dashboard
# would otherwise osacompile + `open` a real stay-open dashboard applet, which
# survives $WORK cleanup and orphans in the Dock. The shim just logs the args.
printf '#!/bin/bash\nprintf "%%s\\\\n" "$*" >> "%s/open.log"\n' "$WORK" > "$WORK/shims/open"
# Stub the Claude Code CLI so remoteinfo's existence guard passes in CI (where it
# isn't installed); a no-op is fine since `screen` is also a shim.
printf '#!/bin/bash\n:\n' > "$WORK/shims/claude"
chmod +x "$WORK/shims/"*

export PATH="$WORK/shims:$PATH"
export CLAUDE_PROFILES_APP="$WORK/Claude.app"
export CLAUDE_PROFILES_APPS_DIR="$WORK/apps"
export CLAUDE_PROFILES_INSTANCES_DIR="$WORK/instances"
LAUNCHER_SRC="$ROOT/src/launcher"
ENGINE="$ROOT/src/engine.sh"

# launcher resolves /usr/bin/osascript absolutely; make a shim-aware copy
L="$WORK/launcher"
sed 's|OSA="/usr/bin/osascript"|OSA="osascript"|' "$LAUNCHER_SRC" > "$L" && chmod +x "$L"

echo "== syntax =="
check "launcher bash syntax"   "bash -n '$LAUNCHER_SRC'"
check "engine bash syntax"     "bash -n '$ENGINE'"
check "cli bash syntax"        "bash -n '$ROOT/cli/claude-profiles.sh'"

echo "== profile lifecycle (dialog flows) =="
printf '＋  Add a profile…\nbutton returned:Create, text returned:Business\nbutton returned:Later\nfalse\n' > "$WORK/queue"
"$L" --classic >/dev/null 2>&1
check "add creates wrapper"    "[ -d '$WORK/apps/Claude Business.app' ]"
check "add creates data dir"   "[ -d '$WORK/instances/business' ]"
touch "$WORK/instances/business/marker"
printf '＋  Add a profile…\nbutton returned:Create, text returned:Business\nbutton returned:Later\nfalse\n' > "$WORK/queue"
"$L" --classic >/dev/null 2>&1
check "re-add preserves data"  "[ -f '$WORK/instances/business/marker' ]"
printf '＋  Add a profile…\nbutton returned:Create, text returned:Eve\" {X}\nbutton returned:Later\nfalse\n' > "$WORK/queue"
"$L" --classic >/dev/null 2>&1
check "hostile names sanitized" "[ -d '$WORK/apps/Claude Eve X.app' ]"
check "--action add dispatch"  "printf 'button returned:Create, text returned:Disp\nbutton returned:Later\n' > '$WORK/queue'; '$L' --action add >/dev/null 2>&1; [ -d '$WORK/apps/Claude Disp.app' ]"

echo "== engine headless lifecycle =="
check "engine create"          "[ \"\$('$ENGINE' create 'Head Less')\" = 'ok headless' ] && [ -d '$WORK/apps/Claude Head Less.app' ]"
check "engine create sanitizes" "[ \"\$('$ENGINE' create 'Bad\":{Name}')\" = 'ok badname' ]"
check "engine create reserves default" "printf '%s' \"\$('$ENGINE' create Default)\" | grep -qi reserved && [ ! -d '$WORK/instances/default' ]"
check "engine create strips XML chars (valid plist)" "[ \"\$('$ENGINE' create 'Q&A')\" = 'ok qa' ] && python3 -c \"import plistlib; plistlib.load(open('$WORK/apps/Claude QA.app/Contents/Info.plist','rb'))\""
check "engine remove keeps data" "mkdir -p '$WORK/instances/headless'; touch '$WORK/instances/headless/m'; [ \"\$('$ENGINE' remove headless)\" = ok ] && [ ! -d '$WORK/apps/Claude Head Less.app' ] && [ -f '$WORK/instances/headless/m' ]"
check "engine purge erases data" "[ \"\$('$ENGINE' purge headless)\" = ok ] && [ ! -d '$WORK/instances/headless' ]"
check "default launch exits 0"   "printf 'x\n' > '$WORK/queue'; '$L' >/dev/null 2>&1"

echo "== per-profile badge icons =="
check "badge color is deterministic" "[ \"\$(bash -c '. \"\$1\"; badge_color_for work' _ '$ENGINE')\" = \"\$(bash -c '. \"\$1\"; badge_color_for work' _ '$ENGINE')\" ]"
check "badge color is r g b triple"  "bash -c '. \"\$1\"; badge_color_for work' _ '$ENGINE' | grep -qE '^[0-9]+ [0-9]+ [0-9]+\$'"
check "badge falls back to plain copy" "rm -rf '$WORK/bf'; mkdir -p '$WORK/bf'; printf icnsDATA > '$WORK/srcicns'; bash -c '. \"\$1\"; RES_DIR=/nonexistent; badge_icon work \"Claude Work\" \"$WORK/srcicns\" \"$WORK/bf\"' _ '$ENGINE' 2>/dev/null; cmp -s '$WORK/srcicns' '$WORK/bf/app.icns'"
# The real render path (sips -> osascript compositor -> iconutil) can't run here:
# this suite shims osascript for the dialog tests, so badge_icon's compositor call
# would hit the shim. The fallback + color tests above cover the bash logic; the
# actual rendering is verified directly with the real osascript (see commit notes).
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
check "throttle button in UI"         "grep -q 'Throttle CPU' '$ROOT/src/dashboard.html'"
check "applet routes throttle"        "grep -q 'throttle' '$ROOT/src/dashboard.applescript'"

echo "== restart (free leaked terminal handles) =="
# A stopped/unknown instance has no tree to cycle, so restart skips straight to
# relaunch and returns ok without blocking. Slug is validated at the boundary.
check "restart relaunches stopped (ok)" "[ \"\$('$ENGINE' restart ghostprof)\" = ok ]"
check "restart rejects spaced slug"     "[ \"\$('$ENGINE' restart 'bad slug')\" = 'err invalid slug' ]"
check "restart rejects traversal slug"  "[ \"\$('$ENGINE' restart '../../evil')\" = 'err invalid slug' ]"
check "applet routes restart"           "grep -q 'restart' '$ROOT/src/dashboard.applescript'"
check "restart control in UI"           "grep -q 'armRestart' '$ROOT/src/dashboard.html'"

echo "== settings & auto-clean =="
check "getconfig defaults to zero"   "[ \"\$('$ENGINE' getconfig)\" = '{\"autoCloseIdleMin\":0,\"autoCleanThresholdMB\":0}' ]"
check "setconfig persists threshold" "[ \"\$('$ENGINE' setconfig autoCleanThresholdMB 500)\" = ok ]"
check "getconfig reflects setting"   "'$ENGINE' getconfig | grep -q '\"autoCleanThresholdMB\":500'"
check "setconfig rejects bad key"    "[ \"\$('$ENGINE' setconfig nope 5)\" = 'err badkey' ]"
check "setconfig rejects bad value"  "[ \"\$('$ENGINE' setconfig autoCloseIdleMin -3)\" = 'err badval' ]"
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

echo "== default instance launch =="
rm -f "$WORK/open.log"   # the `open` shim is set up at the top; isolate this check
check "opendefault launches Claude" "'$ENGINE' opendefault >/dev/null; grep -q -- '-n -a $WORK/Claude.app' '$WORK/open.log'"
check "opendefault button in UI"    "grep -q \"act('opendefault')\" '$ROOT/src/dashboard.html' || grep -q 'opendefault' '$ROOT/src/dashboard.html'"

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
check "cleanup modal in UI"      "grep -q 'id=\"cleanmodal\"' '$ROOT/src/dashboard.html'"
check "killswitch arm-confirm"   "grep -q 'Click again to confirm' '$ROOT/src/dashboard.html'"

echo "== settings UI =="
check "settings modal in UI"     "grep -q 'id=\"setmodal\"' '$ROOT/src/dashboard.html'"
check "settings save wired"      "grep -q 'saveSetting(' '$ROOT/src/dashboard.html'"
check "auto-close warning shown" "grep -q 'can look idle' '$ROOT/src/dashboard.html'"
check "config push hook present" "grep -q 'function updateConfig' '$ROOT/src/dashboard.html'"
check "applet routes autotick"   "grep -q 'autotick' '$ROOT/src/dashboard.applescript'"

echo "== polish =="
check "loading screen present"  "grep -q 'id=\"loading\"' '$ROOT/src/dashboard.html'"
check "button hover states"     "grep -q ':hover' '$ROOT/src/dashboard.html'"
check "keyboard focus ring"     "grep -q 'focus-visible' '$ROOT/src/dashboard.html'"
check "spinner animation"       "grep -q '@keyframes spin' '$ROOT/src/dashboard.html'"

echo "== applet branding =="
check "applet icon override stripped" "grep -q 'Delete :CFBundleIconName' '$LAUNCHER_SRC' && grep -q 'Assets.car' '$LAUNCHER_SRC'"
check "applet bundle id branded"      "grep -q 'local.claude-profiles.dashboard' '$LAUNCHER_SRC'"
check "applet reused when unchanged"  "grep -q 'cmp -s' '$LAUNCHER_SRC'"

echo "== dashboard self-heal (moved app) =="
printf 'property resourcesDir : "/Users/x/Applications/Claude Profiles.app/Contents/Resources"\n' > "$WORK/saved_old.applescript"
# the actual incident: app now at /Applications, baked path was ~/Applications —
# and "/Applications/…" is a SUBSTRING of "/Users/x/Applications/…", so an exact
# match (not a substring test) is required to flag it stale.
check "moved app flagged stale"   "bash -c '. \"\$1\" >/dev/null 2>&1; runtime_applet_stale \"/Applications/Claude Profiles.app/Contents/Resources\" \"\$2\"' _ '$LAUNCHER_SRC' '$WORK/saved_old.applescript'"
check "matching path not stale"   "! bash -c '. \"\$1\" >/dev/null 2>&1; runtime_applet_stale \"/Users/x/Applications/Claude Profiles.app/Contents/Resources\" \"\$2\"' _ '$LAUNCHER_SRC' '$WORK/saved_old.applescript'"
check "no cached build not stale" "! bash -c '. \"\$1\" >/dev/null 2>&1; runtime_applet_stale /any \"\$2\"' _ '$LAUNCHER_SRC' '$WORK/no_such_file'"
check "launch_dashboard self-heals" "grep -q 'runtime_applet_stale' '$LAUNCHER_SRC'"

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

echo "== dashboard JS =="
if command -v node >/dev/null 2>&1; then
    "$ENGINE" stats > "$WORK/stats.json"
    R=$(node -e "
const fs=require('fs');
const html=fs.readFileSync('$ROOT/src/dashboard.html','utf8');
const js=html.match(/<script>([\s\S]*)<\/script>/)[1];
// Per-id element registry so we can observe livePatch's in-place updates (it
// writes to cpuspk-/sub-/etc. by id), not just the grid innerHTML.
const E={};
global.document={getElementById:(id)=>{ if(!E[id]) E[id]={innerHTML:'',textContent:'',className:'',value:'',style:{},focus(){}}; return E[id]; },addEventListener:()=>{},title:''};
global.setTimeout=()=>{};
eval(js);
const d=JSON.parse(fs.readFileSync('$WORK/stats.json','utf8'));
updateStats(d); updateStats(d);   // 2nd tick is a livePatch (structure unchanged)
const grid=(E['grid']||{}).innerHTML||'', loadCls=(E['loading']||{}).className||'';
const allHtml=Object.keys(E).map(k=>E[k].innerHTML||'').join('');
const cards=(grid.match(/class=\"card\"/g)||[]).length, sw=(grid.match(/Show Window/g)||[]).length;
// Sparklines only get a polyline once hist has 2 points — which happens on the
// 2nd tick via livePatch into the cpuspk-/memspk- elements, so this verifies the
// in-place patch actually ran.
const sp=(allHtml.match(/<polyline/g)||[]).length, rm=(grid.match(/Remove profile/g)||[]).length;
let drill=0;
try {
  const run=d.find(p=>p.slug && p.running);
  if (run) {
    toggleExpand(run.slug);
    updateTerminals(run.slug,[{dev:'/dev/ttys001',pid:100,cmd:'bash -l',idle:200}]);
    const dh=(E['drill-'+run.slug]||{}).innerHTML||'', g2=(E['grid']||{}).innerHTML||'';
    if (dh.indexOf('class=\"tterm\"')>-1 && dh.indexOf('ttys001')>-1 && g2.indexOf('expanded')>-1 && dh.indexOf('closeTerm(')>-1 && dh.indexOf(\"act('throttle'\")>-1) drill=1;
  }
} catch(e){}
let tiers=0;
try {
  const stp=d.find(p=>p.slug && !p.running);
  if (stp) {
    expanded=null; toggleExpand(stp.slug);
    const g3=(E['grid']||{}).innerHTML||'';
    if (g3.indexOf('tierbtn')>-1 && g3.indexOf(\"act3('clean'\")>-1) tiers=1;
  }
} catch(e){}
let lock=0;
try { confirmStep['zz']=1; const a=uiLocked(); delete confirmStep['zz']; const b=uiLocked(); lock=(a && !b)?1:0; } catch(e){}
let avatarColor=0;
try { const prof=d.find(p=>p.slug && p.color); const g4=(E['grid']||{}).innerHTML||''; if(prof && g4.indexOf('background:'+prof.color)>-1) avatarColor=1; } catch(e){}
let swatches=0;
try { const g5=(E['grid']||{}).innerHTML||''; if(g5.indexOf('class=\"swatch')>-1 && g5.indexOf('setbadge')>-1) swatches=1; } catch(e){}
let remotebtn=0, detailsbtn=0, defclean=0;
try { const g6=(E['grid']||{}).innerHTML||''; if(g6.indexOf(\"act('remote'\")>-1) remotebtn=1; if(g6.indexOf('+ Details')>-1) detailsbtn=1;
  // the default card gets Remote AND a Details toggle, both keyed 'default'
  if(g6.indexOf(\"act('remote','default')\")>-1 && g6.indexOf(\"toggleExpand('default')\")>-1) defclean=1; } catch(e){}
let ddrill=0;
try {
  expanded=null; toggleExpand('default');
  updateTerminals('default',[{dev:'/dev/ttys004',pid:200,cmd:'Claude',idle:5}]);
  const dh=(E['drill-default']||{}).innerHTML||'';
  // default drill = terminals + throttle, but NO badge picker (no slug)
  if(dh.indexOf('ttys004')>-1 && dh.indexOf(\"act('throttle','default')\")>-1 && dh.indexOf('class=\"swatch')===-1) ddrill=1;
} catch(e){}
let rmfill=0;
try {
  updateRemote({slug:'business',session:'claude-business',user:'me',host:'mac.local',tailscaleIp:'100.64.1.2',alreadyRunning:false});
  const loc=(E['rm-local']||{}).textContent||'', ts=(E['rm-ts']||{}).textContent||'';
  if(loc.indexOf('screen -r claude-business')>-1 && ts.indexOf('100.64.1.2')>-1) rmfill=1;
} catch(e){}
let rmcta=0;
try {
  updateRemote({slug:'business',session:'claude-business',user:'me',host:'mac.local',tailscaleIp:'',alreadyRunning:false});
  if((E['rm-ts-cta']||{style:{}}).style.display!=='none' && (E['rm-ts-cmd']||{style:{}}).style.display==='none') rmcta=1;
} catch(e){}
// /dev/ptmx leak: quiet status-line stat (>= threshold) + cleanup inside Details;
// system banner near the ceiling. All hidden/absent when clean.
let leakhidden=0, bannerhidden=0, leakstat=0, banner=0, leakclean=0;
try {
  expanded=null; restartArmed=null;
  fullRender(d);                              // real stats: low ptmx → no stat, no banner
  const gl=(E['grid']||{}).innerHTML||'';
  leakhidden = (gl.indexOf('leaked')===-1)?1:0;
  bannerhidden = (((E['sysbanner']||{}).className||'').indexOf('hidden')>-1)?1:0;
  const hi=JSON.parse(JSON.stringify(d)), r=hi.find(p=>p.running); r.ptmx=420; r.ptmxMax=511;
  const es=(r.slug||'default');
  fullRender(hi);                             // one instance near the ceiling
  const gh=(E['grid']||{}).innerHTML||'';
  if (gh.indexOf('420 leaked')>-1 && gh.indexOf('class=\"leaked\"')>-1) leakstat=1;  // quiet stat, not a box
  if (((E['sysbanner']||{}).className||'')==='sysbanner') banner=1;
  // cleanup action lives in + Details, NOT on the card face
  const onFace = gh.indexOf('Restart to free handles')>-1;
  updateStats(hi);                            // lastData=hi so profileBySlug sees the leak
  expanded=es;
  updateTerminals(es,[{dev:'/dev/ttys009',pid:1,cmd:'bash',idle:10}]);
  const da=(E['drill-'+es]||{}).innerHTML||'';
  const hasAction = da.indexOf(\"armRestart('\"+es+\"')\")>-1 && da.indexOf('Restart to free handles')>-1;
  restartArmed=es;
  updateTerminals(es,[{dev:'/dev/ttys009',pid:1,cmd:'bash',idle:10}]);
  const dc=(E['drill-'+es]||{}).innerHTML||'';
  const hasConfirm = dc.indexOf(\"doRestart('\"+es+\"')\")>-1 && dc.indexOf('Confirm restart')>-1;
  if (hasAction && hasConfirm && !onFace) leakclean=1;
  restartArmed=null; expanded=null;
} catch(e){}
console.log(cards, sw, sp, rm, drill, tiers, (loadCls.indexOf('hidden')>-1?1:0), lock, avatarColor, swatches, remotebtn, detailsbtn, rmfill, rmcta, defclean, ddrill, leakhidden, bannerhidden, leakstat, banner, leakclean);
" 2>/dev/null)
    check "cards render"        "[ \"\$(echo '$R' | awk '{print \$1}')\" -ge 3 ]"
    check "Show Window buttons" "[ \"\$(echo '$R' | awk '{print \$2}')\" = 2 ]"
    check "sparklines render"   "[ \"\$(echo '$R' | awk '{print \$3}')\" -ge 4 ]"
    check "in-card remove flow"  "[ \"\$(echo '$R' | awk '{print \$4}')\" -ge 1 ]"
    check "drill-down renders terminals" "[ \"\$(echo '$R' | awk '{print \$5}')\" = 1 ]"
    check "stopped drill shows clean tiers" "[ \"\$(echo '$R' | awk '{print \$6}')\" = 1 ]"
    check "loading screen hides on render"  "[ \"\$(echo '$R' | awk '{print \$7}')\" = 1 ]"
    check "input lock derived from confirm state" "[ \"\$(echo '$R' | awk '{print \$8}')\" = 1 ]"
    check "card avatar uses badge color"          "[ \"\$(echo '$R' | awk '{print \$9}')\" = 1 ]"
    check "drill-down shows badge swatches"       "[ \"\$(echo '$R' | awk '{print \$10}')\" = 1 ]"
    check "card shows Remote button"              "[ \"\$(echo '$R' | awk '{print \$11}')\" = 1 ]"
    check "card shows + Details button"           "[ \"\$(echo '$R' | awk '{print \$12}')\" = 1 ]"
    check "remote modal fills ssh lines"          "[ \"\$(echo '$R' | awk '{print \$13}')\" = 1 ]"
    check "remote modal shows tailscale CTA"      "[ \"\$(echo '$R' | awk '{print \$14}')\" = 1 ]"
    check "default card has Remote + Details"     "[ \"\$(echo '$R' | awk '{print \$15}')\" = 1 ]"
    check "default drill is terminals, no badges" "[ \"\$(echo '$R' | awk '{print \$16}')\" = 1 ]"
    check "no leak stat when ptmx low"            "[ \"\$(echo '$R' | awk '{print \$17}')\" = 1 ]"
    check "no system banner when ptmx low"        "[ \"\$(echo '$R' | awk '{print \$18}')\" = 1 ]"
    check "quiet leak stat past threshold"        "[ \"\$(echo '$R' | awk '{print \$19}')\" = 1 ]"
    check "system banner near ptmx ceiling"       "[ \"\$(echo '$R' | awk '{print \$20}')\" = 1 ]"
    check "leak cleanup lives in + Details"       "[ \"\$(echo '$R' | awk '{print \$21}')\" = 1 ]"
else
    echo "  - node not found, skipping JS render tests"
fi

echo "== QR encoder (Remote modal) =="
if command -v node >/dev/null 2>&1; then
    Q=$(node -e "
const fs=require('fs');
const html=fs.readFileSync('$ROOT/src/dashboard.html','utf8');
const js=html.match(/<script>([\s\S]*)<\/script>/)[1];
global.document={getElementById:()=>null,addEventListener:()=>{},title:''};
global.setTimeout=()=>{}; global.setInterval=()=>{};
eval(js);
let fmt=1, gf=0, struct=0, roundtrip=0, svg=0, bump=0;
// 1) format-info BCH known-answer (ECC level L, masks 0..7) — authoritative table
const KAT=['111011111000100','111001011110011','111110110101010','111100010011101','110011000101111','110001100011000','110110001000001','110100101110110'];
for(let mk=0;mk<8;mk++){ if((qrFormatBits(mk)&0x7FFF)!==parseInt(KAT[mk],2)) fmt=0; }
// 2) GF(256) table spot-check (α^8 = 29 with primitive 0x11D)
gf = (QR_EXP[8]===29 && QR_LOG[29]===8) ? 1 : 0;
// 3) structure: short text → v1 (21×21), finder corner is solid 7×7 with a ring
const b=qrBuild('hello');
if(b && b.size===21){
  const m=b.matrix;
  if(m[0][0]===1&&m[0][6]===1&&m[6][0]===1&&m[6][6]===1&&m[1][1]===0&&m[2][2]===1&&m[0][7]===0) struct=1;
}
// 4) round-trip: undo mask + read zigzag → original data+ec codewords
function readback(b){
  const m=b.matrix.map(r=>r.slice());
  for(let r=0;r<b.size;r++)for(let c=0;c<b.size;c++){ if(!b.reserved[r][c]&&qrMaskCond(b.mask,r,c)) m[r][c]^=1; }
  const bits=[]; for(let right=b.size-1;right>=1;right-=2){ if(right===6)right=5;
    for(let vert=0;vert<b.size;vert++)for(let j=0;j<2;j++){ const col=right-j,row=(((right+1)&2)===0)?(b.size-1-vert):vert; if(!b.reserved[row][col]) bits.push(m[row][col]); } }
  const cw=[]; for(let i=0;i+8<=bits.length&&cw.length<b.codewords.length;i+=8){ let v=0; for(let k=0;k<8;k++)v=(v<<1)|bits[i+k]; cw.push(v); } return cw;
}
const rb=readback(b); roundtrip=(rb.length===b.codewords.length && rb.every((v,i)=>v===b.codewords[i]))?1:0;
// 5) svg output; 6) longer text bumps the version (bigger matrix)
const s=qrSvg('hello'); if(s.indexOf('<svg')===0 && s.indexOf('<rect')>-1) svg=1;
const big=qrBuild('ssh someuser@100.115.92.14 -t \"screen -r claude-personal-account\"');
if(big && big.size>21) bump=1;
console.log(fmt,gf,struct,roundtrip,svg,bump);
" 2>/dev/null)
    check "QR format-info BCH matches spec table" "[ \"\$(echo '$Q' | awk '{print \$1}')\" = 1 ]"
    check "QR GF(256) tables correct"             "[ \"\$(echo '$Q' | awk '{print \$2}')\" = 1 ]"
    check "QR finder patterns + v1 size"          "[ \"\$(echo '$Q' | awk '{print \$3}')\" = 1 ]"
    check "QR data round-trips (placement+mask)"  "[ \"\$(echo '$Q' | awk '{print \$4}')\" = 1 ]"
    check "QR renders inline SVG"                 "[ \"\$(echo '$Q' | awk '{print \$5}')\" = 1 ]"
    check "QR bumps version for longer text"      "[ \"\$(echo '$Q' | awk '{print \$6}')\" = 1 ]"
else
    echo "  - node not found, skipping QR tests"
fi

echo
printf '%d passed, %d failed\n' "$PASS" "$FAIL"
[ "$FAIL" -eq 0 ]
