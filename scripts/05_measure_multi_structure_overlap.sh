#!/bin/bash

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/common.sh"

setup 05_multi_structure_overlap "multi-structure overlap on the initial screen"

rm -f "$RESULT_DIR"/*.ansi "$RESULT_DIR"/*.map.txt "$RESULT_DIR"/*.log
export PTY_TIMEOUT="${PTY_TIMEOUT:-90}"

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
    echo "ERROR: fewer than 2 structures (BENCH_DIR=$BENCH_DIR)"
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
        python3 "$SCRIPT_DIR/lib_pty_run.py" "$cols" "$rows" "${out}.ansi" \
            "$BINARY" "$@" -m protein > "${out}.log" 2>&1 || true
        python3 "$SCRIPT_DIR/lib_frame_stats.py" overlap "${out}.ansi" "$n" | tee -a "$REPORT"
        python3 "$SCRIPT_DIR/lib_frame_stats.py" map "${out}.ansi" > "${out}.map.txt"
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

echo "=== summary ==="
grep -E '^(--- \[|  protein [0-9]+ x|  none)' "$REPORT" | sed 's/^/  /'
echo ""
echo "report: $REPORT"
echo "map files: $RESULT_DIR/*.map.txt (ASCII glyph layout)"
