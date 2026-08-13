-- Phase 0(재실측): 소스 현재 구조 전수 조사 (읽기 전용)
--
-- 실행:  tbsql aims_dev/aims_dev@SRC @10_source_inventory.sql
--
-- 배경: 소스의 테이블명이 규약에 따라 변경됐다. 기존 스크립트들은 스키마명·테이블명이
--       박혀 있어 그대로 믿을 수 없다. 이 스크립트는 **아무것도 가정하지 않고** 현재
--       상태를 뽑는다. 시스템 계정만 제외한다.
--
-- 산출물:
--   10_source_inventory.log   사람이 읽는 요약
--   10_source_tables.log      "스키마.테이블" 한 줄씩 — 11_name_diff.sh 가 대조에 쓴다
--   10_source_views.log       "스키마.뷰"
--   10_source_synonyms.log    "스키마.시노님 -> 대상스키마.대상테이블"

SET LINESIZE 300
SET PAGESIZE 500
SET TRIMSPOOL ON
SET SERVEROUTPUT ON

DEFINE SYSACCT = "('SYS','SYSCAT','SYSGIS','SYSMASTER','OUTLN','PUBLIC','TIBERO','TIBERO1','LBACSYS','SYSBACKUP')"

SPOOL 10_source_inventory.log

PROMPT ================================================================
PROMPT [1] 스키마 전수  ** 스키마명이 바뀌었는지 여기서 드러난다 **
PROMPT ================================================================
COL owner FORMAT A25
SELECT owner, object_type, COUNT(*) AS cnt FROM all_objects
 WHERE owner NOT IN &SYSACCT
 GROUP BY owner, object_type ORDER BY 1, 2;

PROMPT
PROMPT -- 계정 목록 (created 로 신규 여부 판단)
COL username FORMAT A25
SELECT username, account_status, default_tablespace, created FROM dba_users
 WHERE username NOT IN &SYSACCT ORDER BY created DESC, username;

PROMPT
PROMPT -- 스키마별 용량
SELECT owner, ROUND(SUM(bytes)/1024/1024) AS mb FROM dba_segments
 WHERE owner NOT IN &SYSACCT GROUP BY owner ORDER BY 2 DESC;

PROMPT
PROMPT ================================================================
PROMPT [2] 시노님이 가리키는 스키마  (Tibero 컬럼: ORG_OBJECT_OWNER/NAME)
PROMPT ================================================================
COL org_object_owner FORMAT A25
SELECT owner, org_object_owner, COUNT(*) AS cnt FROM all_synonyms
 WHERE owner NOT IN &SYSACCT
 GROUP BY owner, org_object_owner ORDER BY 3 DESC;

PROMPT
PROMPT -- 시노님 이름과 대상 이름이 다른 건이 있는가
PROMPT -- (규약 변경으로 한쪽만 바뀌었다면 여기서 드러난다)
COL synonym_name FORMAT A38
COL org_object_name FORMAT A38
SELECT owner, synonym_name, org_object_owner, org_object_name FROM all_synonyms
 WHERE owner NOT IN &SYSACCT AND synonym_name <> org_object_name
 ORDER BY 1, 2;
PROMPT -- (0건이면 시노님명 = 대상 테이블명. 이전과 같은 규칙)

PROMPT
PROMPT ================================================================
PROMPT [3] 테이블명 접두사 분포  ** 규약 변경의 형태를 파악 **
PROMPT ================================================================
COL prefix FORMAT A20
SELECT owner,
       SUBSTR(table_name, 1, INSTR(table_name || '_', '_', 1, 2) - 1) AS prefix,
       COUNT(*) AS cnt
  FROM all_tables WHERE owner NOT IN &SYSACCT
 GROUP BY owner, SUBSTR(table_name, 1, INSTR(table_name || '_', '_', 1, 2) - 1)
 ORDER BY 1, 3 DESC;

PROMPT
PROMPT ================================================================
PROMPT [4] 캐릭터셋 / 제약조건 / 파티션  (이전과 달라졌는지)
PROMPT ================================================================
COL parameter FORMAT A32
COL value FORMAT A32
SELECT parameter, value FROM nls_database_parameters
 WHERE parameter LIKE 'NLS_LANG%' OR parameter = 'NLS_LENGTH_SEMANTICS';

PROMPT
SELECT owner, constraint_type, COUNT(*) AS cnt FROM all_constraints
 WHERE owner NOT IN &SYSACCT GROUP BY owner, constraint_type ORDER BY 1, 2;
PROMPT -- P=PK, U=Unique, R=FK, C=Check/NotNull

PROMPT
SELECT owner, COUNT(*) AS part_tables, SUM(partition_count) AS partitions
  FROM all_part_tables WHERE owner NOT IN &SYSACCT GROUP BY owner ORDER BY 1;

PROMPT
PROMPT -- LOB 컬럼 (이관 시 가장 무거운 대상)
COL table_name FORMAT A40
COL column_name FORMAT A32
SELECT owner, table_name, column_name, data_type FROM all_tab_columns
 WHERE owner NOT IN &SYSACCT
   AND data_type IN ('BLOB','CLOB','NCLOB','RAW','LONG','LONG RAW','BFILE')
 ORDER BY 1, 2, column_id;

SPOOL OFF

-- ---------------------------------------------------------------
-- 대조용 목록 파일 (형식 고정: "스키마.이름")
-- ---------------------------------------------------------------
SET HEADING OFF
SET FEEDBACK OFF
SET PAGESIZE 0
SET LINESIZE 200

SPOOL 10_source_tables.log
SELECT owner || '.' || table_name FROM all_tables
 WHERE owner NOT IN &SYSACCT ORDER BY owner, table_name;
SPOOL OFF

SPOOL 10_source_views.log
SELECT owner || '.' || view_name FROM all_views
 WHERE owner NOT IN &SYSACCT ORDER BY owner, view_name;
SPOOL OFF

SPOOL 10_source_synonyms.log
SELECT owner || '.' || synonym_name || ' -> ' || org_object_owner || '.' || org_object_name
  FROM all_synonyms WHERE owner NOT IN &SYSACCT ORDER BY owner, synonym_name;
SPOOL OFF

SET HEADING ON
SET FEEDBACK ON
SET PAGESIZE 200

PROMPT
PROMPT ================================================================
PROMPT 완료. 다음: ./11_name_diff.sh 로 기존 UT(18629)와 대조
PROMPT ================================================================

EXIT;
