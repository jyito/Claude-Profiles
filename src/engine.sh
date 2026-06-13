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

bundle_id_of() { defaults read "$1/Contents/Info" CFBundleIdentifier 2>/dev/null; }
display_name_of() { defaults read "$1/Contents/Info" CFBundleDisplayName 2>/dev/null; }

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

main_pids_for_dir() {
    # Match --user-data-dir=<dir> as a COMPLETE argv value, not a substring.
    # Substring matching let a profile absorb a prefix-colliding sibling's PIDs
    # (e.g. querying "work" also matched "work2"), confusing every per-instance
    # metric. The char after the dir must be a space (another argv token) or end
    # of line — anything else (-, 2, /) means it's a different, longer dir.
    ps axo pid=,command= | awk -v d="--user-data-dir=$1" '
        !/awk/ {
            i = index($0, d)
            if (i > 0) {
                c = substr($0, i + length(d), 1)
                if (c == "" || c == " ") print $1
            }
        }'
}

tree_pids() {
    local snap all="$*" grew=1
    snap=$(ps axo pid=,ppid=)
    while [ "$grew" -eq 1 ]; do
        grew=0
        while read -r pid ppid; do
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
    lsof -p "$csv" 2>/dev/null | awk '$NF ~ /^\/dev\/ttys/ {print $NF}' | sort -u | wc -l | tr -d ' '
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

profile_json() {  # $1 name, $2 slug, $3 data_dir
    local mains pids cpu=0 mem=0 nproc=0 ptys=0 running=false disk opens=0 last=""
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
    fi
    printf '{"name":"%s","slug":"%s","running":%s,"cpu":%s,"mem":%s,"procs":%s,"ptys":%s,"disk":%s,"opens":%s,"last":"%s"}' \
        "$1" "$2" "$running" "${cpu:-0}" "${mem:-0}" "${nproc:-0}" "${ptys:-0}" "$disk" "$opens" "$last"
}

cmd_stats() {
    local out="[" first=1 app name slug
    # default instance
    local def
    def=$(ps axo pid=,command= | awk '/Claude\.app\/Contents\/MacOS\/Claude/ && !/--user-data-dir/ && !/Helper/ {print $1; exit}')
    if [ -n "$def" ]; then
        local pids cpu mem nproc ptys
        # shellcheck disable=SC2086
        pids=$(tree_pids $def)
        read -r cpu mem nproc <<EOF
$(usage_for_pids $pids)
EOF
        ptys=$(pty_count_for_pids $pids)
        out+="{\"name\":\"Claude (default)\",\"slug\":\"\",\"running\":true,\"cpu\":$cpu,\"mem\":$mem,\"procs\":$nproc,\"ptys\":$ptys,\"disk\":-1,\"opens\":0,\"last\":\"\"}"
        first=0
    else
        out+='{"name":"Claude (default)","slug":"","running":false,"cpu":0,"mem":0,"procs":0,"ptys":0,"disk":-1,"opens":0,"last":""}'
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

cmd_open()  { local w; w=$(wrapper_for_slug "$1") && "$w/Contents/MacOS/launcher" & }
cmd_mainpid() { main_pids_for_dir "$INSTANCES_DIR/${1:?}" | head -n 1; }
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
    name=$(printf '%s' "${1:?}" | tr -d '"\\{}:' | sed 's/^ *//;s/ *$//')
    slug=$(printf '%s' "$name" | tr '[:upper:]' '[:lower:]' | tr -cd 'a-z0-9')
    [ -n "$slug" ] || { printf 'err name needs a letter or number'; return 0; }
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
    [ -n "$icns" ] && cp "$icns" "$wrapper/Contents/Resources/app.icns"
    touch "$wrapper"
    printf 'ok %s' "$slug"
}

cmd_remove() {  # delete the wrapper app only; the data dir (saved login) is untouched
    local w; w=$(wrapper_for_slug "${1:?}") || { printf 'err not found'; return 0; }
    rm -rf "$w"
    printf 'ok'
}

cmd_purge() {  # delete the data dir (saved login + state); dashboard gates this behind typed DELETE
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
cmd_clean() {
    local dir="$INSTANCES_DIR/${1:?}" d
    [ -n "$(main_pids_for_dir "$dir")" ] && { printf 'running'; return 0; }
    for d in "Cache" "Code Cache" "GPUCache" "DawnGraphiteCache" "DawnWebGPUCache" "ShaderCache" "Crashpad/completed" "Crashpad/pending"; do
        rm -rf "${dir:?}/$d" 2>/dev/null
    done
    rm -f "$DISK_CACHE"
    printf 'ok'
}

# Dispatch only when run directly; sourcing (e.g. tests) loads the functions
# without executing the default `stats` command.
if [ "${BASH_SOURCE[0]:-$0}" = "$0" ]; then
case "${1:-stats}" in
    stats) cmd_stats ;;
    open)  cmd_open  "${2:?}" ;;
    quit)  cmd_quit  "${2:?}" ;;
    force) cmd_force "${2:?}" ;;
    clean) cmd_clean "${2:?}" ;;
    mainpid) cmd_mainpid "${2:?}" ;;
    defaultpid) cmd_defaultpid ;;
    create) cmd_create "${2:?}" ;;
    opendefault) cmd_open_default ;;
    quitdefault) cmd_quit_default ;;
    forcedefault) cmd_force_default ;;
    quitall) cmd_quitall ;;
    cleanall) cmd_cleanall ;;
    killswitch) cmd_killswitch ;;
    remove) cmd_remove "${2:?}" ;;
    purge) cmd_purge "${2:?}" ;;
esac
fi
