#!/bin/bash

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/common.sh"

setup 03_memory "peak resident memory"

TIME_BIN="${TIME_BIN:-/usr/bin/time}"
if [ ! -x "$TIME_BIN" ]; then
    echo "ERROR: GNU time not found: $TIME_BIN" >&2
    exit 1
fi

EXAMPLE_ROOT="${EXAMPLE_ROOT:-$RESULT_DIR/example}"
RELEASE_API="${RELEASE_API:-https://api.github.com/repos/steineggerlab/StrucTTY/releases/tags/data}"

find_example_archive() {
    curl -sS --max-time 30 "$RELEASE_API" 2>/dev/null | python3 -c '
import json, re, sys
release = json.load(sys.stdin)
for asset in release.get("assets", []):
    if asset["name"].endswith(".zip"):
        print(asset["browser_download_url"]); break
else:
    found = re.search(r"https://github\.com/user-attachments/files/\S+?\.zip",
                      release.get("body") or "")
    print(found.group(0) if found else "")
' 2>/dev/null
}

if [ ! -d "$EXAMPLE_ROOT" ]; then
    url="$(find_example_archive)"
    if [ -n "$url" ] && curl -fsSL --max-time 180 -o "$RESULT_DIR/example.zip" "$url"; then
        unzip -q -d "$EXAMPLE_ROOT" "$RESULT_DIR/example.zip"
        rm -f "$RESULT_DIR/example.zip"
        echo "  example data downloaded: $EXAMPLE_ROOT"
    else
        echo "  WARN: could not fetch the example archive from $RELEASE_API."
        echo "        Skipping the Foldseek and MSA scenarios."
    fi
fi

CSV="$RESULT_DIR/memory.csv"
printf 'scenario,detail,n_struct,run,peak_rss_kb,wall_s\n' > "$CSV"

RUNS="${RUNS:-5}"

measure() {
    local scenario="$1" detail="$2" nstruct="$3"; shift 3
    local log rss wall
    local -a rss_values=()

    for run in $(seq 1 "$RUNS"); do
        log="$RESULT_DIR/${scenario}_${detail}_run${run}.time"
        printf 'q' | "$TIME_BIN" -v "$BINARY" "$@" > /dev/null 2> "$log" || true
        rss="$(awk -F': ' '/Maximum resident set size/{print $2}' "$log")"
        wall="$(awk -F': ' '/Elapsed \(wall clock\)/{print $2}' "$log")"
        if [ -z "$rss" ]; then
            echo "  SKIP $scenario/$detail run $run (measurement failed - see $log)"
            continue
        fi
        wall="$(python3 -c "
text = '$wall'.strip()
parts = [float(x) for x in text.split(':')] if text else [0.0]
seconds = 0.0
for part in parts:
    seconds = seconds * 60 + part
print(f'{seconds:.2f}')
")"
        printf '%s,%s,%s,%s,%s,%s\n' "$scenario" "$detail" "$nstruct" "$run" "$rss" "$wall" >> "$CSV"
        rss_values+=("$rss")
    done

    [ ${#rss_values[@]} -gt 0 ] || return 0

    python3 - "$scenario" "$detail" "$nstruct" "${rss_values[@]}" <<'SUMMARY'
import sys
scenario, detail, nstruct = sys.argv[1:4]
values = [int(v) for v in sys.argv[4:]]
mean = sum(values) / len(values) / 1024
spread = (max(values) - min(values)) / 1024
print(f"  {scenario:<10} {detail:<22} n={nstruct:<2} {mean:8.1f} MB"
      f"   spread {spread:4.1f} MB over {len(values)} runs")
SUMMARY
}

echo "--- single structure, by size ---"
for f in "$BENCH_DIR"/*.cif; do
    [ -f "$f" ] || continue
    measure single "$(basename "$f" .cif)" 1 "$f" -m protein
done

echo "--- several structures at once ---"
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

echo "--- loading a Foldseek result ---"
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
    echo "  SKIP (no example/foldseek_result)"
fi

echo "--- MSA conservation ---"
if [ -f "$EXAMPLE_ROOT/3A0C-assembly1.cif" ] && [ -f "$EXAMPLE_ROOT/msa_result/query.a3m" ]; then
    measure msa "3A0C_a3m" 1 \
        "$EXAMPLE_ROOT/3A0C-assembly1.cif" -m conservation --msa "$EXAMPLE_ROOT/msa_result/query.a3m"
    measure msa "3A0C_plain" 1 "$EXAMPLE_ROOT/3A0C-assembly1.cif" -m protein
else
    echo "  SKIP (no example/msa_result)"
fi

echo ""
echo "=== summary (peak RSS, mean of $RUNS runs) ==="
python3 - "$CSV" <<'SUMMARY'
import csv
import sys
from collections import OrderedDict

rows = list(csv.DictReader(open(sys.argv[1])))
if not rows:
    print("  no measurements")
    raise SystemExit

grouped = OrderedDict()
for row in rows:
    grouped.setdefault(f"{row['scenario']}/{row['detail']}", []).append(row)

width = max(len(name) for name in grouped)
print(f"  {'scenario':<{width}}  {'mean':>9}  {'min':>8}  {'max':>8}  {'wall':>7}  runs")
for name, group in grouped.items():
    rss = [int(r['peak_rss_kb']) / 1024.0 for r in group]
    wall = sum(float(r['wall_s']) for r in group) / len(group)
    print(f"  {name:<{width}}  {sum(rss) / len(rss):6.1f} MB  "
          f"{min(rss):5.1f} MB  {max(rss):5.1f} MB  {wall:5.2f} s  {len(group):4d}")
SUMMARY
echo ""
echo "csv: $CSV"
