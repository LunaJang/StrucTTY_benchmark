#!/bin/bash
set -euo pipefail

BINARY="$HOME/src/StrucTTY_work/build/StrucTTY"
BENCH_DIR="$HOME/src/StrucTTY_work/benchmark"
RUNS=5
RESULTS_DIR="$HOME/src/StrucTTY_work/benchmark_results"
CPU_CORE=0

mkdir -p "$RESULTS_DIR"

# 메모리 4GB 제한 (KB 단위, virtual memory)
ulimit -v 4194304

echo "=== StrucTTY Benchmark Start ==="
echo "Binary   : $BINARY"
echo "Bench dir: $BENCH_DIR"
echo "Runs/file: $RUNS"
echo "CPU core : $CPU_CORE"
echo "Results  : $RESULTS_DIR"
echo ""

cd "$RESULTS_DIR"  # CSV가 CWD에 저장되므로 결과 디렉토리로 이동

for bench_file in "$BENCH_DIR"/*.cif; do
    name=$(basename "$bench_file" .cif)
    echo "--- [$name] ---"
    for i in $(seq 1 $RUNS); do
        echo "  Run $i / $RUNS"
        taskset -c $CPU_CORE "$BINARY" "$bench_file" -b
        echo "  Done"
    done
    echo ""
done

echo "=== Benchmark Complete ==="
echo "All results saved to: $RESULTS_DIR"
