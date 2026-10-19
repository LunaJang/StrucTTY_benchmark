#!/bin/bash

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/revision_common.sh"
RESULT_DIR="${RESULTS_ROOT}/r3_m4_ss_agreement"

mkdir -p "$RESULT_DIR" "$RESULTS_ROOT"

TOOL="$RESULT_DIR/ss_agreement"
SRC="$SCRIPT_DIR/revision_ss_agreement.cpp"
GEMMI_INC="$STRUCTTY_DIR/lib/gemmi/include"
STRUCT_INC="$STRUCTTY_DIR/src/structure"
SSPRED="$STRUCTTY_DIR/src/structure/SSPredictor.cpp"

echo "=== R3-M4 2차구조 휴리스틱 일치율 ==="
echo "StrucTTY rev: $(git -C "$STRUCTTY_DIR" rev-parse --short HEAD 2>/dev/null || echo N/A)"
echo "Results     : $RESULT_DIR"
echo ""

g++ -std=c++17 -O2 -include cstdint \
    -I "$STRUCT_INC" -isystem "$GEMMI_INC" \
    "$SRC" "$SSPRED" -lz -o "$TOOL" 2> "$RESULT_DIR/compile.log" \
    || { echo "ERROR: 컴파일 실패 — $RESULT_DIR/compile.log"; tail -20 "$RESULT_DIR/compile.log"; exit 1; }

EXAMPLE_ROOT="${EXAMPLE_ROOT:-${RESULTS_ROOT}/r2_7_memory/example}"

FILES=()
for f in "$BENCH_DIR"/*.cif; do [ -f "$f" ] && FILES+=("$f"); done
for f in "$EXAMPLE_ROOT"/*.cif "$EXAMPLE_ROOT"/*.pdb; do [ -f "$f" ] && FILES+=("$f"); done
for f in "$EXAMPLE_DIR"/DB2/*.cif "$EXAMPLE_DIR"/DB1/*.cif; do [ -f "$f" ] && FILES+=("$f"); done

if [ ${#FILES[@]} -eq 0 ]; then
    echo "ERROR: 평가할 구조가 없다"
    exit 1
fi

echo "대상 ${#FILES[@]}개 (HELIX/SHEET 주석이 없는 파일은 자동 제외)"
echo ""
"$TOOL" "${FILES[@]}" > "$RESULT_DIR/agreement.txt" 2> "$RESULT_DIR/skipped.txt"
cat "$RESULT_DIR/agreement.txt"
echo ""
echo "제외된 파일: $(grep -c '^skip ' "$RESULT_DIR/skipped.txt" 2>/dev/null || echo 0)"
echo "report: $RESULT_DIR/agreement.txt"
