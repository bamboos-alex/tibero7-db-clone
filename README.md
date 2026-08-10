# Tibero 데이터 이전(복제) 실행 절차

공동 작업용 Tibero DB의 `AIMS_DEV` / `AIMSC_DEV` 스키마를 사내 **docker tibero7** 인스턴스로 복제한다.

## 왜 기존 덤프를 쓰지 않는가

`/Users/alex/aims_ut_db_20260810/{AIMS_DEV,AIMSC_DEV}` 의 DBeaver 덤프(2.4GB)는 이관 소스로 쓸 수 없다.

- **DDL 없음** — 259개 파일 전부 INSERT만. 0byte 파일이 128개 / 165개라 해당 테이블은 컬럼명조차 없음
- **바이너리 리터럴 비호환** — 5개 테이블이 `0x424DF607…` (MSSQL/MySQL 문법). Tibero는 해석 불가
- **한글 소실** — `T_TIPA_VMS_SYBL_01I`(384MB)는 바이트가 `C2BD **3F** C2B0 **3F**…`, 원문이 `?`로 치환되어 이미 소실. 파일 전체에 정상 UTF-8 한글 0건
- **날짜 리터럴** — `'2026-07-30 16:16:10'` 평문이라 NLS 설정 없이는 적재 실패
- **멀티행 INSERT** — `VALUES (…),(…)` 10행 묶음. Oracle 호환 모드 미지원 가능성

→ 덤프는 **대조용 참고 자료로만 보관**하고, 컨테이너의 Tibero 클라이언트로 소스에 직접 붙어 정식 추출한다.

## 파일 구성

| 파일 | 단계 | 성격 |
|---|---|---|
| `00_env_check.sh` | Phase 0 | 컨테이너 환경·유틸리티·네트워크 점검 (읽기 전용) |
| `01_source_check.sql` | Phase 0 | 소스 캐릭터셋·권한·LOB·한글 원본 바이트 확인 (읽기 전용) |
| `02_baseline_snapshot.sql` | Phase 1 | 검증 기준값 확보 (읽기 전용) |
| `04_target_prepare.sql` | Phase 2 | 타겟 테이블스페이스·계정 생성 **(변경 발생)** |
| `03_export_import.sh` | Phase 2 | 경로 A: tbExport → tbImport **(변경 발생)** |
| `B1_ddl_dbms_metadata.sql` | 경로 B | DBMS_METADATA 로 DDL 추출 (읽기 전용) |
| `B2_ddl_from_dictionary.sql` | 경로 B | 딕셔너리 뷰로 DDL 생성 (읽기 전용, B1 실패 시) |
| `07_recompile_invalid.sql` | Phase 3 말 | 뷰 재컴파일 **(변경 발생, 데이터 영향 없음)** |
| `05_verify.sql` | Phase 4 | 타겟 검증값 수집 (읽기 전용) |
| `06_compare.sh` | Phase 4 | 소스 기준값 대조 리포트 |

## VIEW 처리

이관 대상에 뷰가 포함된다. 뷰는 테이블과 다른 두 가지 문제가 있어 따로 다룬다.

1. **의존 순서** — 뷰가 다른 뷰를 참조하면 생성 순서를 보장할 수 없다. 그래서 `CREATE OR REPLACE **FORCE** VIEW` 로 일단 전부 만들고, 마지막에 `07_recompile_invalid.sql` 로 반복 재컴파일해 해소한다.
2. **정의문이 LONG 타입** — `ALL_VIEWS.TEXT` 는 LONG 이라 SQL 문자열 연결이 불가능하다. `B2` 는 PL/SQL 로 읽는데 **32767자를 넘는 뷰는 추출에 실패**한다. 어떤 뷰가 해당되는지는 `01_source_check.sql` 의 `text_length` 정렬 결과로 미리 알 수 있고, 그런 뷰는 `B1`(DBMS_METADATA) 이나 수동으로 뽑아야 한다.

또 딕셔너리에는 SELECT 본문만 저장되므로, `B2` 는 `ALL_TAB_COLUMNS` 에서 뷰 컬럼 목록을 읽어 `CREATE VIEW v (컬럼목록) AS ...` 형태로 붙인다. 이렇게 해야 뷰 컬럼 별칭이 보존된다.

검증은 개수뿐 아니라 **실제 조회**까지 한다 — `05_verify.sql` 이 모든 뷰에 `SELECT ... WHERE ROWNUM<=1` 을 던져 컴파일만 통과하고 조회에서 깨지는 경우를 잡는다.

## 실행 순서

### Phase 0 — 환경 확인 (되돌릴 것 없음)

```bash
./00_env_check.sh tibero7 121.137.106.217 58629
```

**확인된 환경** (2026-08-10 실행 결과)

| 항목 | 값 |
|---|---|
| 컨테이너 | `tibero7` / `tiberoofficial/tibero:latest` |
| TB_HOME | `/opt/tibero7`, edition = standard |
| 유틸리티 | `tbexport` / `tbimport` **7.2** 존재 → **경로 A 가능** |
| 타겟 DB | `localhost:8629`, DB_NAME=`tibero` |
| 소스 도달 | `121.137.106.217:58629` 도달 가능 |
| 디스크 | 2.5T 여유 (충분) |

> **주의**: `tbexport`/`tbimport` 는 tbdsn DSN을 쓰지 않는다. `IP` / `PORT` / `SID` 파라미터로 직접 접속하고, 문법은 `parameter=value` 나열식이다. `03_export_import.sh` 는 이 문법으로 작성돼 있다.
>
> 다만 `tbsql` (01/02/05 스크립트 실행용)은 DSN이 필요할 수 있다. `tbsql user/pass@IP:PORT:SID` 형식이 안 되면 아래처럼 등록한다.

`$TB_HOME/client/config/tbdsn.tbr` 에 `SRC` DSN을 추가하고 접속을 확인한 뒤:

```bash
docker cp 01_source_check.sql <컨테이너>:/tmp/
docker exec -it <컨테이너> bash -lc "cd /tmp && tbsql <user>/<pw>@SRC @01_source_check.sql"
```

**여기서 반드시 확인할 두 가지**

1. `[2] 캐릭터셋` — 타겟에서도 같은 스크립트를 돌려 값이 **동일한지**. 다르면 이관하지 말고 타겟 DB를 재생성해야 한다 (캐릭터셋은 사후 변경 불가).
2. `[7] 한글 깨짐 원인` — `DUMP(SYBL_NM,16)` 결과 판독:
   - `EC/EB/EA` 3바이트 묶음 → 소스 정상. 덤프 단계의 문자셋 문제였음
   - `3f` 섞임 → 소스 원본이 이미 깨진 상태. tbExport가 그대로 옮기므로 추가 손실은 없음

### Phase 1 — 기준 스냅샷

```bash
tbsql <user>/<pw>@SRC @02_baseline_snapshot.sql
tbsql <user>/<pw>@SRC @02_gen_counts.sql        # 테이블 건수
tbsql <user>/<pw>@SRC @02_gen_view_counts.sql   # 뷰 건수
```

`02_baseline_meta.log`, `02_baseline_counts.log`, `02_baseline_view_counts.log` 를 보관한다. 이게 검증의 유일한 기준이다.

### Phase 2 — 타겟 준비 (변경 발생)

`04_target_prepare.sql` 은 **[0] 확인 구간만 먼저** 실행해 데이터파일 여유를 본다. 소스 용량보다 넉넉한지 확인한 뒤, 주석 처리된 `CREATE TABLESPACE` / `CREATE USER` / `GRANT` 를 환경에 맞게 고쳐 실행한다.

### Phase 3-A — tbExport / tbImport (주 경로)

먼저 이 버전에 파라미터명이 실재하는지 대조한다. 버전마다 이름이 달라 추정이 위험하므로 스크립트가 `-h` 출력과 직접 맞춰본다.

```bash
./03_export_import.sh validate
```

`없음` 표시가 있으면 그 이름부터 고친다. 전부 `OK` 면 진행한다.

```bash
export SRC_SID=<소스DB명> SRC_USER=... SRC_PASS=... TGT_USER=... TGT_PASS=...
./03_export_import.sh check
DRYRUN=0 ./03_export_import.sh pilot
```

`SRC_SID` 는 DBeaver 연결의 JDBC URL 마지막 항목(`jdbc:tibero:thin:@호스트:포트:**DB명**`)이다.

`pilot` 은 작은 테이블 하나만 왕복시킨다. **한글이 정상으로 보이는 것을 확인한 뒤에만** 전량으로 넘어간다.

```bash
DRYRUN=0 ./03_export_import.sh export
DRYRUN=0 ./03_export_import.sh import
```

기본값이 `DRYRUN=1` 이라 명령만 출력된다. 명령을 눈으로 확인하고 `DRYRUN=0` 을 붙여 실제 실행한다.

**추출 옵션에 대해**

- `CONSISTENT=Y` — 공동 작업 DB라 추출 중에도 갱신이 일어난다. 일관된 시점의 스냅샷을 뜬다.
- `COMPRESS=Y` — 384MB LOB 테이블 때문에 덤프가 커진다.
- 적재 시 `GRANT=N` — 타겟에 없는 계정으로의 GRANT 실패를 피한다. 권한이 필요하면 소스의 `dba_tab_privs` 를 보고 따로 부여한다.
- 스키마명을 바꿔 적재하려면 `TOUSER=<새이름>` 을 준다 (`FROMUSER`/`TOUSER` 로 전환된다).
- 적재 로그에 버전 경고가 뜨면 `IMP_OPTS` 에 `EXP_SERVER_VER=<소스버전>` 을 추가한다.

### Phase 3-B — DDL 스크립트 + DBeaver DB→DB (대비 경로)

경로 A가 막혔을 때 사용한다.

```bash
tbsql <user>/<pw>@SRC @B1_ddl_dbms_metadata.sql      # 01 의 [5] 가 "사용 가능" 이면
tbsql <user>/<pw>@SRC @B2_ddl_from_dictionary.sql    # 아니면
```

생성된 파일을 **파일 번호 순서대로** 타겟에 적용한다. **FK는 반드시 데이터 적재 뒤**에 건다.

```
B1: 1_tables → 2_views → [데이터 전송] → 3_fk → 4_indexes → 5_comments → 6_sequences → 07_recompile
B2: 1_tables → 2_pk_uk → 3_default_check → 4_views → [데이터 전송]
                                        → 5_fk → 6_indexes → 7_comments → 8_sequences → 07_recompile
```

마지막에 반드시 실행한다:

```bash
tbsql <user>/<pw>@TGT @07_recompile_invalid.sql
```

DBeaver 데이터 전송: 소스 연결에서 테이블 다중 선택 → `Export data` → `Database` → 타겟 연결 매핑(existing) → 커밋 배치 크기 조정. LOB 5개 테이블(`T_TIPA_VMS_SYBL_01I`, `T_TIPA_LCS_SYBL_01I`, `T_TIPB_VSL_PGRM_01I`, `T_TIPE_LCS_LCTRL_01M`, `T_TIPE_VMST_DDRF_PHSE_OBJ_01L`)은 **별도 배치로 분리**해서 돌린다.

### Phase 4 — 검증

```bash
tbsql <user>/<pw>@TGT @05_verify.sql
tbsql <user>/<pw>@TGT @05_gen_counts.sql
tbsql <user>/<pw>@TGT @05_gen_view_counts.sql

./06_compare.sh 02_baseline_counts.log 05_target_counts.log 02_baseline_meta.log 05_target_meta.log
./06_compare.sh 02_baseline_view_counts.log 05_target_view_counts.log   # 뷰 건수
```

`06_compare_report.txt` 에서 건수 불일치가 0건이어야 하고, `05_target_health.log` 의 무효 객체·비활성 제약조건·사용 불가 인덱스·**뷰 조회 실패**가 모두 0건이어야 한다.

> `06_compare.sh` 는 같은 파일을 덮어쓰므로, 뷰 대조 결과를 남기려면 첫 리포트를 먼저 다른 이름으로 옮겨 둔다.

## 주의

- `01`, `02`, `05`, `B1`, `B2` 는 **읽기 전용**이다. 공동 작업 DB에 영향을 주지 않는다.
- `03`, `04` 는 변경을 발생시킨다. `04` 는 타겟에서만, `03` 의 import 도 타겟에서만 동작한다.
- tbsql 이 만든 `*_gen_*.sql` / `B*_out_*.sql` 파일은 앞뒤에 프롬프트 잔여 줄이 붙을 수 있다. 실행 전에 확인한다.
- `B2` 는 파티션·IOT·가상컬럼·LOB 저장절을 재현하지 않는다. 해당 구조가 있으면 수동 보완이 필요하다.

## 기존 덤프에 대한 기록

- `AIMS_DEV/T_TIPG_TBSP_STAT_01N_*.sql` 은 13:24 / 13:37 두 벌 존재 (둘 다 4425 bytes, 중복 재추출)
- 값 안에 개행이 포함된 행이 있으므로, 혹시 이 덤프를 다루게 되면 파일 분할은 반드시 `^INSERT INTO` 문장 경계로 해야 한다
