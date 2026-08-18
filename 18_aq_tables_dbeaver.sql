-- ============================================================================
--  AQ 앱 테이블 15개 — 원천 공동작업 DB 생성용 DDL  (DBeaver 실행)
--  대상: 121.137.106.217:58629 / TAIMS / 스키마 AIMSC_DEV
--  출처: 2차 UT(28629) AIMSC_DEV 의 실측 구성 (2026-08-18)
-- ============================================================================
--
--  ** 여러 사람이 함께 쓰는 DB 다. 필요한 블록만 골라서 실행할 것. **
--
--  이 파일에는 DROP 이 한 줄도 없다. 순수 추가만 한다.
--  각 블록은 독립적이다 — FK 가 없어 생성 순서에 제약이 없다.
--  다만 시노님 3개는 AIMS_EX 에 대상 테이블이 있어야 한다.
--
--  스키마가 다르면 "AIMSC_DEV." 를 찾아 바꾸면 된다.
--
-- ----------------------------------------------------------------------------
--  실행 전 확인 (아래를 먼저 돌려 볼 것)
-- ----------------------------------------------------------------------------
--
--  1) 이름이 이미 쓰이고 있는가 — 나오는 것은 만들지 말 것
--
--     LIKE 로 훑으면 안 된다. 원천 AIMS_DEV 에는 T_ITSE_AI_BRDW_*,
--     T_ITSE_AI_FETR_ANLY01L, T_ITSE_AI_INFER_JOB01L 등 무관한 AI 테이블이
--     이미 많고, TABLE PARTITION 행까지 섞여 결과를 못 읽는다. 이름을 정확히
--     찍고 파티션 행은 제외한다.
--
--     SELECT object_name, owner, object_type, status
--       FROM all_objects
--      WHERE object_type <> 'TABLE PARTITION'
--        AND object_name IN (
--            'T_ITSE_AI_CCTV01M','T_ITSE_AI_MODL01M','T_ITSE_DATST01M',
--            'T_ITSE_SNSH_STUP01M','T_ITSE_SNSH_GTHR01L','T_ITSE_SNSH_PRPG01L',
--            'T_ITSE_LBLL01L','T_ITSE_ANNT01L','T_ITSE_AI_DGNST01L',
--            'T_ITSE_AI_MVPCT_DGNST01L','T_ITSE_AI_DRF_DGNST01L',
--            'T_ITSE_AI_MODL_OP01L',
--            'T_ITSE_CCTV_01M','T_ITSE_HDQR_01M','T_ITSE_MTNOF_01M')
--      ORDER BY object_name, owner;
--
--  2) 테이블스페이스가 있는가 — 넷 다 나와야 한다
--     (2026-08-18 원천 실측: DATA 20GB / HIST_DATA 20GB / HIST_IDX 10GB / IDX 10GB.
--      UT 보다 훨씬 크다. 용량은 문제되지 않는다)
--
--     SELECT tablespace_name, ROUND(SUM(bytes)/1024/1024) mb FROM dba_data_files
--      WHERE tablespace_name IN ('TS_AIMS_DATA','TS_AIMS_IDX',
--                                'TS_AIMS_HIST_DATA','TS_AIMS_HIST_IDX')
--      GROUP BY tablespace_name ORDER BY 1;
--
-- ----------------------------------------------------------------------------
--  이력 테이블(_01L)에 대해 알고 있어야 할 것 둘
-- ----------------------------------------------------------------------------
--
--  1. PK 가 (업무ID, 파티션키) 복합키다.
--     Oracle 호환 DB 에서 로컬 유니크 인덱스는 파티션 키를 반드시 포함해야
--     한다. Global Index 를 쓰지 않는 이상 피할 수 없다.
--     => 업무ID 단독 유일성은 DB 가 보장하지 않는다. 앱이 UUID 를 생성한다면
--        실무상 문제는 없다.
--
--  2. 파티션 키 컬럼이 NOT NULL 이다. NULL 을 넣으면 INSERT 가 실패한다.
--     ** T_ITSE_AI_MODL_OP01L.MNTG_STRT_DTTM 을 특히 확인할 것. **
--     모니터링 시작 전에 행을 먼저 등록하는 흐름이라면 이 테이블은 파티션을
--     빼야 한다. 파일 맨 아래에 파티션 없는 대안을 함께 넣어 두었다.
--
--  파티션은 P202608 / P202609 / PMAX 로 시작한다. 2026-10 이후 데이터는
--  PMAX 가 받는다. 월별 자동 추가를 원하면 T_ITSE_DATA_BCKP_STUP01P 에
--  등록해야 하며, 그러면 보관 기간이 지난 파티션이 영구 삭제된다.
--
--  관례 출처: AIMS_DEV.T_ITSE_AI_BRDW_JDG01L 의 DBMS_METADATA.GET_DDL
-- ============================================================================


-- ==========================================================================
-- 마스터 테이블 4개 — 파티션 없음
-- ==========================================================================


-- ---- T_ITSE_AI_CCTV01M ---------------------------------------------
CREATE TABLE AIMSC_DEV.T_ITSE_AI_CCTV01M
(
    "CCTV_ID"                    VARCHAR2(12)   NOT NULL,
    "INFO_CRET_DTTM"             DATE,
    "INFO_UPDT_DTTM"             DATE,
    "TRFC_EQPM_TYPE_CD"          VARCHAR2(2),
    "CCTV_RTSP_URL"              VARCHAR2(255),
    "CCTV_LNKN_STAT_CD"          VARCHAR2(2),
    "HDQR_ID"                    VARCHAR2(6),
    "MTNOF_ID"                   VARCHAR2(6),
    "LOCATION"                   VARCHAR2(1000)
)
TABLESPACE TS_AIMS_DATA;

CREATE UNIQUE INDEX AIMSC_DEV."PK_T_ITSE_AI_CCTV01M" ON AIMSC_DEV.T_ITSE_AI_CCTV01M ("CCTV_ID")
    TABLESPACE TS_AIMS_DATA;

ALTER TABLE AIMSC_DEV.T_ITSE_AI_CCTV01M ADD CONSTRAINT "PK_T_ITSE_AI_CCTV01M" PRIMARY KEY ("CCTV_ID");


-- ---- T_ITSE_AI_MODL01M ---------------------------------------------
CREATE TABLE AIMSC_DEV.T_ITSE_AI_MODL01M
(
    "AI_MODL_ID"                 VARCHAR2(36)   NOT NULL,
    "AI_MODL_NM"                 VARCHAR2(200),
    "AI_MODL_VRSN_NM"            VARCHAR2(100),
    "AI_MODL_STAT_CD"            VARCHAR2(2),
    "AI_MODL_USE_OBJTV_CTNT"     VARCHAR2(1000),
    "AI_MODL_FLNM"               VARCHAR2(300),
    "DATST_ID"                   VARCHAR2(36)   NOT NULL,
    "EXPRM_ID"                   VARCHAR2(36),
    "TRNG_STRT_DTTM"             DATE,
    "TRNG_END_DTTM"              DATE,
    "BTCH_SIZE_VAL"              NUMBER(10,0),
    "STUD_RT"                    NUMBER(5,2),
    "EPCH_CNT"                   NUMBER(10,0),
    "MODL_USE_STRT_DTTM"         DATE,
    "TRNG_STUP_CTNT"             VARCHAR2(4000),
    "AI_DGNST_TYPE_CD"           VARCHAR2(2),
    "TRNG_ACRC_RT"               NUMBER(5,2),
    "PSNT_AI_ACRC_RT"            NUMBER(5,2),
    "ACTN_MESR_CTNT"             VARCHAR2(1000)
)
TABLESPACE TS_AIMS_DATA;

CREATE UNIQUE INDEX AIMSC_DEV."PK_T_ITSE_AI_MODL01M" ON AIMSC_DEV.T_ITSE_AI_MODL01M ("AI_MODL_ID")
    TABLESPACE TS_AIMS_DATA;

ALTER TABLE AIMSC_DEV.T_ITSE_AI_MODL01M ADD CONSTRAINT "PK_T_ITSE_AI_MODL01M" PRIMARY KEY ("AI_MODL_ID");


-- ---- T_ITSE_DATST01M ---------------------------------------------
CREATE TABLE AIMSC_DEV.T_ITSE_DATST01M
(
    "DATST_ID"                   VARCHAR2(36)   NOT NULL,
    "DATST_CRET_DTTM"            DATE,
    "DATST_UPDT_DTTM"            DATE,
    "DATST_TYPE_CD"              VARCHAR2(2),
    "TRFC_EQPM_TYPE_CD"          VARCHAR2(2),
    "EQPM_CMPN_TYPE_CD"          VARCHAR2(2),
    "DATST_FILE_PATH"            VARCHAR2(2000),
    "ORTX_DATA_FILE_PATH"        VARCHAR2(2000),
    "AI_TRNG_DATA_TYPE_CD"       VARCHAR2(2),
    "DATA_MSRM_STRT_DTTM"        DATE,
    "DATA_MSRM_END_DTTM"         DATE,
    "TRNG_DATST_RATE"            NUMBER(5,2),
    "LBLL_INFO_FILE_PATH"        VARCHAR2(2000),
    "ANNT_INFO_FILE_PATH"        VARCHAR2(2000)
)
TABLESPACE TS_AIMS_DATA;

CREATE UNIQUE INDEX AIMSC_DEV."PK_T_ITSE_DATST01M" ON AIMSC_DEV.T_ITSE_DATST01M ("DATST_ID")
    TABLESPACE TS_AIMS_DATA;

ALTER TABLE AIMSC_DEV.T_ITSE_DATST01M ADD CONSTRAINT "PK_T_ITSE_DATST01M" PRIMARY KEY ("DATST_ID");


-- ---- T_ITSE_SNSH_STUP01M ---------------------------------------------
CREATE TABLE AIMSC_DEV.T_ITSE_SNSH_STUP01M
(
    "SNSH_STUP_ID"               VARCHAR2(36)   NOT NULL,
    "INFO_CRET_DTTM"             DATE,
    "INFO_UPDT_DTTM"             DATE,
    "SNSH_HOUR_SS"               NUMBER(9,0),
    "SNSH_INTV_SS"               NUMBER(9,0),
    "FILE_PATH"                  VARCHAR2(2000),
    "TRFC_EQPM_TYPE_CD"          VARCHAR2(2)
)
TABLESPACE TS_AIMS_DATA;

CREATE UNIQUE INDEX AIMSC_DEV."PK_T_ITSE_SNSH_STUP01M" ON AIMSC_DEV.T_ITSE_SNSH_STUP01M ("SNSH_STUP_ID")
    TABLESPACE TS_AIMS_DATA;

ALTER TABLE AIMSC_DEV.T_ITSE_SNSH_STUP01M ADD CONSTRAINT "PK_T_ITSE_SNSH_STUP01M" PRIMARY KEY ("SNSH_STUP_ID");


-- ==========================================================================
-- 이력 테이블 8개 — 월별 RANGE 파티션 + 로컬 유니크 인덱스
-- ==========================================================================


-- ---- T_ITSE_SNSH_GTHR01L  (파티션 키 STRT_DTTM) ----------------
CREATE TABLE AIMSC_DEV.T_ITSE_SNSH_GTHR01L
(
    "SNSH_GTHR_ID"               VARCHAR2(36)   NOT NULL,
    "STRT_DTTM"                  DATE           NOT NULL,
    "END_DTTM"                   DATE,
    "FILE_PATH"                  VARCHAR2(2000),
    "FILE_CNT"                   NUMBER(10,0),
    "PRPG_YN"                    VARCHAR2(1),
    "AI_DGNST_YN"                VARCHAR2(1)
)
TABLESPACE TS_AIMS_HIST_DATA
PARTITION BY RANGE("STRT_DTTM")
(
    PARTITION "P202608" VALUES LESS THAN (TO_DATE('20260901','YYYYMMDD')) TABLESPACE TS_AIMS_HIST_DATA,
    PARTITION "P202609" VALUES LESS THAN (TO_DATE('20261001','YYYYMMDD')) TABLESPACE TS_AIMS_HIST_DATA,
    PARTITION "PMAX" VALUES LESS THAN (MAXVALUE) TABLESPACE TS_AIMS_HIST_DATA
);

CREATE UNIQUE INDEX AIMSC_DEV."PK_T_ITSE_SNSH_GTHR01L" ON AIMSC_DEV.T_ITSE_SNSH_GTHR01L ("SNSH_GTHR_ID", "STRT_DTTM")
    TABLESPACE TS_AIMS_HIST_IDX LOCAL
(
    PARTITION "P202608" TABLESPACE TS_AIMS_HIST_IDX,
    PARTITION "P202609" TABLESPACE TS_AIMS_HIST_IDX,
    PARTITION "PMAX" TABLESPACE TS_AIMS_HIST_IDX
);

ALTER TABLE AIMSC_DEV.T_ITSE_SNSH_GTHR01L ADD CONSTRAINT "PK_T_ITSE_SNSH_GTHR01L" PRIMARY KEY ("SNSH_GTHR_ID", "STRT_DTTM");


-- ---- T_ITSE_SNSH_PRPG01L  (파티션 키 PRPG_STRT_DTTM) ----------------
CREATE TABLE AIMSC_DEV.T_ITSE_SNSH_PRPG01L
(
    "PRPG_ID"                    VARCHAR2(36)   NOT NULL,
    "PRPG_STRT_DTTM"             DATE           NOT NULL,
    "PRPG_END_DTTM"              DATE           NOT NULL,
    "PRPG_PRGS_RSLT_CD"          VARCHAR2(2)    NOT NULL
)
TABLESPACE TS_AIMS_HIST_DATA
PARTITION BY RANGE("PRPG_STRT_DTTM")
(
    PARTITION "P202608" VALUES LESS THAN (TO_DATE('20260901','YYYYMMDD')) TABLESPACE TS_AIMS_HIST_DATA,
    PARTITION "P202609" VALUES LESS THAN (TO_DATE('20261001','YYYYMMDD')) TABLESPACE TS_AIMS_HIST_DATA,
    PARTITION "PMAX" VALUES LESS THAN (MAXVALUE) TABLESPACE TS_AIMS_HIST_DATA
);

CREATE UNIQUE INDEX AIMSC_DEV."PK_T_ITSE_SNSH_PRPG01L" ON AIMSC_DEV.T_ITSE_SNSH_PRPG01L ("PRPG_ID", "PRPG_STRT_DTTM")
    TABLESPACE TS_AIMS_HIST_IDX LOCAL
(
    PARTITION "P202608" TABLESPACE TS_AIMS_HIST_IDX,
    PARTITION "P202609" TABLESPACE TS_AIMS_HIST_IDX,
    PARTITION "PMAX" TABLESPACE TS_AIMS_HIST_IDX
);

ALTER TABLE AIMSC_DEV.T_ITSE_SNSH_PRPG01L ADD CONSTRAINT "PK_T_ITSE_SNSH_PRPG01L" PRIMARY KEY ("PRPG_ID", "PRPG_STRT_DTTM");


-- ---- T_ITSE_LBLL01L  (파티션 키 INFO_CRET_DTTM) ----------------
CREATE TABLE AIMSC_DEV.T_ITSE_LBLL01L
(
    "LBLL_ID"                    VARCHAR2(36)   NOT NULL,
    "INFO_CRET_DTTM"             DATE           NOT NULL,
    "INFO_UPDT_DTTM"             DATE,
    "FILE_PATH"                  VARCHAR2(2000),
    "FILE_NM"                    VARCHAR2(500),
    "FILE_DEL_YN"                VARCHAR2(1),
    "PRPG_ID"                    VARCHAR2(36)   NOT NULL
)
TABLESPACE TS_AIMS_HIST_DATA
PARTITION BY RANGE("INFO_CRET_DTTM")
(
    PARTITION "P202608" VALUES LESS THAN (TO_DATE('20260901','YYYYMMDD')) TABLESPACE TS_AIMS_HIST_DATA,
    PARTITION "P202609" VALUES LESS THAN (TO_DATE('20261001','YYYYMMDD')) TABLESPACE TS_AIMS_HIST_DATA,
    PARTITION "PMAX" VALUES LESS THAN (MAXVALUE) TABLESPACE TS_AIMS_HIST_DATA
);

CREATE UNIQUE INDEX AIMSC_DEV."PK_T_ITSE_LBLL01L" ON AIMSC_DEV.T_ITSE_LBLL01L ("LBLL_ID", "INFO_CRET_DTTM")
    TABLESPACE TS_AIMS_HIST_IDX LOCAL
(
    PARTITION "P202608" TABLESPACE TS_AIMS_HIST_IDX,
    PARTITION "P202609" TABLESPACE TS_AIMS_HIST_IDX,
    PARTITION "PMAX" TABLESPACE TS_AIMS_HIST_IDX
);

ALTER TABLE AIMSC_DEV.T_ITSE_LBLL01L ADD CONSTRAINT "PK_T_ITSE_LBLL01L" PRIMARY KEY ("LBLL_ID", "INFO_CRET_DTTM");


-- ---- T_ITSE_ANNT01L  (파티션 키 INFO_CRET_DTTM) ----------------
CREATE TABLE AIMSC_DEV.T_ITSE_ANNT01L
(
    "ANNT_ID"                    VARCHAR2(36)   NOT NULL,
    "INFO_CRET_DTTM"             DATE           NOT NULL,
    "INFO_UPDT_DTTM"             DATE,
    "FILE_PATH"                  VARCHAR2(2000),
    "FILE_NM"                    VARCHAR2(500),
    "FILE_DEL_YN"                VARCHAR2(1),
    "PRPG_ID"                    VARCHAR2(36)   NOT NULL
)
TABLESPACE TS_AIMS_HIST_DATA
PARTITION BY RANGE("INFO_CRET_DTTM")
(
    PARTITION "P202608" VALUES LESS THAN (TO_DATE('20260901','YYYYMMDD')) TABLESPACE TS_AIMS_HIST_DATA,
    PARTITION "P202609" VALUES LESS THAN (TO_DATE('20261001','YYYYMMDD')) TABLESPACE TS_AIMS_HIST_DATA,
    PARTITION "PMAX" VALUES LESS THAN (MAXVALUE) TABLESPACE TS_AIMS_HIST_DATA
);

CREATE UNIQUE INDEX AIMSC_DEV."PK_T_ITSE_ANNT01L" ON AIMSC_DEV.T_ITSE_ANNT01L ("ANNT_ID", "INFO_CRET_DTTM")
    TABLESPACE TS_AIMS_HIST_IDX LOCAL
(
    PARTITION "P202608" TABLESPACE TS_AIMS_HIST_IDX,
    PARTITION "P202609" TABLESPACE TS_AIMS_HIST_IDX,
    PARTITION "PMAX" TABLESPACE TS_AIMS_HIST_IDX
);

ALTER TABLE AIMSC_DEV.T_ITSE_ANNT01L ADD CONSTRAINT "PK_T_ITSE_ANNT01L" PRIMARY KEY ("ANNT_ID", "INFO_CRET_DTTM");


-- ---- T_ITSE_AI_DGNST01L  (파티션 키 STRT_DTTM) ----------------
CREATE TABLE AIMSC_DEV.T_ITSE_AI_DGNST01L
(
    "AI_DGNST_ID"                VARCHAR2(36)   NOT NULL,
    "STRT_DTTM"                  DATE           NOT NULL,
    "END_DTTM"                   DATE           NOT NULL,
    "AI_DGNST_RSLT_CD"           VARCHAR2(2)    NOT NULL,
    "FILE_PATH"                  VARCHAR2(2000) NOT NULL
)
TABLESPACE TS_AIMS_HIST_DATA
PARTITION BY RANGE("STRT_DTTM")
(
    PARTITION "P202608" VALUES LESS THAN (TO_DATE('20260901','YYYYMMDD')) TABLESPACE TS_AIMS_HIST_DATA,
    PARTITION "P202609" VALUES LESS THAN (TO_DATE('20261001','YYYYMMDD')) TABLESPACE TS_AIMS_HIST_DATA,
    PARTITION "PMAX" VALUES LESS THAN (MAXVALUE) TABLESPACE TS_AIMS_HIST_DATA
);

CREATE UNIQUE INDEX AIMSC_DEV."PK_T_ITSE_AI_DGNST01L" ON AIMSC_DEV.T_ITSE_AI_DGNST01L ("AI_DGNST_ID", "STRT_DTTM")
    TABLESPACE TS_AIMS_HIST_IDX LOCAL
(
    PARTITION "P202608" TABLESPACE TS_AIMS_HIST_IDX,
    PARTITION "P202609" TABLESPACE TS_AIMS_HIST_IDX,
    PARTITION "PMAX" TABLESPACE TS_AIMS_HIST_IDX
);

ALTER TABLE AIMSC_DEV.T_ITSE_AI_DGNST01L ADD CONSTRAINT "PK_T_ITSE_AI_DGNST01L" PRIMARY KEY ("AI_DGNST_ID", "STRT_DTTM");


-- ---- T_ITSE_AI_MVPCT_DGNST01L  (파티션 키 AI_DGNST_DTTM) ----------------
CREATE TABLE AIMSC_DEV.T_ITSE_AI_MVPCT_DGNST01L
(
    "AI_MVPCT_DGNST_ID"          VARCHAR2(36)   NOT NULL,
    "AI_DGNST_DTTM"              DATE           NOT NULL,
    "JDG_NRML_YN"                VARCHAR2(1),
    "MVPCT_ERR_CTNT"             VARCHAR2(1000),
    "AI_DGNST_ID"                VARCHAR2(36)   NOT NULL,
    "CCTV_ID"                    VARCHAR2(12)   NOT NULL,
    "DGNST_RSLT_FILE_PATH"       VARCHAR2(2000) NOT NULL,
    "DGNST_TRGT_IMG_FILE_PATH"   VARCHAR2(2000) NOT NULL,
    "DGNST_RLBLT_RT"             NUMBER(5,2)    NOT NULL,
    "EXMN_YN"                    CHAR(1)        NOT NULL,
    "FLPS_YN"                    VARCHAR2(1)
)
TABLESPACE TS_AIMS_HIST_DATA
PARTITION BY RANGE("AI_DGNST_DTTM")
(
    PARTITION "P202608" VALUES LESS THAN (TO_DATE('20260901','YYYYMMDD')) TABLESPACE TS_AIMS_HIST_DATA,
    PARTITION "P202609" VALUES LESS THAN (TO_DATE('20261001','YYYYMMDD')) TABLESPACE TS_AIMS_HIST_DATA,
    PARTITION "PMAX" VALUES LESS THAN (MAXVALUE) TABLESPACE TS_AIMS_HIST_DATA
);

CREATE UNIQUE INDEX AIMSC_DEV."PK_T_ITSE_AI_MVPCT_DGNST01L" ON AIMSC_DEV.T_ITSE_AI_MVPCT_DGNST01L ("AI_MVPCT_DGNST_ID", "AI_DGNST_DTTM")
    TABLESPACE TS_AIMS_HIST_IDX LOCAL
(
    PARTITION "P202608" TABLESPACE TS_AIMS_HIST_IDX,
    PARTITION "P202609" TABLESPACE TS_AIMS_HIST_IDX,
    PARTITION "PMAX" TABLESPACE TS_AIMS_HIST_IDX
);

ALTER TABLE AIMSC_DEV.T_ITSE_AI_MVPCT_DGNST01L ADD CONSTRAINT "PK_T_ITSE_AI_MVPCT_DGNST01L" PRIMARY KEY ("AI_MVPCT_DGNST_ID", "AI_DGNST_DTTM");


-- ---- T_ITSE_AI_DRF_DGNST01L  (파티션 키 AI_DGNST_DTTM) ----------------
CREATE TABLE AIMSC_DEV.T_ITSE_AI_DRF_DGNST01L
(
    "AI_DRF_DGNST_ID"            VARCHAR2(36)   NOT NULL,
    "AI_DGNST_DTTM"              DATE           NOT NULL,
    "JDG_NRML_YN"                VARCHAR2(1),
    "DRF_ERR_CTNT"               VARCHAR2(1000),
    "AI_DGNST_ID"                VARCHAR2(36)   NOT NULL,
    "CCTV_ID"                    VARCHAR2(12)   NOT NULL,
    "DGNST_RSLT_FILE_PATH"       VARCHAR2(2000) NOT NULL,
    "DGNST_TRGT_IMG_FILE_PATH"   VARCHAR2(2000) NOT NULL,
    "DGNST_RLBLT_RT"             NUMBER(5,2)    NOT NULL,
    "EXMN_YN"                    CHAR(1)        NOT NULL,
    "FLPS_YN"                    VARCHAR2(1)
)
TABLESPACE TS_AIMS_HIST_DATA
PARTITION BY RANGE("AI_DGNST_DTTM")
(
    PARTITION "P202608" VALUES LESS THAN (TO_DATE('20260901','YYYYMMDD')) TABLESPACE TS_AIMS_HIST_DATA,
    PARTITION "P202609" VALUES LESS THAN (TO_DATE('20261001','YYYYMMDD')) TABLESPACE TS_AIMS_HIST_DATA,
    PARTITION "PMAX" VALUES LESS THAN (MAXVALUE) TABLESPACE TS_AIMS_HIST_DATA
);

CREATE UNIQUE INDEX AIMSC_DEV."PK_T_ITSE_AI_DRF_DGNST01L" ON AIMSC_DEV.T_ITSE_AI_DRF_DGNST01L ("AI_DRF_DGNST_ID", "AI_DGNST_DTTM")
    TABLESPACE TS_AIMS_HIST_IDX LOCAL
(
    PARTITION "P202608" TABLESPACE TS_AIMS_HIST_IDX,
    PARTITION "P202609" TABLESPACE TS_AIMS_HIST_IDX,
    PARTITION "PMAX" TABLESPACE TS_AIMS_HIST_IDX
);

ALTER TABLE AIMSC_DEV.T_ITSE_AI_DRF_DGNST01L ADD CONSTRAINT "PK_T_ITSE_AI_DRF_DGNST01L" PRIMARY KEY ("AI_DRF_DGNST_ID", "AI_DGNST_DTTM");


-- ---- T_ITSE_AI_MODL_OP01L  (파티션 키 MNTG_STRT_DTTM) ----------------
CREATE TABLE AIMSC_DEV.T_ITSE_AI_MODL_OP01L
(
    "AI_MODL_OP_ID"              VARCHAR2(36)   NOT NULL,
    "AI_MODL_ID"                 VARCHAR2(36)   NOT NULL,
    "EQPM_TYPE_NM"               VARCHAR2(100),
    "MNTG_ITM_NM"                VARCHAR2(100),
    "AI_MODL_USE_OBJTV_CTNT"     VARCHAR2(1000),
    "MNTG_STRT_DTTM"             DATE           NOT NULL,
    "MNTG_END_DTTM"              DATE,
    "AI_MODL_OP_STAT_CD"         VARCHAR2(2),
    "DGNST_PRFM_STAT_NM"         VARCHAR2(100),
    "TRNG_STRT_DTTM"             DATE,
    "TRNG_END_DTTM"              DATE,
    "DATST_ID"                   VARCHAR2(36)   NOT NULL
)
TABLESPACE TS_AIMS_HIST_DATA
PARTITION BY RANGE("MNTG_STRT_DTTM")
(
    PARTITION "P202608" VALUES LESS THAN (TO_DATE('20260901','YYYYMMDD')) TABLESPACE TS_AIMS_HIST_DATA,
    PARTITION "P202609" VALUES LESS THAN (TO_DATE('20261001','YYYYMMDD')) TABLESPACE TS_AIMS_HIST_DATA,
    PARTITION "PMAX" VALUES LESS THAN (MAXVALUE) TABLESPACE TS_AIMS_HIST_DATA
);

CREATE UNIQUE INDEX AIMSC_DEV."PK_T_ITSE_AI_MODL_OP01L" ON AIMSC_DEV.T_ITSE_AI_MODL_OP01L ("AI_MODL_OP_ID", "MNTG_STRT_DTTM")
    TABLESPACE TS_AIMS_HIST_IDX LOCAL
(
    PARTITION "P202608" TABLESPACE TS_AIMS_HIST_IDX,
    PARTITION "P202609" TABLESPACE TS_AIMS_HIST_IDX,
    PARTITION "PMAX" TABLESPACE TS_AIMS_HIST_IDX
);

ALTER TABLE AIMSC_DEV.T_ITSE_AI_MODL_OP01L ADD CONSTRAINT "PK_T_ITSE_AI_MODL_OP01L" PRIMARY KEY ("AI_MODL_OP_ID", "MNTG_STRT_DTTM");


-- ==========================================================================
-- 시노님 3개 — 조회 전용. 실테이블을 복제하지 않는다
-- ==========================================================================
--
-- CCTV / 본사 / 지사 원장은 AIMS_EX 에 하나만 있어야 한다. 같은 이름의
-- 실테이블을 만들면 원장이 둘이 되어 동기화 문제가 생긴다.
-- 이 DB 의 기존 시노님 100여 개가 전부 같은 방식이다.
-- 이미 있으면 만들지 말 것.

CREATE SYNONYM AIMSC_DEV.T_ITSE_CCTV_01M FOR AIMS_EX.T_ITSE_CCTV_01M;
CREATE SYNONYM AIMSC_DEV.T_ITSE_HDQR_01M FOR AIMS_EX.T_ITSE_HDQR_01M;
CREATE SYNONYM AIMSC_DEV.T_ITSE_MTNOF_01M FOR AIMS_EX.T_ITSE_MTNOF_01M;


-- ==========================================================================
-- 대안 — T_ITSE_AI_MODL_OP01L 을 파티션 없이 만드는 경우
-- ==========================================================================
--
-- MNTG_STRT_DTTM 이 NULL 일 수 있는 흐름이면 위의 파티션 버전 대신 이것을 쓴다.
-- 행이 적고(활성 모니터링 건) 파티션 이득이 크지 않아 무리가 없다.
-- 위의 T_ITSE_AI_MODL_OP01L 블록과 ** 둘 중 하나만 ** 실행할 것.
--
/*
CREATE TABLE AIMSC_DEV.T_ITSE_AI_MODL_OP01L
(
    "AI_MODL_OP_ID"              VARCHAR2(36)   NOT NULL,
    "AI_MODL_ID"                 VARCHAR2(36)   NOT NULL,
    "EQPM_TYPE_NM"               VARCHAR2(100),
    "MNTG_ITM_NM"                VARCHAR2(100),
    "AI_MODL_USE_OBJTV_CTNT"     VARCHAR2(1000),
    "MNTG_STRT_DTTM"             DATE,
    "MNTG_END_DTTM"              DATE,
    "AI_MODL_OP_STAT_CD"         VARCHAR2(2),
    "DGNST_PRFM_STAT_NM"         VARCHAR2(100),
    "TRNG_STRT_DTTM"             DATE,
    "TRNG_END_DTTM"              DATE,
    "DATST_ID"                   VARCHAR2(36)   NOT NULL
)
TABLESPACE TS_AIMS_DATA;

CREATE UNIQUE INDEX AIMSC_DEV."PK_T_ITSE_AI_MODL_OP01L" ON AIMSC_DEV.T_ITSE_AI_MODL_OP01L ("AI_MODL_OP_ID")
    TABLESPACE TS_AIMS_DATA;

ALTER TABLE AIMSC_DEV.T_ITSE_AI_MODL_OP01L ADD CONSTRAINT "PK_T_ITSE_AI_MODL_OP01L" PRIMARY KEY ("AI_MODL_OP_ID");
*/


-- ==========================================================================
-- 생성 후 확인
-- ==========================================================================
--
-- 이력 테이블은 PARTITIONED='YES' 여야 로컬 인덱스다. 'NO' 면 글로벌이다.
--
--   SELECT table_name, index_name, uniqueness, partitioned, tablespace_name
--     FROM all_indexes WHERE table_owner='AIMSC_DEV' AND table_name LIKE '%01L'
--    ORDER BY table_name;
--
--   SELECT table_name, partitioning_type, partition_count
--     FROM all_part_tables WHERE owner='AIMSC_DEV' ORDER BY table_name;
--
--   SELECT name, column_name, column_position
--     FROM all_part_key_columns WHERE owner='AIMSC_DEV' ORDER BY name, column_position;
--
--   SELECT table_name, constraint_name, status, validated
--     FROM all_constraints WHERE owner='AIMSC_DEV' AND constraint_type='P'
--    ORDER BY table_name;
--
--   SELECT object_type, object_name, status FROM all_objects
--    WHERE owner='AIMSC_DEV' AND status <> 'VALID';

