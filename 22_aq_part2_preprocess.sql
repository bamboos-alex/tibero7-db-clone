-- ============================================================================
--  AQ 앱 테이블 — Part 2. 전처리 · 라벨링 · 어노테이션
--  대상: 121.137.106.217:58629 / TAIMS / AIMS_DEV   (원천 공동작업 DB)
-- ============================================================================
--
--  담당 모듈: AQ2 — 전처리 결과 / 라벨링 결과 / 어노테이션 결과 저장
--  테이블   : T_ITSE_SNSH_PRPG01L · T_ITSE_LBLL01L · T_ITSE_ANNT01L
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
--  적재 순서가 있다. 라벨링·어노테이션이 PRPG_ID 를 참조하므로 전처리가 먼저다.
--  FK 는 없지만 값이 맞지 않으면 앱이 조회하지 못한다.
--  Part 1 을 먼저 실행해야 한다 (SEED-GTHR-* 참조).
-- ============================================================================


-- ############################################################################
-- ## [1] DDL — 이미 적용됨. 다시 실행하면 "이미 있음" 오류가 난다
-- ############################################################################

-- ---- T_ITSE_SNSH_PRPG01L -------------------------------------
CREATE TABLE AIMS_DEV.T_ITSE_SNSH_PRPG01L
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

CREATE UNIQUE INDEX AIMS_DEV."PK_T_ITSE_SNSH_PRPG01L" ON AIMS_DEV.T_ITSE_SNSH_PRPG01L ("PRPG_ID", "PRPG_STRT_DTTM")
    TABLESPACE TS_AIMS_HIST_IDX LOCAL
(
    PARTITION "P202608" TABLESPACE TS_AIMS_HIST_IDX,
    PARTITION "P202609" TABLESPACE TS_AIMS_HIST_IDX,
    PARTITION "PMAX" TABLESPACE TS_AIMS_HIST_IDX
);

ALTER TABLE AIMS_DEV.T_ITSE_SNSH_PRPG01L ADD CONSTRAINT "PK_T_ITSE_SNSH_PRPG01L" PRIMARY KEY ("PRPG_ID", "PRPG_STRT_DTTM");

-- ---- T_ITSE_LBLL01L ------------------------------------------
CREATE TABLE AIMS_DEV.T_ITSE_LBLL01L
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

CREATE UNIQUE INDEX AIMS_DEV."PK_T_ITSE_LBLL01L" ON AIMS_DEV.T_ITSE_LBLL01L ("LBLL_ID", "INFO_CRET_DTTM")
    TABLESPACE TS_AIMS_HIST_IDX LOCAL
(
    PARTITION "P202608" TABLESPACE TS_AIMS_HIST_IDX,
    PARTITION "P202609" TABLESPACE TS_AIMS_HIST_IDX,
    PARTITION "PMAX" TABLESPACE TS_AIMS_HIST_IDX
);

ALTER TABLE AIMS_DEV.T_ITSE_LBLL01L ADD CONSTRAINT "PK_T_ITSE_LBLL01L" PRIMARY KEY ("LBLL_ID", "INFO_CRET_DTTM");

-- ---- T_ITSE_ANNT01L ------------------------------------------
CREATE TABLE AIMS_DEV.T_ITSE_ANNT01L
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

CREATE UNIQUE INDEX AIMS_DEV."PK_T_ITSE_ANNT01L" ON AIMS_DEV.T_ITSE_ANNT01L ("ANNT_ID", "INFO_CRET_DTTM")
    TABLESPACE TS_AIMS_HIST_IDX LOCAL
(
    PARTITION "P202608" TABLESPACE TS_AIMS_HIST_IDX,
    PARTITION "P202609" TABLESPACE TS_AIMS_HIST_IDX,
    PARTITION "PMAX" TABLESPACE TS_AIMS_HIST_IDX
);

ALTER TABLE AIMS_DEV.T_ITSE_ANNT01L ADD CONSTRAINT "PK_T_ITSE_ANNT01L" PRIMARY KEY ("ANNT_ID", "INFO_CRET_DTTM");


-- ############################################################################
-- ## [2] 샘플 데이터   ** Part 1 을 먼저 실행할 것 **
-- ############################################################################

-- ---- 2-1. 전처리 결과 3건 ---------------------------------------------------
-- PRPG_STRT_DTTM 이 파티션 키다.
INSERT INTO AIMS_DEV.T_ITSE_SNSH_PRPG01L
  (PRPG_ID, PRPG_STRT_DTTM, PRPG_END_DTTM, PRPG_PRGS_RSLT_CD)
VALUES ('SEED-PRPG-001', SYSDATE - 3/24, SYSDATE - 3/24 + 120/86400, '01');

INSERT INTO AIMS_DEV.T_ITSE_SNSH_PRPG01L
  (PRPG_ID, PRPG_STRT_DTTM, PRPG_END_DTTM, PRPG_PRGS_RSLT_CD)
VALUES ('SEED-PRPG-002', SYSDATE - 2/24, SYSDATE - 2/24 + 118/86400, '01');

INSERT INTO AIMS_DEV.T_ITSE_SNSH_PRPG01L
  (PRPG_ID, PRPG_STRT_DTTM, PRPG_END_DTTM, PRPG_PRGS_RSLT_CD)
VALUES ('SEED-PRPG-003', SYSDATE - 1/24, SYSDATE - 1/24 + 95/86400, '02');

COMMIT;

-- ---- 2-2. 라벨링 결과 3건 ---------------------------------------------------
-- INFO_CRET_DTTM 이 파티션 키다. PRPG_ID 로 전처리 건과 이어진다.
INSERT INTO AIMS_DEV.T_ITSE_LBLL01L
  (LBLL_ID, INFO_CRET_DTTM, INFO_UPDT_DTTM, FILE_PATH, FILE_NM, FILE_DEL_YN, PRPG_ID)
VALUES ('SEED-LBLL-001', SYSDATE, SYSDATE,
        '/data/aq/label/20260818', 'label_001.json', 'N', 'SEED-PRPG-001');

INSERT INTO AIMS_DEV.T_ITSE_LBLL01L
  (LBLL_ID, INFO_CRET_DTTM, INFO_UPDT_DTTM, FILE_PATH, FILE_NM, FILE_DEL_YN, PRPG_ID)
VALUES ('SEED-LBLL-002', SYSDATE, SYSDATE,
        '/data/aq/label/20260818', 'label_002.json', 'N', 'SEED-PRPG-002');

INSERT INTO AIMS_DEV.T_ITSE_LBLL01L
  (LBLL_ID, INFO_CRET_DTTM, INFO_UPDT_DTTM, FILE_PATH, FILE_NM, FILE_DEL_YN, PRPG_ID)
VALUES ('SEED-LBLL-003', SYSDATE, SYSDATE,
        '/data/aq/label/20260818', 'label_003.json', 'N', 'SEED-PRPG-003');

COMMIT;

-- ---- 2-3. 어노테이션 결과 3건 -----------------------------------------------
INSERT INTO AIMS_DEV.T_ITSE_ANNT01L
  (ANNT_ID, INFO_CRET_DTTM, INFO_UPDT_DTTM, FILE_PATH, FILE_NM, FILE_DEL_YN, PRPG_ID)
VALUES ('SEED-ANNT-001', SYSDATE, SYSDATE,
        '/data/aq/annot/20260818', 'annot_001.xml', 'N', 'SEED-PRPG-001');

INSERT INTO AIMS_DEV.T_ITSE_ANNT01L
  (ANNT_ID, INFO_CRET_DTTM, INFO_UPDT_DTTM, FILE_PATH, FILE_NM, FILE_DEL_YN, PRPG_ID)
VALUES ('SEED-ANNT-002', SYSDATE, SYSDATE,
        '/data/aq/annot/20260818', 'annot_002.xml', 'N', 'SEED-PRPG-002');

INSERT INTO AIMS_DEV.T_ITSE_ANNT01L
  (ANNT_ID, INFO_CRET_DTTM, INFO_UPDT_DTTM, FILE_PATH, FILE_NM, FILE_DEL_YN, PRPG_ID)
VALUES ('SEED-ANNT-003', SYSDATE, SYSDATE,
        '/data/aq/annot/20260818', 'annot_003.xml', 'N', 'SEED-PRPG-003');

COMMIT;


-- ############################################################################
-- ## [3] 확인
-- ############################################################################

SELECT 'SNSH_PRPG01L' AS tab, COUNT(*) AS rows_cnt FROM AIMS_DEV.T_ITSE_SNSH_PRPG01L
UNION ALL
SELECT 'LBLL01L', COUNT(*) FROM AIMS_DEV.T_ITSE_LBLL01L
UNION ALL
SELECT 'ANNT01L', COUNT(*) FROM AIMS_DEV.T_ITSE_ANNT01L;

-- 전처리 -> 라벨링 / 어노테이션 연결이 맞는가 (3행이 나와야 한다)
SELECT p.PRPG_ID, p.PRPG_PRGS_RSLT_CD, l.FILE_NM AS label_file, a.FILE_NM AS annot_file
  FROM AIMS_DEV.T_ITSE_SNSH_PRPG01L p, AIMS_DEV.T_ITSE_LBLL01L l, AIMS_DEV.T_ITSE_ANNT01L a
 WHERE p.PRPG_ID = l.PRPG_ID AND p.PRPG_ID = a.PRPG_ID
 ORDER BY p.PRPG_ID;


-- ############################################################################
-- ## [4] 정리
-- ############################################################################

-- DELETE FROM AIMS_DEV.T_ITSE_ANNT01L      WHERE ANNT_ID LIKE 'SEED-%';
-- DELETE FROM AIMS_DEV.T_ITSE_LBLL01L      WHERE LBLL_ID LIKE 'SEED-%';
-- DELETE FROM AIMS_DEV.T_ITSE_SNSH_PRPG01L WHERE PRPG_ID LIKE 'SEED-%';
-- COMMIT;
