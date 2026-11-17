# StrucTTY benchmark

Measurement scripts and raw results behind the quantitative claims in the
StrucTTY manuscript. Every number reported in the paper can be regenerated from
this repository.

| Directory | Contents |
|---|---|
| `benchmark/` | The five structures used for the rendering benchmark (1CRN, 1STP, 3BIK, 6VXX, 4V4Q) |
| `benchmark_results/` | Raw per-run CSVs behind the benchmark table |
| `results/` | Raw output of the measurement scripts, one subdirectory per case |
| `scripts/` | The scripts themselves |

## Requirements

`STRUCTTY_DIR` must point at a StrucTTY checkout; nothing else is required.
`scripts/common.sh` derives `BUILD_DIR`, `BINARY` and `EXAMPLE_DIR` from it and
keeps `BENCH_DIR`, `BENCH_RESULTS_DIR` and `RESULTS_ROOT` inside this
repository. Any of them can be overridden. `REBUILD=1` rebuilds StrucTTY from
its current source before measuring.

The example data is the archive distributed with StrucTTY:

```bash
curl -L -o example.zip https://github.com/user-attachments/files/31627970/structty_example.zip
unzip -d example example.zip && rm example.zip
```

`03_measure_peak_memory.sh` fetches it on its own from the `data` release tag
and leaves it in `results/03_memory/example`, which the later scripts reuse. To
include the Foldseek DB scenario it also needs a `foldseek` binary, taken from
`FOLDSEEK` or the path; without one that scenario is skipped.

## Scripts

Numbered in the order they are meant to run.

| Script | What it does |
|---|---|
| `01_run_benchmark.sh` | Renders each benchmark structure `RUNS` times on a single pinned core under a 4 GB limit, writing one CSV per run |
| `02_analyze_benchmark.py` | Turns those CSVs into the benchmark table: load time, time to first frame, per-frame render time and input-to-frame latency |
| `03_measure_peak_memory.sh` | Peak RSS with `/usr/bin/time -v`, five runs per scenario, for single structures by size, several structures at once, a Foldseek result read from a directory and from a Foldseek DB, and an MSA |
| `04_check_render_determinism.sh` | Renders the same file five times, plus copies differing only in name, directory and extension, in four color modes, and compares glyph-layer hashes |
| `05_measure_multi_structure_overlap.sh` | Counts per-structure ink bounding boxes, bounding-box intersections and same-cell collisions for 2 to 9 structures at three terminal sizes |
| `06_measure_ss_agreement.sh` | Builds `ss_agreement.cpp` against StrucTTY's own `SSPredictor` and compares its P-SEA assignment residue by residue against the HELIX/SHEET records in each file |
| `07_compare_with_biotite.py` | Compares the same assignment against `biotite.structure.annotate_sse`, the reference implementation of P-SEA, and splits the result by whether the chain is continuous |

`common.sh` holds the shared path resolution, rebuild and frame-capture
helpers. `lib_frame_stats.py` parses a rendered frame (`cells`, `map`,
`overlap`, `hash` subcommands) and `lib_pty_run.py` renders one frame in a pty
of a given size; both are called by the scripts above rather than run directly.

```bash
export STRUCTTY_DIR=~/src/StrucTTY
scripts/01_run_benchmark.sh
python3 scripts/02_analyze_benchmark.py benchmark_results
scripts/03_measure_peak_memory.sh
REBUILD=1 scripts/04_check_render_determinism.sh
scripts/05_measure_multi_structure_overlap.sh
scripts/06_measure_ss_agreement.sh
python3 scripts/07_compare_with_biotite.py results/03_memory/example
```

## Per-frame render time

The `frame` event in the CSVs is logged at millisecond resolution, which is too
coarse for the smaller structures. `02_analyze_benchmark.py` therefore sums the
six microsecond-resolution stage timers (`ph_calibrate`, `ph_layout`,
`ph_torender`, `ph_render`, `ph_panel`, `ph_print`) logged once per frame.

## Secondary structure agreement

Both secondary-structure scripts evaluate the eleven experimental depositions
in the example archive, 9,379 residues in total. Predicted models are left out,
so that the HELIX/SHEET records being compared against are deposited
annotations throughout. Each script writes into the `results/` subdirectory carrying its own number:
`results/06_ss_agreement/agreement.txt` holds the per-structure table and
`results/07_biotite_comparison/comparison.txt` the comparison against the
reference implementation.

The assignment agrees with the Biotite reference implementation on 99.9% of
residues. Against the deposited HELIX/SHEET records it agrees on 73.1%, with
helix precision 98.6% at 68.7% recall and strand precision 76.0% at 53.6%
recall. The two references answer different questions: `07` checks that the
implementation is P-SEA, while `06` measures how far a C-alpha-only method can
follow annotations derived from the full backbone.

`07_compare_with_biotite.py` needs Biotite and builds `ss_dump.cpp` first:

```bash
g++ -std=c++17 -O2 -I$STRUCTTY_DIR/src/structure -o scripts/ss_dump \
    scripts/ss_dump.cpp $STRUCTTY_DIR/src/structure/SSPredictor.cpp
```
