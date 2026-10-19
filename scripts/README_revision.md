# 리비전 재현 스크립트 (BIOADV-2026-562)

Bioinformatics Advances 리뷰어 코멘트를 **코드로 재현**하기 위한 스크립트 모음.
결과는 전부 `../revision_results/<케이스>/` 아래에 쌓인다.

| 스크립트 | 대상 코멘트 | 하는 일 |
|---|---|---|
| `revision_common.sh` | (공용) | 경로·빌드·헤드리스 캡처 헬퍼. `REBUILD=1` 이면 StrucTTY 를 현재 소스로 다시 빌드 |
| `revision_r2_1_determinism.sh` | R2-1 렌더링 비결정성 | 같은 파일 5회 반복 + 이름/디렉터리/확장자만 다른 사본 5종을 4개 모드(protein·interface·chain·align-near)로 렌더해 **글리프 레이어 해시**를 비교 |
| `revision_r2_4_multi_overlap.sh` | R2-4 다중 구조 겹침 | 구조 2~9개를 protein 모드로 띄우고 단백질별 ink bbox·bbox 교차·동일 셀 충돌을 센다. 터미널 크기 3종(80x24·120x40·200x60)에서 반복 |
| `revision_r2_7_memory.sh` | R2-7 메모리 | `/usr/bin/time -v` 로 peak RSS 측정: 단일 구조(크기별), 다중 구조 동시, Foldseek 결과 로딩, MSA conservation. 예제 데이터는 릴리스에서 자동으로 받는다 |
| `revision_r3_m4_ss_agreement.sh` + `revision_ss_agreement.cpp` | R3-M4 | StrucTTY 의 `SSPredictor` 를 그대로 링크해, 파일에 들어 있는 HELIX/SHEET 주석과 잔기 단위로 비교(일치율·H/S recall·precision) |
| `revision_r1_1_example_zip.sh` | R1-1 예제 ZIP | README 의 zip URL·`unzip` 명령·참조 경로 19개를 추출해 다운로드·무결성·레이아웃·경로 존재를 검사. 오프라인이면 로컬 `example/` 과 대조 |
| `revision_frame_stats.py` | (공용) | 프레임(ANSI+Braille) 파서. `cells` / `map` / `overlap` / `hash` 서브커맨드 |
| `revision_pty_run.py` | (공용) | 지정한 크기의 pty 에서 한 프레임 렌더 후 stdout 저장 (터미널 크기 의존성 테스트용) |

## 전제

- StrucTTY 바이너리: `$HOME/src/StrucTTY/build/StrucTTY` (`BINARY` 로 덮어쓰기 가능)
- 테스트 구조: `../benchmark/*.cif` + `$HOME/src/StrucTTY/example/DB1/3cna-assembly1.cif`
- 파이썬 표준 라이브러리만 사용 (frame_stats·pty_run)

## 비교 기준에 대한 주의

프레임 **전체** md5 로 비교하면 안 된다 — 하단 패널에 입력 파일 경로가 찍히므로
내용이 같아도 파일명만 다르면 해시가 달라진다. `revision_frame_stats.py hash` 는
braille 글리프(위치+색+점자 비트)만 해싱해 이 문제를 피한다.

헤드리스 캡처 시 stdout 을 파일로 돌리면 `Terminal::get_size()` 의 ioctl 이 실패해
80x24 폴백이 걸린다(`src/utils/Terminal.cpp:76-79`). 크기 의존 동작을 보려면
`revision_pty_run.py` 로 pty 크기를 직접 지정해야 한다.

## 실행

```bash
# 전부 (첫 실행은 REBUILD=1 권장)
REBUILD=1 ./revision_r2_1_determinism.sh
./revision_r2_4_multi_overlap.sh      # 4V4Q 포함이라 수 분 소요
./revision_r1_1_example_zip.sh
```
