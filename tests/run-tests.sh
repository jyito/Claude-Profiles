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
  *"pid=,command="*) echo "\$T" | awk '{printf "%s ", \$1; for(i=5;i<=NF;i++) printf "%s ", \$i; print ""}' ;;
  *"pid=,ppid="*)    echo "\$T" | awk '{print \$1, \$2}' ;;
  *"-o pcpu=,rss= -p"*) p="\${@: -1}"; echo "\$T" | awk -v p=",\$p," '{ if (index(p, ","\$1",")) print \$3, \$4 }' ;;
esac
EOF

cat > "$WORK/shims/lsof" <<'EOF'
#!/bin/bash
case "$*" in
  *100*) printf 'c 100 u 17u CHR /dev/ttys001\nc 101 u 18u CHR /dev/ttys002\nc 102 u 19u CHR /dev/ttys003\n' ;;
  *200*) printf 'c 200 u 17u CHR /dev/ttys004\n' ;;
esac
EOF
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
"$L" >/dev/null 2>&1
check "add creates wrapper"    "[ -d '$WORK/apps/Claude Business.app' ]"
check "add creates data dir"   "[ -d '$WORK/instances/business' ]"
touch "$WORK/instances/business/marker"
printf '＋  Add a profile…\nbutton returned:Create, text returned:Business\nbutton returned:Later\nfalse\n' > "$WORK/queue"
"$L" >/dev/null 2>&1
check "re-add preserves data"  "[ -f '$WORK/instances/business/marker' ]"
printf '＋  Add a profile…\nbutton returned:Create, text returned:Eve\" {X}\nbutton returned:Later\nfalse\n' > "$WORK/queue"
"$L" >/dev/null 2>&1
check "hostile names sanitized" "[ -d '$WORK/apps/Claude Eve X.app' ]"
check "--action add dispatch"  "printf 'button returned:Create, text returned:Disp\nbutton returned:Later\n' > '$WORK/queue'; '$L' --action add >/dev/null 2>&1; [ -d '$WORK/apps/Claude Disp.app' ]"

echo "== engine stats =="
printf '2026-06-10 08:12\n2026-06-12 09:14\n' > "$WORK/instances/business/.profile-activity"
S=$("$ENGINE" stats)
check "stats is valid JSON"    "printf '%s' '$S' | python3 -m json.tool >/dev/null"
check "cpu summed over tree"   "printf '%s' '$S' | grep -q '\"cpu\":16.8'"
check "mem summed over tree"   "printf '%s' '$S' | grep -q '\"mem\":896'"
check "pty count attributed"   "printf '%s' '$S' | grep -q '\"ptys\":3'"
check "default instance shown" "printf '%s' '$S' | grep -q 'Claude (default)'"
check "opens counted"          "printf '%s' '$S' | grep -q '\"opens\":2'"
check "mainpid resolves"       "[ \"\$('$ENGINE' mainpid business)\" = 100 ]"
check "defaultpid resolves"    "[ \"\$('$ENGINE' defaultpid)\" = 200 ]"

echo "== engine cleanup safety =="
mkdir -p "$WORK/instances/evex/GPUCache"
dd if=/dev/zero of="$WORK/instances/evex/GPUCache/b" bs=1024 count=256 2>/dev/null
dd if=/dev/zero of="$WORK/instances/evex/Cookies" bs=1024 count=4 2>/dev/null
check "clean frees caches"     "[ \"\$('$ENGINE' clean evex)\" = ok ] && [ ! -d '$WORK/instances/evex/GPUCache' ]"
check "clean preserves login"  "[ -f '$WORK/instances/evex/Cookies' ]"
check "clean refuses if running" "[ \"\$('$ENGINE' clean business)\" = running ]"

echo "== dashboard JS =="
if command -v node >/dev/null 2>&1; then
    "$ENGINE" stats > "$WORK/stats.json"
    R=$(node -e "
const fs=require('fs');
const html=fs.readFileSync('$ROOT/src/dashboard.html','utf8');
const js=html.match(/<script>([\s\S]*)<\/script>/)[1];
let grid='',kpi='';
global.document={getElementById:(id)=>({set innerHTML(v){if(id==='grid')grid=v;else kpi=v;},set textContent(v){}}),title:''};
global.setTimeout=()=>{};
eval(js);
const d=JSON.parse(fs.readFileSync('$WORK/stats.json','utf8'));
updateStats(d); updateStats(d);
console.log((grid.match(/class=\"card\"/g)||[]).length, (grid.match(/Show Window/g)||[]).length, (grid.match(/<polyline/g)||[]).length);
" 2>/dev/null)
    check "cards render"        "[ \"\$(echo '$R' | awk '{print \$1}')\" -ge 3 ]"
    check "Show Window buttons" "[ \"\$(echo '$R' | awk '{print \$2}')\" = 2 ]"
    check "sparklines render"   "[ \"\$(echo '$R' | awk '{print \$3}')\" -ge 4 ]"
else
    echo "  - node not found, skipping JS render tests"
fi

echo
printf '%d passed, %d failed\n' "$PASS" "$FAIL"
[ "$FAIL" -eq 0 ]
