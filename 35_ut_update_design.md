# 2차 UT(28629) 를 합사 테스트 DB 로 갱신 — 백업을 포함한 절차

작성 2026-09-08

## 목적

개발 서버 `192.168.0.101` 의 2차 UT 인스턴스(`tibero7_ut_tablename`, 호스트 포트 28629)
내용을 합사 테스트 서버(`121.137.106.217:58629/TAIMS`)의 현재 상태로 갱신한다.
갱신 전 기존 데이터를 되돌릴 수 있는 형태로 백업한다.

대상 스키마는 `AIMS_EX`, `AIMS_DEV`, `AIMSC_DEV` 셋이다.
개발용(8629) 과 1차 UT(18629) 는 건드리지 않는다.

## 배경 — 왜 백업 단계가 새로 필요한가

갱신 경로 자체는 `09_refresh.sh` 에 이미 있다. 소스 추출 → 타겟 적재 → 뷰 재컴파일 →
건수 대조까지 자동이다. 그러나 이 스크립트는 1단계에서 `DROP USER CASCADE` 를 하고,
헤더에 "되돌리기는 없다" 고 명시돼 있다. 백업 단계가 없다.

지난 이관(2026-08-13) 이후 2차 UT 의 `AIMSC_DEV` 에 AQ 앱 테이블 작업이 쌓였다
(마스터 4 + 이력 8 + 시노님 3 + `_BAK` 8). 원천에는 같은 것이 `AIMS_DEV` 스키마에 있고
`AIMSC_DEV` 에는 없다. **전량 재적재하면 이 작업물은 소스에서 복구되지 않는다.**

## 결정 사항

| 항목 | 결정 | 근거 |
|---|---|---|
| 보존 범위 | 3개 스키마 전량 재적재 후 AQ 를 재생성 | 합사와의 정합성과 AQ 작업물을 둘 다 지킨다 |
| 백업 방식 | 물리 콜드 백업 (`data/` tar) | 비트 단위 동일. 계정·권한·테이블스페이스·AQ 까지 통째로 되돌아온다 |
| 실행 형태 | 단계별 수동 실행 | 실행 주체와 시점을 사람이 통제한다 |
| 갱신 스크립트 | `09_refresh.sh` 수정 없이 사용 | 검증된 경로다. 백업은 성격이 달라 밖에 둔다 |

### 채택하지 않은 것

- **논리 덤프(tbExport)만으로 백업** — 무정지가 장점이지만, 복원이 `DROP USER` + tbImport
  라서 재적재와 같은 실패 지점을 다시 통과해야 한다. 추출에 15분이 더 든다.
- **`AIMSC_DEV` 를 갱신 대상에서 제외** — AQ 작업물은 지켜지지만 `AIMSC_DEV` 가 합사와
  어긋난 채 남는다.
- **`09_refresh.sh` 안에 백업 단계를 넣기** — 이 스크립트는 cron 일일 재적재 용도도 겸한다.
  매 회차마다 컨테이너를 내리게 된다.

## 전체 흐름

```
0) 사전 점검 ──────── 라이선스 만료일 · 디스크 여유 · 컨테이너 상태   (읽기 전용)
1) 백업 ──────────── 컨테이너 정지 → data/config/license tar → 재기동  (정지 발생)
2) 백업 검증 ─────── tar 목록 · sha256 · 재기동 후 접속/건수 확인
3) 갱신 ──────────── DRYRUN=0 ./09_refresh.sh                      (약 15분, 되돌리기 없음)
4) AQ 재생성 ─────── 17_aq_tables_ddl.sql (SCHEMA=AIMSC_DEV)
5) 검증 ──────────── 09 의 건수 대조(자동) + 19_aq_verify_dbeaver.sql
   실패 시 ────────  35 restore 로 1) 시점으로 되돌림
```

각 단계는 따로 실행하고 결과를 확인한 뒤 다음으로 넘어간다.

## 구성 요소

### 새로 만드는 것 — `35_cold_backup.sh`

서버(`bamboos@192.168.0.101`)의 `~/alex/tibero7_ut_tablename/migration` 에서 실행한다.
맥에서 편집하고 `sync.sh push` 로 올린다. 기존 스크립트와 같은 규약을 따른다:
기본값 `DRYRUN=1`, 한국어 출력, 읽기 전용 단계와 변경 단계를 구분해 표시.

| 서브커맨드 | 하는 일 | 변경 |
|---|---|---|
| `check` | 데이터 크기, 디스크 여유, 컨테이너 상태, 라이선스 만료일 | 없음 |
| `backup` | `stop` → `data/`·`config/`·`license/` 를 tar → sha256 → `start` → 기동 확인 | 정지·재기동 |
| `list` | 백업 목록 (파일명·크기·시각·해시) | 없음 |
| `restore <파일>` | `stop` → `data/` 를 `data.old_<TS>` 로 rename → 해제 → `start` → 기동 확인 | 정지·교체 |

기본 인터페이스:

```bash
./35_cold_backup.sh check                      # 읽기 전용
DRYRUN=0 ./35_cold_backup.sh backup
./35_cold_backup.sh list
DRYRUN=0 ./35_cold_backup.sh restore <파일명>
```

환경변수: `CONTAINER`(기본 `tibero7_ut_tablename`), `BASEDIR`(기본 `~/alex/tibero7_ut_tablename`),
`BACKUPDIR`(기본 `$BASEDIR/backup`), `COMPRESS`(기본 1, 0 이면 무압축), `DRYRUN`(기본 1).

설계 근거:

1. **정지 후 tar.** 가동 중 복사하면 데이터파일이 깨진 상태로 저장된다. 콜드 백업이어야
   복원이 성립한다.
2. **라이선스를 정지 전에 확인하고, 만료면 중단.** 라이선스는 기동 시점에만 검사된다.
   만료된 상태로 내리면 다시 올라오지 않는다. 현재 `end_date=2026/10/07` 이라 여유가 있지만
   조건 자체를 스크립트에 둔다. `09_refresh.sh` 의 preflight 과 같은 판정을 쓴다.
3. **`config/` 와 `license/` 도 함께 뜬다.** 2차 UT 는 2026-09-08 에 `TOTAL_SHM_SIZE` 를 6G 로
   올렸고 그 설정은 호스트의 `config/TAIMS.tip` 에 있다. 복원본이 같은 성능으로 떠야 한다.
4. **복원은 삭제가 아니라 rename.** `data/` 를 `data.old_<TS>` 로 옮기고 새로 푼다. 복원이
   잘못돼도 원본이 남는다. 대신 디스크가 한때 2배 필요하므로 `check` 가 이를 확인한다.
5. **`--sparse` 사용.** Tibero 데이터파일은 테이블스페이스 크기만큼 미리 잡혀 있어 빈 블록이
   많다. sparse 처리하지 않으면 백업이 실제 사용량보다 훨씬 커진다.
6. **`restore` 는 대상 파일명을 명시해야 동작한다.** "가장 최근" 같은 암묵 선택을 두지 않는다.

### 그대로 쓰는 것

| 파일 | 단계 | 비고 |
|---|---|---|
| `09_refresh.sh` | 3 | 수정하지 않는다. `DRYRUN=0 ./09_refresh.sh` |
| `17_aq_tables_ddl.sql` | 4 | `DEFINE SCHEMA = "AIMSC_DEV"` 가 기본값. DROP 이 없어 재실행이 안전하다 |
| `19_aq_verify_dbeaver.sql` | 5 | AQ 6항목 검증 |
| `sync.sh` | 전 단계 | 맥 ↔ 서버 ↔ 컨테이너 파일 전달 |

## 단계별 절차

### 0) 사전 점검

```bash
REMOTE=bamboos@192.168.0.101 DRYRUN=0 ./sync.sh push
# 서버에서
cd ~/alex/tibero7_ut_tablename/migration
./35_cold_backup.sh check
```

확인 항목: 컨테이너 가동 중, 라이선스 만료일이 오늘 이후, 백업 대상 크기와 여유 공간
(복원까지 감안해 데이터 크기의 2배 이상).

합사 DB 도달 여부는 `09_refresh.sh` 의 preflight 이 3) 에서 확인한다. 35 는 확인하지 않는다
— 백업만 뜨고 갱신은 하지 않는 경우에도 쓰이기 때문이다.

### 1) 백업

```bash
DRYRUN=0 ./35_cold_backup.sh backup
```

컨테이너가 내려갔다 올라온다. 앱이 붙어 있으면 그동안 오류가 난다. 사용자가 없는 시간에 돌린다.

### 2) 백업 검증

`list` 로 파일이 생겼는지, 크기가 0이 아닌지, sha256 이 기록됐는지 본다.
재기동 후 접속과 대표 테이블 건수를 확인한다. 여기까지 통과해야 3) 으로 간다.

### 3) 갱신

```bash
DRYRUN=0 ./09_refresh.sh
```

약 15분. `AIMS_EX → AIMS_DEV → AIMSC_DEV` 순으로 `DROP USER CASCADE` 후 전량 재적재하고,
뷰 재컴파일과 건수 대조까지 한다. **종료 코드 0 = 건수 전량 일치.** 그 외는 실패다.

### 4) AQ 재생성

```bash
docker exec -it tibero7_ut_tablename bash -lc \
  'cd /tmp/tbmig && tbsql sys/tibero123@TAIMS @17_aq_tables_ddl.sql'
```

`AIMSC_DEV` 에 마스터 4 + 이력 8 + 시노님 3 을 만든다.
`AIMS_DEV` 쪽 AQ 테이블은 원천에 있어 3) 에서 함께 들어오므로 따로 만들지 않는다.
`_BAK` 8개는 재생성하지 않는다 — 원래 정리 대상이었다.

파티션은 `P202608 / P202609 / PMAX` 로 시작한다. 2026-10 이후 데이터는 `PMAX` 가 받는다.
월 파티션 추가는 이번 범위에 넣지 않는다.

### 5) 검증

- `09_refresh.sh` 자동 판정: 건수 전량 일치, 뷰 조회 실패 0건, `TBR-11048` 0건
- `19_aq_verify_dbeaver.sql` 6항목: 이력 8개 `PARTITIONED='YES'`, 로컬 유니크 인덱스,
  파티션 24개(8×3), PK 12개 `ENABLED`, 무효 객체 0, 컬럼 수 대조

### 실패 시 되돌리기

```bash
./35_cold_backup.sh list
DRYRUN=0 ./35_cold_backup.sh restore ut_tablename_<TS>.tar.gz
```

1) 시점으로 통째로 돌아간다. 3) 이 중간에 끊겨 스키마가 비어 있는 상태여도 무관하다.

## 위험과 대응

| 위험 | 대응 |
|---|---|
| 백업 후 컨테이너가 다시 뜨지 않음 | `backup` 이 정지 전에 라이선스 만료일을 확인하고, 재기동 후 기동 확인까지 한 뒤 성공 처리 |
| 갱신 중 실패로 스키마가 빈 채 남음 | `restore` 로 1) 시점 복원 |
| 디스크 부족 | `check` 가 데이터 크기의 2배 여유를 확인 |
| 엉뚱한 인스턴스에 실행 | 스크립트 기본값이 `tibero7_ut_tablename` 고정. `check` 가 대상 컨테이너와 포트를 출력 |
| AQ 재생성 누락 | 5) 의 `19_aq_verify_dbeaver.sql` 6항목이 잡는다 |
| 복원본이 느려짐 (`TOTAL_SHM_SIZE` 유실) | 백업에 `config/` 포함 |

## 범위 밖

- 개발용(8629)·1차 UT(18629) — 건드리지 않는다
- 월 파티션 자동 추가
- `_BAK` 8개 복구
- `09_refresh.sh` 수정
