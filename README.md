# StrucTTY benchmark

Scripts, inputs and raw output behind every measurement reported in the
[StrucTTY](https://github.com/steineggerlab/StrucTTY) manuscript. Each section
below gives the command that produced a number and the file it was read from.

```
benchmark/          the five structures used for the rendering benchmark
benchmark_results/  per-run CSVs written by the viewer's benchmark mode
results/            raw output of the measurement scripts, one directory per script
scripts/            the scripts themselves
```

## Setup

`STRUCTTY_DIR` must point at a StrucTTY checkout; everything else is derived
from it. Set `REBUILD=1` to rebuild the viewer from its current source before
measuring.

```bash
git clone --recurse-submodules https://github.com/steineggerlab/StrucTTY.git ~/src/StrucTTY
cmake -S ~/src/StrucTTY -B ~/src/StrucTTY/build -DCMAKE_BUILD_TYPE=Release
cmake --build ~/src/StrucTTY/build -j $(nproc)

export STRUCTTY_DIR=~/src/StrucTTY
export BM=$(pwd)
```

`BUILD_DIR`, `BINARY` and `EXAMPLE_DIR` follow `STRUCTTY_DIR`; `BENCH_DIR`,
`BENCH_RESULTS_DIR` and `RESULTS_ROOT` stay inside this repository. Any of them
can be overridden.

The example structures are the archive distributed with StrucTTY.
`03_measure_peak_memory.sh` downloads it on its own into
`results/03_memory/example`, which the later scripts reuse, so running that
script first saves the manual step:

```bash
curl -L -o example.zip https://github.com/user-attachments/files/31627970/structty_example.zip
unzip -d example example.zip && rm example.zip
```

Two scripts need more than a compiler. `03` takes a `foldseek` binary from
`FOLDSEEK` or the path to build a target database, and skips that one scenario
without it. `07` needs [Biotite](https://www.biotite-python.org/)
(`pip install biotite`).

## Rendering benchmark

`-b` replays a fixed key script and logs per-frame timings. The analyzer
averages five runs per structure.

```bash
scripts/01_run_benchmark.sh
python3 scripts/02_analyze_benchmark.py benchmark_results
```

| Structure | Cα | Load (ms) | TTFF (ms) | Frame mean | Frame p95 | Latency mean | Latency p95 |
|---|---:|---:|---:|---:|---:|---:|---:|
| 1CRN | 46 | 4.8 | 39.6 | 0.16 | 0.18 | <1 | <1 |
| 1STP | 121 | 11.0 | 74.4 | 0.28 | 0.32 | <1 | <1 |
| 3BIK | 446 | 45.2 | 175.6 | 0.62 | 0.67 | <1 | <1 |
| 6VXX | 2916 | 201.4 | 856.8 | 3.25 | 3.37 | 3.00 | 3.00 |
| 4V4Q | 11463 | 2575.6 | 4744.8 | 10.58 | 10.78 | 10.34 | 11.00 |

Measured on a single pinned core of an Arm Cortex-X925, 4 GB limit, Ubuntu
24.04 LTS, g++ 13.3, CMake Release. Each run is 200 warm-up iterations followed
by 2000 timed ones.

The `frame` event is logged at millisecond resolution, too coarse for the
smaller structures, so the frame columns are the per-frame sum of the six
microsecond stage timers `ph_calibrate`, `ph_layout`, `ph_torender`,
`ph_render`, `ph_panel` and `ph_print`.

## Peak memory

Peak resident set size over a load-and-render run, five runs per scenario.

```bash
scripts/03_measure_peak_memory.sh
column -s, -t results/03_memory/memory.csv
```

| Scenario | Peak RSS |
|---|---:|
| 1CRN / 1STP / 3BIK / 6VXX / 4V4Q | 6.1 / 7.4 / 13.4 / 44.7 / 379.1 MB |
| 3BIK ×3 / ×6 / ×9 | 13.9 / 14.3 / 14.5 MB |
| Foldseek result, targets from a directory | 21.7 MB |
| Foldseek result, targets from a Foldseek DB | 21.0 MB |
| Foldseek multimer report | 22.1 MB |
| 3A0C with and without A3M conservation | 9.1 MB both |

Runs varied by at most 0.4 MB. The peak is set by parsing the largest single
file rather than by how much is on screen, and reading the `_ca` entries a hit
refers to is cheaper than parsing the same targets from a directory.

## Rendering determinism

The same structure is rendered five times, plus copies that differ only in file
name, directory and extension, in four color modes, and the glyph layer
(position, color, braille bits) is hashed. Whole-frame hashes differ by design
because the panel prints the input path.

```bash
scripts/04_check_render_determinism.sh
column -t results/04_determinism/summary.tsv
```

120 runs over three structures and four modes. All 96 that rendered produced
one glyph hash per structure and mode — identical across repeats, file names
and directories. The remaining 24 are the copies given a `.pdb` or `.ent`
extension while holding mmCIF content; those exit with a diagnostic naming the
mismatch instead of rendering.

## Multi-structure layout

Per-structure ink bounding boxes, bounding-box intersections and same-cell
collisions for 2 to 9 structures at three terminal sizes.

```bash
scripts/05_measure_multi_structure_overlap.sh
grep -E "^(--- \[|  )" results/05_multi_structure_overlap/report.txt
```

27 cases, no intersections and no collisions in any of them. Before the grid
spacing was computed from the projected size, the same sweep had 19
intersections and lost three structures off-screen at 80×24.

## Secondary structure

StrucTTY uses the HELIX/SHEET records when a file carries them and falls back to
[P-SEA](https://doi.org/10.1093/bioinformatics/13.3.291) otherwise. Two
measurements, answering different questions. Both evaluate the eleven
experimental depositions of the example archive, 9,379 residues; predicted
models are left out so that every reference annotation is a deposited one.

```bash
scripts/06_measure_ss_agreement.sh
column -t results/06_ss_agreement/agreement.txt

g++ -std=c++17 -O2 -I$STRUCTTY_DIR/src/structure -o scripts/ss_dump \
    scripts/ss_dump.cpp $STRUCTTY_DIR/src/structure/SSPredictor.cpp
python3 scripts/07_compare_with_biotite.py results/03_memory/example
```

`06` links the viewer's own `SSPredictor` and compares residue by residue
against the deposited records: 73.1 % agreement, helix precision 98.6 % at
68.7 % recall, strand precision 76.0 % at 53.6 % recall. `07` compares the same
assignment against `biotite.structure.annotate_sse`, the reference
implementation of the same algorithm, and agrees on 99.9 % of residues.

So `07` checks that the implementation is P-SEA, while `06` measures how far a
Cα-only method follows annotations derived from the full backbone. Most of the
missed helix residues are the first and last turn of an annotated helix, which
fall outside the geometric windows.

## Helpers

`common.sh` resolves paths, rebuilds on request and captures a frame headlessly.
`lib_frame_stats.py` parses a rendered frame (`cells`, `map`, `overlap`, `hash`)
and `lib_pty_run.py` renders one frame in a pty of a given size. Both are called
by the scripts above rather than run directly.
