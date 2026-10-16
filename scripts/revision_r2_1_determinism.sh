#!/bin/bash
# 리비전 R2-1 재현: "동일한 ATOM 레코드 사본을 서로 다른 파일로 로드하면
# 픽셀 수준 차이가 난다 (특히 interface 모드)".
#
# 검증 축:
#   A. 같은 파일 5회 반복      -> 실행 간 비결정성이 있는가
#   B. 같은 내용 다른 파일명    -> 파일명 의존성이 있는가
#   C. 같은 내용 다른 디렉터리  -> 경로 의존성이 있는가
#   D. 확장자만 .pdb/.ent 로 바꾼 사본 -> 확장자 분기 의존성 (InputProbe/Protein::load_data)
#   E. 위를 모드별로 반복       -> protein / interface / chain / align-near
#
# 비교 단위는 **글리프 레이어 해시**(위치+색+점자 비트만) 이다. 프레임 전체 md5 는
# 하단 패널에 파일 경로가 찍히기 때문에 이름만 달라도 무조건 달라진다 -- 렌더링
# 차이와 구분되지 않는다. 전체 md5 도 참고용으로 summary.tsv 에 함께 남긴다.
# stdout 리다이렉트 때문에 터미널 크기는 80x24 로 고정된다(revision_common.sh 주석).

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

# 테스트 구조: 단일 체인(3BIK 은 다중 체인) + 다중 체인 assembly
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

    # 사본 준비 (내용 동일, 이름/경로/확장자만 다름)
    cp "$src" "$WORK/same_name.cif"
    cp "$src" "$WORK/renamed_copy.cif"
    cp "$src" "$WORK/dirA/${stem}.cif"
    cp "$src" "$WORK/dirB/${stem}.cif"
    cp "$src" "$WORK/as_pdb_ext.pdb"
    cp "$src" "$WORK/as_ent_ext.ent"

    for mode in "${MODES[@]}"; do
        hashes=()

        # A. 같은 파일 5회
        for i in 1 2 3 4 5; do
            out="$RESULT_DIR/${stem}_${mode}_repeat${i}"
            raw="$(capture_frame "$out" "$WORK/same_name.cif" -m "$mode")"
            read -r gh gn <<< "$(python3 "$SCRIPT_DIR/revision_frame_stats.py" hash "${out}.ansi")"
            printf '%s\t%s\trepeat%d\t%s\t%s\t%s\t%s\n' \
                "$base" "$mode" "$i" "same_name.cif" "$gh" "$gn" "$raw" >> "$SUMMARY"
            hashes+=("$gh")
        done

        # B~D. 이름/경로/확장자만 다른 사본
        for variant in renamed_copy.cif dirA/${stem}.cif dirB/${stem}.cif as_pdb_ext.pdb as_ent_ext.ent; do
            tag="$(echo "$variant" | tr '/' '_')"
            out="$RESULT_DIR/${stem}_${mode}_${tag}"
            raw="$(capture_frame "$out" "$WORK/$variant" -m "$mode")"
            read -r gh gn <<< "$(python3 "$SCRIPT_DIR/revision_frame_stats.py" hash "${out}.ansi")"
            printf '%s\t%s\tvariant\t%s\t%s\t%s\t%s\n' \
                "$base" "$mode" "$variant" "$gh" "$gn" "$raw" >> "$SUMMARY"
            hashes+=("$gh")
        done

        # 빈 프레임(= 파싱 실패/크래시)은 렌더 차이와 별도로 집계한다.
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
