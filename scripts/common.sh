#!/bin/bash

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"

STRUCTTY_DIR="${STRUCTTY_DIR:-}"
BUILD_DIR="${BUILD_DIR:-}"
BINARY="${BINARY:-}"
EXAMPLE_DIR="${EXAMPLE_DIR:-}"

BENCH_DIR="${BENCH_DIR:-$REPO_DIR/benchmark}"
RESULTS_ROOT="${RESULTS_ROOT:-$REPO_DIR/results}"
BENCH_RESULTS_DIR="${BENCH_RESULTS_DIR:-$REPO_DIR/benchmark_results}"

resolve_paths() {
    if [ -z "$STRUCTTY_DIR" ]; then
        echo "ERROR: STRUCTTY_DIR is not set." >&2
        echo "       Point it at a StrucTTY checkout, for example" >&2
        echo "       STRUCTTY_DIR=~/src/StrucTTY $0" >&2
        exit 1
    fi
    BUILD_DIR="${BUILD_DIR:-$STRUCTTY_DIR/build}"
    BINARY="${BINARY:-$BUILD_DIR/StrucTTY}"
    EXAMPLE_DIR="${EXAMPLE_DIR:-$STRUCTTY_DIR/example}"
}

rebuild_if_requested() {
    [ "${REBUILD:-0}" = "1" ] || return 0
    echo "--- rebuild: $STRUCTTY_DIR ($(git -C "$STRUCTTY_DIR" rev-parse --short HEAD)) ---"
    cmake -S "$STRUCTTY_DIR" -B "$BUILD_DIR" -DCMAKE_BUILD_TYPE=Release > /dev/null
    cmake --build "$BUILD_DIR" -j "$(nproc)" > "$RESULTS_ROOT/build.log" 2>&1 \
        || { echo "ERROR: build failed - see $RESULTS_ROOT/build.log" >&2; exit 1; }
    echo "    ok"
}

require_binary() {
    [ -x "$BINARY" ] && return 0
    echo "ERROR: StrucTTY binary not found: $BINARY" >&2
    echo "       Re-run with REBUILD=1 or build it yourself." >&2
    exit 1
}

setup() {
    RESULT_DIR="$RESULTS_ROOT/$1"
    mkdir -p "$RESULT_DIR"
    resolve_paths
    rebuild_if_requested
    require_binary
    echo "=== $2 ==="
    echo "Binary      : $BINARY"
    echo "StrucTTY rev: $(git -C "$STRUCTTY_DIR" rev-parse --short HEAD 2>/dev/null || echo N/A)"
    echo "Binary mtime: $(date -r "$BINARY" '+%Y-%m-%d %H:%M:%S' 2>/dev/null || echo N/A)"
    echo "Results     : $RESULT_DIR"
    echo ""
}

capture_frame() {
    local out="$1"; shift
    printf 'q' | "$BINARY" "$@" > "${out}.ansi" 2> "${out}.err" || true
    printf '%s' "$(md5sum < "${out}.ansi" | cut -d' ' -f1)"
}
