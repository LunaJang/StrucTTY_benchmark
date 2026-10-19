# 리비전 재현 결과 (BIOADV-2026-562)

- 실행일: 2026-10-16
- StrucTTY: `2d66226` (branch `main`) 소스로 재빌드한 `build/StrucTTY`
- 스크립트: `../scripts/revision_*.sh` (사용법은 `../scripts/README_revision.md`)

---

## R2-1 렌더링 비결정성 — **재현 안 됨 (결정론적)**

스크립트: `revision_r2_1_determinism.sh` · 원자료: `r2_1_determinism/summary.tsv`

구조 3종(3BIK 다중체인 / 1STP / 3cna-assembly1 4체인) × 모드 4종(protein, interface,
chain, align-near) × 실행 11회(같은 파일 5회 + 이름·디렉터리·확장자만 다른 사본 5종 +
기준 1회) = 132회. 비교는 **글리프 레이어 해시**(위치+색+점자 비트).

- 렌더에 성공한 실행(모드당 8회)은 **전부 동일한 글리프 해시**. 반복 실행·파일명 변경·
  디렉터리 변경 어느 축에서도 픽셀 차이 없음
- 예: 3BIK protein 모드 — `same_name.cif` 5회, `renamed_copy.cif`, `dirA/`, `dirB/`
  모두 `96f7e53c…` / 글리프 217개로 일치
- interface 모드도 동일(리뷰어가 특히 지목한 모드)
- 코드상으로도 난수원·시간 의존 렌더 경로 없음. z-test 는 글리프 단위로 결정론적
  (`src/render/Renderer.cpp:153-154`)

**주의 — 프레임 전체 md5 로 비교하면 "차이 있음"으로 잘못 나온다.** 하단 패널에 입력
파일 경로가 찍히기 때문(`Screen::normalize_proteins` → `Panel::add_panel_info`,
`src/visualization/Screen.cpp:619-625`). 첫 실행에서 이 함정을 그대로 밟았고, 글리프
레이어만 해싱하도록 바꾼 뒤 결정론적임이 드러났다. 리뷰어가 본 "픽셀 수준 차이"도
① 터미널 크기 차이 ② 아래 R2-1b 의 확장자 분기 중 하나일 가능성이 높다.

### R2-1b 파생 발견 — 확장자 분기 버그 2건

| 케이스 | 결과 | 근거 |
|---|---|---|
| mmCIF 내용을 `.ent` 확장자로 | 렌더 0 글리프 + `Error: input file format is not supported.` | `Protein::load_data` 가 경로에 `.pdb`/`.cif` 문자열이 있을 때만 파싱한다(`src/structure/Protein.cpp:260`). `.ent` 는 `InputProbe::has_structure_extension`(`InputProbe.cpp:29-35`)·`--help`·README 가 지원한다고 광고 |
| mmCIF 내용을 `.pdb` 확장자로 | **크래시** — `terminate called after throwing an instance of 'std::runtime_error'  what(): Incorrect file format (perhaps it is cif not pdb?)` | gemmi 예외가 `load_init_atoms` 경로에서 잡히지 않는다. `is_ss_in_file`·`count_seqres` 만 try/catch 를 두고 있음(`Protein.cpp:86-93`, `:111-127`) |

둘 다 `r2_1_determinism/*_as_ent_ext.ent.err`, `*_as_pdb_ext.pdb.err` 에 그대로 남아 있다.

---

## R2-4 다중 구조 겹침 — **재현됨**

스크립트: `revision_r2_4_multi_overlap.sh` · 원자료: `r2_4_multi_overlap/report.txt`,
`*.map.txt`

구조 2~9개를 protein 모드로 띄우고 단백질별 ink bounding box 교차를 셌다. 터미널
크기 3종(80x24 / 120x40 / 200x60)에서 각각 반복.

| 케이스 | 80x24 | 120x40 | 200x60 |
|---|---|---|---|
| 서로 다른 구조 2~5개 | 교차 없음 | 교차 없음 | 교차 없음 |
| 같은 구조 사본 6개 | 2쌍 교차(각 18 cell) | **4쌍 교차(각 40 cell)** | **4쌍 교차(각 120 cell)** |
| 같은 구조 사본 9개 | 1쌍 교차 | 3쌍 교차 | 5쌍 교차(최대 98 cell) |

- 겹침은 **가로 방향 이웃 칸 사이**에서만 생긴다(예: `protein 0 x 1: rows 3-17,
  cols 76-83`) — 3열 격자의 열 간격이 구조 폭보다 좁다
- 터미널이 클수록 교차 면적이 커진다 → 격자 간격이 화면 크기에 비례해 벌어지지
  않는다는 뜻. 배치 코드: `Screen::normalize_proteins`, 3열 고정 + step 0.5/0.75 +
  `focal_offset *= max_dim * 0.6/0.8`(`src/visualization/Screen.cpp:673-703`)
- 같은 셀을 두 구조가 다투는 경우(글리프 충돌)는 0건 — z-test 가 앞쪽 하나를
  고르므로 "덮어쓰기"가 아니라 **시각적 인접·접촉**으로 나타난다
- 크기가 다른 구조를 섞으면 교차가 사라지는 이유: 전역 bounding box 기준으로
  스케일을 잡아(`Screen.cpp:628-637`) 작은 구조가 자기 칸 안에서 더 작게 찍힌다

### R2-4b 파생 발견 — 작은 터미널에서 상단 격자 행이 통째로 잘림

| 케이스 | 80x24 | 120x40 | 200x60 |
|---|---|---|---|
| 서로 다른 구조 4개 | **protein 0,1 안 보임** | 4개 다 보임 | 4개 다 보임 |
| 서로 다른 구조 5개 | **protein 0,1,2 안 보임** | 5개 다 보임 | 5개 다 보임 |
| 같은 구조 9개 | **protein 0,1,2 안 보임** | 9개 다 보임 | 9개 다 보임 |

`print_screen_braille()` 이 `row = ty - (y_offset/2) - 3` 을 계산해 음수 행을 버린다
(`src/visualization/Screen.cpp:912-913`). 패널이 터미널 높이의 2/5 까지 차지할 수
있어(`Screen.cpp:826-841`) 24행 터미널에서는 첫 격자 행이 화면 밖으로 밀린다.
**경고 없이 구조가 사라지므로** R2-4·R2-5 답변에서 같이 다뤄야 한다.

---

## 수정 후 재검증 (`after_fix/`)

StrucTTY 측 수정: 격자 간격을 실제 투영 크기 + 최소 여백(문자 셀 2칸)에서 계산하고
(`Screen::layout_grid()`), 렌더 영역 높이를 패널 제외분에 맞추며, 터미널 크기가
바뀌면 격자를 다시 잡는다. README 의 죽은 예제 zip URL 도 교체.

| 항목 | 수정 전 | 수정 후 |
|---|---|---|
| bbox 교차(27 케이스 합계) | 19건 | **0건** |
| 화면에서 사라진 구조 | 80x24 에서 3개 케이스(최대 3개 구조 누락) | **없음** |
| 글리프 레이어 결정성 | 동일 | 동일(회귀 없음) |

---

## R1-1 예제 ZIP — **원인 확정 (README 링크만 404)**

릴리스 `data` 태그가 가리키는 자산(`…/files/31627970/structty_example.zip`)은 정상
(2.4 MB, `unzip -t` OK, 최상위 평면 구조). README 가 가리키던
`…/files/31204019/…` 만 404 였다. 릴리스 zip 으로 압축을 풀면 README 가 본문에서
참조하는 경로 **19/19 전부 존재**하고 `example/example/…` 이중 중첩도 없다.
즉 R1-1 은 "zip 파손"이 아니라 **README 링크가 낡아서** 생긴 문제다.

### (초기 조사 기록) 로컬 example/ 과의 대조

스크립트: `revision_r1_1_example_zip.sh` · 원자료: `r1_1_example_zip/report.txt`

- README 의 다운로드 URL `https://github.com/user-attachments/files/31204019/structty_example.zip`
  → **HTTP 404**
- 대조군: `github.com` = 200(네트워크 정상), README 의 데모 영상
  `user-attachments/assets/…` = 404 → user-attachments 계열이 curl 로는 전부 404라
  **링크 생사를 curl 만으로 단정할 수 없다. 브라우저로 직접 확인 필요**
- README 본문이 참조하는 `../example/...` 경로 **19개**를 추출해 로컬 `example/` 과
  대조한 결과 **19/19 전부 없음**. 로컬은 `example/DB1/`, `example/DB2/`,
  `example/result`, `example/result_multimer{,_report}` 구조인데 README 는
  `example/3A0C-assembly1.cif`, `example/foldseek_result/DB1/3cna-assembly1.cif`,
  `example/msa_result/query.a3m` 등을 가리킨다
- 즉 zip 을 받더라도 README 의 Quick Start 명령이 그대로 돌아갈지 확인되지 않은
  상태다. 리뷰어의 "압축을 풀어 예제를 쓸 수 없었다"와 합치한다

---

## 답변서에 바로 쓸 수 있는 문장 재료

1. R2-1 → "렌더링에 확률적 요소는 없다. 동일 입력에 대해 글리프 레이어가 바이트
   단위로 재현됨을 132회 실행으로 확인했다(스크립트 공개). 리뷰어가 본 차이는
   터미널 크기 의존 배치 또는 확장자에 따른 파서 분기에서 비롯된 것으로 보이며,
   후자는 이번 수정에서 고쳤다."
2. R2-4 → "3열 격자 간격이 구조 폭보다 좁아 가로 이웃끼리 접촉한다. 측정값
   (n=6, 200x60 에서 쌍당 120 cell 교차) 과 수정 방침을 본문에 기재."
3. R1-1 → "예제 배포 링크와 README 경로를 재정비했다. 저장소 경로와 1:1 로 맞는
   아카이브로 교체하고 다운로드·압축 해제·실행을 CI 에서 검증한다."

---

## R2-7 메모리 (peak RSS) — 측정 완료

스크립트: `revision_r2_7_memory.sh` · 원자료: `r2_7_memory/memory.csv`

| 시나리오 | 입력 | peak RSS |
|---|---|---|
| 단일 구조 | 1CRN (46 Cα) | 6.0 MB |
| 단일 구조 | 1STP (121) | 7.3 MB |
| 단일 구조 | 3BIK (446) | 13.4 MB |
| 단일 구조 | 6VXX (2,916) | 44.7 MB |
| 단일 구조 | 4V4Q (11,463) | 379.0 MB |
| 다중 구조 | 3BIK × 3 | 13.8 MB |
| 다중 구조 | 3BIK × 6 | 14.0 MB |
| 다중 구조 | 3BIK × 9 | 14.4 MB |
| Foldseek | m8 + 디렉터리 target | 21.9 MB |
| Foldseek | 디렉터리 query 다중 순회 | 21.6 MB |
| Foldseek | 멀티머 `_report` | 22.0 MB |
| MSA | 3A0C + a3m conservation | 9.2 MB |
| MSA | 3A0C (대조군, conservation 없음) | 9.2 MB |

읽을 점 두 가지.
- **구조를 더 열어도 메모리는 거의 안 는다** — 3BIK 1개 13.4 MB vs 9개 14.4 MB. 피크는 '가장 큰 파일 하나를 파싱하는 순간'이 지배하고, 파싱이 끝나면 Cα 만 남긴다.
- **MSA 경로의 추가 비용은 측정 한계 이하** — conservation 유무가 9.2 MB 로 같다.

## R2-6 macOS — CI 추가

`.github/workflows/build.yml` 신설: macOS 14(Apple Silicon)·macOS 13(Intel)·Ubuntu 에서 서브모듈 포함 체크아웃 → CMake Release 빌드 → 릴리스 예제 데이터 내려받기 → 스모크 3종(단일 구조 렌더, Foldseek hit 렌더, a3m conservation). 예제 zip 내려받기가 CI 단계라 **R1-1 처럼 링크가 죽으면 CI 가 먼저 잡는다**. 스모크 명령 3개는 로컬에서 릴리스 데이터로 통과 확인(frame 6,236 B / hit 3,589 B / cons 5,737 B).

## R3-M4 2차구조 휴리스틱 — 주석 대비 일치율

스크립트: `revision_r3_m4_ss_agreement.sh` (StrucTTY `SSPredictor` 를 그대로 링크) · 원자료: `r3_m4_ss_agreement/agreement.txt`

구조 17개(주석 없는 2개 제외), 잔기 **24,512개** 기준:

| 지표 | 값 |
|---|---|
| 전체 일치율 | **71.2 %** |
| helix recall / precision | 60.4 % / **98.0 %** |
| sheet recall / precision | 78.8 % / 52.5 % |
| coil recall | 74.3 % |

해석: **helix 로 칠한 것은 거의 항상 실제 helix**(precision 98 %)지만 짧은 helix 를 놓친다(recall 60 %). sheet 는 반대로 넓게 잡는다(recall 79 %, precision 53 %). 표시용으로는 쓸 만하고 분석용 할당으로는 부적절하다는 서술과 맞는 수치다. `-s` 는 파일에 HELIX/SHEET 가 있으면 그 주석을 그대로 쓰고, 없을 때만 이 휴리스틱을 돌린다는 점도 함께 적을 것.
