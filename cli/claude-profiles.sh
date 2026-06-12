#!/bin/bash
# Copyright 2026 jyito — Licensed under the Apache License, Version 2.0.
# See LICENSE and NOTICE in the repository root.
#
# claude-profiles — multi-account Claude Desktop launcher manager for macOS
#
# Generates lightweight native .app wrapper bundles that launch Claude Desktop
# with a per-profile --user-data-dir, so multiple accounts stay logged in
# simultaneously. The launcher never touches credentials: Claude Desktop keeps
# all session state inside the per-profile data dir itself.
#
# Usage:
#   claude-profiles add <Name>       create wrapper app + data dir
#   claude-profiles list             show profiles, paths, disk usage
#   claude-profiles remove <Name>    delete wrapper (data dir needs separate confirmation)
#   claude-profiles open <Name>      launch a profile from the terminal
#   claude-profiles code-alias <Name>  (optional) append a Claude Code alias to ~/.zshrc
#
# Requirements: macOS built-ins only (bash, open, defaults, du, sips optional).

set -u

APPS_DIR="${CLAUDE_PROFILES_APPS_DIR:-$HOME/Applications}"
INSTANCES_DIR="${CLAUDE_PROFILES_INSTANCES_DIR:-$HOME/.claude-instances}"
BUNDLE_ID_PREFIX="local.claude-profiles"

err()  { printf 'claude-profiles: %s\n' "$*" >&2; }
die()  { err "$*"; exit 1; }

# ---------------------------------------------------------------------------
# Helpers
# ---------------------------------------------------------------------------

slugify() {
    # lowercase alphanumeric only: "Work Account" -> "workaccount"
    printf '%s' "$1" | tr '[:upper:]' '[:lower:]' | tr -cd 'a-z0-9'
}

app_name_for() {
    # "Business" -> "Claude Business"; "Claude Business" stays as-is
    local name="$1"
    case "$name" in
        Claude\ *|claude\ *|Claude|claude) printf '%s' "$name" ;;
        *) printf 'Claude %s' "$name" ;;
    esac
}

detect_claude_app() {
    # Env override is useful for testing and non-standard installs.
    if [ -n "${CLAUDE_PROFILES_APP:-}" ] && [ -d "${CLAUDE_PROFILES_APP}" ]; then
        printf '%s' "$CLAUDE_PROFILES_APP"
        return 0
    fi
    local candidate
    for candidate in "/Applications/Claude.app" "$HOME/Applications/Claude.app"; do
        if [ -d "$candidate" ]; then
            printf '%s' "$candidate"
            return 0
        fi
    done
    return 1
}

bundle_identifier_of() {
    # $1 = path to .app bundle; prints CFBundleIdentifier or nothing
    defaults read "$1/Contents/Info" CFBundleIdentifier 2>/dev/null
}

display_name_of() {
    defaults read "$1/Contents/Info" CFBundleDisplayName 2>/dev/null
}

profile_wrappers() {
    # Print paths of wrapper .app bundles managed by this tool, one per line.
    local app id
    [ -d "$APPS_DIR" ] || return 0
    for app in "$APPS_DIR"/*.app; do
        [ -d "$app" ] || continue
        id=$(bundle_identifier_of "$app") || continue
        case "$id" in
            "$BUNDLE_ID_PREFIX".*) printf '%s\n' "$app" ;;
        esac
    done
}

wrapper_for_slug() {
    # Find the wrapper .app whose bundle id matches the slug.
    local slug="$1" app id
    while IFS= read -r app; do
        id=$(bundle_identifier_of "$app")
        [ "$id" = "$BUNDLE_ID_PREFIX.$slug" ] && { printf '%s' "$app"; return 0; }
    done <<EOF
$(profile_wrappers)
EOF
    return 1
}

human_size() {
    # du -sh of a dir, or "—" if missing
    if [ -d "$1" ]; then
        du -sh "$1" 2>/dev/null | awk '{print $1}'
    else
        printf '%s' "—"
    fi
}

# ---------------------------------------------------------------------------
# add
# ---------------------------------------------------------------------------

cmd_add() {
    local name="${1:-}"
    [ -n "$name" ] || die "usage: claude-profiles add <Name>"

    local slug app_name claude_app
    slug=$(slugify "$name")
    [ -n "$slug" ] || die "profile name must contain at least one letter or number"
    app_name=$(app_name_for "$name")

    claude_app=$(detect_claude_app) || die \
"Claude.app not found in /Applications or ~/Applications.
Install Claude Desktop first (https://claude.ai/download), or set CLAUDE_PROFILES_APP=/path/to/Claude.app"

    local wrapper="$APPS_DIR/$app_name.app"
    local data_dir="$INSTANCES_DIR/$slug"
    local rebuilt=0
    [ -d "$wrapper" ] && rebuilt=1

    # Idempotent rebuild: blow away the wrapper bundle only. The data dir is
    # precious (it holds the logged-in session) and is never touched here.
    rm -rf "$wrapper"
    mkdir -p "$wrapper/Contents/MacOS" "$wrapper/Contents/Resources"
    mkdir -p "$data_dir"
    mkdir -p "$APPS_DIR"

    # --- Info.plist ---------------------------------------------------------
    cat > "$wrapper/Contents/Info.plist" <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
	<key>CFBundleName</key>
	<string>$app_name</string>
	<key>CFBundleDisplayName</key>
	<string>$app_name</string>
	<key>CFBundleIdentifier</key>
	<string>$BUNDLE_ID_PREFIX.$slug</string>
	<key>CFBundleExecutable</key>
	<string>launcher</string>
	<key>CFBundleIconFile</key>
	<string>app</string>
	<key>CFBundlePackageType</key>
	<string>APPL</string>
	<key>CFBundleVersion</key>
	<string>1.0</string>
	<key>CFBundleShortVersionString</key>
	<string>1.0</string>
	<key>LSUIElement</key>
	<true/>
	<key>LSMinimumSystemVersion</key>
	<string>11.0</string>
</dict>
</plist>
PLIST

    if command -v plutil >/dev/null 2>&1; then
        plutil -lint -s "$wrapper/Contents/Info.plist" >/dev/null \
            || die "generated Info.plist failed validation (this is a bug)"
    fi

    # --- launcher -----------------------------------------------------------
    # Falls back to re-detecting Claude.app if the recorded path disappears
    # (e.g. Anthropic relocates/renames the bundle), and surfaces a dialog
    # instead of failing silently.
    cat > "$wrapper/Contents/MacOS/launcher" <<LAUNCHER
#!/bin/bash
DATA_DIR="\$HOME/.claude-instances/$slug"
mkdir -p "\$DATA_DIR"

CLAUDE_APP="$claude_app"
if [ ! -d "\$CLAUDE_APP" ]; then
    for candidate in "/Applications/Claude.app" "\$HOME/Applications/Claude.app"; do
        if [ -d "\$candidate" ]; then
            CLAUDE_APP="\$candidate"
            break
        fi
    done
fi

if [ ! -d "\$CLAUDE_APP" ]; then
    /usr/bin/osascript -e 'display alert "$app_name" message "Claude.app could not be found in /Applications or ~/Applications. Reinstall Claude Desktop, then run: claude-profiles add $name" as critical buttons {"OK"} default button "OK"' >/dev/null 2>&1
    exit 1
fi

exec /usr/bin/open -n -a "\$CLAUDE_APP" --args --user-data-dir="\$DATA_DIR"
LAUNCHER
    chmod +x "$wrapper/Contents/MacOS/launcher"

    # Honor a custom instances dir (used in tests) by rewriting the data dir line.
    if [ "$INSTANCES_DIR" != "$HOME/.claude-instances" ]; then
        sed -i '' "s|^DATA_DIR=.*|DATA_DIR=\"$INSTANCES_DIR/$slug\"|" \
            "$wrapper/Contents/MacOS/launcher" 2>/dev/null \
        || sed -i "s|^DATA_DIR=.*|DATA_DIR=\"$INSTANCES_DIR/$slug\"|" \
            "$wrapper/Contents/MacOS/launcher"
    fi

    # --- icon ---------------------------------------------------------------
    local icns
    icns=$(ls "$claude_app/Contents/Resources/"*.icns 2>/dev/null | head -n 1)
    if [ -n "$icns" ]; then
        cp "$icns" "$wrapper/Contents/Resources/app.icns"
    else
        err "warning: no .icns found in Claude.app; wrapper will use a generic icon"
    fi

    # Nudge LaunchServices/Finder to pick up the new bundle promptly.
    touch "$wrapper"

    if [ "$rebuilt" -eq 1 ]; then
        printf 'Rebuilt %s (data dir untouched).\n' "$wrapper"
    else
        printf 'Created %s\n' "$wrapper"
    fi
    cat <<NEXT

Profile:   $name  (slug: $slug)
Wrapper:   $wrapper
Data dir:  $data_dir   <- your login session will live here

Next steps:
  1. Launch it:  claude-profiles open $name   (or open it from Finder/Spotlight)
  2. Log in to the account you want for this profile — one time only.
     Tip: if the browser "Open in Claude" redirect lands in the wrong window,
     use the manual copy-code/paste-code option on the login page instead.
  3. Done. Every future launch of "$app_name" is already authenticated.
NEXT
}

# ---------------------------------------------------------------------------
# list
# ---------------------------------------------------------------------------

cmd_list() {
    local found=0 app id slug data_dir dname
    printf '%-22s %-14s %-9s %s\n' "PROFILE" "SLUG" "DATA SIZE" "PATHS"
    while IFS= read -r app; do
        [ -n "$app" ] || continue
        found=1
        id=$(bundle_identifier_of "$app")
        slug="${id#"$BUNDLE_ID_PREFIX".}"
        dname=$(display_name_of "$app")
        data_dir="$INSTANCES_DIR/$slug"
        printf '%-22s %-14s %-9s app:  %s\n' "$dname" "$slug" "$(human_size "$data_dir")" "$app"
        printf '%-22s %-14s %-9s data: %s%s\n' "" "" "" "$data_dir" \
            "$([ -d "$data_dir" ] || printf ' (missing — will be created on launch)')"
    done <<EOF
$(profile_wrappers)
EOF
    if [ "$found" -eq 0 ]; then
        printf '\nNo profiles yet. Create one with:  claude-profiles add <Name>\n'
    fi
}

# ---------------------------------------------------------------------------
# remove
# ---------------------------------------------------------------------------

cmd_remove() {
    local name="${1:-}"
    [ -n "$name" ] || die "usage: claude-profiles remove <Name>"
    local slug wrapper data_dir
    slug=$(slugify "$name")
    wrapper=$(wrapper_for_slug "$slug") || die "no profile found for '$name' (slug: $slug). Try: claude-profiles list"
    data_dir="$INSTANCES_DIR/$slug"

    printf 'Delete wrapper app %s? [y/N] ' "$wrapper"
    read -r reply
    case "$reply" in
        y|Y|yes|YES)
            rm -rf "$wrapper"
            printf 'Deleted wrapper.\n'
            ;;
        *)
            printf 'Aborted; nothing deleted.\n'
            return 0
            ;;
    esac

    # The data dir is precious: it contains the saved login session, MCP
    # config, and local state. Deleting it logs this profile out for good.
    if [ -d "$data_dir" ]; then
        printf '\nThe data directory still exists:\n  %s  (%s)\n' "$data_dir" "$(human_size "$data_dir")"
        printf 'It contains the SAVED LOGIN and local state for this profile.\n'
        printf "To delete it too, type the profile slug ('%s') to confirm, or press Enter to keep it: " "$slug"
        read -r confirm
        if [ "$confirm" = "$slug" ]; then
            rm -rf "$data_dir"
            printf 'Deleted data dir (profile fully removed).\n'
        else
            printf 'Kept data dir. Re-running "claude-profiles add %s" will reuse the saved login.\n' "$name"
        fi
    fi
}

# ---------------------------------------------------------------------------
# open
# ---------------------------------------------------------------------------

cmd_open() {
    local name="${1:-}"
    [ -n "$name" ] || die "usage: claude-profiles open <Name>"
    local slug wrapper
    slug=$(slugify "$name")
    wrapper=$(wrapper_for_slug "$slug") || die "no profile found for '$name'. Try: claude-profiles list"
    # Run the launcher directly: it execs `open -n`, which forces a new
    # instance whether or not another Claude is already running.
    "$wrapper/Contents/MacOS/launcher"
}

# ---------------------------------------------------------------------------
# code-alias (optional enhancement: Claude Code parity)
# ---------------------------------------------------------------------------

cmd_code_alias() {
    local name="${1:-}"
    [ -n "$name" ] || die "usage: claude-profiles code-alias <Name>"
    local slug alias_line rc="$HOME/.zshrc"
    slug=$(slugify "$name")
    [ -n "$slug" ] || die "profile name must contain at least one letter or number"
    alias_line="alias claude-$slug='CLAUDE_CONFIG_DIR=\$HOME/.claude-code-instances/$slug claude'"
    if [ -f "$rc" ] && grep -qF "claude-code-instances/$slug" "$rc"; then
        printf 'Alias for %s already present in %s\n' "$slug" "$rc"
        return 0
    fi
    {
        printf '\n# claude-profiles: Claude Code profile "%s"\n' "$name"
        printf '%s\n' "$alias_line"
    } >> "$rc"
    printf 'Added to %s:\n  %s\nOpen a new shell (or run: source %s) to use it.\n' "$rc" "$alias_line" "$rc"
}

# ---------------------------------------------------------------------------
# main
# ---------------------------------------------------------------------------

usage() {
    sed -n '2,17p' "$0" | sed 's/^# \{0,1\}//'
}

main() {
    local cmd="${1:-}"
    [ $# -gt 0 ] && shift
    case "$cmd" in
        add)        cmd_add "$@" ;;
        list|ls)    cmd_list "$@" ;;
        remove|rm)  cmd_remove "$@" ;;
        open)       cmd_open "$@" ;;
        code-alias) cmd_code_alias "$@" ;;
        -h|--help|help|"") usage ;;
        *) die "unknown command '$cmd' (try: add, list, remove, open, code-alias)" ;;
    esac
}

main "$@"
