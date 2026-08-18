-- ============================================================================
--  AQ 앱 테이블 — Part 3. 데이터셋
--  대상: 121.137.106.217:58629 / TAIMS / AIMS_DEV   (원천 공동작업 DB)
-- ============================================================================
--
--  담당 모듈: AQ3 — 데이터셋 관리 정보 생성
--  테이블   : T_ITSE_DATST01M
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
--  Part 2 를 먼저 실행해야 한다. 데이터셋은 라벨링·어노테이션 산출물을 묶는다.
-- ============================================================================


-- ############################################################################
-- ## [1] DDL — 이미 적용됨. 다시 실행하면 "이미 있음" 오류가 난다
-- ############################################################################

-- ---- T_ITSE_DATST01M -----------------------------------------
CREATE TABLE AIMS_DEV.T_ITSE_DATST01M
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

CREATE UNIQUE INDEX AIMS_DEV."PK_T_ITSE_DATST01M" ON AIMS_DEV.T_ITSE_DATST01M ("DATST_ID")
    TABLESPACE TS_AIMS_DATA;

ALTER TABLE AIMS_DEV.T_ITSE_DATST01M ADD CONSTRAINT "PK_T_ITSE_DATST01M" PRIMARY KEY ("DATST_ID");


-- ############################################################################
-- ## [2] 샘플 데이터   ** Part 2 를 먼저 실행할 것 **
-- ############################################################################

-- 학습 70% / 검증 30% 로 나눈 데이터셋 1건.
INSERT INTO AIMS_DEV.T_ITSE_DATST01M
  (DATST_ID, DATST_CRET_DTTM, DATST_UPDT_DTTM, DATST_TYPE_CD,
   TRFC_EQPM_TYPE_CD, EQPM_CMPN_TYPE_CD, DATST_FILE_PATH, ORTX_DATA_FILE_PATH,
   AI_TRNG_DATA_TYPE_CD, DATA_MSRM_STRT_DTTM, DATA_MSRM_END_DTTM,
   TRNG_DATST_RATE, LBLL_INFO_FILE_PATH, ANNT_INFO_FILE_PATH)
VALUES
  ('SEED-DATST-001', SYSDATE, SYSDATE, '01',
   '01', '01', '/data/aq/dataset/20260818', '/data/aq/snapshot/20260818',
   '01', SYSDATE - 3/24, SYSDATE,
   70.00, '/data/aq/label/20260818', '/data/aq/annot/20260818');

COMMIT;


-- ############################################################################
-- ## [3] 확인
-- ############################################################################

SELECT DATST_ID, DATST_TYPE_CD, TRNG_DATST_RATE,
       DATA_MSRM_STRT_DTTM, DATA_MSRM_END_DTTM
  FROM AIMS_DEV.T_ITSE_DATST01M ORDER BY DATST_ID;

-- 데이터셋이 가리키는 경로에 실제 라벨링·어노테이션 건이 있는가
SELECT d.DATST_ID,
       (SELECT COUNT(*) FROM AIMS_DEV.T_ITSE_LBLL01L l WHERE l.FILE_PATH = d.LBLL_INFO_FILE_PATH) AS label_cnt,
       (SELECT COUNT(*) FROM AIMS_DEV.T_ITSE_ANNT01L a WHERE a.FILE_PATH = d.ANNT_INFO_FILE_PATH) AS annot_cnt
  FROM AIMS_DEV.T_ITSE_DATST01M d WHERE d.DATST_ID LIKE 'SEED-%';


-- ############################################################################
-- ## [4] 정리
-- ############################################################################

-- DELETE FROM AIMS_DEV.T_ITSE_DATST01M WHERE DATST_ID LIKE 'SEED-%';
-- COMMIT;
