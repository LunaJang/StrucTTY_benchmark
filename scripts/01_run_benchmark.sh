#!/bin/bash

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/common.sh"

RUNS="${RUNS:-5}"
CPU_CORE="${CPU_CORE:-0}"
MEMORY_LIMIT_KB="${MEMORY_LIMIT_KB:-4194304}"

resolve_paths
rebuild_if_requested
require_binary
mkdir -p "$BENCH_RESULTS_DIR"

ulimit -v "$MEMORY_LIMIT_KB"

echo "=== rendering benchmark ==="
echo "Binary   : $BINARY"
echo "Bench dir: $BENCH_DIR"
echo "Runs/file: $RUNS"
echo "CPU core : $CPU_CORE"
echo "Results  : $BENCH_RESULTS_DIR"
echo ""

cd "$BENCH_RESULTS_DIR"

for bench_file in "$BENCH_DIR"/*.cif; do
    name=$(basename "$bench_file" .cif)
    echo "--- [$name] ---"
    for i in $(seq 1 "$RUNS"); do
        echo "  Run $i / $RUNS"
        taskset -c "$CPU_CORE" "$BINARY" "$bench_file" -b
        echo "  Done"
    done
    echo ""
done

echo "=== done ==="
echo "results: $BENCH_RESULTS_DIR"