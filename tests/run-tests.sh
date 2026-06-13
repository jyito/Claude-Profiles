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
cat > "$WORK/shims/stat" <<'EOF'
#!/bin/bash
# emulate macOS `stat -f %m <path>` → device mtime epoch (fixed, in the past)
echo 1700000000
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
check "engine remove keeps data" "mkdir -p '$WORK/instances/headless'; touch '$WORK/instances/headless/m'; [ \"\$('$ENGINE' remove headless)\" = ok ] && [ ! -d '$WORK/apps/Claude Head Less.app' ] && [ -f '$WORK/instances/headless/m' ]"
check "engine purge erases data" "[ \"\$('$ENGINE' purge headless)\" = ok ] && [ ! -d '$WORK/instances/headless' ]"
check "default launch exits 0"   "printf 'x\n' > '$WORK/queue'; '$L' >/dev/null 2>&1"

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

echo "== terminals (drill-down data) =="
T=$("$ENGINE" terminals business)
check "terminals is valid JSON"   "printf '%s' '$T' | python3 -m json.tool >/dev/null"
check "terminals lists 3 devices" "[ \"\$(printf '%s' '$T' | python3 -c 'import sys,json; print(len(json.load(sys.stdin)))')\" = 3 ]"
check "terminals rows carry dev"  "printf '%s' '$T' | grep -q '\"dev\":\"/dev/ttys001\"'"
check "terminals rows carry idle" "printf '%s' '$T' | grep -q '\"idle\":[0-9]'"
check "terminals rows carry cmd"  "printf '%s' '$T' | grep -q '\"cmd\":\"'"
check "terminals empty when stopped" "[ \"\$('$ENGINE' terminals evex)\" = '[]' ]"

echo "== closeterm (guarded terminal close) =="
# Only devices in THIS instance's own tree may be closed. business owns ttys001-003
# (lsof shim for pid 100 tree); the default's ttys004 and unknown devices are refused.
check "closeterm accepts own device"    "[ \"\$('$ENGINE' closeterm business ttys001)\" = ok ]"
check "closeterm refuses other instance" "[ \"\$('$ENGINE' closeterm business ttys004)\" = refused ]"
check "closeterm refuses unknown device" "[ \"\$('$ENGINE' closeterm business ttys999)\" = refused ]"
check "closeterm refuses when stopped"   "[ \"\$('$ENGINE' closeterm evex ttys001)\" = refused ]"
check "closeterm rejects bad device arg" "[ \"\$('$ENGINE' closeterm business notadev)\" = baddev ]"

echo "== default instance launch =="
printf '#!/bin/bash\nprintf "%%s\\\\n" "$*" >> "%s/open.log"\n' "$WORK" > "$WORK/shims/open" && chmod +x "$WORK/shims/open"
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

echo "== bulk cleanup =="
mkdir -p "$WORK/instances/bulkstopped/GPUCache"; dd if=/dev/zero of="$WORK/instances/bulkstopped/GPUCache/b" bs=1024 count=64 2>/dev/null
mkdir -p "$WORK/apps/Claude BulkStopped.app/Contents"
printf '<plist><dict>\n<key>CFBundleIdentifier</key>\n<string>local.claude-profiles.bulkstopped</string>\n<key>CFBundleDisplayName</key>\n<string>Claude BulkStopped</string>\n</dict></plist>\n' > "$WORK/apps/Claude BulkStopped.app/Contents/Info.plist"
R=$("$ENGINE" cleanall)
check "cleanall cleans stopped"  "case \"\$R\" in ok*bulkstopped*) [ ! -d '$WORK/instances/bulkstopped/GPUCache' ] ;; *) false ;; esac"
check "cleanall skips running"   "case \"\$R\" in *business*) false ;; *) true ;; esac"
check "cleanup modal in UI"      "grep -q 'id=\"cleanmodal\"' '$ROOT/src/dashboard.html'"
check "killswitch arm-confirm"   "grep -q 'Click again to confirm' '$ROOT/src/dashboard.html'"

echo "== applet branding =="
check "applet icon override stripped" "grep -q 'Delete :CFBundleIconName' '$LAUNCHER_SRC' && grep -q 'Assets.car' '$LAUNCHER_SRC'"
check "applet bundle id branded"      "grep -q 'local.claude-profiles.dashboard' '$LAUNCHER_SRC'"
check "applet reused when unchanged"  "grep -q 'cmp -s' '$LAUNCHER_SRC'"

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
let grid='',kpi='';
global.document={getElementById:(id)=>({set innerHTML(v){if(id==='grid')grid=v;else kpi=v;},set textContent(v){},get className(){return ''},set className(v){},focus(){},value:''}),addEventListener:()=>{},title:''};
global.setTimeout=()=>{};
eval(js);
const d=JSON.parse(fs.readFileSync('$WORK/stats.json','utf8'));
updateStats(d); updateStats(d);
const cards=(grid.match(/class=\"card\"/g)||[]).length, sw=(grid.match(/Show Window/g)||[]).length;
const sp=(grid.match(/<polyline/g)||[]).length, rm=(grid.match(/Remove profile/g)||[]).length;
let drill=0;
try {
  const run=d.find(p=>p.slug && p.running);
  if (run) {
    toggleExpand(run.slug);
    updateTerminals(run.slug,[{dev:'/dev/ttys001',pid:100,cmd:'bash -l',idle:200}]);
    if (grid.indexOf('class=\"tterm\"')>-1 && grid.indexOf('ttys001')>-1 && grid.indexOf('expanded')>-1 && grid.indexOf('closeTerm(')>-1) drill=1;
  }
} catch(e){}
let tiers=0;
try {
  const stp=d.find(p=>p.slug && !p.running);
  if (stp) {
    expanded=null; toggleExpand(stp.slug);
    if (grid.indexOf('tierbtn')>-1 && grid.indexOf(\"act3('clean'\")>-1) tiers=1;
  }
} catch(e){}
console.log(cards, sw, sp, rm, drill, tiers);
" 2>/dev/null)
    check "cards render"        "[ \"\$(echo '$R' | awk '{print \$1}')\" -ge 3 ]"
    check "Show Window buttons" "[ \"\$(echo '$R' | awk '{print \$2}')\" = 2 ]"
    check "sparklines render"   "[ \"\$(echo '$R' | awk '{print \$3}')\" -ge 4 ]"
    check "in-card remove flow"  "[ \"\$(echo '$R' | awk '{print \$4}')\" -ge 1 ]"
    check "drill-down renders terminals" "[ \"\$(echo '$R' | awk '{print \$5}')\" = 1 ]"
    check "stopped drill shows clean tiers" "[ \"\$(echo '$R' | awk '{print \$6}')\" = 1 ]"
else
    echo "  - node not found, skipping JS render tests"
fi

echo
printf '%d passed, %d failed\n' "$PASS" "$FAIL"
[ "$FAIL" -eq 0 ]
