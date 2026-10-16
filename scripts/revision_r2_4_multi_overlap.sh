#!/bin/bash
# 리비전 R2-4 재현: "여러 PDB 구조를 동시에 열면 초기 화면에서 투영이 겹친다".
#
# 방법: n = 2..9 개 구조를 protein 모드로 띄우고 stdout 프레임을 캡처한 뒤,
# 각 단백질의 색(= protein 인덱스별 3밴드 색)으로 글리프를 분류해
#   (1) 단백질별 ink bounding box
#   (2) bbox 쌍별 교차 영역
#   (3) 같은 셀을 두 단백질이 점유한 횟수
# 를 센다. 격자 배치 코드 근거: src/visualization/Screen.cpp:673-703
# (3열 grid, step 0.5/0.75, focal_offset *= max_dim * 0.6/0.8).

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/revision_common.sh"
RESULT_DIR="${RESULTS_ROOT}/r2_4_multi_overlap"

mkdir -p "$RESULT_DIR" "$RESULTS_ROOT"
rm -f "$RESULT_DIR"/*.ansi "$RESULT_DIR"/*.map.txt "$RESULT_DIR"/*.log   # 이전 실행 잔재 제거
maybe_rebuild
require_binary
export PTY_TIMEOUT="${PTY_TIMEOUT:-90}"

echo "=== R2-4 다중 구조 초기 화면 겹침 재현 ==="
print_env

# 크기가 다른 구조를 섞어야 "칸 밖으로 넘치는" 현상이 드러난다.
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

# 터미널 크기별로 본다. 작은 터미널에서는 패널 높이 때문에 상단 격자 행이
# 통째로 잘린다(Screen.cpp:912-913) -- 겹침 판정과 구분하려고 크기를 바꿔 돌린다.
TERM_SIZES=("80x24" "120x40" "200x60")

run_case() {
    # run_case <label> <files...>
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

# 1) 서로 다른 구조를 2~5개 (크기 편차 큼)
for n in 2 3 4 5; do
    if [ "$n" -le "${#AVAIL[@]}" ]; then
        run_case "mixed_n${n}" "${AVAIL[@]:0:$n}"
    fi
done

# 2) 같은 구조 사본 N개 — 격자 배치 자체만 보기 위한 대조군
WORK="$RESULT_DIR/work"; rm -rf "$WORK"; mkdir -p "$WORK"
SRC="${AVAIL[1]:-${AVAIL[0]}}"   # 중간 크기
for i in $(seq 1 9); do cp "$SRC" "$WORK/copy${i}.cif"; done
for n in 2 4 6 9; do
    files=()
    for i in $(seq 1 "$n"); do files+=("$WORK/copy${i}.cif"); done
    run_case "same_n${n}" "${files[@]}"
done

# 3) 단일 구조 기준선 (겹침이 있을 수 없는 경우)
run_case "single" "${AVAIL[0]}"

echo "=== 요약 ==="
grep -E '^(--- \[|  protein [0-9]+ x|  없음)' "$REPORT" | sed 's/^/  /'
echo ""
echo "report: $REPORT"
echo "맵 파일: $RESULT_DIR/*.map.txt (글리프 배치 ASCII)"
