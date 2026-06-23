#!/bin/bash
# Copyright 2026 jyito — Licensed under the Apache License, Version 2.0.
# See LICENSE and NOTICE in the repository root.
#
# flows.sh — the e2e smoke flows, sourced by scripts/e2.sh after the app is up and
# axdrive is compiled. Each flow drives the running "Claude Profiles" app by the
# accessibilityIdentifiers the SwiftUI views set, and asserts via the AX tree
# (axdrive wait/value) or the stub's call log ($E2E_STUB_LOG). Exits non-zero on
# the first failed assertion so scripts/e2e.sh can fail the run.
#
# Expects from the caller: $AXDRIVE (path to the compiled driver), $APP_NAME,
# $E2E_STUB_LOG.
set -u

APP_NAME="${APP_NAME:-Claude Profiles}"
fails=0

pass() { printf '  ok   %s\n' "$1"; }
fail() { printf '  FAIL %s\n' "$1"; fails=$((fails + 1)); }

# Assert an element with the given identifier appears within $2 seconds.
expect_present() {
    if "$AXDRIVE" wait "$APP_NAME" "$1" "${2:-10}" >/dev/null 2>&1; then
        pass "present: $1"
    else
        fail "absent: $1"
    fi
}

# Assert the stub recorded a call whose line matches $1 (a grep ERE).
expect_logged() {
    if [ -n "${E2E_STUB_LOG:-}" ] && grep -Eq "$1" "$E2E_STUB_LOG" 2>/dev/null; then
        pass "engine called: $1"
    else
        fail "engine never called: $1"
    fi
}

press() { "$AXDRIVE" press "$APP_NAME" "$1" >/dev/null 2>&1; }

# --- Flow 1: launch -> first render shows the profile cards ----------------------
# The stub's stats emit two profiles + the default, so the work card and the
# default card must both materialize after the first poll.
flow_first_render() {
    printf 'flow: launch -> first render\n'
    expect_present "card-work-showwindow" 12
    expect_present "card-default-showwindow" 12
    # The engine was actually consulted (stats is the first call on launch).
    expect_logged "^stats$"
}

# --- Flow 2: the New Profile sheet opens ----------------------------------------
# Pressing the toolbar's New Profile control should reveal the sheet's name field.
flow_new_profile_sheet() {
    printf 'flow: New Profile sheet opens\n'
    if press "toolbar-new-profile"; then
        expect_present "newprofile-field" 6
    else
        fail "could not press toolbar-new-profile"
    fi
}

# --- Flow 3: the grid/list of instances is present ------------------------------
# After first render the stopped profile's card is also in the tree (proves the
# whole grid built, not just the running one).
flow_grid_present() {
    printf 'flow: instance grid present\n'
    expect_present "card-personal-details" 8
}

run_flows() {
    flow_first_render
    flow_new_profile_sheet
    flow_grid_present
    return $fails
}
