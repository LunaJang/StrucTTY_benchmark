#!/bin/bash
# 리비전(BIOADV-2026-562) 재현 스크립트 공용 설정.
# 각 revision_*.sh 가 source 한다.

set -euo pipefail

STRUCTTY_DIR="${STRUCTTY_DIR:-$HOME/src/StrucTTY}"
BUILD_DIR="${BUILD_DIR:-$STRUCTTY_DIR/build}"
BINARY="${BINARY:-$BUILD_DIR/StrucTTY}"
BENCH_DIR="${BENCH_DIR:-$HOME/src/StrucTTY_benchmark/benchmark}"
EXAMPLE_DIR="${EXAMPLE_DIR:-$STRUCTTY_DIR/example}"
RESULTS_ROOT="${RESULTS_ROOT:-$HOME/src/StrucTTY_benchmark/revision_results}"

# 헤드리스 캡처: stdout 을 파일로 돌리면 Terminal::get_size() 의 ioctl 이 실패해
# 80x24 폴백이 걸린다(src/utils/Terminal.cpp:76-79). 터미널 크기가 고정되므로
# 프레임 바이트 비교가 가능하다. stdin 이 tty 가 아니면 raw mode 없이 진행되고
# read_key() 가 파이프에서 바이트를 읽는다(src/utils/Terminal.cpp:43, :107).
capture_frame() {
    # capture_frame <out_prefix> <args...>
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

# REBUILD=1 이면 현재 소스로 다시 빌드한다.
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
