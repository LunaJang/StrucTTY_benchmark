#!/usr/bin/env python3
"""Compare StrucTTY's P-SEA assignment against the Biotite reference implementation.

Both assign secondary structure from CA coordinates with the same published
algorithm, so this checks that the implementation is P-SEA rather than our
reading of it. The structures are the experimental depositions in the example
archive; predicted models are left out.

Usage:
    g++ -std=c++17 -O2 -I$STRUCTTY_DIR/src/structure -o ss_dump \
        ss_dump.cpp $STRUCTTY_DIR/src/structure/SSPredictor.cpp
    python3 07_compare_with_biotite.py <example-directory>
"""

import os
import subprocess
import sys
from collections import OrderedDict

import numpy as np
import biotite.structure as struc
import biotite.structure.io.pdb as pdb
import biotite.structure.io.pdbx as pdbx

SCRIPT_DIR = os.path.dirname(os.path.abspath(__file__))
SS_DUMP = os.path.join(SCRIPT_DIR, "ss_dump")
RESULTS_ROOT = os.environ.get("RESULTS_ROOT",
                              os.path.abspath(os.path.join(SCRIPT_DIR, os.pardir, "results")))
RESULT_DIR = os.path.join(RESULTS_ROOT, "07_biotite_comparison")

STRUCTURES = [
    "1CJK-assembly1.cif",
    "1NPL-assembly1.cif",
    "3A0C-assembly1.cif",
    "3HGM-assembly1.cif",
    "3OAG-assembly1.cif",
    "8KGM-assembly1.cif",
    "9FL9-assembly1.cif",
    "9N47-assembly1.cif",
    "foldseek_result/DB1/3cna-assembly1.cif",
    "foldseek_result/DB2/2PEL.cif",
    "foldseek_result/DB2/4K1Z.cif",
]

CHAIN_BREAK = 4.8


def read_structure(path):
    if path.endswith(".cif"):
        return pdbx.get_structure(pdbx.CIFFile.read(path), model=1, use_author_fields=True)
    return pdb.PDBFile.read(path).get_structure(model=1)


def structty_labels(path):
    arr = read_structure(path)
    ca = arr[(arr.atom_name == "CA") & struc.filter_amino_acids(arr)]
    chains = OrderedDict()
    for i in range(ca.array_length()):
        chains.setdefault(ca.chain_id[i], []).append((int(ca.res_id[i]), ca.coord[i]))
    lines = [
        f"{chain}\t{resid}\t{xyz[0]:.3f}\t{xyz[1]:.3f}\t{xyz[2]:.3f}"
        for chain, residues in chains.items()
        for resid, xyz in residues
    ]
    proc = subprocess.run([SS_DUMP], input="\n".join(lines), capture_output=True, text=True)
    labels = {}
    for line in proc.stderr.splitlines():
        chain, resid, label = line.split("\t")
        labels[(chain, int(resid))] = label
    return ca, labels


def biotite_labels(path):
    arr = read_structure(path)
    arr = arr[struc.filter_amino_acids(arr)]
    symbol = {"a": "H", "b": "S", "c": "x"}
    labels = {}
    for chain in OrderedDict.fromkeys(arr.chain_id):
        sub = arr[arr.chain_id == chain]
        if sub.array_length() == 0:
            continue
        sse = struc.annotate_sse(sub)
        resids = struc.get_residues(sub)[0]
        if len(sse) != len(resids):
            continue
        for resid, code in zip(resids, struc.PSeaElement.to_symbols(sse)):
            labels[(chain, int(resid))] = symbol.get(str(code), "x")
    return labels


def main(example_dir):
    os.makedirs(RESULT_DIR, exist_ok=True)
    report = open(os.path.join(RESULT_DIR, "comparison.txt"), "w")

    def emit(line=""):
        print(line)
        report.write(line + "\n")

    total = agree = 0
    continuous = (0, 0)
    gapped = (0, 0)

    for rel in STRUCTURES:
        path = os.path.join(example_dir, rel)
        ca, ours = structty_labels(path)
        theirs = biotite_labels(path)

        shared = [k for k in ours if k in theirs]
        same = sum(1 for k in shared if ours[k] == theirs[k])
        total += len(shared)
        agree += same
        emit(f"{os.path.basename(rel):24s} residues={len(shared):5d} "
             f"agreement={same / len(shared) * 100:5.1f}%")

        for chain in OrderedDict.fromkeys(ca.chain_id):
            sub = ca[ca.chain_id == chain]
            resids = [int(r) for r in sub.res_id]
            if len(resids) < 2:
                continue
            steps = np.linalg.norm(np.diff(sub.coord, axis=0), axis=1)
            unbroken = (all(b - a == 1 for a, b in zip(resids, resids[1:]))
                        and bool((steps <= CHAIN_BREAK).all()))
            keys = [(chain, r) for r in resids if (chain, r) in ours and (chain, r) in theirs]
            matched = sum(1 for k in keys if ours[k] == theirs[k])
            n, m = continuous if unbroken else gapped
            if unbroken:
                continuous = (n + len(keys), m + matched)
            else:
                gapped = (n + len(keys), m + matched)

    emit()
    emit(f"{len(STRUCTURES)} structures, {total} residues")
    emit(f"agreement with Biotite P-SEA: {agree / total * 100:.1f}%")
    emit(f"  continuous chains : {continuous[1] / continuous[0] * 100:.1f}% "
         f"({continuous[0]} residues)")
    emit(f"  chains with gaps  : {gapped[1] / gapped[0] * 100:.1f}% "
         f"({gapped[0]} residues)")
    report.close()
    print(f"\nreport: {os.path.join(RESULT_DIR, 'comparison.txt')}")


if __name__ == "__main__":
    if len(sys.argv) != 2:
        sys.exit(__doc__)
    main(sys.argv[1])
