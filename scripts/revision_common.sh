#!/bin/bash

set -euo pipefail

STRUCTTY_DIR="${STRUCTTY_DIR:-$HOME/src/StrucTTY}"
BUILD_DIR="${BUILD_DIR:-$STRUCTTY_DIR/build}"
BINARY="${BINARY:-$BUILD_DIR/StrucTTY}"
BENCH_DIR="${BENCH_DIR:-$HOME/src/StrucTTY_benchmark/benchmark}"
EXAMPLE_DIR="${EXAMPLE_DIR:-$STRUCTTY_DIR/example}"
RESULTS_ROOT="${RESULTS_ROOT:-$HOME/src/StrucTTY_benchmark/revision_results}"

capture_frame() {
    local out="$1"; shift
    printf 'q' | "$BINARY" "$@" > "${out}.ansi" 2> "${out}.err" || true
    printf '%s' "$(md5sum < "${out}.ansi" | cut -d' ' -f1)"
}

require_binary() {
    if [ ! -x "$BINARY" ]; then
        echo "ERROR: StrucTTY 바이너리가 없다: $BINARY"
        echo "       REBUILD=1 로 다시 돌리거나 직접 빌드할 것."
        exit 1
    fi
}

maybe_rebuild() {
    if [ "${REBUILD:-0}" = "1" ]; then
        echo "--- rebuild: $STRUCTTY_DIR ($(git -C "$STRUCTTY_DIR" rev-parse --short HEAD)) ---"
        cmake -S "$STRUCTTY_DIR" -B "$BUILD_DIR" -DCMAKE_BUILD_TYPE=Release > /dev/null
        cmake --build "$BUILD_DIR" -j "$(nproc)" > "${RESULTS_ROOT}/build.log" 2>&1 \
            || { echo "ERROR: 빌드 실패 — ${RESULTS_ROOT}/build.log 확인"; exit 1; }
        echo "    ok"
    fi
}

print_env() {
    echo "Binary      : $BINARY"
    echo "StrucTTY rev: $(git -C "$STRUCTTY_DIR" rev-parse --short HEAD 2>/dev/null || echo N/A)"
    echo "Binary mtime: $(date -r "$BINARY" '+%Y-%m-%d %H:%M:%S' 2>/dev/null || echo N/A)"
    echo "Results     : $RESULT_DIR"
    echo ""
}
