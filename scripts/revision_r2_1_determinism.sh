#!/bin/bash

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/revision_common.sh"
RESULT_DIR="${RESULTS_ROOT}/r2_1_determinism"

mkdir -p "$RESULT_DIR" "$RESULTS_ROOT"
maybe_rebuild
require_binary

echo "=== R2-1 렌더링 결정성 재현 ==="
print_env

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
    echo "ERROR: 테스트 구조가 하나도 없다 (BENCH_DIR=$BENCH_DIR, EXAMPLE_DIR=$EXAMPLE_DIR)"
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
            read -r gh gn <<< "$(python3 "$SCRIPT_DIR/revision_frame_stats.py" hash "${out}.ansi")"
            printf '%s\t%s\trepeat%d\t%s\t%s\t%s\t%s\n' \
                "$base" "$mode" "$i" "same_name.cif" "$gh" "$gn" "$raw" >> "$SUMMARY"
            hashes+=("$gh")
        done

        for variant in renamed_copy.cif dirA/${stem}.cif dirB/${stem}.cif as_pdb_ext.pdb as_ent_ext.ent; do
            tag="$(echo "$variant" | tr '/' '_')"
            out="$RESULT_DIR/${stem}_${mode}_${tag}"
            raw="$(capture_frame "$out" "$WORK/$variant" -m "$mode")"
            read -r gh gn <<< "$(python3 "$SCRIPT_DIR/revision_frame_stats.py" hash "${out}.ansi")"
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
            echo "  $mode: 렌더된 ${#rendered[@]}회 글리프 해시 1종 — 결정론적 (빈 프레임 ${empty_n}건)"
        else
            verdict_all_same=0
            echo "  $mode: 글리프 해시 ${uniq_count}종 — 렌더 차이 발생! (빈 프레임 ${empty_n}건)"
            printf '%s\n' "${rendered[@]}" | sort | uniq -c | sed 's/^/      /'
        fi
    done
done

echo ""
echo "=== 결론 ==="
if [ "$verdict_all_same" -eq 1 ]; then
    echo "렌더에 성공한 모든 실행에서 글리프 레이어(위치+색+점자 비트)가 동일 ->"
    echo "반복 실행·파일명·디렉터리 변경에 따른 렌더링 비결정성은 재현되지 않음."
else
    echo "렌더 차이가 재현됨 -> summary.tsv 에서 어느 축인지 확인할 것."
fi
echo ""
echo "빈 프레임(파싱 실패) 케이스:"
awk -F'\t' '$6==0 {print "  "$1"  "$2"  "$4}' "$SUMMARY" | sort -u | head
echo "  -> stderr 는 ${RESULT_DIR}/*.err 참조"
echo "summary: $SUMMARY"
