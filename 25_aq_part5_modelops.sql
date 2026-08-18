-- ============================================================================
--  AQ 앱 테이블 — Part 5. 모델 운영 · 정확도 API
--  대상: 121.137.106.217:58629 / TAIMS / AIMS_DEV   (원천 공동작업 DB)
-- ============================================================================
--
--  담당 모듈: AQ5 / AQ6 — 활성 모니터링 건 조회, 모델 정확도·통계 API
--  테이블   : T_ITSE_AI_MODL_OP01L
--
--  구성
--    [1] DDL          2026-08-18 원천에 이미 적용했다. 재현·검토용이다.
--    [2] 샘플 데이터   앱 연동 시험용. 실행 여부는 선택이다.
--    [3] 확인
--    [4] 정리(삭제)
--
--  ** 여러 사람이 함께 쓰는 DB 다. **
--  샘플 데이터의 업무 ID 는 전부 'SEED-' 로 시작한다. [4] 로 깨끗이 지울 수 있다.
--  파티션 키 값은 SYSDATE 를 쓰므로 2026-08 파티션(P202608)에 들어간다.
--
--  Part 3(데이터셋) 과 Part 4(모델) 를 먼저 실행해야 한다.
--
--  ** 이 테이블은 주의가 필요하다. **
--  MNTG_STRT_DTTM 이 파티션 키이자 PK 구성 컬럼이라 NOT NULL 이다.
--  모니터링을 시작하기 전에 행을 먼저 등록하는 흐름이라면 파티션 버전을 쓸 수
--  없다. 그 경우 18_aq_tables_dbeaver.sql 맨 아래의 파티션 없는 대안으로
--  다시 만들어야 한다.
-- ============================================================================


-- ############################################################################
-- ## [1] DDL — 이미 적용됨. 다시 실행하면 "이미 있음" 오류가 난다
-- ############################################################################

-- ---- T_ITSE_AI_MODL_OP01L ------------------------------------
CREATE TABLE AIMS_DEV.T_ITSE_AI_MODL_OP01L
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

CREATE UNIQUE INDEX AIMS_DEV."PK_T_ITSE_AI_MODL_OP01L" ON AIMS_DEV.T_ITSE_AI_MODL_OP01L ("AI_MODL_OP_ID", "MNTG_STRT_DTTM")
    TABLESPACE TS_AIMS_HIST_IDX LOCAL
(
    PARTITION "P202608" TABLESPACE TS_AIMS_HIST_IDX,
    PARTITION "P202609" TABLESPACE TS_AIMS_HIST_IDX,
    PARTITION "PMAX" TABLESPACE TS_AIMS_HIST_IDX
);

ALTER TABLE AIMS_DEV.T_ITSE_AI_MODL_OP01L ADD CONSTRAINT "PK_T_ITSE_AI_MODL_OP01L" PRIMARY KEY ("AI_MODL_OP_ID", "MNTG_STRT_DTTM");


-- ############################################################################
-- ## [2] 샘플 데이터   ** Part 3, Part 4 를 먼저 실행할 것 **
-- ############################################################################

-- 운영 중 1건(종료일 없음) + 종료 1건.
-- MNTG_END_DTTM 은 NULL 을 허용하지만 MNTG_STRT_DTTM 은 NULL 일 수 없다.
INSERT INTO AIMS_DEV.T_ITSE_AI_MODL_OP01L
  (AI_MODL_OP_ID, AI_MODL_ID, EQPM_TYPE_NM, MNTG_ITM_NM, AI_MODL_USE_OBJTV_CTNT,
   MNTG_STRT_DTTM, MNTG_END_DTTM, AI_MODL_OP_STAT_CD, DGNST_PRFM_STAT_NM,
   TRNG_STRT_DTTM, TRNG_END_DTTM, DATST_ID)
VALUES
  ('SEED-OP-001', 'SEED-MODL-001', 'CCTV', '영상품질', 'CCTV 화면 이상 상시 감시',
   SYSDATE - 4, NULL, '01', '수행중',
   SYSDATE - 7, SYSDATE - 5, 'SEED-DATST-001');

INSERT INTO AIMS_DEV.T_ITSE_AI_MODL_OP01L
  (AI_MODL_OP_ID, AI_MODL_ID, EQPM_TYPE_NM, MNTG_ITM_NM, AI_MODL_USE_OBJTV_CTNT,
   MNTG_STRT_DTTM, MNTG_END_DTTM, AI_MODL_OP_STAT_CD, DGNST_PRFM_STAT_NM,
   TRNG_STRT_DTTM, TRNG_END_DTTM, DATST_ID)
VALUES
  ('SEED-OP-002', 'SEED-MODL-002', 'VMS', '표출문안', 'VMS 문안 오류 상시 감시',
   SYSDATE - 3, SYSDATE - 1, '02', '종료',
   SYSDATE - 6, SYSDATE - 4, 'SEED-DATST-001');

COMMIT;


-- ############################################################################
-- ## [3] 확인
-- ############################################################################

SELECT AI_MODL_OP_ID, AI_MODL_ID, MNTG_ITM_NM, AI_MODL_OP_STAT_CD,
       MNTG_STRT_DTTM, MNTG_END_DTTM
  FROM AIMS_DEV.T_ITSE_AI_MODL_OP01L ORDER BY AI_MODL_OP_ID;

-- AQ5/AQ6 이 쓰는 조회 모양 — 활성 모니터링 건에 모델 정확도를 붙인다
SELECT o.AI_MODL_OP_ID, o.MNTG_ITM_NM, o.DGNST_PRFM_STAT_NM,
       m.AI_MODL_NM, m.AI_MODL_VRSN_NM,
       m.TRNG_ACRC_RT, m.PSNT_AI_ACRC_RT, m.ACTN_MESR_CTNT
  FROM AIMS_DEV.T_ITSE_AI_MODL_OP01L o, AIMS_DEV.T_ITSE_AI_MODL01M m
 WHERE o.AI_MODL_ID = m.AI_MODL_ID
   AND o.MNTG_END_DTTM IS NULL          -- 활성 건만
 ORDER BY o.AI_MODL_OP_ID;


-- ############################################################################
-- ## [4] 정리
-- ############################################################################

-- DELETE FROM AIMS_DEV.T_ITSE_AI_MODL_OP01L WHERE AI_MODL_OP_ID LIKE 'SEED-%';
-- COMMIT;
