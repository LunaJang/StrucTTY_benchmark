#!/bin/bash

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/common.sh"

setup 04_determinism "rendering determinism"

WORK="$RESULT_DIR/work"
rm -rf "$WORK"; mkdir -p "$WORK/dirA" "$WORK/dirB"

CANDIDATES=(
    "$BENCH_DIR/3_3BIK.cif"
    "$BENCH_DIR/2_1STP.cif"
    "$EXAMPLE_DIR/DB1/3cna-assembly1.cif"
)
STRUCTS=()
for f in "${CANDIDATES[@]}"; do
    [ -f "$f" ] && STRUCTS+=("$f")
done
if [ ${#STRUCTS[@]} -eq 0 ]; then
    echo "ERROR: no test structures found (BENCH_DIR=$BENCH_DIR, EXAMPLE_DIR=$EXAMPLE_DIR)"
    exit 1
fi

MODES=(protein interface chain align-near)
SUMMARY="$RESULT_DIR/summary.tsv"
printf 'structure\tmode\tcase\tfile\tglyph_hash\tglyphs\tframe_md5\n' > "$SUMMARY"

verdict_all_same=1

for src in "${STRUCTS[@]}"; do
    base="$(basename "$src")"
    stem="${base%.*}"
    echo "--- [$base] ---"

    cp "$src" "$WORK/same_name.cif"
    cp "$src" "$WORK/renamed_copy.cif"
    cp "$src" "$WORK/dirA/${stem}.cif"
    cp "$src" "$WORK/dirB/${stem}.cif"
    cp "$src" "$WORK/as_pdb_ext.pdb"
    cp "$src" "$WORK/as_ent_ext.ent"

    for mode in "${MODES[@]}"; do
        hashes=()

        for i in 1 2 3 4 5; do
            out="$RESULT_DIR/${stem}_${mode}_repeat${i}"
            raw="$(capture_frame "$out" "$WORK/same_name.cif" -m "$mode")"
            read -r gh gn <<< "$(python3 "$SCRIPT_DIR/lib_frame_stats.py" hash "${out}.ansi")"
            printf '%s\t%s\trepeat%d\t%s\t%s\t%s\t%s\n' \
                "$base" "$mode" "$i" "same_name.cif" "$gh" "$gn" "$raw" >> "$SUMMARY"
            hashes+=("$gh")
        done

        for variant in renamed_copy.cif dirA/${stem}.cif dirB/${stem}.cif as_pdb_ext.pdb as_ent_ext.ent; do
            tag="$(echo "$variant" | tr '/' '_')"
            out="$RESULT_DIR/${stem}_${mode}_${tag}"
            raw="$(capture_frame "$out" "$WORK/$variant" -m "$mode")"
            read -r gh gn <<< "$(python3 "$SCRIPT_DIR/lib_frame_stats.py" hash "${out}.ansi")"
            printf '%s\t%s\tvariant\t%s\t%s\t%s\t%s\n' \
                "$base" "$mode" "$variant" "$gh" "$gn" "$raw" >> "$SUMMARY"
            hashes+=("$gh")
        done

        EMPTY_HASH="d41d8cd98f00b204e9800998ecf8427e"
        rendered=()
        empty_n=0
        for h in "${hashes[@]}"; do
            if [ "$h" = "$EMPTY_HASH" ]; then empty_n=$((empty_n+1)); else rendered+=("$h"); fi
        done
        uniq_count=$(printf '%s\n' "${rendered[@]}" | sort -u | wc -l)
        if [ "$uniq_count" -le 1 ]; then
            echo "  $mode: ${#rendered[@]} rendered runs, 1 glyph hash - deterministic (${empty_n} empty frames)"
        else
            verdict_all_same=0
            echo "  $mode: ${uniq_count} glyph hashes - rendering differs! (${empty_n} empty frames)"
            printf '%s\n' "${rendered[@]}" | sort | uniq -c | sed 's/^/      /'
        fi
    done
done

echo ""
echo "=== conclusion ==="
if [ "$verdict_all_same" -eq 1 ]; then
    echo "every successful run produced the same glyph layer (position, color, braille bits) ->"
    echo "rendering non-determinism across repeats, file names and directories does not reproduce."
else
    echo "rendering differences reproduce -> check summary.tsv for the axis responsible."
fi
echo ""
echo "empty frames (parse failures):"
awk -F'\t' '$6==0 {print "  "$1"  "$2"  "$4}' "$SUMMARY" | sort -u | head
echo "  -> see ${RESULT_DIR}/*.err for stderr"
echo "summary: $SUMMARY"
