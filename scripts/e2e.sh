#!/bin/bash
# Copyright 2026 jyito — Licensed under the Apache License, Version 2.0.
# See LICENSE and NOTICE in the repository root.
#
# e2e.sh — Layer-3 smoke harness for the native SwiftUI "Claude Profiles" app.
# Compiles the AXUIElement driver, launches the app pointed at a fixture engine
# (SPIKE_ENGINE -> scripts/e2e/engine-stub.sh — NO real Claude touched), drives a
# few flows by accessibilityIdentifier, and asserts against the AX tree + the
# stub's call log.
#
# This is a MAINTAINER GATE, not hosted CI: driving the AX tree needs an
# Accessibility (TCC) grant for the terminal running this, which SIP blocks on
# GitHub runners. See docs/E2E.md for the one-time grant and the rationale.
#
#   bash scripts/e2e.sh            # build the app if needed, then run the flows
#   bash scripts/e2e.sh --no-build # use the existing dist/ bundle as-is
#
# Exit: 0 all flows passed · non-zero on any failed assertion or setup error.
set -uo pipefail
cd "$(dirname "$0")/.."

APP_NAME="Claude Profiles"
APP_BUNDLE="dist/$APP_NAME.app"
APP_BIN="$APP_BUNDLE/Contents/MacOS/Profiles"
AXDRIVE="$(mktemp -d)/axdrive"
STUB="$PWD/scripts/e2e/engine-stub.sh"
export E2E_STUB_LOG; E2E_STUB_LOG="$(mktemp)"
export APP_NAME AXDRIVE

if [ "$(uname)" != "Darwin" ]; then
    echo "e2e: macOS only (needs AppKit + the Accessibility TCC grant)" >&2
    exit 2
fi

# 1) Build the bundle unless asked to reuse it.
if [ "${1:-}" != "--no-build" ] || [ ! -x "$APP_BIN" ]; then
    echo "==> Building the app bundle (scripts/build.sh)"
    bash scripts/build.sh >/dev/null
fi
[ -x "$APP_BIN" ] || { echo "e2e: no app binary at $APP_BIN" >&2; exit 1; }

# 2) Compile the AX driver (swiftc, no Xcode).
echo "==> Compiling the AX driver"
swiftc -o "$AXDRIVE" scripts/e2e/axdrive.swift || { echo "e2e: axdrive failed to compile" >&2; exit 1; }

# 3) Driver must be Accessibility-trusted (the maintainer grants the terminal once).
if ! "$AXDRIVE" dump "$APP_NAME" >/dev/null 2>&1; then
    : # app not up yet is fine; a *trust* failure surfaces below when flows run
fi

# 4) Launch the app pointed at the fixture engine.
# Run the bundled binary directly (not `open`): `open` won't forward SPIKE_ENGINE /
# E2E_STUB_LOG into the app's environment, and the stub needs both to serve fixture
# data and record the call log the flows assert against. Launching the Mach-O in the
# bundle still gets a normal windowed app (the .app dir resolves Resources/Info.plist).
echo "==> Launching $APP_NAME with the fixture engine"
SPIKE_ENGINE="$STUB" E2E_STUB_LOG="$E2E_STUB_LOG" "$APP_BIN" >/dev/null 2>&1 &
APP_PID=$!

cleanup() {
    # Quit the app we launched; tolerate either launch path.
    osascript -e "tell application \"$APP_NAME\" to quit" >/dev/null 2>&1 || true
    kill "$APP_PID" >/dev/null 2>&1 || true
    rm -f "$E2E_STUB_LOG" 2>/dev/null || true
}
trap cleanup EXIT

# Give the window + first stats poll a moment to render.
sleep 3

# 5) Run the flows.
# shellcheck source=scripts/e2e/flows.sh
. scripts/e2e/flows.sh
run_flows
rc=$?

echo
if [ "$rc" -eq 0 ]; then
    echo "e2e: all flows passed"
else
    echo "e2e: $rc flow assertion(s) failed"
fi
exit "$rc"
