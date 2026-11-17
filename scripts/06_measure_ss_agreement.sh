#!/bin/bash

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/common.sh"

setup 06_ss_agreement "secondary structure agreement"

TOOL="$RESULT_DIR/ss_agreement"
SRC="$SCRIPT_DIR/ss_agreement.cpp"
GEMMI_INC="$STRUCTTY_DIR/lib/gemmi/include"
STRUCT_INC="$STRUCTTY_DIR/src/structure"
SSPRED="$STRUCTTY_DIR/src/structure/SSPredictor.cpp"

g++ -std=c++17 -O2 -include cstdint \
    -I "$STRUCT_INC" -isystem "$GEMMI_INC" \
    "$SRC" "$SSPRED" -lz -o "$TOOL" 2> "$RESULT_DIR/compile.log" \
    || { echo "ERROR: compilation failed - see $RESULT_DIR/compile.log" >&2; tail -20 "$RESULT_DIR/compile.log"; exit 1; }

EXAMPLE_ROOT="${EXAMPLE_ROOT:-${RESULTS_ROOT}/03_memory/example}"

STRUCTURES=(
    "1CJK-assembly1.cif"
    "1NPL-assembly1.cif"
    "3A0C-assembly1.cif"
    "3HGM-assembly1.cif"
    "3OAG-assembly1.cif"
    "8KGM-assembly1.cif"
    "9FL9-assembly1.cif"
    "9N47-assembly1.cif"
    "foldseek_result/DB1/3cna-assembly1.cif"
    "foldseek_result/DB2/2PEL.cif"
    "foldseek_result/DB2/4K1Z.cif"
)

FILES=()
for s in "${STRUCTURES[@]}"; do
    f="$EXAMPLE_ROOT/$s"
    if [ -f "$f" ]; then
        FILES+=("$f")
    else
        echo "  missing: $s" >&2
    fi
done

if [ ${#FILES[@]} -eq 0 ]; then
    echo "ERROR: no structures to evaluate under $EXAMPLE_ROOT" >&2
    echo "       Run 03_measure_peak_memory.sh first, or set EXAMPLE_ROOT." >&2
    exit 1
fi

echo "${#FILES[@]} experimental structures from the example archive"
echo ""
"$TOOL" "${FILES[@]}" > "$RESULT_DIR/agreement.txt" 2> "$RESULT_DIR/skipped.txt"
cat "$RESULT_DIR/agreement.txt"
echo ""
echo "report: $RESULT_DIR/agreement.txt"
