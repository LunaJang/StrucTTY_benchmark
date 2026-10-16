#!/bin/bash

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/revision_common.sh"
RESULT_DIR="${RESULTS_ROOT}/r2_4_multi_overlap"

mkdir -p "$RESULT_DIR" "$RESULTS_ROOT"
rm -f "$RESULT_DIR"/*.ansi "$RESULT_DIR"/*.map.txt "$RESULT_DIR"/*.log
maybe_rebuild
require_binary
export PTY_TIMEOUT="${PTY_TIMEOUT:-90}"

echo "=== R2-4 다중 구조 초기 화면 겹침 재현 ==="
print_env

POOL=(
    "$BENCH_DIR/1_1CRN.cif"
    "$BENCH_DIR/2_1STP.cif"
    "$BENCH_DIR/3_3BIK.cif"
    "$BENCH_DIR/4_6VXX.cif"
    "$BENCH_DIR/5_4V4Q.cif"
)
AVAIL=()
for f in "${POOL[@]}"; do
    [ -f "$f" ] && AVAIL+=("$f")
done
if [ ${#AVAIL[@]} -lt 2 ]; then
    echo "ERROR: 구조가 2개 미만 (BENCH_DIR=$BENCH_DIR)"
    exit 1
fi

REPORT="$RESULT_DIR/report.txt"
: > "$REPORT"

TERM_SIZES=("80x24" "120x40" "200x60")

run_case() {
    local label="$1"; shift
    local n=$#
    for size in "${TERM_SIZES[@]}"; do
        local cols="${size%x*}" rows="${size#*x}"
        local out="$RESULT_DIR/${label}_${size}"
        echo "--- [$label @ ${size}] n=$n ---" | tee -a "$REPORT"
        python3 "$SCRIPT_DIR/revision_pty_run.py" "$cols" "$rows" "${out}.ansi" \
            "$BINARY" "$@" -m protein > "${out}.log" 2>&1 || true
        python3 "$SCRIPT_DIR/revision_frame_stats.py" overlap "${out}.ansi" "$n" | tee -a "$REPORT"
        python3 "$SCRIPT_DIR/revision_frame_stats.py" map "${out}.ansi" > "${out}.map.txt"
        echo "" | tee -a "$REPORT"
    done
}

for n in 2 3 4 5; do
    if [ "$n" -le "${#AVAIL[@]}" ]; then
        run_case "mixed_n${n}" "${AVAIL[@]:0:$n}"
    fi
done

WORK="$RESULT_DIR/work"; rm -rf "$WORK"; mkdir -p "$WORK"
SRC="${AVAIL[1]:-${AVAIL[0]}}"
for i in $(seq 1 9); do cp "$SRC" "$WORK/copy${i}.cif"; done
for n in 2 4 6 9; do
    files=()
    for i in $(seq 1 "$n"); do files+=("$WORK/copy${i}.cif"); done
    run_case "same_n${n}" "${files[@]}"
done

run_case "single" "${AVAIL[0]}"

echo "=== 요약 ==="
grep -E '^(--- \[|  protein [0-9]+ x|  없음)' "$REPORT" | sed 's/^/  /'
echo ""
echo "report: $REPORT"
echo "맵 파일: $RESULT_DIR/*.map.txt (글리프 배치 ASCII)"
