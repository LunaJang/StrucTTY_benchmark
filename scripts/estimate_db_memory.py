#!/usr/bin/env python3
"""
FoldseekDBReader in-memory index size estimator.

Calculates theoretical memory usage of the three unordered_maps
(lookup_, ca_index_, seq_index_) that FoldseekDBReader::prepare() builds.

Based on libstdc++ unordered_map layout on 64-bit Linux:
  - Each entry = heap node (next_ptr 8B) + key + value
  - Bucket array = bucket_count * 8B  (reserve() pre-allocates)
  - std::string = 32B object + heap alloc if len > 15 (SSO threshold)
  - malloc overhead per heap alloc = ~16B

Usage:
  python3 estimate_db_memory.py <foldseek_result.m8> [max_hits]
"""

import sys
import os

# ── libstdc++ 64-bit constants ──────────────────────────────────────────────
PTR_SIZE       = 8   # next-pointer in unordered_map node
STR_OBJ_SIZE   = 32  # sizeof(std::string): SSO buf (16) + length (8) + data_ptr (8)
SSO_THRESHOLD  = 15  # strings ≤ 15 chars fit in SSO buffer (no heap alloc)
MALLOC_OVERHEAD = 16 # per-allocation bookkeeping (glibc)
UINT32_SIZE    = 4
SIZE_T_SIZE    = 8   # sizeof(size_t) on 64-bit

# ── IndexEntry = { size_t offset, size_t length } ──────────────────────────
INDEX_ENTRY_SIZE = SIZE_T_SIZE * 2  # 16 bytes

def align8(n):
    return (n + 7) & ~7

def node_size_lookup(accession: str) -> int:
    """
    unordered_map<string, uint32_t> node:
      next_ptr | string_obj | [heap_string_data] | uint32 | [padding]
    """
    heap_alloc = 0
    if len(accession) > SSO_THRESHOLD:
        heap_alloc = MALLOC_OVERHEAD + len(accession) + 1  # +1 for null terminator

    # node content: PTR + string_obj + uint32, aligned to 8
    content = PTR_SIZE + STR_OBJ_SIZE + UINT32_SIZE
    content = align8(content)
    return MALLOC_OVERHEAD + content + heap_alloc  # node itself also malloc'd

def node_size_index() -> int:
    """
    unordered_map<uint32_t, IndexEntry> node:
      next_ptr | uint32 | [pad 4B] | IndexEntry(16B)
    """
    content = PTR_SIZE + UINT32_SIZE + 4 + INDEX_ENTRY_SIZE  # 4 = alignment padding
    content = align8(content)
    return MALLOC_OVERHEAD + content

def bucket_array_bytes(n: int) -> int:
    """reserve(n) → bucket_count ≥ n, each bucket = one pointer"""
    return n * PTR_SIZE

def estimate(accessions: list[str]) -> dict:
    n = len(accessions)
    if n == 0:
        return {}

    avg_len = sum(len(a) for a in accessions) / n

    lookup_nodes  = sum(node_size_lookup(a) for a in accessions)
    lookup_bucket = bucket_array_bytes(n)

    idx_node_size = node_size_index()
    ca_nodes    = n * idx_node_size
    ca_bucket   = bucket_array_bytes(n)
    seq_nodes   = n * idx_node_size
    seq_bucket  = bucket_array_bytes(n)

    total = lookup_nodes + lookup_bucket + ca_nodes + ca_bucket + seq_nodes + seq_bucket

    return {
        "n_targets"     : n,
        "avg_acc_len"   : avg_len,
        "lookup_KB"     : (lookup_nodes + lookup_bucket) / 1024,
        "ca_index_KB"   : (ca_nodes + ca_bucket) / 1024,
        "seq_index_KB"  : (seq_nodes + seq_bucket) / 1024,
        "total_KB"      : total / 1024,
        "per_entry_bytes": total / n,
    }

def main():
    if len(sys.argv) < 2:
        print("Usage: estimate_db_memory.py <foldseek_result.m8> [max_hits]")
        print()
        print("  foldseek_result.m8  : Foldseek .m8 result file (tab-separated)")
        print("  max_hits            : Limit to first N hits (default: all)")
        sys.exit(1)

    result_file = sys.argv[1]
    max_hits = int(sys.argv[2]) if len(sys.argv) >= 3 else None

    if not os.path.exists(result_file):
        print(f"Error: file not found: {result_file}")
        sys.exit(1)

    # m8 format: query target ... (target is column index 1)
    target_set = set()
    total_rows = 0
    with open(result_file) as f:
        for line in f:
            line = line.strip()
            if not line or line.startswith('#'):
                continue
            parts = line.split('\t')
            if len(parts) < 2:
                continue
            target_set.add(parts[1])
            total_rows += 1
            if max_hits and total_rows >= max_hits:
                break

    accessions = list(target_set)
    result = estimate(accessions)

    print("=" * 55)
    print("  FoldseekDBReader Memory Estimate")
    print("=" * 55)
    print(f"  Result file      : {result_file}")
    print(f"  Total rows read  : {total_rows}")
    print(f"  Unique targets   : {result['n_targets']}")
    print(f"  Avg accession len: {result['avg_acc_len']:.1f} chars")
    print()
    print(f"  lookup_          : {result['lookup_KB']:.1f} KB")
    print(f"  ca_index_        : {result['ca_index_KB']:.1f} KB")
    print(f"  seq_index_       : {result['seq_index_KB']:.1f} KB")
    print(f"  ─────────────────────────────")
    print(f"  Total (estimate) : {result['total_KB']:.1f} KB")
    print(f"  Per entry        : {result['per_entry_bytes']:.0f} bytes")
    print()
    print(f"  README claim     : ~152 KB (for 1000 hits)")
    claimed_per_entry = 152 * 1024 / 1000
    print(f"  ↳ implies        : ~{claimed_per_entry:.0f} bytes/entry")

    # Check at 1000-entry scale
    if result['n_targets'] != 1000:
        sample = accessions[:1000] if len(accessions) >= 1000 else accessions * (1000 // len(accessions) + 1)
        sample = sample[:1000]
        r1k = estimate(sample)
        print()
        print(f"  Estimate @ 1000 entries : {r1k['total_KB']:.1f} KB")
        diff_pct = (r1k['total_KB'] - 152) / 152 * 100
        verdict = "MATCHES" if abs(diff_pct) < 20 else "DIFFERS"
        print(f"  vs README claim 152 KB  : {diff_pct:+.1f}%  [{verdict}]")
    else:
        diff_pct = (result['total_KB'] - 152) / 152 * 100
        verdict = "MATCHES" if abs(diff_pct) < 20 else "DIFFERS"
        print(f"  vs README claim 152 KB  : {diff_pct:+.1f}%  [{verdict}]")

    print("=" * 55)

if __name__ == "__main__":
    main()
