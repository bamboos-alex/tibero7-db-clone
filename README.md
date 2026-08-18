# Tibero 데이터 이전(복제) 실행 절차

> ## ✅ 이관 완료 (2026-08-10)
>
> | 항목 | 결과 |
> |---|---|
> | 테이블 건수 | **416/416 일치** — 4,802,221행 |
> | 무효 객체 | 0건 |
> | 뷰 실제 조회 | 성공 111 / 실패 0 |
> | 비활성·미검증 제약조건 | 0건 |
> | 사용 불가 인덱스 | 0건 |
> | 한글 바이트 | 소스와 동일 (`a8,f6,3f,...`) |
>
> 타겟: `tibero7_ut` 컨테이너 / `TAIMS` / **MSWIN949** / 호스트 포트 18629
> 접속: `AIMS_EX` · `AIMS_DEV` · `AIMSC_DEV` (비밀번호 = 계정명)
>
> **⚠ 라이선스가 2026-08-19 만료된다.** 이후 계속 쓰려면 갱신이 필요하다.
>
> 덤프와 로그는 `~/alex/tibero7_ut/work/` 에 남아 있다(볼륨). 재적재가 필요하면
> 추출 없이 `03_export_import.sh import` 만 다시 돌리면 된다.

> ## ✅ 2차 이관 완료 (2026-08-13) — 테이블명 규약 변경분
>
> | 항목 | 결과 |
> |---|---|
> | 테이블 건수 | **260/260 일치** — 5,182,877행 |
> | 뷰 실제 조회 | 성공 59 / 실패 0 |
> | 무효 객체 | 1건 — **소스와 동일** (`AIMSC_DEV` 패키지 본문) |
> | 제약조건·인덱스 | 이상 0건 |
> | 한글 바이트 | 소스와 동일 |
> | 계정 롤 | 소스와 일치 (`CONNECT`/`RESOURCE`/`DBA`) |
>
> 타겟: `tibero7_ut_tablename` / `TAIMS` / MSWIN949 / 호스트 포트 **28629**

> ## ✅ AIMSC_DEV 이력 테이블 파티션 재구축 완료 (2026-08-18)
>
> AI 영상품질진단 앱이 쓰는 테이블 15개를 실측해 정리했다. 정의서가 필요한
> 테이블은 **0개**였다 — 12개는 이미 `AIMSC_DEV` 에 있었고 3개는 다른 스키마의
> 실테이블이었다.
>
> | 항목 | 결과 |
> |---|---|
> | 이력(`_01L`) 재구축 | **8/8** — 건수 차이 0 |
> | 인덱스 | 8개 전부 `UNIQUE` + `PARTITIONED=YES` (**로컬**) |
> | 파티션 | 8개 × `RANGE` 3개 (`P202608`/`P202609`/`PMAX`) |
> | PK 제약 | 8개 전부 `ENABLED` / `VALIDATED` |
> | 마스터(`_01M`) 4개 | 손대지 않음 — 파티션 불필요, 배치도 관례대로 |
> | 시노님 | `HDQR`/`MTNOF` 기존 유지 + `CCTV` 신규 추가 — 15,243행 조회 확인 |
>
> **백업 테이블 `T_..._BAK` 8개가 남아 있다.** 되돌릴 유일한 수단이라 자동으로
> 지우지 않았다. 앱 동작을 확인한 뒤 `DROP` 할 것.
>
> ⚠ **파티션 키 6개가 `NOT NULL` 이 됐다.** 앞으로 앱이 이 컬럼에 `NULL` 을
> 넣으면 `INSERT` 가 실패한다 — `T_ITSE_AI_DRF_DGNST01L.AI_DGNST_DTTM`,
> `T_ITSE_AI_MODL_OP01L.MNTG_STRT_DTTM`, `T_ITSE_AI_MVPCT_DGNST01L.AI_DGNST_DTTM`,
> `T_ITSE_ANNT01L.INFO_CRET_DTTM`, `T_ITSE_LBLL01L.INFO_CRET_DTTM`,
> `T_ITSE_SNSH_GTHR01L.STRT_DTTM`.
>
> ⚠ **PK 가 복합키(`기존PK`, `파티션키`)가 됐다.** 기존 PK 컬럼 단독 유일성은
> 이제 DB 가 보장하지 않는다. 로컬 유니크 인덱스의 요건이라 피할 수 없다.
>
> 남은 것: `AIMS_DEV.T_ITSE_AI_MVPCT_DGNST01L` 이 중복으로 남아 있다
> (`12_create_ai_mvpct_dgnst01l.sql` 산물). 앱은 `AIMSC_DEV` 를 쓰므로 정리 대상.

공동 작업용 Tibero DB(`121.137.106.217:58629/TAIMS`)의 `AIMS_EX` / `AIMS_DEV` / `AIMSC_DEV` 스키마를
사내 서버의 **docker `tibero7_ut`** 인스턴스로 복제한다.

기존 `tibero7` 컨테이너에도 `AIMS_DEV` 가 있으나 **개발용이라 보존해야 하므로 건드리지 않는다.**
스키마 rename 은 Oracle 호환 DB에서 불가능하고, 다른 스키마명으로 적재하면 뷰·시노님 정의문이 깨진다.
그래서 별도 인스턴스(`tibero7_ut`)를 새로 만들었다 — `docker-compose.yml` 참고.

## 인스턴스 3개 — 어디에 붙을지부터 확인할 것

접속 정보가 **포트만 다르다.** DB명(`TAIMS`)도 스키마명도 전부 같아서 틀리기 쉽다.

| 포트 | 컨테이너 | 서버 폴더 | 내용 |
|---|---|---|---|
| 8629 | `tibero7` | `~/alex/tibero7/` | **개발용.** 건드리지 말 것 |
| 18629 | `tibero7_ut` | `~/alex/tibero7_ut/` | 1차 UT — 변경 **전** 이름. 비교 기준으로 유지 |
| **28629** | **`tibero7_ut_tablename`** | **`~/alex/tibero7_ut_tablename/`** | **2차 UT — 변경 후 이름. 현재 기본값** |

스크립트 기본값은 2차를 가리킨다. 1차를 다룰 때만 환경변수로 되돌린다.

```bash
RPATH=alex/tibero7_ut/migration CONTAINER=tibero7_ut ./sync.sh up
CONTAINER=tibero7_ut ./03_export_import.sh check
```

`11_name_diff.sh` 의 `OLD_CONTAINER` 만 `tibero7_ut` 로 고정돼 있다 — 변경 전 스냅샷이
비교 기준이기 때문이다.

## 2차 이관 — 테이블명 규약 변경 (2026-08-13)

### 무엇이 바뀌었나

**세 계열의 접두사가 `T_ITSE_` 하나로 통합됐다.** 뒷부분은 그대로다.

```
AIMS_DEV.T_AAAA_CMMN01C         ->  AIMS_DEV.T_ITSE_CMMN01C
AIMS_DEV.T_AAAB_CCAD01M         ->  AIMS_DEV.T_ITSE_CCAD01M
AIMS_EX.T_TIPA_VMS_SYBL_01I     ->  AIMS_EX.T_ITSE_VMS_SYBL_01I
AIMS_EX.T_TIPG_TBSP_STAT_01L    ->  AIMS_EX.T_ITSE_TBSP_STAT_01L
```

**바뀌지 않은 것**: 스키마명, 시노님의 동명 1:1 구조, LOB 컬럼명, 테이블스페이스명,
캐릭터셋(MSWIN949).

뷰(`V_AAAA_` → `V_ITSE_`)와 패키지(`P_AAAA_PRTT_TBL_MGMT` → `P_ITSE_PRTT_TBL_MGMT`)도
같은 규칙을 따랐다. 다만 **인덱스·제약조건 이름은 테이블마다 다르다** — 개명 전부터
있던 테이블은 `PK_AAAA_*` 를 유지하고, 새로 만든 `T_ITSE_AI_*` 계열은 `PK_ITSE_*` 를 쓴다.

`AIMSC_DEV` 의 패키지만 옛 이름 `P_AAAA_PRTT_TBL_MGMT` 로 남아 있고 `INVALID` 다.
이 스키마 전체가 정리되지 않은 상태다.

### 1차 대비 구성 변화

| | 1차 (8/10) | 2차 (8/13) |
|---|---|---|
| 전체 테이블 | 416 | **260** |
| 전체 행 | 4,802,221 | **5,182,877** |
| `AIMS_EX` | 101 테이블 / 954MB | 동일 |
| `AIMS_DEV` | 158 테이블 / 58 뷰 | **159 / 59** (신규 추가 있음) |
| `AIMSC_DEV` | 157 테이블(전부 0행) | **테이블 없음** — 시노님 100 + 패키지만 |

`AIMSC_DEV` 의 테이블·뷰가 소스에서 사라졌다. 계정은 `OPEN` 이고 시노님 100개와
패키지가 남아 있다. `DBA_TABLES` 로도 0건이라 권한 문제가 아니라 실제 삭제다.
이관 범위에는 그대로 두었다 — 시노님·패키지가 있어 추출 대상이 되고, 소스 상태를
있는 그대로 복제하는 것이 맞다.

### 발견 절차

이름이 바뀐 상태에서는 기존 스크립트를 믿을 수 없다. 아무것도 가정하지 않는
단계를 앞에 두었다.

1. **`10_source_inventory.sql`** — 스키마명조차 하드코딩하지 않고 시스템 계정만 제외해
   전수 조회. 테이블/뷰/시노님 목록을 대조용 형식으로 파일에 남긴다
2. **`11_name_diff.sh`** — 1차 UT(변경 전 스냅샷)와 대조. 유지/신규/삭제를 스키마별로
   집계하고, 스크립트에 박힌 테이블명이 살아있는지 점검한다

1차 UT 를 남겨둔 덕분에 변경 내역을 기계적으로 뽑을 수 있었다. **비교 기준이 되는
인스턴스를 지우지 말 것.**

### 이름 의존을 줄인 조치

같은 일이 반복될 것을 전제로 검증부를 고쳤다.

- `02` / `05` 의 **LOB 검증** — 하드코딩 5개 테이블을 버리고 딕셔너리에서 BLOB/CLOB
  컬럼을 찾아 동적 집계. 테이블·컬럼명을 아예 참조하지 않는다
- `05` 의 **한글 검증 표본** — `DEFINE KOR_TAB` / `KOR_COL` / `CODE_TAB` 로 분리.
  다음에 바뀌면 세 줄만 고치면 된다
- `06` 의 수동 점검 항목도 특정 테이블명을 뺐다

여전히 이름에 의존하는 곳: `03` 의 `PILOT_TABLE`, `01` 의 `DBMS_METADATA` 대상.
둘 다 한 줄짜리라 그대로 두었다.

### 이번에 걸린 것

| 증상 | 원인 | 조치 |
|---|---|---|
| `TBR-7071: SYS.USER_PATH not found` 2건 | 소스의 **DIRECTORY 객체**에 대한 `GRANT` 를 옮기려다 실패. 타겟에 그 디렉터리가 없다 | 데이터와 무관. 앱이 파일 I/O 를 쓰면 타겟에도 `CREATE DIRECTORY` 필요 |
| `AIMSC_DEV` 패키지 본문 `INVALID` | 본문이 옛 이름 `T_AAAA_DB_JOB_PROS01L` 을 참조. **소스도 동일하게 무효** | 정상 복제. 고칠 대상은 소스 |
| `aims_dev` 로 접속 시 `AIMSC_DEV` 안 보임 | 소스는 세 계정 모두 `DBA` 인데 `04b` 가 `CONNECT`/`RESOURCE` 만 부여 | `GRANT DBA` 추가 (아래) |


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
| `sync.sh` | 전 단계 | 맥 ↔ 서버 ↔ 컨테이너 파일 동기화 |
| `docker-compose.yml` | Phase 2 | 타겟 인스턴스 `tibero7_ut` 정의 (**MSWIN949** / DB_NAME=TAIMS) |
| `04b_target_create.sql` | Phase 2 | 테이블스페이스 4개 + 계정 3개 생성 **(변경 발생)** |
| `08_expected_from_exportlog.sh` | Phase 4 | 추출 로그에서 기대 건수 산출 — **검증의 기준값** |
| `09_refresh.sh` | 운영 | 전량 재적재 — 초기화→추출→적재→재컴파일→검증 **(변경 발생)** |
| `10_source_inventory.sql` | 재실측 | 아무것도 가정하지 않고 소스 전수 조회 (읽기 전용) |
| `11_name_diff.sh` | 재실측 | 소스 현재 vs 1차 UT 대조 — 이름 변경 내역 추출 |
| `docker-compose.ut_tablename.yml` | Phase 2 | 2차 인스턴스 정의 (28629) |
| `db-structure.html` | 참고 | DB 구조 설명 (그림 버전). 브라우저로 열면 된다 |
| `01b`/`01c` | Phase 0 | 이관 범위·시노님 대상 스키마 확정 (읽기 전용) |
| `12_create_ai_mvpct_dgnst01l.sql` | 신규 | AI 영상화질 진단 이력 테이블 생성 — 파티션 + 로컬 인덱스 **(변경 발생)** |
| `13_target_survey.sql` | 신규 | AIMSC_DEV 신규 테이블 15개 현재 상태 실측 (읽기 전용) |
| `13b_hist_detail.sql` | 신규 | 이력 테이블 PK 구성·파티션 키 NULL·원본 DDL 실측 (읽기 전용) |
| `14_aimsc_precheck.sql` | 신규 | 재구축 전 안전 점검 — FK·의존객체·권한·NULL (읽기 전용) |
| `15_aimsc_hist_rebuild.sql` | 신규 | 이력 8개 파티션+로컬인덱스 재구축 **(변경 발생)** |
| `16_aimsc_synonym.sql` | 신규 | AIMSC_DEV 에 T_ITSE_CCTV_01M 시노님 추가 **(변경 발생)** |
| `17_aq_tables_ddl.sql` | 이식 | AQ 앱 테이블 15개 생성 DDL — 다른 DB 로 옮길 때 쓴다 **(변경 발생)** |

## 파일 동기화

스크립트는 맥에서 편집하고, 서버에서 실행하고, SQL은 컨테이너 안에서 돌아간다. 3단 경로를 `sync.sh` 로 오간다.

```
맥 ./              --up-->   서버 ~/alex/tibero7_ut/migration   --in-->   컨테이너 /tmp/tbmig
맥 ./results/    <--down--   서버 ~/alex/tibero7_ut/migration  <--out--   컨테이너 /tmp/tbmig
```

```bash
REMOTE=bamboos@192.168.0.101 DRYRUN=0 ./sync.sh push   # up + in  (배포)
REMOTE=bamboos@192.168.0.101 DRYRUN=0 ./sync.sh pull   # out + down (로그 회수)
```

기본값 `DRYRUN=1` 이라 `rsync -n` 으로 목록만 보여준다. 서버에서 직접 실행할 때는 `REMOTE=` 로 비운다.

전송 필터는 방향마다 다르다. **up** 은 `*.sh` `*.sql` `*.md` `*.yml` `*.html` 만 올리고 `--delete` 를 쓰지 않는다 — 서버에서 생성된 로그를 지우지 않기 위해서다. **down** 은 `*.log` `*_out_*.sql` `*_gen_*.sql` `*.txt` 만 `./results/` 로 받는다. 원본과 산출물이 섞이지 않는다.

## 확정된 이관 범위 (2026-08-10 소스 실측)

| 스키마 | 객체 | 용량 | 구성 |
|---|---|---|---|
| `AIMS_EX` | 117 | **954MB** | 테이블 101, 인덱스 16. 뷰·파티션 없음. BLOB 186MB |
| `AIMS_DEV` | 1,186 | 127MB | 테이블 158, 뷰 58, 시노님 101, 파티션 81, 패키지 1 |
| `AIMSC_DEV` | 1,174 | 104MB | 테이블 157, 뷰 53, 시노님 101, 파티션 81, 패키지 1 |
| 합계 | | **1,185MB** | |

`LBACSYS` 는 Tibero 라벨보안 시스템 계정이라 대상이 아니다.

**적재 순서는 `AIMS_EX` → `AIMS_DEV` → `AIMSC_DEV`** 다. `AIMS_DEV`/`AIMSC_DEV` 의 시노님 101개가 전부 `AIMS_EX` 의 동명 테이블을 가리키므로, 대상이 먼저 존재해야 한다. `ALL_SYNONYMS` 에 `DB_LINK` 컬럼 자체가 없어 **원격 참조는 없다** — 전부 같은 DB 안이다.

### 처음 파악과 달라진 점

DBeaver 덤프의 259개 파일은 **테이블 158개 + 시노님 101개**였다. 즉 파일 목록의 40%가 `AIMS_EX` 의 테이블을 시노님으로 본 것이고, 실데이터 대부분(954MB)이 `AIMS_EX` 에 있다. 처음 계획의 2개 스키마 범위로는 이관이 성립하지 않는다.

### 기준 스냅샷 (2026-08-10 실측, 검증의 기준값)

| 스키마 | 행 수 | 비고 |
|---|---|---|
| `AIMS_EX` | 약 450만 | 실질적으로 이관 작업의 전부 |
| `AIMS_DEV` | 약 1만 | 설정·코드성 데이터 위주 |
| `AIMSC_DEV` | **0** | 157개 테이블 전부 비어 있음 — 사실상 DDL만 옮기는 작업 |

`AIMS_EX` 상위: `T_TIPG_TBSP_STAT_01L` 879,615 · `T_TIPE_EMBR_STAT_01N` 835,460 · `T_TIPD_VDS_CWNO_HR_01S` 486,744 · `T_TIPB_LDS_STAT_01L` 295,568 · `T_TIPB_LCS_STAT_01L` 264,178 · `T_TIPG_DB_LOCK_01L` 242,360

**FK·UNIQUE·시퀀스가 0건이다.** 제약조건은 PK(158/157/7)와 NOT NULL 계열(`C`)뿐이다. 따라서 적재 순서 제약은 **시노님 대상인 `AIMS_EX` 선행** 하나뿐이고, `B1_out_3_fk.sql` / `B1_out_6_sequences.sql` 은 빈 파일이 된다.

`AIMS_EX` 는 테이블 101개 중 PK가 7개뿐이라, 적재 후 **건수 대조가 사실상 유일한 무결성 검증 수단**이다.

기준 파일: `02_baseline_meta.log`, `02_baseline_counts.log`(476개 테이블), `02_baseline_view_counts.log`(111개 뷰)

### 덤프 1.2GB × 2의 정체

두 덤프가 똑같이 1.2GB였던 이유는 **양쪽 모두 시노님을 통해 같은 `AIMS_EX` 데이터를 중복으로 담았기** 때문이다. `AIMSC_DEV` 덤프의 0byte 파일 165개 = 자기 테이블 157개(전부 빈 테이블) + 빈 시노님 대상 8개. 숫자가 정확히 맞는다.

### 경로 B2는 탈락

소스에 **RANGE 파티션 테이블이 162개** 있다. 딕셔너리 뷰만으로는 파티션 정의를 재현할 수 없다. `DBMS_METADATA` 는 정상 동작이 확인됐으므로 **경로 A(tbExport) 주력, B1 보조**로 간다. `B2` 는 참고용으로만 남긴다.

### Tibero 딕셔너리는 Oracle과 다르다

스크립트 작성 중 실제로 걸린 차이들:

| 뷰 | Tibero 실제 컬럼 | Oracle 기준 (없음) |
|---|---|---|
| `ALL_VIEWS` | `OWNER, VIEW_NAME, TEXT` | `TEXT_LENGTH` |
| `ALL_SYNONYMS` | `OWNER, SYNONYM_NAME, ORG_OBJECT_OWNER, ORG_OBJECT_NAME` | `TABLE_OWNER, TABLE_NAME, DB_LINK` |
| `ALL_DEPENDENCIES` | `OWNER, NAME, TYPE, PARENT_OBJ_OWNER, PARENT_OBJ_NAME, PARENT_OBJ_TYPE` | `REFERENCED_*` |
| `ALL_TAB_PARTITIONS` | `TABLE_OWNER` 없음 — 파티션 정보는 `ALL_PART_TABLES` 로 본다 | `TABLE_OWNER` |
| `ALL_TAB_PRIVS` | `TABLE_SCHEMA` 없음 | `TABLE_SCHEMA` |
| `DBMS_METADATA` | `GET_DDL('PACKAGE',...)` 불가 — 본문은 `ALL_SOURCE` 로 읽는다 | 동작 |
| 캐릭터셋 | `NLS_LANG_AT_BOOT` — **DB 캐릭터셋이 아니다** | `NLS_CHARACTERSET` |

tbsql / PSM 쪽 차이도 있다.

| 항목 | Tibero |
|---|---|
| `SET LONGCHUNKSIZE` | 거부한다 (`TBS-70003`). `SET LONG` 만 쓴다 |
| PL/SQL RECORD 생성자 | `t_rec(...)` 형태를 지원하지 않는다 (`TBR-15048`). 목록은 인라인 커서(`SELECT ... UNION ALL`)로 만든다 |
| `EXIT;` | 스크립트 끝에 없으면 `SQL>` 프롬프트에서 멈춘다 |

### 캐릭터셋 — 초기 판단을 뒤집은 사실

**소스 DB는 UTF8이 아니라 MSWIN949(CP949)다.**

처음에 `NLS_LANG_AT_BOOT=UTF8` 을 DB 캐릭터셋으로 읽었는데 이는 오판이었다. 그 값은 인스턴스 기동 시점의 클라이언트 NLS 이지 DB 캐릭터셋이 아니다. 소스와 UTF8로 만든 타겟이 이 값은 똑같은데 실제 저장 바이트는 달랐던 것이 결정적 증거다.

실측 근거:

- `tbexport` 가 매 실행마다 출력한 `Export character set: MSWIN949` — 접속한 DB의 실제 캐릭터셋이다
- 소스 `DUMP`: `신월여의지하도로종점` = **10자 / 20바이트**, `bd,c5,bf,f9,bf,a9,...` (CP949 2바이트 문자)

**결과**: UTF8 타겟에 적재하면 `tbimport` 가 CP949 → UTF-8 로 정상 변환하지만 **길이가 1.5배**가 된다. 한글 11자 = CP949 22바이트 → UTF-8 33바이트 → `VARCHAR(30 BYTE)` 초과. 실제로 4개 테이블이 이 오류로 부분 적재됐다(`T_TIPA_NODE_01M` 679/811 등).

전수 조사 결과 **VARCHAR/CHAR BYTE 컬럼 6,131개 중 2,469개**가 UTF-8 변환 시 정의 길이를 초과한다. 컬럼을 넓히는 대안은 성립하지 않는다.

**결론**: 타겟을 `CHAR_SET=MSWIN949` 로 재생성해 소스와 문자셋을 맞춘다. 변환이 없으므로 길이 초과가 사라지고 바이트 단위로 동일한 복제본이 된다. UT 환경은 운영과 같게 동작해야 한다.

부수적으로 확인된 것: `tbexport`/`tbimport` 에는 문자셋 파라미터가 없다. 캐릭터셋은 DB에서 결정되며 클라이언트 환경변수(`TB_NLS_LANG` 등)로 바꿀 수 없다.

### 한글 손상은 소스 원본 문제

`AIMS_EX.T_TIPA_VMS_SYBL_01I.SYBL_NM` 의 바이트가 `a8,f6,**3f**,a1,c6,**3f**,...` 다. CP949 대역 바이트에 `3f`(`?`)가 섞여 있다 — 소스 DB에 이미 일부 문자가 `?` 로 치환된 채 저장돼 있다. **DBeaver 추출 탓이 아니다.** 타겟도 MSWIN949 이므로 tbExport/tbImport 는 이 바이트를 변환 없이 그대로 옮긴다. 이관으로 인한 추가 손실은 없고, 원본 복구는 이 작업 범위 밖이다.

### 계정 롤도 소스와 맞춰야 한다

소스는 `AIMS_EX` / `AIMS_DEV` / `AIMSC_DEV` **세 계정 모두 `DBA`** 를 갖고 있다
(`dba_role_privs` 실측). `04b` 가 처음에 `CONNECT` / `RESOURCE` 만 줬더니, 타겟에서
`aims_dev` 로 접속했을 때 **`AIMSC_DEV` 스키마가 보이지 않았다.** 남의 스키마라
목록에 뜨지 않는 것이다.

앱 동작에는 지장이 없지만(자기 스키마와 시노님만 쓰므로) UT 는 운영과 같게 동작해야
한다. 권한이 다르면 "소스에선 되는데 UT에선 안 되는" 현상을 디버깅하게 된다.

`04b` 와 `09` 에 `GRANT DBA` 를 넣었다. `EXP_FULL_DATABASE` / `SELECT_CATALOG_ROLE` /
`SCHEDULER_ADMIN` 은 `DBA` 에 딸려 오므로 따로 줄 필요가 없다.

기존에 만든 타겟에는 수동으로 부여한다.

```bash
docker exec -i tibero7_ut_tablename bash -lc 'tbsql -s sys/tibero123' <<'EOF'
GRANT DBA TO AIMS_EX;
GRANT DBA TO AIMS_DEV;
GRANT DBA TO AIMSC_DEV;
EXIT;
EOF
```

1차 UT(18629)도 같은 상태다. 필요하면 `CONTAINER=tibero7_ut` 로 동일하게 부여한다.

## DB 구조

> 그림 버전: [`db-structure.html`](db-structure.html) — 브라우저로 열면 된다.
> 게시본: https://claude.ai/code/artifact/7044ce1d-d7aa-4d2a-ba3c-87dae6fbc548

세 스키마는 대등하지 않다. **업무 스키마 2개가 원천 스키마 1개를 참조하는 형태**다.
이 구조를 모르면 테이블을 추가해도 앱에서 보이지 않고, 이관 범위를 잘못 잡는다.

```
                        앱 / DBeaver
                             │
              ┌──────────────┴──────────────┐
              ▼                             ▼
   ┌────────────────────┐        ┌────────────────────┐
   │ AIMS_DEV    127MB  │        │ AIMSC_DEV   104MB  │   업무 스키마
   │ 테이블 158         │        │ 테이블 157 (0행)   │
   │ 뷰 58              │        │ 뷰 53              │
   │ 파티션 81          │        │ 파티션 81          │
   │ 시노님 101 ────┐   │        │ 시노님 101 ────┐   │
   └────────────────┼───┘        └────────────────┼───┘
                    │                             │
                    └──────────────┬──────────────┘
                                   ▼
                    ┌──────────────────────────┐
                    │ AIMS_EX          954MB   │   원천 스키마
                    │ 테이블 101 · 약 450만 행 │
                    │ BLOB 195MB · PK 7        │
                    │ 뷰 0 · 시노님 0          │
                    └──────────────────────────┘
```

화살표는 시노님이 가리키는 방향이고, 데이터는 반대로 흐른다.

**이름 규칙이 소속을 말해준다.** `T_AAAA_*` · `T_AAAB_*` 는 업무 스키마의 자체 테이블,
`T_TIP*` · `IAM_*` · `ITWM_*` 는 `AIMS_EX` 의 원천 테이블이다. 앱에서
`AIMS_DEV.T_TIPA_CCTV_01M` 을 조회해도 실체는 `AIMS_EX` 에 있다.

### 실데이터 위치

| 스키마 | 용량 | 행 | 성격 |
|---|---:|---:|---|
| **`AIMS_EX`** | **954MB** | **약 450만** | 실질적으로 데이터의 전부. CCTV·VMS·터널·검지기 등 현장 수집 이력 |
| `AIMS_DEV` | 127MB | 약 1만 | 설정·코드성 데이터 위주 (메뉴, 권한, 공통코드, 점검계획) |
| `AIMSC_DEV` | 104MB | 0 | 157개 테이블 전부 비어 있음. 구조만 존재 |

`AIMSC_DEV` 가 0행인데도 104MB인 것은 세그먼트가 할당돼 있기 때문이다. 뷰를 조회하면
값이 나오는데, **자기 데이터가 아니라 시노님을 통해 `AIMS_EX` 를 보고 있어서**다.

### 조회 경로

앱이 뷰 하나를 조회할 때 실제로 거치는 층.

```
AIMS_DEV.V_AAAA_CCTV_STAT01L    상태 뷰 — 앱이 호출
        ↓ 참조
AIMS_DEV.V_AAAA_CCTV01M         장비 마스터 뷰 — 뷰가 뷰를 참조
        ↓ 참조
AIMS_DEV.T_TIPA_CCTV_01M        시노님 — 실체 없음, 가리키기만 함
        ↓ 가리킴
AIMS_EX.T_TIPA_CCTV_01M         실테이블 15,243행  ← 데이터는 여기
```

시노님은 **이름만 빌려주는 포인터**다. 저장 공간도 데이터도 갖지 않는다. 덕분에 앱은
스키마를 하나만 알면 된다. 대신 **권한이 반드시 따라와야 한다** — 시노님이 있어도
`AIMS_EX` 객체에 `SELECT` 권한이 없으면 조회가 실패한다. 이관 시 `tbimport GRANT=Y` 로
소스의 객체 권한을 그대로 옮긴 이유다.

### 뷰 구성

`AIMS_DEV` 58개 / `AIMSC_DEV` 53개 / `AIMS_EX` **0개**. 원천 스키마에는 뷰가 없다.

뷰끼리의 참조가 **87건** 있고 두 층으로 나뉜다.

| 층 | 이름 패턴 | 역할 |
|---|---|---|
| 1층 | `V_..._01M` | 장비 마스터. 시노님(원천 테이블)을 감싸 업무 관점으로 정리 |
| 2층 | `V_..._01L` / `_01S` | 상태·이력·집계. 1층 뷰를 참조 |

`V_AAAA_FILD_EQPM01M` 이 팬인(fan-in) 지점이다. 장비 종류별 1층 뷰 **12개**(CCTV, VMS,
VDS, AVC, VSL, LCS, EMBR, WIM, IOT, UTLPH, RADR_SNSR, DSR_MCU)를 하나로 묶는다.
이 뷰가 깨지면 `V_AAAA_BRDW_PROS01L`, `V_AAAA_ISPC_PLAN01L` 까지 연쇄로 무효가 된다.
이관 직후 무효 뷰가 109개였다가 재컴파일 한 번에 0이 된 것도 이 의존 사슬 때문이다.

### DDL 이 없던 이유는 시노님이 아니다

처음 받은 DBeaver 덤프에서 관측된 세 현상은 원인이 각각 다르다.

| 관측 | 실제 원인 | 시노님과 관계 |
|---|---|---|
| DDL 이 하나도 없음 (259개 파일 전부 INSERT) | DBeaver 가 **데이터만** 익스포트하도록 설정됐다. 전 테이블 공통 | 무관 |
| 파일 259개 ≠ 테이블 158개 | DBeaver 트리가 **시노님도 테이블처럼** 보여준다. 158 + 101 = 259 | **이것이 시노님** |
| 0 byte 파일 128개 | 해당 테이블에 **행이 없어서**다 | 무관 |

시노님이 실제로 문제였던 지점은 따로 있다. **덤프 2벌이 똑같이 1.2GB였던 이유**가 그것이다.
양쪽 덤프가 각자의 시노님을 통해 **같은 `AIMS_EX` 데이터를 중복으로** 담고 있었다.

### 왜 이렇게 구성했나

**수집계와 업무계를 스키마로 분리**한 구조다.

| 스키마 | 맡는 일 | 쓰기 주체 |
|---|---|---|
| `AIMS_EX` | 현장 장비·외부 시스템에서 들어온 원천 데이터 적재 | 수집 배치 / 연계 인터페이스 |
| `AIMS_DEV` | 업무 로직 — 고장판단, 점검계획, 결재, 권한, 공통코드 | AIMS 애플리케이션 |
| `AIMSC_DEV` | 동일 구조의 사본 (현재 데이터 없음) | — |

분리하면 수집 부하와 업무 트랜잭션이 간섭하지 않고 원천 데이터의 소유·권한을 따로 관리할
수 있다. 그러면서도 **시노님 덕분에 앱은 스키마가 하나인 것처럼** 쿼리를 쓰고, 뷰가 그 위에서
원천 테이블을 업무 용어로 번역한다.

구조상 특이한 점 둘 — **FK 0건**, **`AIMS_EX` 의 PK 가 101개 중 7개**. 대량 적재 성능을 위해
제약을 DB 가 아니라 애플리케이션에 둔 설계로 보인다. 시퀀스도 0건이라 키 생성도 앱이 한다.

### 테이블 추가·수정 시 유의점

**1. `AIMS_EX` 에 테이블을 추가하면 시노님도 만들어야 한다.**
테이블만 만들면 앱에서 보이지 않는다. `AIMS_DEV`·`AIMSC_DEV` 양쪽에 `CREATE SYNONYM` 과
`GRANT` 를 함께 해야 한다. 기존 101개도 전부 이 짝을 이루고 있다.

**2. 권한 없이는 시노님이 동작하지 않는다.**
시노님은 이름만 가리킬 뿐 권한을 주지 않는다. 조회 시 "테이블이 없다"가 아니라 권한
오류로 나타나 원인을 놓치기 쉽다.

**3. 원천 테이블 컬럼을 바꾸면 위층 뷰가 무효화된다.**
시노님은 포인터라 자동으로 따라오지만 그 위 1층·2층 뷰는 `INVALID` 가 된다. 뷰→뷰 참조가
87건이라 연쇄로 번진다. 변경 후 `07_recompile_invalid.sql` 로 재컴파일하고 무효 객체 0을
확인할 것.

**4. 문자셋이 MSWIN949 — 한글 1자가 2바이트다.**
`VARCHAR2(30)` 은 **한글 15자**다. UTF-8 기준(10자)으로 설계하면 안 된다. 반대로 이 DB를
UTF-8로 옮기면 길이가 1.5배가 되어 **6,131개 컬럼 중 2,469개가 정의 길이를 초과**한다.

**5. PK 가 없으니 중복 방지는 앱 책임이다.**
`AIMS_EX` 는 101개 중 7개만 PK 가 있고 FK 는 전 스키마 0건이다. 이관 검증이 건수 대조에
의존하는 것도 이 때문이다.

**6. 파티션 테이블 162개는 패키지가 관리한다.**
RANGE 파티션 578개가 `AIMS_DEV`·`AIMSC_DEV` 에 있고 `P_AAAA_PRTT_TBL_MGMT` 패키지가 이를
다룬다. 파티션 테이블을 추가하거나 기간을 늘릴 때는 이 패키지의 대상 목록도 함께 확인할 것.

**7. UT DB 를 갱신하면 로컬 변경은 사라진다.**
`09_refresh.sh` 는 전량 교체다. UT 중 입력한 테스트 데이터와 타겟에만 추가한 객체는 남지 않는다.

## VIEW 처리

이관 대상에 뷰가 포함된다. 뷰는 테이블과 다른 두 가지 문제가 있어 따로 다룬다.

1. **의존 순서** — 뷰가 다른 뷰를 참조하면 생성 순서를 보장할 수 없다. 그래서 `CREATE OR REPLACE **FORCE** VIEW` 로 일단 전부 만들고, 마지막에 `07_recompile_invalid.sql` 로 반복 재컴파일해 해소한다.
2. **정의문이 LONG 타입** — `ALL_VIEWS.TEXT` 는 LONG 이라 SQL 문자열 연결이 불가능하다. `B2` 는 PL/SQL 로 읽는데 **32767자를 넘는 뷰는 추출에 실패**한다. 어떤 뷰가 해당되는지는 `01_source_check.sql` 의 `text_length` 정렬 결과로 미리 알 수 있고, 그런 뷰는 `B1`(DBMS_METADATA) 이나 수동으로 뽑아야 한다.

또 딕셔너리에는 SELECT 본문만 저장되므로, `B2` 는 `ALL_TAB_COLUMNS` 에서 뷰 컬럼 목록을 읽어 `CREATE VIEW v (컬럼목록) AS ...` 형태로 붙인다. 이렇게 해야 뷰 컬럼 별칭이 보존된다.

검증은 개수뿐 아니라 **실제 조회**까지 한다 — `05_verify.sql` 이 모든 뷰에 `SELECT ... WHERE ROWNUM<=1` 을 던져 컴파일만 통과하고 조회에서 깨지는 경우를 잡는다.

## 실행 순서

### Phase 0 — 환경 확인 (되돌릴 것 없음)

```bash
./00_env_check.sh tibero7_ut 121.137.106.217 58629
```

**확인된 환경** (2026-08-10 실행 결과)

| 항목 | 값 |
|---|---|
| 작업 컨테이너 | `tibero7_ut` / `tiberoofficial/tibero:latest` (호스트 포트 18629) |
| TB_HOME | `/opt/tibero7`, edition = standard |
| 유틸리티 | `tbexport` / `tbimport` **7.2** 존재 → **경로 A 가능** |
| 타겟 DB | 컨테이너 내부 `localhost:8629`, DB_NAME=**`TAIMS`** |
| 캐릭터셋 | 소스·타겟 모두 **MSWIN949** (아래 "캐릭터셋 — 초기 판단을 뒤집은 사실" 참고) |
| 소스 | `121.137.106.217:58629/TAIMS`, Tibero 7.2 |
| 디스크 | 2.5T 여유 (충분) |
| ⚠ 라이선스 | **2026-08-19 만료** (30일 데모). 이후 사용하려면 갱신 필요 |

> **이관 작업은 `tibero7_ut` 컨테이너 "안에서" 수행한다.** 타겟이 자기 자신이라 `localhost:8629`
> 로 닿고, 소스는 외부 IP 라 그대로 닿는다. `tibero7` 컨테이너에서 실행하면 `localhost` 가
> 자기 자신을 가리켜 타겟에 도달하지 못한다.

> **주의**: `tbexport`/`tbimport` 는 tbdsn DSN을 쓰지 않는다. `IP` / `PORT` / `SID` 파라미터로 직접 접속하고, 문법은 `parameter=value` 나열식이다. `03_export_import.sh` 는 이 문법으로 작성돼 있다.
>
> 다만 `tbsql` (01/02/05 스크립트 실행용)은 DSN이 필요할 수 있다. `tbsql user/pass@IP:PORT:SID` 형식이 안 되면 아래처럼 등록한다.

**소스 접속 정보 (확정)**

| 항목 | 값 |
|---|---|
| HOST | `121.137.106.217` |
| PORT | `58629` |
| SID (DB_NAME) | `TAIMS` |

`$TB_HOME/client/config/tbdsn.tbr` 에 `SRC` DSN을 추가하고 접속을 확인한 뒤:

```bash
./03_export_import.sh dsn            # DRYRUN — 추가될 내용 확인
DRYRUN=0 ./03_export_import.sh dsn   # 실제 등록 (.bak 백업 후)
```

타겟은 `gen_tip.sh` 가 만든 `TAIMS` 항목을 그대로 쓴다.

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



## 전량 재적재 (`09_refresh.sh`)

### 이 스크립트가 하는 일

**타겟 스키마를 통째로 버리고, 소스의 특정 시점 모습으로 다시 만든다.** 차이만 반영하는
동기화가 아니라 **전량 교체**다. 실행이 끝나면 타겟은 "추출 시점(`CONSISTENT=Y` 스냅샷)의
소스와 동일한 상태"가 된다.

그 말은 곧 아래가 **전부 사라진다**는 뜻이다.

- UT 중 타겟에 입력·수정한 테스트 데이터
- 타겟에만 추가한 객체 (인덱스, 임시 테이블, 뷰 등)
- 타겟에서 바꾼 계정 비밀번호 → `schema_pw()` 값(계정명과 동일)으로 재설정된다

반대로 얻는 것.

- 소스의 **DDL 변경**(컬럼·테이블 추가/삭제)이 자동으로 따라온다
- 결과가 **건수로 증명**된다 — 불일치하면 비정상 종료
- 부분 적재나 누적 오염이 남지 않는다. 매번 같은 출발점

**실행 중 해당 스키마가 비어 있는 구간이 생긴다** (DROP 직후 ~ 적재 완료). 앱이 붙어 있으면
그 시간 동안 오류가 난다. 사용자가 없는 시간에 돌릴 것.

**되돌리기는 없다.** 직전 상태로 복원하려면 그 시점의 덤프가 필요한데 `work/` 에는 마지막
추출본만 남는다. 중요한 시점이 있으면 `work/*.dat` 을 따로 복사해 두면 된다.

### 왜 전량 재적재인가

증분 동기화는 이 DB 구조에서 성립하지 않는다.

- `AIMS_EX` 는 테이블 101개 중 **PK 가 7개** — 변경분을 식별할 키가 없다
- **FK 0건** — 누락을 잡아낼 참조 무결성이 없다
- 변경 추적 컬럼이 일관되지 않고, 삭제된 행은 추적 불가

증분으로 가면 "동기화됐다"를 증명할 수단이 없다. 반면 전량 재적재는 실측 15분이면 끝나고
결과가 건수로 증명된다(추출 13분 + 적재 2분).

`TRUNCATE` 가 아니라 **`DROP USER CASCADE` → 재생성**을 쓴다. 소스가 개발 DB 라 컬럼·테이블이
늘어날 수 있는데 TRUNCATE 방식은 DDL 변경을 반영하지 못한다. 테이블스페이스는 유지되므로
`04b` 를 다시 돌릴 필요는 없다.

### 사용

```bash
./09_refresh.sh                                  # 계획만 출력 (DRYRUN)
DRYRUN=0 ./09_refresh.sh                         # 전량 (소스 추출부터, 약 15분)
DRYRUN=0 ./09_refresh.sh --skip-export           # 기존 덤프로 재적재만 (약 3분)
DRYRUN=0 SCHEMAS="AIMS_DEV" ./09_refresh.sh      # 특정 스키마만
```

**종료 코드 0 = 건수 전량 일치**, 그 외는 실패다.

### 실패로 끊는 지점

- 컨테이너 미기동 / 소스 미도달
- **라이선스 만료** — 만료 시 중단, 7일 이내면 경고
- `TBR-11048`(컬럼 길이 초과) — 타겟 캐릭터셋이 MSWIN949 가 아니라는 신호
- 건수 불일치
- 뷰 조회 실패

`flock` 으로 중복 실행을 막는다(없는 환경에서는 경고 후 진행).

### 추출 시간을 줄이려면

`EXCLUDE_TABLES` 로 이력성 대형 테이블을 뺀다. 상위 4개만 빼도 4.8M행 중 2.4M행이 줄고,
`T_TIPA_VMS_SYBL_01I`(BLOB 195MB)를 빼면 **추출 13분이 1~2분으로** 떨어진다.

```
T_TIPA_VMS_SYBL_01I    BLOB 195MB — 추출 시간의 대부분
T_TIPG_TBSP_STAT_01L   879,615행
T_TIPE_EMBR_STAT_01N   835,460행
T_TIPD_VDS_CWNO_HR_01S 486,744행
T_TIPG_DB_LOCK_01L     242,360행
```

단 `tbexport EXCLUDE` 의 문법은 이 버전에서 아직 검증하지 않았다. 켜기 전에 소량으로 확인할 것.
`tbimport EXCLUDE_TABLE` 은 도움말에 명시돼 있어 더 안전하다(추출 시간은 줄지 않는다).

### 검토했으나 채택하지 않은 것

- **DB Link + MERGE** — PK 가 없어 병합 기준을 잡을 수 없다. 인터넷 구간으로 4.8M행을 당기는 것도 tbexport 보다 느리다
- **Tibero 복제 솔루션** — 실시간 동기화용. UT 환경에 별도 라이선스 비용을 쓸 이유가 없다

### 검증 이력

`AIMSC_DEV`(157 테이블 / 53 뷰 / 101 시노님, 0행) 단독으로 전 단계를 실행해 확인했다 —
초기화, 적재(`TBR-11048` 0건), 뷰 재컴파일, **부분 스키마 대조 157/157**, 정상 종료.
다른 두 스키마는 영향받지 않았다.

부분 스키마로 돌릴 때 `05_gen_counts.sql` 은 3개 스키마가 고정돼 있어 항상 416개를 센다.
`09` 가 대상 스키마만 걸러 `09_target_counts_subset.log` 로 대조하는 이유다.

### 로그 마스킹

`09` 의 출력은 `refresh_*.log` 로 그대로 남으므로, 접속 비밀번호와 스키마 계정 비밀번호를
화면·로그에서 지운다. 명령 문자열(`mask`)과 표준출력 스트림(`mask_stream`) 양쪽에 적용된다.

```
cd /tmp/tbmig && tbsql sys/******** @07_recompile_invalid.sql
CREATE USER AIMS_DEV IDENTIFIED BY "********" DEFAULT TABLESPACE TS_AIMS_DATA;
```

계정명(`AIMS_DEV`)과 비밀번호(`aims_dev`)는 대소문자가 달라 치환이 겹치지 않는다. 다만
접속 계정명이 비밀번호와 같은 문자열이면 계정명도 함께 가려진다 — 판독에는 지장이 없다.

## 실행 중 걸린 것들 (재현 시 참고)

| 증상 | 원인 | 대응 |
|---|---|---|
| `Mode confliction` | `tbexport` 의 `FULL`/`USER`/`TABLE` 은 상호 배타적 모드 | 테이블 단위는 `TABLE=스키마.테이블` 만 |
| tbsql 실행 후 터미널 멈춤 | 스크립트 끝에 `EXIT;` 없어 프롬프트 대기 | 모든 `.sql` 과 **생성되는 스크립트**에 `EXIT;` |
| `TBS-70003` (host:port:sid) | `tbsql` 은 DSN만 받음 | `tbdsn.tbr` 에 등록 (`03 dsn`). tbexport/tbimport 는 DSN 불필요 |
| `--sysdba` 옵션 없음 | tbsql 에 해당 옵션 자체가 없음 | DSN 없이 `tbsql sys/<pw>` 로 로컬 접속 |
| `TBR-11048` 길이 초과 | UTF8 타겟에서 CP949→UTF-8 변환으로 길이 1.5배 | 타겟을 MSWIN949 로 재생성 |
| 건수가 아침 기준값과 불일치 | 소스가 가동 중이라 로그성 테이블이 증가 | `08_expected_from_exportlog.sh` 로 추출 시점 기준값 사용 |
| `echo "A;B;"` 한 줄 실행 실패 | tbsql 은 문장 사이 개행 필요 | heredoc 사용 (`<<'EOF'`) |
| 컨테이너 재생성 시 덤프 소실 | `/tmp/tbmig` 가 볼륨이 아니었음 | compose 에 `./work:/tmp/tbmig` 추가 |
