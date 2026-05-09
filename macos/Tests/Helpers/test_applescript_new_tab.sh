#!/usr/bin/env bash
# Regression test for: `tell application "Ghostty" to new tab` returning -1708.
#
# Bug: ScriptTab held its parent ScriptWindow with a weak reference, so a tab
# returned from `handleNewTabScriptCommand:` whose parent ScriptWindow was a
# function-local value (the no-args fallback path) lost its window before
# Cocoa Scripting could call `objectSpecifier`, and the framework reported
# the result back to AppleScript as errAEEventNotHandled.
#
# This test verifies that all three forms succeed:
#   1. tell application "Ghostty" to new tab                 (was broken)
#   2. tell application "Ghostty" to new tab in front window (was working)
#   3. tell application "Ghostty" to new window              (was working)
#
# Usage:
#   macos/Tests/Helpers/test_applescript_new_tab.sh [path/to/Ghostty.app]
#
# Defaults to macos/build/Debug/Ghostty.app relative to the repo root.

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/../../.." && pwd)"
APP="${1:-$REPO_ROOT/macos/build/Debug/Ghostty.app}"

if [ ! -d "$APP" ]; then
    echo "FAIL: Ghostty.app not found at $APP"
    echo "Build it first: macos/build.nu --configuration Debug --action build"
    exit 1
fi

cleanup() {
    osascript -e "tell application \"$APP\" to quit" >/dev/null 2>&1 || true
}
trap cleanup EXIT

osascript -e "tell application \"$APP\" to activate"
sleep 4

run_case() {
    local name="$1"
    local script="$2"
    local out
    local rc
    if out=$(osascript -e "$script" 2>&1); then
        rc=0
    else
        rc=$?
    fi
    if [ $rc -ne 0 ] || [[ "$out" == *"-1708"* ]] || [[ "$out" == *"error"* ]]; then
        echo "FAIL [$name]: $out"
        return 1
    fi
    echo "PASS [$name]: $out"
    return 0
}

failures=0
run_case "new tab (no args)"        "tell application \"$APP\" to new tab"                || failures=$((failures+1))
run_case "new tab in front window"  "tell application \"$APP\" to new tab in front window" || failures=$((failures+1))
run_case "new window"               "tell application \"$APP\" to new window"             || failures=$((failures+1))

if [ $failures -eq 0 ]; then
    echo "OK: 3/3 AppleScript creation forms succeeded"
    exit 0
fi
echo "FAILED: $failures/3 cases"
exit 1
