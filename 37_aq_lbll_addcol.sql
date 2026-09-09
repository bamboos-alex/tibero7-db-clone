-- ============================================================================
--  T_ITSE_LBLL01L 에 PRPG_STRT_DTTM 추가        ** 실제 변경이 일어난다 **
--  대상: 2차 UT  192.168.0.101:28629 / TAIMS / 스키마 AIMSC_DEV
-- ============================================================================
--
--  왜 필요한가
--    17_aq_tables_ddl.sql 은 2026-08-18 의 원천 구성으로 만들어졌다. 그 뒤 원천이
--    T_ITSE_LBLL01L 에 컬럼을 하나 늘렸는데 스크립트에는 반영되지 않아, 2026-09-08
--    AQ 재생성 결과가 원천보다 한 컬럼 적게 나왔다 (원천 8 / UT 7).
--
--      원천 AIMS_DEV.T_ITSE_LBLL01L  = 8컬럼  ... PRPG_STRT_DTTM DATE (NULL 허용)
--      UT  AIMSC_DEV.T_ITSE_LBLL01L  = 7컬럼  ... 그 컬럼 없음
--
--    T_ITSE_SNSH_PRPG01L 의 PK 가 (PRPG_ID, PRPG_STRT_DTTM) 복합키라, 그것을
--    가리키려면 파티션 키까지 함께 들고 있어야 한다. 앞서 기록해 둔 "PK 가 복합키라
--    업무 ID 단독으로는 찾아갈 수 없다" 의 결과가 컬럼으로 드러난 것이다.
--
--    17_aq_tables_ddl.sql 도 함께 고쳤다. 새로 만드는 DB 에는 이 스크립트가 필요 없다.
--
--  실행:
--    docker exec -it tibero7_ut_tablename bash -lc \
--      'cd /tmp/tbmig && tbsql sys/tibero123@TAIMS @37_aq_lbll_addcol.sql'
--
--  ** DROP 이 없다. 컬럼 추가뿐이고 기존 행은 NULL 이 된다 (원천도 NULL 허용). **
-- ============================================================================

SET LINESIZE 200
SET PAGESIZE 100

PROMPT ================================================================
PROMPT [0] 변경 전 — 7컬럼이어야 한다 (8이면 이미 적용된 것이니 [1] 은 실패한다)
PROMPT ================================================================
COL COLUMN_NAME FORMAT A24
COL DATA_TYPE FORMAT A12
SELECT COLUMN_ID, COLUMN_NAME, DATA_TYPE, DATA_LENGTH, NULLABLE
  FROM ALL_TAB_COLUMNS
 WHERE OWNER = 'AIMSC_DEV' AND TABLE_NAME = 'T_ITSE_LBLL01L'
 ORDER BY COLUMN_ID;

PROMPT ================================================================
PROMPT [1] 컬럼 추가
PROMPT ================================================================
ALTER TABLE AIMSC_DEV.T_ITSE_LBLL01L ADD ("PRPG_STRT_DTTM" DATE);

PROMPT ================================================================
PROMPT [2] 확인 — 8컬럼, 마지막이 PRPG_STRT_DTTM DATE / NULL 허용(Y)
PROMPT ================================================================
SELECT COLUMN_ID, COLUMN_NAME, DATA_TYPE, DATA_LENGTH, NULLABLE
  FROM ALL_TAB_COLUMNS
 WHERE OWNER = 'AIMSC_DEV' AND TABLE_NAME = 'T_ITSE_LBLL01L'
 ORDER BY COLUMN_ID;

PROMPT -- 파티션·PK 가 그대로인지 (파티션 3 / PK ENABLED)
SELECT PARTITION_NO, PARTITION_NAME FROM ALL_TAB_PARTITIONS
 WHERE OWNER='AIMSC_DEV' AND TABLE_NAME='T_ITSE_LBLL01L' ORDER BY PARTITION_NO;
SELECT CONSTRAINT_NAME, STATUS FROM ALL_CONSTRAINTS
 WHERE OWNER='AIMSC_DEV' AND TABLE_NAME='T_ITSE_LBLL01L' AND CONSTRAINT_TYPE='P';

EXIT;
