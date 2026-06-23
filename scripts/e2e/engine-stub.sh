#!/bin/bash
# Copyright 2026 jyito — Licensed under the Apache License, Version 2.0.
# See LICENSE and NOTICE in the repository root.
#
# engine-stub.sh — a fixture "engine" for the Layer-3 e2e smoke harness. Point the
# app at it with SPIKE_ENGINE so the GUI renders deterministic data with NO real
# Claude, NO process scanning, NO disk I/O. Emits the same JSON shapes engine.sh
# does (matching the Codable structs in app/Sources/ProfilesCore) and records each
# invocation to $E2E_STUB_LOG so flows.sh can assert side-effects (e.g. that a
# button press reached the engine).
#
# Contract mirrors src/engine.sh's subcommands the SwiftUI app calls:
#   stats getconfig setconfig create terminals mainpid defaultpid remoteinfo copy
#   + action verbs (open quit force restart focus clean rebadge purge remove ...)
set -u

# Append every call (verb + args) to the log, if the harness asked for one.
if [ -n "${E2E_STUB_LOG:-}" ]; then
    printf '%s\n' "$*" >> "$E2E_STUB_LOG"
fi

cmd="${1:-}"
shift || true

case "$cmd" in
    stats)
        # Two profiles (one running, one stopped) + the default instance (empty slug).
        # Fields match ProfileStat: name slug running cpu mem procs ptys ptmx ptmxMax
        # disk opens last color remote.
        cat <<'JSON'
[
  {"name":"Work","slug":"work","running":true,"cpu":42.5,"mem":812.0,"procs":6,"ptys":2,"ptmx":3,"ptmxMax":511,"disk":1536,"opens":48,"last":"2026-06-22 14:00","color":"59 125 216","remote":false},
  {"name":"Personal","slug":"personal","running":false,"cpu":0.0,"mem":0.0,"procs":0,"ptys":0,"ptmx":0,"ptmxMax":511,"disk":920,"opens":0,"last":"2026-06-21 09:30","color":"93 202 165","remote":false},
  {"name":"Claude","slug":"","running":true,"cpu":18.0,"mem":640.0,"procs":4,"ptys":1,"ptmx":1,"ptmxMax":511,"disk":2048,"opens":30,"last":"2026-06-22 14:05","color":"216 90 48","remote":false}
]
JSON
        ;;
    getconfig)
        printf '{"autoCleanThresholdMB":0,"autoCloseIdleMin":0,"autoRestartLeakAt":0}\n'
        ;;
    setconfig)
        # key + value; engine prints nothing on success.
        ;;
    create)
        # `create <name>` -> `ok <slug>`. Slug = lowercased name (good enough for a stub).
        name="${1:-New}"
        slug=$(printf '%s' "$name" | tr '[:upper:]' '[:lower:]' | tr -cs 'a-z0-9' '-' \
            | sed 's/^-*//; s/-*$//')
        [ -n "$slug" ] || slug="profile"
        printf 'ok %s\n' "$slug"
        ;;
    terminals)
        # `[{dev,pid,cmd,idle}]` — one fixture terminal for the running profile.
        printf '[{"dev":"/dev/ttys001","pid":4242,"cmd":"claude","idle":12}]\n'
        ;;
    mainpid)
        printf '4242\n'
        ;;
    defaultpid)
        printf '5151\n'
        ;;
    remoteinfo)
        slug="${1:-work}"
        printf '{"slug":"%s","session":"claude-%s","user":"maintainer","host":"mac.local","tailscaleIp":"100.64.0.1","alreadyRunning":false}\n' "$slug" "$slug"
        ;;
    copy)
        # `copy <text>` -> pbcopy in the real engine; the stub just succeeds (logged above).
        ;;
    *)
        # Action verbs (open quit force restart focus clean rebadge purge remove autotick
        # closeterm throttle ...) — exit 0 with no output, mirroring engine.sh success.
        ;;
esac
exit 0
