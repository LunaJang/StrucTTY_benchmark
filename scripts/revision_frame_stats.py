#!/usr/bin/env python3
"""StrucTTY 가 stdout 으로 뿜은 한 프레임(ANSI + Braille)을 파싱해 통계를 낸다.

리비전 코멘트 R2-1(렌더링 비결정성)·R2-4(다중 구조 겹침) 재현용.

프레임 포맷 근거 (src/visualization/Screen.cpp:944-956):
    ESC[<row>;<col>H  ESC[38;5;<xterm>m  <braille UTF-8 3바이트>  ESC[0m
행 선두마다 ESC[<row>;1H ESC[K 가 먼저 나온다(:917).

사용법:
    revision_frame_stats.py cells   <frame.ansi>            # 셀 수·ink bbox·색 분포
    revision_frame_stats.py map     <frame.ansi>            # ASCII 맵(단백질 인덱스)
    revision_frame_stats.py overlap <frame.ansi> <nstruct>  # 단백질별 bbox + 겹침 판정
    revision_frame_stats.py hash    <frame.ansi>            # 글리프 레이어만의 md5

`hash` 는 (row, col, xterm, glyph) 목록만 해싱한다. 하단 패널에 찍히는 파일 경로·
체인 길이 같은 텍스트는 braille 글리프가 아니므로 제외된다 -- 파일명만 다른 사본끼리
"렌더링이 같은지"를 보려면 프레임 전체 md5 가 아니라 이 값을 비교해야 한다.
"""

import hashlib
import re
import sys
from collections import defaultdict

# src/visualization/Palette.hpp 의 protein 모드 3밴드 테이블.
# color_from_style(): band0 = idx+120(NEAR), band1 = idx+1(COLORS), band2 = idx+200(FAR)
#   -- src/render/Renderer.cpp:85-90
PROTEIN_COLORS = [100, 80, 27, 129, 213, 209, 130, 214, 160]
PROTEIN_NEAR = [184, 159, 105, 177, 225, 223, 220, 229, 210]
PROTEIN_FAR = [58, 30, 18, 54, 96, 130, 94, 136, 88]

GLYPH_RE = re.compile(
    rb"\x1b\[(\d+);(\d+)H"      # 커서 이동
    rb"\x1b\[38;5;(\d+)m"       # 전경색
    rb"(\xe2[\xa0-\xa3][\x80-\xbf])"  # U+2800..U+28FF
)


def parse_frame(path, with_glyph=False):
    """-> [(row, col, xterm[, glyph])] (1-based row/col, 화면에 실제로 찍힌 글리프만)"""
    with open(path, "rb") as fh:
        data = fh.read()
    out = []
    for m in GLYPH_RE.finditer(data):
        rec = (int(m.group(1)), int(m.group(2)), int(m.group(3)))
        out.append(rec + (m.group(4),) if with_glyph else rec)
    return out


def cmd_hash(path):
    cells = parse_frame(path, with_glyph=True)
    h = hashlib.md5()
    for r, c, x, g in cells:
        h.update(f"{r},{c},{x},".encode())
        h.update(g)
    print(f"{h.hexdigest()} {len(cells)}")


def protein_index_map(nstruct):
    """xterm 코드 -> 단백질 인덱스. 모호한 코드(여러 인덱스 매핑)는 None 으로 표시."""
    mapping = {}
    ambiguous = set()
    for idx in range(min(nstruct, 9)):
        for table in (PROTEIN_COLORS, PROTEIN_NEAR, PROTEIN_FAR):
            code = table[idx]
            if code in mapping and mapping[code] != idx:
                ambiguous.add(code)
            mapping[code] = idx
    for code in ambiguous:
        mapping[code] = None
    return mapping, ambiguous


def bbox(cells):
    rows = [r for r, _, _ in cells]
    cols = [c for _, c, _ in cells]
    return (min(rows), min(cols), max(rows), max(cols))


def rect_overlap(a, b):
    r0 = max(a[0], b[0])
    c0 = max(a[1], b[1])
    r1 = min(a[2], b[2])
    c1 = min(a[3], b[3])
    if r0 > r1 or c0 > c1:
        return 0, None
    return (r1 - r0 + 1) * (c1 - c0 + 1), (r0, c0, r1, c1)


def cmd_cells(path):
    cells = parse_frame(path)
    if not cells:
        print(f"{path}: glyphs=0 (빈 프레임)")
        return
    by_color = defaultdict(int)
    for _, _, x in cells:
        by_color[x] += 1
    r0, c0, r1, c1 = bbox(cells)
    print(f"file       : {path}")
    print(f"glyphs     : {len(cells)}")
    print(f"unique cell: {len(set((r, c) for r, c, _ in cells))}")
    print(f"ink bbox   : rows {r0}-{r1}, cols {c0}-{c1}")
    print(f"colors     : {len(by_color)} -> " +
          ", ".join(f"{k}:{v}" for k, v in sorted(by_color.items(), key=lambda kv: -kv[1])))


def cmd_map(path):
    cells = parse_frame(path)
    if not cells:
        print("(빈 프레임)")
        return
    codes = sorted({x for _, _, x in cells})
    sym = {code: chr(ord("a") + i) for i, code in enumerate(codes)}
    grid = {}
    for r, c, x in cells:
        grid[(r, c)] = sym[x]
    rows = [r for r, _, _ in cells]
    cols = [c for _, c, _ in cells]
    for r in range(min(rows), max(rows) + 1):
        line = "".join(grid.get((r, c), ".") for c in range(1, max(cols) + 1))
        print(f"{r:3d} {line}")
    print("legend: " + ", ".join(f"{s}=xterm{code}" for code, s in sym.items()))


def cmd_overlap(path, nstruct):
    cells = parse_frame(path)
    if not cells:
        print(f"{path}: 빈 프레임 — 판정 불가")
        return 1
    mapping, ambiguous = protein_index_map(nstruct)
    per_protein = defaultdict(list)
    unknown = 0
    amb_cells = 0
    for r, c, x in cells:
        if x not in mapping:
            unknown += 1
            continue
        idx = mapping[x]
        if idx is None:
            amb_cells += 1
            continue
        per_protein[idx].append((r, c, x))

    print(f"file          : {path}")
    print(f"structures    : {nstruct}")
    print(f"glyphs        : {len(cells)}")
    if ambiguous:
        print(f"ambiguous code: {sorted(ambiguous)} -> {amb_cells} glyph 제외 "
              f"(protein 테이블 간 중복)")
    if unknown:
        print(f"unmapped      : {unknown} glyph (protein 모드 외 색)")

    boxes = {}
    for idx in sorted(per_protein):
        b = bbox(per_protein[idx])
        boxes[idx] = b
        print(f"  protein {idx}: glyphs={len(per_protein[idx]):5d}  "
              f"bbox rows {b[0]:3d}-{b[2]:3d}, cols {b[1]:3d}-{b[3]:3d}")

    # 같은 셀을 두 단백질이 다투는 경우(실제 픽셀 충돌)
    owner = {}
    collisions = defaultdict(int)
    for idx, lst in per_protein.items():
        for r, c, _ in lst:
            key = (r, c)
            if key in owner and owner[key] != idx:
                collisions[tuple(sorted((owner[key], idx)))] += 1
            else:
                owner[key] = idx

    print("  --- bbox 교차 ---")
    any_overlap = False
    idxs = sorted(boxes)
    for i in range(len(idxs)):
        for j in range(i + 1, len(idxs)):
            a, b = idxs[i], idxs[j]
            area, rect = rect_overlap(boxes[a], boxes[b])
            if area:
                any_overlap = True
                print(f"  protein {a} x {b}: bbox 교차 {area} cell @ rows "
                      f"{rect[0]}-{rect[2]}, cols {rect[1]}-{rect[3]}")
    if not any_overlap:
        print("  없음")

    print("  --- 동일 셀 점유 충돌 ---")
    if collisions:
        for (a, b), n in sorted(collisions.items()):
            print(f"  protein {a} x {b}: {n} cell")
    else:
        print("  없음")
    return 0


def main():
    if len(sys.argv) < 3:
        print(__doc__)
        return 2
    cmd, path = sys.argv[1], sys.argv[2]
    if cmd == "cells":
        cmd_cells(path)
    elif cmd == "map":
        cmd_map(path)
    elif cmd == "hash":
        cmd_hash(path)
    elif cmd == "overlap":
        n = int(sys.argv[3]) if len(sys.argv) > 3 else 9
        return cmd_overlap(path, n)
    else:
        print(__doc__)
        return 2
    return 0


if __name__ == "__main__":
    sys.exit(main())
