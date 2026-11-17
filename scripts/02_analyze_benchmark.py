#!/usr/bin/env python3
"""Analyze StrucTTY benchmark CSV results and print a summary table.

Metrics (averaged over N runs per structure):
  Load     -- dt_ms of the 'load' event (file parse time)
  TTFF     -- dt_ms of the 'ttff' event (time-to-first-frame from app start)
  Frame    -- mean / p95 of the per-frame sum of the six stage timers, in ms
  Latency  -- mean / p95 of dt_ms for all 'latency' events after bench_begin

The 'frame' event is logged at millisecond resolution, which is too coarse for
the smaller structures. The six stage timers below are logged in microseconds,
one row each per frame, and their sum is the render time of that frame.
"""

import csv
import os
import re
import sys
from collections import defaultdict

import numpy as np

BENCHMARK_DIR = os.path.join(os.path.dirname(__file__), "..", "benchmark_results")

FILE_PATTERN = re.compile(
    r"structty_bench_\d+_\d+_\d+_\d+_([A-Z0-9]+)\.csv$"
)

STAGE_TIMERS = ["ph_calibrate", "ph_layout", "ph_torender",
                "ph_render", "ph_panel", "ph_print"]


def parse_file(path: str) -> dict:
    """Return per-run metrics extracted from a single CSV file."""
    load_ms = None
    ttff_ms = None
    num_ca = None
    latency_dts: list[float] = []
    stages: dict[str, list[float]] = {t: [] for t in STAGE_TIMERS}
    in_bench = False

    with open(path, newline="") as f:
        for row in csv.DictReader(f):
            tag = row["tag"]
            dt = float(row["dt_ms"])

            if tag == "load":
                load_ms = dt
            elif tag == "bench_begin":
                in_bench = True
            elif tag == "ttff":
                ttff_ms = dt
                num_ca = int(row["num_ca"])
            elif tag == "latency" and in_bench:
                latency_dts.append(dt)
            elif tag in stages:
                stages[tag].append(dt)

    n_frames = min(len(v) for v in stages.values())
    if n_frames:
        frame_dts = list(
            np.sum([stages[t][:n_frames] for t in STAGE_TIMERS], axis=0) / 1000.0
        )
    else:
        frame_dts = []

    return {
        "load_ms": load_ms,
        "ttff_ms": ttff_ms,
        "num_ca": num_ca,
        "frame_dts": frame_dts,
        "latency_dts": latency_dts,
    }


def summarize(runs: list[dict]) -> dict:
    """Aggregate per-run metrics across multiple runs."""
    loads = [r["load_ms"] for r in runs if r["load_ms"] is not None]
    ttffs = [r["ttff_ms"] for r in runs if r["ttff_ms"] is not None]
    num_ca = next((r["num_ca"] for r in runs if r["num_ca"] is not None), None)

    frame_means = [np.mean(r["frame_dts"]) for r in runs if r["frame_dts"]]
    frame_p95s  = [np.percentile(r["frame_dts"], 95) for r in runs if r["frame_dts"]]
    lat_means   = [np.mean(r["latency_dts"]) for r in runs if r["latency_dts"]]
    lat_p95s    = [np.percentile(r["latency_dts"], 95) for r in runs if r["latency_dts"]]

    return {
        "num_ca":       num_ca,
        "load_mean":    np.mean(loads)        if loads        else float("nan"),
        "ttff_mean":    np.mean(ttffs)        if ttffs        else float("nan"),
        "frame_mean":   np.mean(frame_means)  if frame_means  else float("nan"),
        "frame_p95":    np.mean(frame_p95s)   if frame_p95s   else float("nan"),
        "lat_mean":     np.mean(lat_means)    if lat_means    else float("nan"),
        "lat_p95":      np.mean(lat_p95s)     if lat_p95s     else float("nan"),
        "n_runs":       len(runs),
    }


def main(bench_dir: str = BENCHMARK_DIR) -> None:
    if not os.path.isdir(bench_dir):
        print(f"Directory not found: {bench_dir}", file=sys.stderr)
        sys.exit(1)

    groups: dict[str, list[str]] = defaultdict(list)
    for fname in sorted(os.listdir(bench_dir)):
        m = FILE_PATTERN.match(fname)
        if m:
            groups[m.group(1)].append(os.path.join(bench_dir, fname))

    if not groups:
        print("No benchmark CSV files found.", file=sys.stderr)
        sys.exit(1)

    rows = []
    for protein, files in groups.items():
        runs = [parse_file(f) for f in files]
        summary = summarize(runs)
        rows.append({"structure": protein, **summary})

    rows.sort(key=lambda r: r["num_ca"] or 0)

    col_w = [10, 7, 10, 11, 12, 11, 13, 11, 6]
    headers = [
        "Structure", "C_alpha", "Load(ms)", "TTFF(ms)",
        "Frame mean", "Frame p95", "Latency mean", "Latency p95", "Runs",
    ]
    sep = "  "

    header_line = sep.join(f"{h:>{w}}" for h, w in zip(headers, col_w))
    print(header_line)
    print("-" * len(header_line))

    for r in rows:
        print(sep.join([
            f"{r['structure']:>{col_w[0]}}",
            f"{r['num_ca']:>{col_w[1]}}",
            f"{r['load_mean']:>{col_w[2]}.1f}",
            f"{r['ttff_mean']:>{col_w[3]}.1f}",
            f"{r['frame_mean']:>{col_w[4]}.2f}",
            f"{r['frame_p95']:>{col_w[5]}.2f}",
            f"{r['lat_mean']:>{col_w[6]}.2f}",
            f"{r['lat_p95']:>{col_w[7]}.2f}",
            f"{r['n_runs']:>{col_w[8]}}",
        ]))


if __name__ == "__main__":
    bench_dir = sys.argv[1] if len(sys.argv) > 1 else BENCHMARK_DIR
    main(bench_dir)
