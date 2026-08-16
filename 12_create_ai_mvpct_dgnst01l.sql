-- 신규 테이블 생성: AIMS_DEV.T_ITSE_AI_MVPCT_DGNST01L
--   AI 영상화질 진단 이력 (파티션 + 로컬 인덱스)
--
-- 실행:
--   docker exec -it tibero7_ut_tablename bash -lc \
--     'cd /tmp/tbmig && tbsql aims_dev/aims_dev @12_create_ai_mvpct_dgnst01l.sql'
--
-- ** 이 DDL 은 설계한 것이 아니라 기존 형제 테이블을 본뜬 것이다. **
--   원본: AIMS_DEV.T_ITSE_AI_BRDW_JDG01L  (DBMS_METADATA.GET_DDL 로 추출)
--   같은 계열: T_ITSE_AI_BRDW_DETL01L / T_ITSE_AI_FETR_ANLY01L
--
-- 확인된 관례 (2026-08-16 실측)
--   파티션      RANGE, **월 단위**. 이름 P<YYYYMM> + 마지막에 PMAX (MAXVALUE)
--               경계는 TO_DATE('YYYYMMDD','YYYYMMDD') 형식
--   파티션 키   TIMESTAMP(6), NOT NULL
--   PK          (업무ID, 파티션키) **복합키**. 이름은 PK_ + 테이블명에서 T_ 를 뗀 것
--               -> 로컬 유니크 인덱스. Tibero/Oracle 은 로컬 유니크 인덱스에
--                  파티션 키가 반드시 포함되어야 하므로 복합키가 강제된다
--   보조 인덱스 IX + 2자리 순번 + 테이블명에서 T_ 를 뗀 것 (언더스코어 없음)
--               예: IX01ITSE_AI_BRDW_JDG01L
--               **비유니크 로컬 인덱스는 파티션 키를 붙이지 않는다** (형제 테이블 확인)
--   테이블스페이스  테이블 TS_AIMS_HIST_DATA / 인덱스 TS_AIMS_HIST_IDX
--
-- 원 요청안에서 바꾼 것
--   1. AI_DGNST_DTTM  DATE -> TIMESTAMP(6) NOT NULL   (파티션 키. 관례 + NULL 불가)
--   2. PK 를 단일키 -> 복합키 (AI_MVPCT_DGNST_ID, AI_DGNST_DTTM)
--      => AI_MVPCT_DGNST_ID 단독 유일성은 DB 가 보장하지 않는다.
--         애플리케이션이 UUID 를 생성하므로 실무상 문제는 없으나 명시해 둔다.
--   3. VARCHAR -> VARCHAR2 (Tibero 내부 표기. 동작 동일)
--
-- 파티션은 2026-08 / 2026-09 두 달 + PMAX 로 시작한다 (형제 테이블과 동일).
--
-- ** 월별 파티션 자동 추가는 현재 동작하지 않는다 (2026-08-16 확인) **
--   P_ITSE_PRTT_TBL_MGMT.sp_manage_partiton 이 담당하지만, 대상을 설정 테이블
--   T_ITSE_DATA_BCKP_STUP01P 에서 읽는데 그 테이블이 **0행**이다.
--   이름 규칙이나 전수 순회가 아니라 명시적 등록 방식이라, 등록 전에는 무동작이다.
--   형제 테이블들의 P202608/P202609 도 이 잡이 만든 게 아니라 생성 DDL 에 있던 것이다.
--
--   등록하지 않아도 깨지지 않는다 — 2026-10-01 이후 데이터는 PMAX 가 전부 받는다.
--   조회·입력 정상이고 파티션 프루닝 이득만 줄어든다. 형제 테이블도 같은 처지다.
--
--   보관 정책이 정해지면 아래 한 줄로 등록한다. 단 sp_drop_part 는 보관 기간이
--   지난 파티션을 DROP PARTITION 한다 — 백업이 아니라 **영구 삭제**다.
--
--     INSERT INTO AIMS_DEV.T_ITSE_DATA_BCKP_STUP01P
--       (TBL_NM, DATA_KPNG_MNTHS_CNT, DATA_PRTT_CLMN_TYPE_CD, DATA_PRTT_CLMN_FRMT,
--        TBSP_NM, PRTT_TBL_NM, LSTTM_MODFR_ID, LSTTM_ALTR_DTTM)
--     VALUES
--       ('T_ITSE_AI_MVPCT_DGNST01L', <보관개월>, 'D', NULL,
--        'TS_AIMS_HIST_DATA', NULL, USER, SYSDATE);
--
--   'D'=DATE형 키, PRTT_TBL_NM=NULL 이면 접미사 없는 P202608 형태.
--   DATA_PRTT_CLMN_FRMT 는 문자형('C')일 때만 쓰이므로 NULL.
--   등록해도 sp_manage_partiton 을 호출하는 스케줄 잡이 없으면 여전히 무동작이다.
--
-- ** 인덱스를 LOCAL 로 만들어야 하는 또 하나의 이유 **
--   sp_rebuild_part_index 는 USER_IND_PARTITIONS 만 보고 재구축한다. 즉 로컬
--   인덱스 파티션만 손댄다. GLOBAL 인덱스는 SPLIT PARTITION 때 통째로 UNUSABLE
--   이 되는데 이 프로시저가 건드리지 않아 죽은 채 방치된다.

SET LINESIZE 200
SET PAGESIZE 200

PROMPT ================================================================
PROMPT [1] 테이블 생성 (RANGE 파티션)
PROMPT ================================================================

CREATE TABLE "AIMS_DEV"."T_ITSE_AI_MVPCT_DGNST01L"
(
    "AI_MVPCT_DGNST_ID"        VARCHAR2(36)   NOT NULL,
    "AI_DGNST_DTTM"            TIMESTAMP(6)   NOT NULL,
    "JDG_NRML_YN"              VARCHAR2(1),
    "MVPCT_ERR_CTNT"           VARCHAR2(1000),
    "AI_DGNST_ID"              VARCHAR2(36)   NOT NULL,
    "CCTV_ID"                  VARCHAR2(12)   NOT NULL,
    "DGNST_RSLT_FILE_PATH"     VARCHAR2(2000) NOT NULL,
    "DGNST_TRGT_IMG_FILE_PATH" VARCHAR2(2000) NOT NULL,
    "DGNST_RLBLT_RT"           NUMBER(5,2)    NOT NULL,
    "EXMN_YN"                  CHAR(1)        NOT NULL,
    "FLPS_YN"                  VARCHAR2(1)
)
TABLESPACE "TS_AIMS_HIST_DATA"
PARTITION BY RANGE("AI_DGNST_DTTM")
(
    PARTITION "P202608" VALUES LESS THAN (TO_DATE('20260901','YYYYMMDD')) TABLESPACE "TS_AIMS_HIST_DATA",
    PARTITION "P202609" VALUES LESS THAN (TO_DATE('20261001','YYYYMMDD')) TABLESPACE "TS_AIMS_HIST_DATA",
    PARTITION "PMAX"    VALUES LESS THAN (MAXVALUE)                       TABLESPACE "TS_AIMS_HIST_DATA"
);

PROMPT
PROMPT ================================================================
PROMPT [2] PK — 로컬 유니크 인덱스를 먼저 만들고 제약조건이 그것을 쓰게 한다
PROMPT ================================================================
--
-- 인라인 "USING INDEX LOCAL" 대신 2단계로 나눈 이유:
--   형제 테이블의 실제 객체 구성이 이 형태다(인덱스와 제약조건이 같은 이름으로 분리).
--   인라인 구문의 Tibero 수용 여부는 검증하지 않았고, 이 방식은 확실하다.

CREATE UNIQUE INDEX "AIMS_DEV"."PK_ITSE_AI_MVPCT_DGNST01L"
    ON "AIMS_DEV"."T_ITSE_AI_MVPCT_DGNST01L" ("AI_MVPCT_DGNST_ID", "AI_DGNST_DTTM")
    TABLESPACE "TS_AIMS_HIST_IDX" LOCAL
(
    PARTITION "P202608" TABLESPACE "TS_AIMS_HIST_IDX",
    PARTITION "P202609" TABLESPACE "TS_AIMS_HIST_IDX",
    PARTITION "PMAX"    TABLESPACE "TS_AIMS_HIST_IDX"
);

ALTER TABLE "AIMS_DEV"."T_ITSE_AI_MVPCT_DGNST01L"
    ADD CONSTRAINT "PK_ITSE_AI_MVPCT_DGNST01L"
    PRIMARY KEY ("AI_MVPCT_DGNST_ID", "AI_DGNST_DTTM");

PROMPT
PROMPT ================================================================
PROMPT [3] 보조 로컬 인덱스
PROMPT ================================================================
--
-- ** 이 두 개는 추정이다. ** 형제 테이블은 조회 키 하나에만 인덱스를 걸었다.
--   IX01 CCTV_ID       — CCTV 별 진단 이력 조회를 가정
--   IX02 AI_DGNST_ID   — 진단 마스터와의 조인을 가정
-- 실제 쿼리 패턴과 맞지 않으면 지울 것. 안 쓰는 인덱스는 적재만 느리게 한다.

CREATE INDEX "AIMS_DEV"."IX01ITSE_AI_MVPCT_DGNST01L"
    ON "AIMS_DEV"."T_ITSE_AI_MVPCT_DGNST01L" ("CCTV_ID")
    TABLESPACE "TS_AIMS_HIST_IDX" LOCAL
(
    PARTITION "P202608" TABLESPACE "TS_AIMS_HIST_IDX",
    PARTITION "P202609" TABLESPACE "TS_AIMS_HIST_IDX",
    PARTITION "PMAX"    TABLESPACE "TS_AIMS_HIST_IDX"
);

CREATE INDEX "AIMS_DEV"."IX02ITSE_AI_MVPCT_DGNST01L"
    ON "AIMS_DEV"."T_ITSE_AI_MVPCT_DGNST01L" ("AI_DGNST_ID")
    TABLESPACE "TS_AIMS_HIST_IDX" LOCAL
(
    PARTITION "P202608" TABLESPACE "TS_AIMS_HIST_IDX",
    PARTITION "P202609" TABLESPACE "TS_AIMS_HIST_IDX",
    PARTITION "PMAX"    TABLESPACE "TS_AIMS_HIST_IDX"
);

PROMPT
PROMPT ================================================================
PROMPT [4] 생성 결과 확인
PROMPT ================================================================

COL index_name FORMAT A32
COL uniqueness FORMAT A10
COL partitioned FORMAT A11
COL tablespace_name FORMAT A20

PROMPT -- 인덱스: PARTITIONED 가 전부 YES 여야 로컬이다. PK 는 UNIQUE.
SELECT index_name, uniqueness, partitioned, tablespace_name
  FROM all_indexes
 WHERE table_owner = 'AIMS_DEV'
   AND table_name  = 'T_ITSE_AI_MVPCT_DGNST01L'
 ORDER BY index_name;

PROMPT
PROMPT -- 파티션 키
COL name FORMAT A32
COL column_name FORMAT A24
SELECT name, column_name, column_position
  FROM all_part_key_columns
 WHERE owner = 'AIMS_DEV'
   AND name  = 'T_ITSE_AI_MVPCT_DGNST01L'
 ORDER BY column_position;

PROMPT
PROMPT -- PK 제약조건
COL constraint_name FORMAT A32
COL status FORMAT A10
SELECT constraint_name, constraint_type, status
  FROM all_constraints
 WHERE owner = 'AIMS_DEV'
   AND table_name = 'T_ITSE_AI_MVPCT_DGNST01L'
 ORDER BY constraint_name;

PROMPT
PROMPT ================================================================
PROMPT 참고 — 2026-10 이후 데이터는 PMAX 파티션에 쌓인다.
PROMPT   월별 파티션 자동 추가 잡(P_ITSE_PRTT_TBL_MGMT)의 설정 테이블
PROMPT   T_ITSE_DATA_BCKP_STUP01P 가 0행이라 현재 무동작이다. 형제 테이블도 같다.
PROMPT   동작에는 문제가 없다. 등록 방법은 이 파일 상단 주석 참조.
PROMPT ================================================================

-- tbsql 이 SQL> 프롬프트에서 대기하지 않도록 반드시 종료한다.
EXIT;
