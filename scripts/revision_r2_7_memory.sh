#!/bin/bash

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/revision_common.sh"
RESULT_DIR="${RESULTS_ROOT}/r2_7_memory"

mkdir -p "$RESULT_DIR" "$RESULTS_ROOT"
maybe_rebuild
require_binary

TIME_BIN="${TIME_BIN:-/usr/bin/time}"
if [ ! -x "$TIME_BIN" ]; then
    echo "ERROR: GNU time 이 없다: $TIME_BIN"
    exit 1
fi

EXAMPLE_ARCHIVE_URL="${EXAMPLE_ARCHIVE_URL:-https://github.com/steineggerlab/StrucTTY/releases/tag/data}"
EXAMPLE_ROOT="${EXAMPLE_ROOT:-$RESULT_DIR/example}"
RELEASE_API="${RELEASE_API:-https://api.github.com/repos/steineggerlab/StrucTTY/releases/tags/data}"

echo "=== R2-7 메모리(peak RSS) 측정 ==="
print_env

if [ ! -d "$EXAMPLE_ROOT" ]; then
    url="$(curl -sS --max-time 30 "$RELEASE_API" 2>/dev/null \
        | python3 -c "import json,re,sys; d=json.load(sys.stdin); a=[x['browser_download_url'] for x in d.get('assets',[]) if x['name'].endswith('.zip')]; m=re.search(r'https://github\.com/user-attachments/files/\S+?\.zip', d.get('body') or ''); print(a[0] if a else (m.group(0) if m else ''))" 2>/dev/null)"
    if [ -n "$url" ] && curl -fsSL --max-time 180 -o "$RESULT_DIR/example.zip" "$url"; then
        unzip -q -d "$EXAMPLE_ROOT" "$RESULT_DIR/example.zip"
        rm -f "$RESULT_DIR/example.zip"
        echo "  example 데이터 내려받음: $EXAMPLE_ROOT"
    else
        echo "  WARN: example 데이터를 받지 못했다 ($EXAMPLE_ARCHIVE_URL). MSA/Foldseek 시나리오는 건너뛴다."
    fi
fi

CSV="$RESULT_DIR/memory.csv"
printf 'scenario,detail,n_struct,peak_rss_kb,wall_s\n' > "$CSV"

measure() {
    local scenario="$1" detail="$2" nstruct="$3"; shift 3
    local log="$RESULT_DIR/${scenario}_${detail}.time"
    printf 'q' | "$TIME_BIN" -v "$BINARY" "$@" > /dev/null 2> "$log" || true
    local rss wall
    rss="$(awk -F': ' '/Maximum resident set size/{print $2}' "$log")"
    wall="$(awk -F': ' '/Elapsed \(wall clock\)/{print $2}' "$log")"
    if [ -z "$rss" ]; then
        echo "  SKIP $scenario/$detail (측정 실패 — $log 확인)"
        return
    fi
    local wall_s
    wall_s="$(python3 -c "
import sys
t='''$wall'''.strip()
p=[float(x) for x in t.split(':')] if t else [0.0]
s=0.0
for v in p: s = s*60 + v
print(f'{s:.2f}')
")"
    printf '%s,%s,%s,%s,%s\n' "$scenario" "$detail" "$nstruct" "$rss" "$wall_s" >> "$CSV"
    printf '  %-12s %-28s n=%-2s  %8s KB  %6ss\n' "$scenario" "$detail" "$nstruct" "$rss" "$wall_s"
}

echo "--- 단일 구조 (크기별) ---"
for f in "$BENCH_DIR"/*.cif; do
    [ -f "$f" ] || continue
    measure single "$(basename "$f" .cif)" 1 "$f" -m protein
done

echo "--- 다중 구조 동시 ---"
WORK="$RESULT_DIR/work"; rm -rf "$WORK"; mkdir -p "$WORK"
SRC="$BENCH_DIR/3_3BIK.cif"
if [ -f "$SRC" ]; then
    for i in $(seq 1 9); do cp "$SRC" "$WORK/copy${i}.cif"; done
    for n in 3 6 9; do
        files=()
        for i in $(seq 1 "$n"); do files+=("$WORK/copy${i}.cif"); done
        measure multi "3BIK_x${n}" "$n" "${files[@]}" -m protein
    done
fi

echo "--- Foldseek 결과 로딩 ---"
FS_DIR="$EXAMPLE_ROOT/foldseek_result"
if [ -d "$FS_DIR/DB1" ] && [ -f "$FS_DIR/result" ]; then
    measure foldseek "dir_target_m8" 2 \
        "$FS_DIR/DB1/3cna-assembly1.cif" -fst "$FS_DIR/DB2/" -fsr "$FS_DIR/result" -m align
    measure foldseek "dir_query_multi" 2 \
        "$FS_DIR/DB1/" -fst "$FS_DIR/DB2/" -fsr "$FS_DIR/result" -m align
    if [ -f "$FS_DIR/result_multimer_report" ]; then
        measure foldseek "multimer_report" 2 \
            "$FS_DIR/DB1/" -fst "$FS_DIR/DB2/" -fsr "$FS_DIR/result_multimer_report" -m align-near
    fi
else
    echo "  SKIP (example/foldseek_result 없음)"
fi

echo "--- MSA conservation ---"
if [ -f "$EXAMPLE_ROOT/3A0C-assembly1.cif" ] && [ -f "$EXAMPLE_ROOT/msa_result/query.a3m" ]; then
    measure msa "3A0C_a3m" 1 \
        "$EXAMPLE_ROOT/3A0C-assembly1.cif" -m conservation --msa "$EXAMPLE_ROOT/msa_result/query.a3m"
    measure msa "3A0C_plain" 1 "$EXAMPLE_ROOT/3A0C-assembly1.cif" -m protein
else
    echo "  SKIP (example/msa_result 없음)"
fi

echo ""
echo "=== 요약 (peak RSS) ==="
python3 - "$CSV" <<'EOF'
import csv, sys
rows = list(csv.DictReader(open(sys.argv[1])))
if not rows:
    print("  측정 결과 없음"); raise SystemExit
w = max(len(f"{r['scenario']}/{r['detail']}") for r in rows)
for r in rows:
    mb = int(r['peak_rss_kb']) / 1024.0
    print(f"  {r['scenario']+'/'+r['detail']:<{w}}  {mb:8.1f} MB   {r['wall_s']:>6} s")
EOF
echo ""
echo "csv: $CSV"
