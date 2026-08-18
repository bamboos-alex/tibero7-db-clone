-- AIMSC_DEV 이력 테이블 8개 — 재구축에 필요한 나머지 실측 (읽기 전용)
--
-- 실행:
--   docker exec -it tibero7_ut_tablename bash -lc \
--     'cd /tmp/tbmig && tbsql sys/tibero123 @13b_hist_detail.sql'
--
-- 산출물: 13b_hist_detail.log
--
-- 13_target_survey.sql 로 알아낸 것
--   AIMSC_DEV 에 12개 테이블이 이미 있고, 이력(_01L) 8개는 파티션이 없다.
--   전체 79행(시험 데이터)이라 재구축 부담은 없다.
--
-- 아직 모르는 것 — 이것이 없으면 DDL 을 쓸 수 없다
--   1. PK 가 어느 컬럼으로 구성되는가
--      로컬 유니크 인덱스는 파티션 키를 반드시 포함해야 하므로,
--      기존 PK 에 파티션 키를 덧붙인 복합키로 바꿔야 한다.
--   2. 파티션 키 후보 컬럼에 NULL 이 들어 있는가
--      PK 컬럼은 NOT NULL 이어야 한다. 기존 행에 NULL 이 있으면
--      재구축 시 적재가 실패하므로 먼저 메워야 한다.
--   3. 실제 데이터의 날짜 범위
--      월별 파티션을 어느 달부터 만들지 정하는 근거.

SET LINESIZE 300
SET PAGESIZE 500
SET TRIMSPOOL ON
SET SERVEROUTPUT ON SIZE 1000000
SET LONG 200000

SPOOL 13b_hist_detail.log

COL table_name      FORMAT A28
COL constraint_name FORMAT A30
COL column_name     FORMAT A24
COL index_name      FORMAT A30

PROMPT ================================================================
PROMPT [1] AIMSC_DEV 12개 테이블의 PK 컬럼 구성
PROMPT     복합키로 바꿀 때 기존 컬럼 순서를 유지하기 위해 필요하다.
PROMPT ================================================================
SELECT c.table_name, c.constraint_name, cc.position, cc.column_name
  FROM all_constraints c, all_cons_columns cc
 WHERE c.owner = 'AIMSC_DEV'
   AND c.constraint_type = 'P'
   AND cc.owner = c.owner
   AND cc.constraint_name = c.constraint_name
 ORDER BY c.table_name, cc.position;

PROMPT
PROMPT -- 위가 비어 있으면 all_cons_columns 컬럼명이 다른 것이다.
PROMPT -- 그때는 인덱스 컬럼으로 대신 본다 (PK 는 유니크 인덱스로 구현돼 있다).
SELECT table_name, index_name, column_position, column_name
  FROM all_ind_columns
 WHERE table_owner = 'AIMSC_DEV'
 ORDER BY table_name, index_name, column_position;

PROMPT
PROMPT ================================================================
PROMPT [2] 날짜 컬럼의 NULL 건수와 값 범위
PROMPT     NULL 이 있으면 그 컬럼은 그대로 파티션 키로 쓸 수 없다.
PROMPT     (PK 컬럼은 NOT NULL 이어야 하고, 파티션 키는 PK 에 들어가야 한다)
PROMPT ================================================================
DECLARE
  v_tot   NUMBER;
  v_null  NUMBER;
  v_min   VARCHAR2(30);
  v_max   VARCHAR2(30);
  v_prev  VARCHAR2(128) := '~';
BEGIN
  DBMS_OUTPUT.PUT_LINE(RPAD('테이블.컬럼', 56) || LPAD('전체',7) || LPAD('NULL',7)
                       || '  ' || RPAD('최소', 12) || RPAD('최대', 12));
  DBMS_OUTPUT.PUT_LINE(RPAD('-', 96, '-'));
  FOR c IN (
    SELECT t.table_name, c.column_name
      FROM all_tables t, all_tab_columns c
     WHERE t.owner = 'AIMSC_DEV'
       AND c.owner = t.owner AND c.table_name = t.table_name
       AND c.data_type IN ('DATE','TIMESTAMP')
     ORDER BY t.table_name, c.column_id )
  LOOP
    IF c.table_name <> v_prev AND v_prev <> '~' THEN
      DBMS_OUTPUT.PUT_LINE(' ');
    END IF;
    v_prev := c.table_name;
    BEGIN
      EXECUTE IMMEDIATE
        'SELECT COUNT(*), COUNT(*) - COUNT("' || c.column_name || '"),'
        || ' NVL(TO_CHAR(MIN("' || c.column_name || '"),''YYYY/MM/DD''),''-''),'
        || ' NVL(TO_CHAR(MAX("' || c.column_name || '"),''YYYY/MM/DD''),''-'')'
        || ' FROM "AIMSC_DEV"."' || c.table_name || '"'
        INTO v_tot, v_null, v_min, v_max;
      DBMS_OUTPUT.PUT_LINE(
        RPAD(c.table_name || '.' || c.column_name, 56)
        || LPAD(TO_CHAR(v_tot), 7) || LPAD(TO_CHAR(v_null), 7)
        || '  ' || RPAD(v_min, 12) || RPAD(v_max, 12)
        || CASE WHEN v_tot > 0 AND v_null = 0 THEN '  <- 파티션 키 가능' ELSE '' END);
    EXCEPTION WHEN OTHERS THEN
      DBMS_OUTPUT.PUT_LINE(RPAD(c.table_name || '.' || c.column_name, 56)
                           || '  <실패: ' || SQLERRM || '>');
    END;
  END LOOP;
END;
/

PROMPT
PROMPT ================================================================
PROMPT [3] 이력 테이블 8개의 현재 DDL 원본
PROMPT     재구축 시 컬럼 정의를 그대로 옮기기 위한 근거다.
PROMPT     (DEFAULT 값, 컬럼 순서 등 딕셔너리 조회로는 놓치는 것이 있다)
PROMPT ================================================================
SET HEADING OFF
SET FEEDBACK OFF
SELECT DBMS_METADATA.GET_DDL('TABLE', table_name, 'AIMSC_DEV')
  FROM all_tables
 WHERE owner = 'AIMSC_DEV' AND table_name LIKE '%01L'
 ORDER BY table_name;
SET HEADING ON
SET FEEDBACK ON

SPOOL OFF

PROMPT
PROMPT ================================================================
PROMPT 결과 파일: 13b_hist_detail.log
PROMPT ================================================================

-- tbsql 이 SQL> 프롬프트에서 대기하지 않도록 반드시 종료한다.
EXIT;
