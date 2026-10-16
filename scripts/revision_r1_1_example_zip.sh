#!/bin/bash

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/revision_common.sh"
RESULT_DIR="${RESULTS_ROOT}/r1_1_example_zip"

mkdir -p "$RESULT_DIR" "$RESULTS_ROOT"
README="$STRUCTTY_DIR/README.md"
REPORT="$RESULT_DIR/report.txt"
: > "$REPORT"

log() { printf '%s\n' "$*" | tee -a "$REPORT"; }

echo "=== R1-1 예제 ZIP 재현 ==="
echo "README      : $README"
echo "Results     : $RESULT_DIR"
echo ""

if [ ! -f "$README" ]; then
    echo "ERROR: README 없음: $README"; exit 1
fi

URL="$(grep -oE 'https://github\.com/user-attachments/files/[^ )"]+\.zip' "$README" | head -1)"
UNZIP_CMD="$(grep -nE '^\s*unzip ' "$README" | head -1 | sed 's/^[0-9]*://')"
mapfile -t REF_PATHS < <(grep -oE '\.\./example/[A-Za-z0-9._/-]+' "$README" | sed 's|^\.\./||' | sort -u)

log "[1] README 추출"
log "  download URL : ${URL:-(없음)}"
log "  unzip 명령   : ${UNZIP_CMD:-(없음)}"
log "  참조 경로 수 : ${#REF_PATHS[@]}"
for p in "${REF_PATHS[@]}"; do log "    $p"; done
log ""

RELEASE_API="${RELEASE_API:-https://api.github.com/repos/steineggerlab/StrucTTY/releases/tags/data}"
RELEASE_URL=""
log "[1b] 릴리스 태그 'data' 조회"
if curl -sS --max-time 30 "$RELEASE_API" -o "$RESULT_DIR/release.json" 2>/dev/null; then
    RELEASE_URL="$(python3 - "$RESULT_DIR/release.json" <<'PY'
import json, re, sys
d = json.load(open(sys.argv[1]))
if "tag_name" not in d:
    sys.exit(0)
for a in d.get("assets", []):
    if a["name"].endswith(".zip"):
        print(a["browser_download_url"]); sys.exit(0)
m = re.search(r'https://github\.com/user-attachments/files/\S+?\.zip', d.get("body") or "")
if m:
    print(m.group(0))
PY
)"
    log "  release 자산 URL : ${RELEASE_URL:-(없음)}"
    if [ -n "$RELEASE_URL" ] && [ -n "$URL" ] && [ "$RELEASE_URL" != "$URL" ]; then
        log "  !! README 링크와 릴리스 링크가 다르다"
        log "     README : $URL"
        log "     release: $RELEASE_URL"
    fi
else
    log "  SKIP: 릴리스 API 조회 실패"
fi
log ""

ZIP="$RESULT_DIR/example.zip"
DOWNLOADED=0
SOURCE_USED=""
log "[2] 다운로드"
if [ -s "$ZIP" ]; then
    log "  이미 받은 파일 사용: $ZIP ($(stat -c%s "$ZIP") bytes)"
    DOWNLOADED=1; SOURCE_USED="cached"
else
    if [ -n "$URL" ] && curl -fsSL --max-time 180 -o "$ZIP" "$URL" 2> "$RESULT_DIR/curl_readme.err"; then
        log "  README 링크 OK: $(stat -c%s "$ZIP") bytes"
        DOWNLOADED=1; SOURCE_USED="readme"
    else
        code="$(curl -sS -o /dev/null -w '%{http_code}' -L --max-time 30 "$URL" 2>/dev/null || echo 000)"
        gh="$(curl -sS -o /dev/null -w '%{http_code}' --max-time 20 https://github.com 2>/dev/null || echo 000)"
        log "  README 링크 FAIL: HTTP $code (대조군 github.com=$gh)"
        if [ -n "$RELEASE_URL" ] && [ "$RELEASE_URL" != "$URL" ]; then
            if curl -fsSL --max-time 180 -o "$ZIP" "$RELEASE_URL" 2> "$RESULT_DIR/curl_release.err"; then
                log "  릴리스 링크 OK: $(stat -c%s "$ZIP") bytes"
                log "  => README 의 zip URL 만 죽어 있다. R1-1 의 직접 원인."
                DOWNLOADED=1; SOURCE_USED="release"
            else
                log "  릴리스 링크도 FAIL ($RESULT_DIR/curl_release.err)"
            fi
        fi
    fi
fi
log ""

if [ "$DOWNLOADED" = "1" ]; then
    log "[3] zip 무결성·구조 (source=$SOURCE_USED)"
    if unzip -t "$ZIP" > "$RESULT_DIR/unzip_t.log" 2>&1; then
        log "  unzip -t : OK"
    else
        log "  unzip -t : FAIL (파손 또는 비표준 zip)"
        tail -5 "$RESULT_DIR/unzip_t.log" | while read -r l; do log "    $l"; done
    fi
    unzip -Z1 "$ZIP" > "$RESULT_DIR/zip_listing.txt" 2>/dev/null || true
    log "  엔트리 수 : $(wc -l < "$RESULT_DIR/zip_listing.txt")"
    log "  최상위    :"
    cut -d/ -f1 "$RESULT_DIR/zip_listing.txt" | sort -u | while read -r l; do log "    $l"; done
    log ""

    log "[4] README 지시대로 압축 해제 ($UNZIP_CMD)"
    EXTRACT="$RESULT_DIR/extract"
    rm -rf "$EXTRACT"; mkdir -p "$EXTRACT"
    if ( cd "$EXTRACT" && unzip -q "$ZIP" -d example ) > "$RESULT_DIR/unzip_run.log" 2>&1; then
        log "  unzip : OK"
    else
        log "  unzip : FAIL"
        tail -5 "$RESULT_DIR/unzip_run.log" | while read -r l; do log "    $l"; done
    fi
    if [ -d "$EXTRACT/example/example" ]; then
        log "  !! 이중 중첩: example/example/ 이 생긴다 -> README 경로가 전부 빗나감"
    fi
    log "  결과 트리(2단계):"
    find "$EXTRACT" -maxdepth 3 | sed "s|$EXTRACT|.|" | sort | head -40 | while read -r l; do log "    $l"; done
    log ""

    log "[5] README 참조 경로 존재 확인 (압축 해제 결과 기준)"
    miss=0
    for p in "${REF_PATHS[@]}"; do
        if [ -e "$EXTRACT/$p" ]; then
            log "    OK   $p"
        else
            log "    MISS $p"; miss=$((miss+1))
        fi
    done
    log "  누락 ${miss}/${#REF_PATHS[@]}"
    log ""
else
    log "[3~5] 다운로드 실패로 생략"
    log ""
fi

log "[6] 로컬 $EXAMPLE_DIR 와 README 참조 경로 대조"
if [ ! -d "$EXAMPLE_DIR" ]; then
    log "  로컬 example/ 없음"
else
    log "  로컬 트리(2단계):"
    find "$EXAMPLE_DIR" -maxdepth 2 | sed "s|$EXAMPLE_DIR|example|" | sort | head -30 \
        | while read -r l; do log "    $l"; done
    miss=0
    for p in "${REF_PATHS[@]}"; do
        rel="${p#example/}"
        if [ -e "$EXAMPLE_DIR/$rel" ]; then
            log "    OK   $p"
        else
            log "    MISS $p"; miss=$((miss+1))
        fi
    done
    log "  누락 ${miss}/${#REF_PATHS[@]}"
fi

echo ""
echo "report: $REPORT"
