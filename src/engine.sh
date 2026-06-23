#!/bin/bash
# Copyright 2026 jyito — Licensed under the Apache License, Version 2.0.
# See LICENSE and NOTICE in the repository root.
# engine.sh — data + actions backend for the Claude Profiles dashboard window.
# Subcommands:  stats | open <slug> | quit <slug> | force <slug> | clean <slug>
set -u

APPS_DIR="${CLAUDE_PROFILES_APPS_DIR:-$HOME/Applications}"
INSTANCES_DIR="${CLAUDE_PROFILES_INSTANCES_DIR:-$HOME/.claude-instances}"
BUNDLE_ID_PREFIX="local.claude-profiles"
DISK_CACHE="${TMPDIR:-/tmp}/claude-profiles-disk-cache"
SETTINGS_FILE="$INSTANCES_DIR/.runtime/settings"
BADGES_FILE="$INSTANCES_DIR/.runtime/badges"
RES_DIR=$(cd "$(dirname "${BASH_SOURCE[0]:-$0}")" 2>/dev/null && pwd)  # where badge-icon.applescript lives

bundle_id_of() { defaults read "$1/Contents/Info" CFBundleIdentifier 2>/dev/null; }
display_name_of() { defaults read "$1/Contents/Info" CFBundleDisplayName 2>/dev/null; }

badge_palette() {  # "r g b" for palette index $1 — colours that contrast the coral Claude icon
    case "$1" in
        0) printf '59 125 216' ;;   # blue
        1) printf '93 202 165' ;;   # mint
        2) printf '224 165 94' ;;   # amber
        3) printf '124 92 196' ;;   # purple
        4) printf '210 95 140' ;;   # pink
        *) printf '76 169 178' ;;   # teal
    esac
}
badge_override_for() {  # the user's chosen palette index for slug $1, or empty
    [ -f "$BADGES_FILE" ] && awk -v k="$1" '$1==k {print $2; exit}' "$BADGES_FILE"
}
badge_index_for() {  # resolved index: user override if set, else a deterministic default
    local ov n
    ov=$(badge_override_for "$1")
    case "$ov" in 0|1|2|3|4|5) printf '%s' "$ov"; return ;; esac
    n=$(printf '%s' "$1" | cksum | awk '{print $1}')
    printf '%s' "$((n % 6))"
}
badge_color_for() {  # "r g b" for slug $1, honouring any per-profile override
    badge_palette "$(badge_index_for "$1")"
}

badge_icon() {  # write a badged Claude icon to <resdir>/app.icns; degrade to a plain copy
    # of the Claude icns if the imaging tools or the compositor aren't available
    # (non-macOS, CI). The badged icon is generated locally and never committed.
    local slug="$1" name="$2" icns="$3" resdir="$4"
    local script="$RES_DIR/badge-icon.applescript"
    if ! command -v osascript >/dev/null 2>&1 || ! command -v sips >/dev/null 2>&1 \
        || ! command -v iconutil >/dev/null 2>&1 || [ ! -f "$script" ] || [ -z "$icns" ]; then
        [ -n "$icns" ] && cp "$icns" "$resdir/app.icns" 2>/dev/null
        return 0
    fi
    local letter color tmp base pair s nm
    letter=$(printf '%s' "$name" | sed 's/^Claude //' | cut -c1 | tr '[:lower:]' '[:upper:]')
    [ -n "$letter" ] || letter="C"
    color=$(badge_color_for "$slug")
    tmp=$(mktemp -d) || { cp "$icns" "$resdir/app.icns" 2>/dev/null; return 0; }
    base="$tmp/base.png"
    mkdir -p "$tmp/icon.iconset"
    # shellcheck disable=SC2086
    if sips -s format png -z 1024 1024 "$icns" --out "$base" >/dev/null 2>&1 \
        && osascript "$script" "$base" "$tmp/badged.png" "$letter" $color >/dev/null 2>&1 \
        && [ -f "$tmp/badged.png" ]; then
        for pair in "16 icon_16x16" "32 icon_16x16@2x" "32 icon_32x32" "64 icon_32x32@2x" \
            "128 icon_128x128" "256 icon_128x128@2x" "256 icon_256x256" \
            "512 icon_256x256@2x" "512 icon_512x512" "1024 icon_512x512@2x"; do
            s=${pair%% *}; nm=${pair#* }
            sips -z "$s" "$s" "$tmp/badged.png" --out "$tmp/icon.iconset/$nm.png" >/dev/null 2>&1
        done
        iconutil -c icns "$tmp/icon.iconset" -o "$resdir/app.icns" >/dev/null 2>&1 \
            || cp "$icns" "$resdir/app.icns" 2>/dev/null
    else
        cp "$icns" "$resdir/app.icns" 2>/dev/null
    fi
    rm -rf "$tmp"
}

profile_wrappers() {
    local app id
    [ -d "$APPS_DIR" ] || return 0
    for app in "$APPS_DIR"/*.app; do
        [ -d "$app" ] || continue
        id=$(bundle_id_of "$app") || continue
        [ "$id" = "$BUNDLE_ID_PREFIX.manager" ] && continue
        case "$id" in "$BUNDLE_ID_PREFIX".*) printf '%s\n' "$app" ;; esac
    done
}

# PS_SNAP: an optional, caller-scoped `ps axo pid=,ppid=,command=` snapshot.
# A full-system `ps` costs ~65ms; cmd_stats used to spawn one PER profile PER
# helper (4+ per tick), so the 2s refresh blocked the applet's main thread for
# ~0.5s and got worse with every profile. cmd_stats now captures ONE snapshot
# and the helpers below reuse it via bash dynamic scoping. When PS_SNAP is unset
# (standalone calls, the test suite's shimmed ps) they fall back to their own ps,
# so behavior is unchanged. The snapshot carries command= AND ppid=, so both the
# argv match and the parent-tree walk read from the same single capture.
main_pids_for_dir() {
    # Match --user-data-dir=<dir> as a COMPLETE argv value, not a substring.
    # Substring matching let a profile absorb a prefix-colliding sibling's PIDs
    # (e.g. querying "work" also matched "work2"), confusing every per-instance
    # metric. The char after the dir must be a space (another argv token) or end
    # of line — anything else (-, 2, /) means it's a different, longer dir.
    # awk prints $1 (pid is always the first column) so a 2-col or 3-col snapshot
    # both work.
    printf '%s\n' "${PS_SNAP:-$(ps axo pid=,command=)}" | awk -v d="--user-data-dir=$1" '
        !/awk/ {
            i = index($0, d)
            if (i > 0) {
                c = substr($0, i + length(d), 1)
                if (c == "" || c == " ") print $1
            }
        }'
}

tree_pids() {
    local snap all="$*" grew=1 pid ppid rest
    # `rest` absorbs the command column when reading a 3-col PS_SNAP, so pid/ppid
    # stay clean (a bare `read pid ppid` would dump the command into ppid).
    snap="${PS_SNAP:-$(ps axo pid=,ppid=)}"
    while [ "$grew" -eq 1 ]; do
        grew=0
        while read -r pid ppid rest; do
            case " $all " in *" $pid "*) continue ;; esac
            case " $all " in *" $ppid "*) all="$all $pid"; grew=1 ;; esac
        done <<EOF
$snap
EOF
    done
    printf '%s' "$all"
}

usage_for_pids() {
    local csv; csv=$(printf '%s' "$*" | tr ' ' ',')
    ps -o pcpu=,rss= -p "$csv" 2>/dev/null | awk '{c+=$1; m+=$2; n++} END {printf "%.1f %.0f %d", c, m/1024, n}'
}

pty_count_for_pids() {
    # Count DISTINCT terminal devices, not lsof lines: a single /dev/ttysNN held
    # by the Electron main process and inherited by helpers would otherwise be
    # counted once per holder, inflating the terminal total. Dedup by device.
    local csv; csv=$(printf '%s' "$*" | tr ' ' ',')
    lsof -nP -p "$csv" 2>/dev/null | awk '$NF ~ /^\/dev\/ttys/ {print $NF}' | sort -u | wc -l | tr -d ' '
}

ptmx_count_for_pids() {  # count /dev/ptmx MASTER fds held by the tree (NOT deduped). Claude
    # Desktop leaks these — opening a pty master per session and never closing it —
    # which can exhaust the system pool (kern.tty.ptmx_max) and wedge the whole Mac.
    local csv; csv=$(printf '%s' "$*" | tr ' ' ',')
    lsof -nP -p "$csv" 2>/dev/null | grep -c '/dev/ptmx'
}

ptmx_max() {  # the system /dev/ptmx ceiling; 0 if the key isn't readable (older macOS)
    sysctl -n kern.tty.ptmx_max 2>/dev/null || printf '0'
}

remote_live() {  # is slug $1's Claude Code `screen` session (claude-<slug>) running?
    # Matches the session name as a whole token (trailing whitespace) so claude-work
    # doesn't match claude-work2 — same boundary cmd_remoteinfo uses. Reads the
    # caller's SCREEN_SNAP (one `screen -ls` per stats tick) when set.
    printf '%s\n' "${SCREEN_SNAP:-$(screen -ls 2>/dev/null)}" | grep -qE "[.]claude-$1[[:space:]]"
}

resolve_mains() {  # main PID(s) for a profile slug, or the default instance when slug is "default".
    # Keeps terminals/closeterm/throttle correctly scoped to the requested
    # instance's OWN tree — the default's PIDs come from the default detection,
    # not a profile data dir.
    if [ "$1" = "default" ]; then cmd_defaultpid; else main_pids_for_dir "$INSTANCES_DIR/$1"; fi
}

instance_devices() {  # the /dev/ttysNN devices owned by slug $1's process tree, deduped
    local mains pids csv
    mains=$(resolve_mains "$1"); [ -z "$mains" ] && return
    # shellcheck disable=SC2086
    pids=$(tree_pids $mains); csv=$(printf '%s' "$pids" | tr ' ' ',')
    lsof -nP -p "$csv" 2>/dev/null | awk '$NF ~ /^\/dev\/ttys/ {print $NF}' | sort -u
}

json_str() {  # minimal JSON string escaping for arbitrary text (e.g. a command line)
    printf '%s' "$1" | sed 's/\\/\\\\/g; s/"/\\"/g' | tr -d '\n\r\t'
}

tty_idle() {  # seconds since the terminal last produced output (its device mtime).
    # macOS stat syntax; a terminal printing output keeps this fresh, so a busy
    # session does not read as idle. Returns nothing if the device can't be stat'd.
    local mt now
    mt=$(stat -f %m "$1" 2>/dev/null) || return
    [ -n "$mt" ] || return
    now=$(date +%s)
    printf '%s' "$(( now - mt ))"
}

disk_mb() {  # cached 30s — du on multi-GB dirs is too slow for a live tick
    local key="$1" now ts line size
    now=$(date +%s)
    if [ -f "$DISK_CACHE" ]; then
        line=$(grep "^$key " "$DISK_CACHE" 2>/dev/null | tail -1)
        if [ -n "$line" ]; then
            ts=$(printf '%s' "$line" | awk '{print $2}')
            size=$(printf '%s' "$line" | awk '{print $3}')
            [ $((now - ts)) -lt 30 ] && { printf '%s' "$size"; return 0; }
        fi
    fi
    size=$(( $(du -sk "$key" 2>/dev/null | awk '{print $1}') / 1024 ))
    grep -v "^$key " "$DISK_CACHE" 2>/dev/null > "$DISK_CACHE.t" || true
    printf '%s %s %s\n' "$key" "$now" "$size" >> "$DISK_CACHE.t"
    mv "$DISK_CACHE.t" "$DISK_CACHE"
    printf '%s' "$size"
}

profile_json() {  # $1 name, $2 slug, $3 data_dir.  PTMX_MAX is set by cmd_stats (dynamic scope).
    local mains pids cpu=0 mem=0 nproc=0 ptys=0 ptmx=0 running=false disk opens=0 last=""
    disk=$(disk_mb "$3")
    if [ -f "$3/.profile-activity" ]; then
        opens=$(wc -l < "$3/.profile-activity" | tr -d ' ')
        last=$(tail -n 1 "$3/.profile-activity")
    fi
    mains=$(main_pids_for_dir "$3")
    if [ -n "$mains" ]; then
        running=true
        # shellcheck disable=SC2086
        pids=$(tree_pids $mains)
        read -r cpu mem nproc <<EOF
$(usage_for_pids $pids)
EOF
        ptys=$(pty_count_for_pids $pids)
        ptmx=$(ptmx_count_for_pids $pids)
    fi
    local color remote=false
    remote_live "$2" && remote=true   # is this profile's Claude Code session live?
    # shellcheck disable=SC2046
    color=$(printf '#%02X%02X%02X' $(badge_color_for "$2"))  # same color as the Dock badge
    printf '{"name":"%s","slug":"%s","running":%s,"cpu":%s,"mem":%s,"procs":%s,"ptys":%s,"ptmx":%s,"ptmxMax":%s,"disk":%s,"opens":%s,"last":"%s","color":"%s","remote":%s}' \
        "$1" "$2" "$running" "${cpu:-0}" "${mem:-0}" "${nproc:-0}" "${ptys:-0}" "${ptmx:-0}" "${PTMX_MAX:-0}" "$disk" "$opens" "$last" "$color" "$remote"
}

cmd_stats() {
    local out="[" first=1 app name slug
    # One full-system ps for the whole tick. Every helper called below reads this
    # via dynamic scope instead of spawning its own ps (see PS_SNAP note above).
    local PS_SNAP PTMX_MAX SCREEN_SNAP
    PS_SNAP=$(ps axo pid=,ppid=,command=)
    PTMX_MAX=$(ptmx_max)
    SCREEN_SNAP=$(screen -ls 2>/dev/null)   # one listing per tick; remote_live reads it
    # default instance
    local def
    def=$(printf '%s\n' "$PS_SNAP" | awk '/Claude\.app\/Contents\/MacOS\/Claude/ && !/--user-data-dir/ && !/Helper/ {print $1; exit}')
    local dremote=false
    remote_live default && dremote=true   # default's Claude Code session (claude-default)
    if [ -n "$def" ]; then
        local pids cpu mem nproc ptys ptmx
        # shellcheck disable=SC2086
        pids=$(tree_pids $def)
        read -r cpu mem nproc <<EOF
$(usage_for_pids $pids)
EOF
        ptys=$(pty_count_for_pids $pids)
        ptmx=$(ptmx_count_for_pids $pids)
        out+="{\"name\":\"Claude (default)\",\"slug\":\"\",\"running\":true,\"cpu\":$cpu,\"mem\":$mem,\"procs\":$nproc,\"ptys\":$ptys,\"ptmx\":$ptmx,\"ptmxMax\":$PTMX_MAX,\"disk\":-1,\"opens\":0,\"last\":\"\",\"color\":\"#6E6A62\",\"remote\":$dremote}"
        first=0
    else
        out+="{\"name\":\"Claude (default)\",\"slug\":\"\",\"running\":false,\"cpu\":0,\"mem\":0,\"procs\":0,\"ptys\":0,\"ptmx\":0,\"ptmxMax\":$PTMX_MAX,\"disk\":-1,\"opens\":0,\"last\":\"\",\"color\":\"#6E6A62\",\"remote\":$dremote}"
        first=0
    fi
    while IFS= read -r app; do
        [ -n "$app" ] || continue
        name=$(display_name_of "$app")
        slug=$(bundle_id_of "$app" | sed "s/^$BUNDLE_ID_PREFIX\.//")
        [ "$first" -eq 0 ] && out+=","
        out+=$(profile_json "$name" "$slug" "$INSTANCES_DIR/$slug")
        first=0
    done <<EOF
$(profile_wrappers)
EOF
    printf '%s]' "$out"
}

cmd_menulist() {  # one line per instance for the menu-bar switcher:
    #   slug<TAB>display-name<TAB>running(1|0)
    # "default" is the sentinel slug for the default instance, listed first.
    # Lighter than `stats` (no metrics) — cheap to call on every menu open.
    local PS_SNAP def app name slug
    PS_SNAP=$(ps axo pid=,ppid=,command=)
    def=$(printf '%s\n' "$PS_SNAP" | awk '/Claude\.app\/Contents\/MacOS\/Claude/ && !/--user-data-dir/ && !/Helper/ {print $1; exit}')
    if [ -n "$def" ]; then printf 'default\tClaude (default)\t1\n'; else printf 'default\tClaude (default)\t0\n'; fi
    while IFS= read -r app; do
        [ -n "$app" ] || continue
        name=$(display_name_of "$app")
        slug=$(bundle_id_of "$app" | sed "s/^$BUNDLE_ID_PREFIX\.//")
        if [ -n "$(main_pids_for_dir "$INSTANCES_DIR/$slug")" ]; then
            printf '%s\t%s\t1\n' "$slug" "$name"
        else
            printf '%s\t%s\t0\n' "$slug" "$name"
        fi
    done <<EOF
$(profile_wrappers)
EOF
}

wrapper_for_slug() {
    local app
    while IFS= read -r app; do
        [ -n "$app" ] || continue
        [ "$(bundle_id_of "$app")" = "$BUNDLE_ID_PREFIX.$1" ] && { printf '%s' "$app"; return 0; }
    done <<EOF
$(profile_wrappers)
EOF
    return 1
}

cmd_focus() {  # raise an instance's windows by slug (or "default"). Headless twin of
    # the applet's in-process focus — for external callers (e.g. a Hammerspoon
    # global-hotkey recipe). System Events `set frontmost` reliably travels across
    # Spaces (asks the CALLER for Automation once). osascript is a macOS built-in.
    local slug="${1:?}" pid
    case "$slug" in default) : ;; *[!a-z0-9]*) printf 'err invalid slug'; return 0 ;; esac
    pid=$(resolve_mains "$slug" | head -n 1)
    [ -z "$pid" ] && { printf 'err not running'; return 0; }
    osascript -e "tell application \"System Events\" to set frontmost of (first application process whose unix id is $pid) to true" >/dev/null 2>&1
    printf 'ok'
}
cmd_open()  { local w; w=$(wrapper_for_slug "$1") && "$w/Contents/MacOS/launcher" & }
cmd_mainpid() { main_pids_for_dir "$INSTANCES_DIR/${1:?}" | head -n 1; }
cmd_throttle() {  # lower this instance's OWN process tree CPU priority (renice +10).
    # One-way by design: unprivileged users can't lower niceness back, so the only
    # way to restore is to relaunch the instance. Guarded to the instance's tree —
    # renice is never aimed at an arbitrary pid.
    local slug="${1:?}" mains pids
    mains=$(resolve_mains "$slug")
    [ -z "$mains" ] && { printf 'notrunning'; return 0; }
    # shellcheck disable=SC2086
    pids=$(tree_pids $mains)
    # shellcheck disable=SC2086
    renice 10 $pids >/dev/null 2>&1
    printf 'ok'
}

cmd_closeterm() {  # close a terminal by device — refuses any device not owned by this
                   # instance's tree, so it can never touch another instance or an
                   # arbitrary process. SIGHUP goes to processes whose CONTROLLING
                   # terminal is the device (the session inside the pty), not the
                   # Electron pty master (which merely holds an fd on it).
    local slug="${1:?}" dev="${2:?}" tdev sess
    case "$dev" in
        ttys*)     dev="/dev/$dev" ;;
        /dev/ttys*) ;;
        *) printf 'baddev'; return 0 ;;
    esac
    instance_devices "$slug" | grep -qx "$dev" || { printf 'refused'; return 0; }
    tdev=${dev#/dev/}
    sess=$(ps -t "$tdev" -o pid= 2>/dev/null)
    # shellcheck disable=SC2086
    [ -n "$sess" ] && kill -HUP $sess 2>/dev/null
    printf 'ok'
}

cmd_terminals() {  # JSON array of this instance's terminals: [{dev,pid,cmd,idle}]
    # Devices are discovered only within this instance's own process tree, so each
    # /dev/ttysNN belongs to exactly one instance — no cross-app confusion. One row
    # per device (first holder wins, matching the deduped terminal count).
    local mains pids snap csv out="[" first=1
    mains=$(resolve_mains "${1:?}")
    [ -z "$mains" ] && { printf '[]'; return 0; }
    # shellcheck disable=SC2086
    pids=$(tree_pids $mains)
    snap=$(ps axo pid=,command=)
    csv=$(printf '%s' "$pids" | tr ' ' ',')
    local seen=" " line dev pid cmd idle
    while IFS= read -r line; do
        case "$line" in *' /dev/ttys'*) ;; *) continue ;; esac
        dev=$(printf '%s' "$line" | awk '{print $NF}')
        # lsof truncates COMMAND to 9 chars and it may contain a space (e.g.
        # "Claude He"), so the PID is not reliably field 2. Take the first
        # all-numeric field instead — that's the PID column.
        pid=$(printf '%s' "$line" | awk '{for(i=1;i<=NF;i++) if($i ~ /^[0-9]+$/){print $i; break}}')
        case "$seen" in *" $dev "*) continue ;; esac
        seen="$seen$dev "
        cmd=$(printf '%s' "$snap" | awk -v p="$pid" '$1==p {$1=""; sub(/^ /,""); print; exit}')
        idle=$(tty_idle "$dev"); [ -n "$idle" ] || idle=-1
        [ "$first" -eq 0 ] && out="$out,"
        out="$out{\"dev\":\"$dev\",\"pid\":$pid,\"cmd\":\"$(json_str "$cmd")\",\"idle\":$idle}"
        first=0
    done <<EOF
$(lsof -nP -p "$csv" 2>/dev/null)
EOF
    printf '%s]' "$out"
}
cmd_defaultpid() {
    ps axo pid=,command= | awk '/Claude\.app\/Contents\/MacOS\/Claude/ && !/--user-data-dir/ && !/Helper/ {print $1; exit}'
}

detect_claude_app() {
    if [ -n "${CLAUDE_PROFILES_APP:-}" ] && [ -d "${CLAUDE_PROFILES_APP}" ]; then
        printf '%s' "$CLAUDE_PROFILES_APP"; return 0
    fi
    local c
    for c in "/Applications/Claude.app" "$HOME/Applications/Claude.app"; do
        [ -d "$c" ] && { printf '%s' "$c"; return 0; }
    done
    return 1
}

cmd_create() {  # headless profile creation for the dashboard; prints "ok <slug>" or "err <msg>"
    local name slug app_name claude_app
    # Strip quote/brace/colon AND XML-significant chars (< > &): the name is
    # embedded into the wrapper's Info.plist, so an unescaped & or < corrupts it
    # (the wrapper then can't be read and silently never appears on the dashboard).
    name=$(printf '%s' "${1:?}" | tr -d '"\\{}:<>&' | sed 's/^ *//;s/ *$//')
    slug=$(printf '%s' "$name" | tr '[:upper:]' '[:lower:]' | tr -cd 'a-z0-9')
    [ -n "$slug" ] || { printf 'err name needs a letter or number'; return 0; }
    # "default" is a reserved sentinel: the GUI/engine use it to target the real
    # default instance's process tree (remoteinfo/terminals/throttle/closeterm).
    # A profile slugged "default" would collide with that — refuse it.
    [ "$slug" = "default" ] && { printf 'err "default" is a reserved name — pick another'; return 0; }
    case "$name" in Claude\ *|claude\ *|Claude|claude) app_name="$name" ;; *) app_name="Claude $name" ;; esac
    claude_app=$(detect_claude_app) || { printf 'err Claude.app not found'; return 0; }

    local wrapper="$APPS_DIR/$app_name.app" data_dir="$INSTANCES_DIR/$slug"
    rm -rf "$wrapper"
    mkdir -p "$wrapper/Contents/MacOS" "$wrapper/Contents/Resources" "$data_dir"

    cat > "$wrapper/Contents/Info.plist" <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
	<key>CFBundleName</key><string>$app_name</string>
	<key>CFBundleDisplayName</key><string>$app_name</string>
	<key>CFBundleIdentifier</key><string>$BUNDLE_ID_PREFIX.$slug</string>
	<key>CFBundleExecutable</key><string>launcher</string>
	<key>CFBundleIconFile</key><string>app</string>
	<key>CFBundlePackageType</key><string>APPL</string>
	<key>CFBundleVersion</key><string>1.0</string>
	<key>CFBundleShortVersionString</key><string>1.0</string>
	<key>LSUIElement</key><true/>
	<key>LSMinimumSystemVersion</key><string>11.0</string>
</dict>
</plist>
PLIST

    cat > "$wrapper/Contents/MacOS/launcher" <<LAUNCHER
#!/bin/bash
DATA_DIR="$data_dir"
mkdir -p "\$DATA_DIR"
LOG="\$DATA_DIR/.profile-activity"
date '+%Y-%m-%d %H:%M' >> "\$LOG" && tail -n 50 "\$LOG" > "\$LOG.t" && mv "\$LOG.t" "\$LOG"
CLAUDE_APP="$claude_app"
if [ ! -d "\$CLAUDE_APP" ]; then
    for c in "/Applications/Claude.app" "\$HOME/Applications/Claude.app"; do
        [ -d "\$c" ] && CLAUDE_APP="\$c" && break
    done
fi
if [ ! -d "\$CLAUDE_APP" ]; then
    /usr/bin/osascript -e 'display alert "$app_name" message "Claude.app could not be found. Reinstall Claude Desktop, then re-create this profile in Claude Profiles." as critical buttons {"OK"} default button "OK"' >/dev/null 2>&1
    exit 1
fi
exec /usr/bin/open -n -a "\$CLAUDE_APP" --args --user-data-dir="\$DATA_DIR"
LAUNCHER
    chmod +x "$wrapper/Contents/MacOS/launcher"
    local icns
    icns=$(ls "$claude_app/Contents/Resources/"*.icns 2>/dev/null | head -n 1)
    badge_icon "$slug" "$app_name" "$icns" "$wrapper/Contents/Resources"
    touch "$wrapper"
    printf 'ok %s' "$slug"
}

cmd_rebadge() {  # regenerate the per-profile badged icon for an existing wrapper
    local w name icns claude_app
    w=$(wrapper_for_slug "${1:?}") || { printf 'err not found'; return 0; }
    name=$(display_name_of "$w"); [ -n "$name" ] || name="Claude $1"
    claude_app=$(detect_claude_app) || { printf 'err Claude.app not found'; return 0; }
    icns=$(ls "$claude_app/Contents/Resources/"*.icns 2>/dev/null | head -n 1)
    badge_icon "$1" "$name" "$icns" "$w/Contents/Resources"
    touch "$w"
    printf 'ok'
}

cmd_setbadge() {  # setbadge <slug> <index 0-5>: persist the colour choice, then re-apply the icon
    local slug="${1:?}" idx="${2:?}"
    case "$idx" in 0|1|2|3|4|5) ;; *) printf 'err badindex'; return 0 ;; esac
    mkdir -p "$(dirname "$BADGES_FILE")"
    { [ -f "$BADGES_FILE" ] && grep -v "^$slug " "$BADGES_FILE"; printf '%s %s\n' "$slug" "$idx"; } > "$BADGES_FILE.t" 2>/dev/null
    mv "$BADGES_FILE.t" "$BADGES_FILE"
    cmd_rebadge "$slug"
}

cmd_remove() {  # delete the wrapper app only; the data dir (saved login) is untouched
    local w; w=$(wrapper_for_slug "${1:?}") || { printf 'err not found'; return 0; }
    rm -rf "$w"
    printf 'ok'
}

cmd_purge() {  # delete the data dir (saved login + state); dashboard gates this behind typed DELETE
    # Enforce the [a-z0-9] slug invariant at the engine boundary before the rm -rf,
    # so a traversal slug can never escape $INSTANCES_DIR regardless of caller.
    case "${1:?}" in *[!a-z0-9]*) printf 'err invalid slug'; return 0 ;; esac
    rm -rf "${INSTANCES_DIR:?}/${1:?}"
    rm -f "$DISK_CACHE"
    printf 'ok'
}

# Default-instance process controls. Signals and plain launch only — the default
# data dir (~/Library/Application Support/Claude) is never read or written by
# this tool. -n is required: without it, LaunchServices just activates any
# running profile instance (same bundle id) instead of launching the default.
# No --user-data-dir arg means Claude uses its default dir, untouched by us.
cmd_open_default()  { local app; app=$(detect_claude_app) || { printf 'err Claude.app not found'; return 0; }; open -n -a "$app"; true; }
cmd_quit_default()  { local m; m=$(cmd_defaultpid); [ -n "$m" ] && kill -TERM $m 2>/dev/null; true; }
cmd_force_default() { local m; m=$(cmd_defaultpid); [ -n "$m" ] && kill -9 $(tree_pids $m) 2>/dev/null; true; }

# Bulk cleanup. All of these are process signals or regenerable-cache deletion
# only — sign-ins and data dirs are never touched, so even the killswitch is
# safe: every instance reopens already authenticated.
all_profile_slugs() {
    local app
    while IFS= read -r app; do
        [ -n "$app" ] || continue
        bundle_id_of "$app" | sed "s/^$BUNDLE_ID_PREFIX\.//"
    done <<EOF
$(profile_wrappers)
EOF
}

cmd_quitall() {  # graceful TERM to every running profile instance (default untouched)
    local slug m
    for slug in $(all_profile_slugs); do
        m=$(main_pids_for_dir "$INSTANCES_DIR/$slug")
        # shellcheck disable=SC2086
        [ -n "$m" ] && kill -TERM $m 2>/dev/null
    done
    true
}

cmd_cleanall() {  # clear caches for every STOPPED profile; running ones are skipped
    local slug out=""
    for slug in $(all_profile_slugs); do
        [ -n "$(main_pids_for_dir "$INSTANCES_DIR/$slug")" ] && continue
        cmd_clean "$slug" >/dev/null
        out="$out $slug"
    done
    printf 'ok%s' "$out"
}

cmd_killswitch() {  # emergency stop: SIGKILL every Claude instance tree, default included
    local slug m
    for slug in $(all_profile_slugs); do
        m=$(main_pids_for_dir "$INSTANCES_DIR/$slug")
        # shellcheck disable=SC2086
        [ -n "$m" ] && kill -9 $(tree_pids $m) 2>/dev/null
    done
    m=$(cmd_defaultpid)
    # shellcheck disable=SC2086
    [ -n "$m" ] && kill -9 $(tree_pids $m) 2>/dev/null
    true
}
cmd_quit()  { local m; m=$(main_pids_for_dir "$INSTANCES_DIR/$1"); [ -n "$m" ] && kill -TERM $m 2>/dev/null; true; }
cmd_force() { local m; m=$(main_pids_for_dir "$INSTANCES_DIR/$1"); [ -n "$m" ] && kill -9 $(tree_pids $m) 2>/dev/null; true; }
cmd_restart() {  # quit an instance's whole tree, wait for it to exit (force if stubborn),
    # then relaunch it. The ONLY way to reclaim the /dev/ptmx master fds Claude Desktop
    # leaks — you can't free another process's fds from outside, so the process must cycle.
    # Sign-ins and data dirs are untouched: it reopens already authenticated.
    local slug="${1:?}" mains i
    case "$slug" in
        default) : ;;                                  # the default is signal-only, allowed here
        *[!a-z0-9]*) printf 'err invalid slug'; return 0 ;;
    esac
    mains=$(resolve_mains "$slug")
    if [ -n "$mains" ]; then
        # shellcheck disable=SC2086
        kill -TERM $(tree_pids $mains) 2>/dev/null
        i=0
        while [ "$i" -lt 25 ]; do
            [ -z "$(resolve_mains "$slug")" ] && break
            sleep 0.2
            i=$((i + 1))
        done
        mains=$(resolve_mains "$slug")
        # shellcheck disable=SC2086
        [ -n "$mains" ] && kill -9 $(tree_pids $mains) 2>/dev/null
    fi
    if [ "$slug" = "default" ]; then cmd_open_default >/dev/null; else cmd_open "$slug"; fi
    printf 'ok'
}
cmd_clean() {
    local dir="$INSTANCES_DIR/${1:?}" tier="${2:-all}" d
    [ -n "$(main_pids_for_dir "$dir")" ] && { printf 'running'; return 0; }
    # set -- preserves "Code Cache" (has a space) without bash-4 arrays. Every tier
    # is regenerable Electron data — sign-ins (Cookies, Local Storage) are never here.
    case "$tier" in
        caches) set -- "Cache" "Code Cache" ;;
        gpu)    set -- "GPUCache" "DawnGraphiteCache" "DawnWebGPUCache" "ShaderCache" ;;
        logs)   set -- "logs" "Crashpad/completed" "Crashpad/pending" ;;
        *)      set -- "Cache" "Code Cache" "GPUCache" "DawnGraphiteCache" "DawnWebGPUCache" "ShaderCache" "Crashpad/completed" "Crashpad/pending" ;;
    esac
    for d in "$@"; do
        rm -rf "${dir:?}/$d" 2>/dev/null
    done
    rm -f "$DISK_CACHE"
    printf 'ok'
}

# Settings — local key/value file (never networked). Two opt-in automation knobs,
# both default 0 = disabled. Stored as "key value" lines; emitted as JSON for the UI.
setting_get() {  # $1 key -> integer value, or empty if unset
    [ -f "$SETTINGS_FILE" ] && awk -v k="$1" '$1==k {print $2; exit}' "$SETTINGS_FILE"
}
cmd_getconfig() {
    local ac am ar
    ac=$(setting_get autoCloseIdleMin); am=$(setting_get autoCleanThresholdMB)
    ar=$(setting_get autoRestartLeakAt)
    printf '{"autoCloseIdleMin":%s,"autoCleanThresholdMB":%s,"autoRestartLeakAt":%s}' \
        "${ac:-0}" "${am:-0}" "${ar:-0}"
}
cmd_setconfig() {  # setconfig <key> <non-negative-integer>; validates then persists
    local key="${1:?}" val="${2:?}" tmp
    case "$key" in autoCloseIdleMin|autoCleanThresholdMB|autoRestartLeakAt) ;; *) printf 'err badkey'; return 0 ;; esac
    case "$val" in ''|*[!0-9]*) printf 'err badval'; return 0 ;; esac
    mkdir -p "$(dirname "$SETTINGS_FILE")"
    tmp="$SETTINGS_FILE.t"
    { [ -f "$SETTINGS_FILE" ] && grep -v "^$key " "$SETTINGS_FILE"; printf '%s %s\n' "$key" "$val"; } > "$tmp" 2>/dev/null
    mv "$tmp" "$SETTINGS_FILE"
    printf 'ok'
}

cmd_autotick() {  # enforce the opt-in auto rules; a cheap no-op while both are 0.
    # Called periodically by the dashboard applet. Only ever signals processes or
    # deletes regenerable caches — sign-ins and data dirs are never touched.
    local am ac ar slug dir d secs mt now dev mains n
    am=$(setting_get autoCleanThresholdMB); ac=$(setting_get autoCloseIdleMin)
    ar=$(setting_get autoRestartLeakAt)
    am=${am:-0}; ac=${ac:-0}; ar=${ar:-0}
    [ "$am" -eq 0 ] && [ "$ac" -eq 0 ] && [ "$ar" -eq 0 ] && { printf 'ok'; return 0; }
    if [ "$ar" -gt 0 ]; then  # auto-restart a profile leaking >= ar /dev/ptmx masters
        # Profiles only — never the default (same invariant as auto-clean/close).
        # restart reclaims the leaked fds; sign-in and data are untouched.
        for slug in $(all_profile_slugs); do
            mains=$(main_pids_for_dir "$INSTANCES_DIR/$slug")
            [ -z "$mains" ] && continue
            # shellcheck disable=SC2086
            n=$(ptmx_count_for_pids $(tree_pids $mains))
            [ "${n:-0}" -ge "$ar" ] && cmd_restart "$slug" >/dev/null
        done
    fi
    if [ "$am" -gt 0 ]; then  # auto-clean stopped profiles over the disk threshold
        for slug in $(all_profile_slugs); do
            dir="$INSTANCES_DIR/$slug"
            [ -n "$(main_pids_for_dir "$dir")" ] && continue
            d=$(disk_mb "$dir")
            [ "${d:-0}" -gt "$am" ] && cmd_clean "$slug" >/dev/null
        done
    fi
    if [ "$ac" -gt 0 ]; then  # auto-close terminals idle past the threshold (opt-in, risky)
        secs=$((ac * 60)); now=$(date +%s)
        for slug in $(all_profile_slugs); do
            [ -z "$(main_pids_for_dir "$INSTANCES_DIR/$slug")" ] && continue
            instance_devices "$slug" | while IFS= read -r dev; do
                [ -n "$dev" ] || continue
                mt=$(stat -f %m "$dev" 2>/dev/null) || continue
                [ -n "$mt" ] && [ $((now - mt)) -ge "$secs" ] && cmd_closeterm "$slug" "$dev" >/dev/null
            done
        done
    fi
    printf 'ok'
}

cmd_remoteinfo() {  # start/reuse a profile's Claude Code screen session; emit JSON for the dashboard
    local slug="${1:?}" session cfg claude_bin host lhn user ts_ip already=false
    # The slug arrives over the title bridge (a trust boundary) and is interpolated
    # into a nested `bash -lc` and a filesystem path below. Reject anything that
    # isn't a bare engine slug — this blocks shell injection and path traversal.
    case "$slug" in ""|*[!a-z0-9]*) printf '{"error":"invalid profile id"}'; return 0 ;; esac
    command -v screen >/dev/null 2>&1 || { printf '{"error":"screen not found (it ships with macOS)"}'; return 0; }
    command -v claude >/dev/null 2>&1 || { printf '{"error":"Claude Code CLI not found on PATH — install it, then click Remote again."}'; return 0; }
    claude_bin=$(command -v claude)
    session="claude-$slug"
    cfg="$HOME/.claude-code-instances/$slug"
    mkdir -p "$cfg"
    if screen -ls 2>/dev/null | grep -qE "[.]${session}[[:space:]]"; then
        already=true
    else
        screen -dmS "$session" bash -lc "CLAUDE_CONFIG_DIR='$cfg' '$claude_bin'"
    fi
    lhn=$(scutil --get LocalHostName 2>/dev/null)
    if [ -n "$lhn" ]; then host="$lhn.local"; else host=$(ipconfig getifaddr en0 2>/dev/null || ipconfig getifaddr en1 2>/dev/null || true); fi
    user=$(whoami)
    ts_ip=""
    command -v tailscale >/dev/null 2>&1 && ts_ip=$(tailscale ip -4 2>/dev/null | head -n1)
    printf '{"slug":"%s","session":"%s","user":"%s","host":"%s","tailscaleIp":"%s","alreadyRunning":%s}' \
        "$(json_str "$slug")" "$(json_str "$session")" "$(json_str "$user")" "$(json_str "$host")" "$(json_str "$ts_ip")" "$already"
}

cmd_remote_stop() {  # stop a profile's Claude Code screen session (claude-<slug>); idempotent
    local slug="${1:?}"
    # Same trust boundary as cmd_remoteinfo: the slug is interpolated into the
    # session name, so reject anything that isn't a bare engine slug. "default"
    # is all-lowercase, so it passes (claude-default).
    case "$slug" in ""|*[!a-z0-9]*) printf 'ok'; return 0 ;; esac
    command -v screen >/dev/null 2>&1 || { printf 'ok'; return 0; }
    # Target the exact session name as a whole token — claude-work must not touch
    # claude-work2 (same boundary remote_live/cmd_remoteinfo use). `-X quit` to a
    # missing session is a harmless no-op, so this is idempotent; swallow its exit
    # so the command always succeeds.
    screen -S "claude-$slug" -X quit 2>/dev/null || true
    printf 'ok'
}

cmd_copy() {  # put text on the clipboard for the dashboard's Copy buttons (macOS only)
    command -v pbcopy >/dev/null 2>&1 || return 0
    printf '%s' "${1:-}" | pbcopy
}

# Dispatch only when run directly; sourcing (e.g. tests) loads the functions
# without executing the default `stats` command.
if [ "${BASH_SOURCE[0]:-$0}" = "$0" ]; then
case "${1:-stats}" in
    stats) cmd_stats ;;
    menulist) cmd_menulist ;;
    focus) cmd_focus "${2:?}" ;;
    open)  cmd_open  "${2:?}" ;;
    quit)  cmd_quit  "${2:?}" ;;
    force) cmd_force "${2:?}" ;;
    restart) cmd_restart "${2:?}" ;;
    clean) cmd_clean "${2:?}" "${3:-}" ;;
    mainpid) cmd_mainpid "${2:?}" ;;
    terminals) cmd_terminals "${2:?}" ;;
    closeterm) cmd_closeterm "${2:?}" "${3:?}" ;;
    throttle) cmd_throttle "${2:?}" ;;
    defaultpid) cmd_defaultpid ;;
    create) cmd_create "${2:?}" ;;
    opendefault) cmd_open_default ;;
    quitdefault) cmd_quit_default ;;
    forcedefault) cmd_force_default ;;
    quitall) cmd_quitall ;;
    cleanall) cmd_cleanall ;;
    killswitch) cmd_killswitch ;;
    remove) cmd_remove "${2:?}" ;;
    rebadge) cmd_rebadge "${2:?}" ;;
    setbadge) cmd_setbadge "${2:?}" "${3:?}" ;;
    purge) cmd_purge "${2:?}" ;;
    getconfig) cmd_getconfig ;;
    setconfig) cmd_setconfig "${2:?}" "${3:?}" ;;
    autotick) cmd_autotick ;;
    remoteinfo) cmd_remoteinfo "${2:?}" ;;
    remotestop) cmd_remote_stop "${2:?}" ;;
    copy) cmd_copy "${2:-}" ;;
esac
fi
