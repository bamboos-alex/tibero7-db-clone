-- ============================================================================
--  AQ 앱 테이블 — Part 1. 수집
--  대상: 121.137.106.217:58629 / TAIMS / AIMS_DEV   (원천 공동작업 DB)
-- ============================================================================
--
--  담당 모듈: AQ1 — 수집 대상 조회 / 수집 동작 설정 / 수집 결과 저장
--  테이블   : T_ITSE_AI_CCTV01M · T_ITSE_SNSH_STUP01M · T_ITSE_SNSH_GTHR01L
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
--  T_ITSE_AI_CCTV01M 만 예외다. PK 가 실제 CCTV_ID 라 'SEED-' 를 붙일 수 없어,
--  AIMS_EX.T_ITSE_CCTV_01M 에서 실제 장비 5대를 골라 넣는다. 정리는 [4] 참조.
-- ============================================================================


-- ############################################################################
-- ## [1] DDL — 이미 적용됨. 다시 실행하면 "이미 있음" 오류가 난다
-- ############################################################################

-- ---- T_ITSE_AI_CCTV01M ---------------------------------------
CREATE TABLE AIMS_DEV.T_ITSE_AI_CCTV01M
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

CREATE UNIQUE INDEX AIMS_DEV."PK_T_ITSE_AI_CCTV01M" ON AIMS_DEV.T_ITSE_AI_CCTV01M ("CCTV_ID")
    TABLESPACE TS_AIMS_DATA;

ALTER TABLE AIMS_DEV.T_ITSE_AI_CCTV01M ADD CONSTRAINT "PK_T_ITSE_AI_CCTV01M" PRIMARY KEY ("CCTV_ID");

-- ---- T_ITSE_SNSH_STUP01M -------------------------------------
CREATE TABLE AIMS_DEV.T_ITSE_SNSH_STUP01M
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

CREATE UNIQUE INDEX AIMS_DEV."PK_T_ITSE_SNSH_STUP01M" ON AIMS_DEV.T_ITSE_SNSH_STUP01M ("SNSH_STUP_ID")
    TABLESPACE TS_AIMS_DATA;

ALTER TABLE AIMS_DEV.T_ITSE_SNSH_STUP01M ADD CONSTRAINT "PK_T_ITSE_SNSH_STUP01M" PRIMARY KEY ("SNSH_STUP_ID");

-- ---- T_ITSE_SNSH_GTHR01L -------------------------------------
CREATE TABLE AIMS_DEV.T_ITSE_SNSH_GTHR01L
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

CREATE UNIQUE INDEX AIMS_DEV."PK_T_ITSE_SNSH_GTHR01L" ON AIMS_DEV.T_ITSE_SNSH_GTHR01L ("SNSH_GTHR_ID", "STRT_DTTM")
    TABLESPACE TS_AIMS_HIST_IDX LOCAL
(
    PARTITION "P202608" TABLESPACE TS_AIMS_HIST_IDX,
    PARTITION "P202609" TABLESPACE TS_AIMS_HIST_IDX,
    PARTITION "PMAX" TABLESPACE TS_AIMS_HIST_IDX
);

ALTER TABLE AIMS_DEV.T_ITSE_SNSH_GTHR01L ADD CONSTRAINT "PK_T_ITSE_SNSH_GTHR01L" PRIMARY KEY ("SNSH_GTHR_ID", "STRT_DTTM");


-- ############################################################################
-- ## [2] 샘플 데이터
-- ############################################################################

-- ---- 2-1. 수집 대상 장비 5대 ------------------------------------------------
-- 값을 지어내지 않고 AIMS_EX 의 실제 CCTV 원장에서 가져온다.
-- RTSP URL 이 있고 사용 중인 것만 고른다.
INSERT INTO AIMS_DEV.T_ITSE_AI_CCTV01M
  (CCTV_ID, INFO_CRET_DTTM, INFO_UPDT_DTTM, TRFC_EQPM_TYPE_CD,
   CCTV_RTSP_URL, CCTV_LNKN_STAT_CD, HDQR_ID, MTNOF_ID, LOCATION)
SELECT c.CCTV_ID, SYSDATE, SYSDATE, '01',
       SUBSTR(c.EX_NTWK_RTSP_URL, 1, 255), '01', c.HDQR_ID, c.MTNOF_ID,
       SUBSTR(c.CCTV_ISTC, 1, 1000)
  FROM AIMS_EX.T_ITSE_CCTV_01M c
 WHERE c.USE_YN = 'Y'
   AND c.EX_NTWK_RTSP_URL IS NOT NULL
   AND c.HDQR_ID IS NOT NULL
   AND ROWNUM <= 5;

COMMIT;

-- ---- 2-2. 수집 동작 설정 1건 ------------------------------------------------
-- 10초짜리 영상을 5분 간격으로 수집하는 설정.
INSERT INTO AIMS_DEV.T_ITSE_SNSH_STUP01M
  (SNSH_STUP_ID, INFO_CRET_DTTM, INFO_UPDT_DTTM,
   SNSH_HOUR_SS, SNSH_INTV_SS, FILE_PATH, TRFC_EQPM_TYPE_CD)
VALUES
  ('SEED-STUP-001', SYSDATE, SYSDATE, 10, 300, '/data/aq/snapshot', '01');

COMMIT;

-- ---- 2-3. 수집 결과 3건 -----------------------------------------------------
-- STRT_DTTM 이 파티션 키다. SYSDATE 이므로 P202608 로 들어간다.
INSERT INTO AIMS_DEV.T_ITSE_SNSH_GTHR01L
  (SNSH_GTHR_ID, STRT_DTTM, END_DTTM, FILE_PATH, FILE_CNT, PRPG_YN, AI_DGNST_YN)
VALUES ('SEED-GTHR-001', SYSDATE - 3/24, SYSDATE - 3/24 + 10/86400,
        '/data/aq/snapshot/20260818/001', 120, 'Y', 'Y');

INSERT INTO AIMS_DEV.T_ITSE_SNSH_GTHR01L
  (SNSH_GTHR_ID, STRT_DTTM, END_DTTM, FILE_PATH, FILE_CNT, PRPG_YN, AI_DGNST_YN)
VALUES ('SEED-GTHR-002', SYSDATE - 2/24, SYSDATE - 2/24 + 10/86400,
        '/data/aq/snapshot/20260818/002', 118, 'Y', 'N');

INSERT INTO AIMS_DEV.T_ITSE_SNSH_GTHR01L
  (SNSH_GTHR_ID, STRT_DTTM, END_DTTM, FILE_PATH, FILE_CNT, PRPG_YN, AI_DGNST_YN)
VALUES ('SEED-GTHR-003', SYSDATE - 1/24, SYSDATE - 1/24 + 10/86400,
        '/data/aq/snapshot/20260818/003', 121, 'N', 'N');

COMMIT;


-- ############################################################################
-- ## [3] 확인
-- ############################################################################

SELECT 'AI_CCTV01M'   AS tab, COUNT(*) AS rows_cnt FROM AIMS_DEV.T_ITSE_AI_CCTV01M
UNION ALL
SELECT 'SNSH_STUP01M',  COUNT(*) FROM AIMS_DEV.T_ITSE_SNSH_STUP01M
UNION ALL
SELECT 'SNSH_GTHR01L',  COUNT(*) FROM AIMS_DEV.T_ITSE_SNSH_GTHR01L;

-- 수집 결과가 어느 파티션에 들어갔는가 (P202608 이어야 한다)
SELECT 'P202608' AS part, COUNT(*) AS rows_cnt
  FROM AIMS_DEV.T_ITSE_SNSH_GTHR01L PARTITION (P202608)
UNION ALL
SELECT 'P202609', COUNT(*) FROM AIMS_DEV.T_ITSE_SNSH_GTHR01L PARTITION (P202609)
UNION ALL
SELECT 'PMAX',    COUNT(*) FROM AIMS_DEV.T_ITSE_SNSH_GTHR01L PARTITION (PMAX);

-- 실제 장비와 연결됐는가
SELECT a.CCTV_ID, a.HDQR_ID, a.MTNOF_ID, c.CAMR_NM
  FROM AIMS_DEV.T_ITSE_AI_CCTV01M a, AIMS_EX.T_ITSE_CCTV_01M c
 WHERE a.CCTV_ID = c.CCTV_ID ORDER BY a.CCTV_ID;


-- ############################################################################
-- ## [4] 정리 — 샘플 데이터만 지운다
-- ############################################################################

-- DELETE FROM AIMS_DEV.T_ITSE_SNSH_GTHR01L WHERE SNSH_GTHR_ID LIKE 'SEED-%';
-- DELETE FROM AIMS_DEV.T_ITSE_SNSH_STUP01M WHERE SNSH_STUP_ID LIKE 'SEED-%';
-- -- AI_CCTV01M 은 PK 가 실제 CCTV_ID 라 접두사로 못 거른다. 넣은 5건은
-- -- INFO_CRET_DTTM 이 적재 시각이므로 그것으로 지운다.
-- DELETE FROM AIMS_DEV.T_ITSE_AI_CCTV01M WHERE INFO_CRET_DTTM >= TRUNC(SYSDATE);
-- COMMIT;
