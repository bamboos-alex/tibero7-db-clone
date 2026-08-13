-- Phase 4: 타겟 검증 (읽기 전용)
--
-- 실행:  tbsql <user>/<pw>@TGT @05_verify.sql
--
-- 산출물:
--   05_target_meta.log       02_baseline_meta.log 과 대조
--   05_gen_counts.sql        타겟 건수 스크립트 (자동 생성)
--   05_target_counts.log     02_baseline_counts.log 과 대조
--
-- 대조는 06_compare.sh 로 수행한다.

SET LINESIZE 300
SET PAGESIZE 200
SET TRIMSPOOL ON
SET SERVEROUTPUT ON

-- 한글 검증 표본. 소스 테이블명이 바뀌면 이 두 줄만 고치면 된다.
-- (2026-08-13 규약 변경: T_AAAA_/T_AAAB_/T_TIP?_ -> T_ITSE_ 로 통합)
DEFINE KOR_TAB  = "AIMS_EX.T_ITSE_VMS_SYBL_01I"
DEFINE KOR_COL  = "SYBL_NM"
DEFINE CODE_TAB = "AIMS_DEV.T_ITSE_CMMN01C"

-- ---------------------------------------------------------------
-- (1) 메타 개수 — 02 와 동일한 쿼리 (그대로 diff 하기 위해 순서·형식 유지)
-- ---------------------------------------------------------------
SPOOL 05_target_meta.log

PROMPT === 접속/시각 ===
SELECT USER AS connected_user, SYSDATE AS snapshot_at FROM DUAL;

PROMPT
PROMPT === 스키마별 객체 개수 ===
COL owner FORMAT A20
SELECT owner, object_type, COUNT(*) AS cnt FROM all_objects
 WHERE owner IN ('AIMS_DEV','AIMSC_DEV','AIMS_EX') GROUP BY owner, object_type ORDER BY 1,2;

PROMPT
PROMPT === 테이블/컬럼 개수 ===
SELECT owner, COUNT(DISTINCT table_name) AS tables, COUNT(*) AS columns
  FROM all_tab_columns WHERE owner IN ('AIMS_DEV','AIMSC_DEV','AIMS_EX') GROUP BY owner ORDER BY 1;

PROMPT
PROMPT === 제약조건 개수 (유형별) ===
SELECT owner, constraint_type, COUNT(*) AS cnt FROM all_constraints
 WHERE owner IN ('AIMS_DEV','AIMSC_DEV','AIMS_EX') GROUP BY owner, constraint_type ORDER BY 1,2;

PROMPT
PROMPT === 인덱스 개수 ===
SELECT owner, COUNT(*) AS cnt FROM all_indexes
 WHERE owner IN ('AIMS_DEV','AIMSC_DEV','AIMS_EX') GROUP BY owner ORDER BY 1;

PROMPT
PROMPT === 시노님 개수  (AIMS_DEV/AIMSC_DEV 각 101개 -> AIMS_EX) ===
SELECT owner, COUNT(*) AS cnt FROM all_synonyms
 WHERE owner IN ('AIMS_DEV','AIMSC_DEV','AIMS_EX') GROUP BY owner ORDER BY 1;

PROMPT
PROMPT === 파티션 테이블 / 파티션 개수  ** 소스 기준 162개 테이블 ** ===
SELECT owner, COUNT(*) AS part_tables, SUM(partition_count) AS partitions
  FROM all_part_tables
 WHERE owner IN ('AIMS_DEV','AIMSC_DEV','AIMS_EX') GROUP BY owner ORDER BY 1;

PROMPT
PROMPT === 패키지 / 프로시저 ===
COL object_name FORMAT A40
SELECT owner, object_type, object_name, status FROM all_objects
 WHERE owner IN ('AIMS_DEV','AIMSC_DEV','AIMS_EX')
   AND object_type IN ('PACKAGE','PACKAGE BODY','PROCEDURE','FUNCTION','TRIGGER','TYPE')
 ORDER BY 1,2,3;

PROMPT
PROMPT === 뷰 목록 ===
PROMPT -- Tibero ALL_VIEWS 에는 TEXT_LENGTH 컬럼이 없다 (OWNER / VIEW_NAME / TEXT 뿐)
COL view_name FORMAT A40
SELECT owner, view_name FROM all_views
 WHERE owner IN ('AIMS_DEV','AIMSC_DEV','AIMS_EX') ORDER BY owner, view_name;

PROMPT
PROMPT === 시퀀스 ===
COL sequence_name FORMAT A35
SELECT sequence_owner, sequence_name, last_number, increment_by FROM all_sequences
 WHERE sequence_owner IN ('AIMS_DEV','AIMSC_DEV','AIMS_EX') ORDER BY 1,2;

SPOOL OFF

-- ---------------------------------------------------------------
-- (2) 타겟 고유 점검
-- ---------------------------------------------------------------
SPOOL 05_target_health.log

PROMPT === 무효 객체  ** 0건이어야 정상 ** ===
PROMPT -- 뷰가 남아 있으면 07_recompile_invalid.sql 을 먼저 실행했는지 확인할 것
COL object_name FORMAT A40
SELECT owner, object_type, object_name, status FROM all_objects
 WHERE owner IN ('AIMS_DEV','AIMSC_DEV','AIMS_EX') AND status <> 'VALID' ORDER BY 1,2,3;

PROMPT
PROMPT === 뷰 실제 조회 가능 여부  ** 컴파일만 통과하고 조회에서 깨지는 경우를 잡는다 ** ===
DECLARE
  v_cnt PLS_INTEGER;
  v_ok  PLS_INTEGER := 0;
  v_ng  PLS_INTEGER := 0;
BEGIN
  FOR r IN ( SELECT owner, view_name FROM all_views
              WHERE owner IN ('AIMS_DEV','AIMSC_DEV','AIMS_EX') ORDER BY owner, view_name ) LOOP
    BEGIN
      EXECUTE IMMEDIATE 'SELECT COUNT(*) FROM (SELECT * FROM "' || r.owner || '"."'
                        || r.view_name || '" WHERE ROWNUM <= 1)' INTO v_cnt;
      v_ok := v_ok + 1;
    EXCEPTION WHEN OTHERS THEN
      v_ng := v_ng + 1;
      DBMS_OUTPUT.PUT_LINE('조회 실패: ' || r.owner || '.' || r.view_name || ' -> ' || SQLERRM);
    END;
  END LOOP;
  DBMS_OUTPUT.PUT_LINE('뷰 조회 성공 ' || v_ok || '건 / 실패 ' || v_ng || '건');
END;
/

PROMPT
PROMPT === 비활성/미검증 제약조건  ** 0건이어야 정상 ** ===
COL constraint_name FORMAT A35
SELECT owner, table_name, constraint_name, constraint_type, status, validated
  FROM all_constraints
 WHERE owner IN ('AIMS_DEV','AIMSC_DEV','AIMS_EX')
   AND (status <> 'ENABLED' OR validated <> 'VALIDATED')
 ORDER BY 1,2,3;

PROMPT
PROMPT === 사용 불가 인덱스  ** 0건이어야 정상 ** ===
SELECT owner, index_name, table_name, status FROM all_indexes
 WHERE owner IN ('AIMS_DEV','AIMSC_DEV','AIMS_EX') AND status NOT IN ('VALID','N/A') ORDER BY 1,2;

PROMPT
PROMPT === 한글 무결성 확인  ** 소스의 01_source_check.sql [7] 결과와 바이트 단위로 일치해야 함 ** ===
COL sample FORMAT A40
COL raw_bytes FORMAT A120
SELECT &KOR_COL AS sample, DUMP(&KOR_COL,16) AS raw_bytes
  FROM &KOR_TAB WHERE ROWNUM <= 5;

PROMPT
PROMPT === 일반 한글 표본 ===
SELECT CD_ID, CD_NM FROM &CODE_TAB WHERE ROWNUM <= 10;

PROMPT
PROMPT === LOB 총량 (BLOB/CLOB 컬럼을 가진 테이블 전수) ===
PROMPT -- 테이블명을 박아두지 않는다. 딕셔너리에서 LOB 컬럼을 찾아 동적으로 집계한다.
PROMPT -- (소스의 테이블명 규약이 바뀌어도 이 블록은 그대로 동작한다)
DECLARE
  v_cols  VARCHAR2(4000);
  v_rows  NUMBER;
  v_bytes NUMBER;
  v_n     PLS_INTEGER := 0;
BEGIN
  FOR t IN ( SELECT owner, table_name FROM all_tab_columns
              WHERE owner IN ('AIMS_DEV','AIMSC_DEV','AIMS_EX')
                AND data_type IN ('BLOB','CLOB','NCLOB')
              GROUP BY owner, table_name
              ORDER BY owner, table_name ) LOOP
    v_cols := NULL;
    FOR c IN ( SELECT column_name FROM all_tab_columns
                WHERE owner = t.owner AND table_name = t.table_name
                  AND data_type IN ('BLOB','CLOB','NCLOB')
                ORDER BY column_id ) LOOP
      v_cols := v_cols || CASE WHEN v_cols IS NULL THEN '' ELSE ' + ' END
             || 'NVL(DBMS_LOB.GETLENGTH("' || c.column_name || '"),0)';
    END LOOP;

    BEGIN
      EXECUTE IMMEDIATE 'SELECT COUNT(*), NVL(SUM(' || v_cols || '),0) FROM "'
                        || t.owner || '"."' || t.table_name || '"'
        INTO v_rows, v_bytes;
      v_n := v_n + 1;
      DBMS_OUTPUT.PUT_LINE(RPAD(t.owner || '.' || t.table_name, 46)
        || LPAD(TO_CHAR(v_rows), 12) || LPAD(TO_CHAR(v_bytes), 16));
    EXCEPTION WHEN OTHERS THEN
      DBMS_OUTPUT.PUT_LINE(RPAD(t.owner || '.' || t.table_name, 46) || '  조회 실패: ' || SQLERRM);
    END;
  END LOOP;
  DBMS_OUTPUT.PUT_LINE('-- LOB 보유 테이블 ' || v_n || '개 (좌: 행수, 우: LOB 바이트)');
END;
/

SPOOL OFF

-- ---------------------------------------------------------------
-- (3) 타겟 건수 스크립트 생성 (02 와 동일 로직, 출력 파일명만 다름)
-- ---------------------------------------------------------------
SET HEADING OFF
SET FEEDBACK OFF
SET PAGESIZE 0
SET LINESIZE 500

SPOOL 05_gen_counts.sql

SELECT txt FROM (
    SELECT 1 AS s1, 0 AS s2, 'SET PAGESIZE 5000'                     AS txt FROM DUAL
    UNION ALL SELECT 1, 1, 'SET LINESIZE 200'                               FROM DUAL
    UNION ALL SELECT 1, 2, 'SET FEEDBACK OFF'                               FROM DUAL
    UNION ALL SELECT 1, 3, 'SET TRIMSPOOL ON'                               FROM DUAL
    UNION ALL SELECT 1, 4, 'COL tab FORMAT A45'                             FROM DUAL
    UNION ALL SELECT 1, 5, 'SPOOL 05_target_counts.log'                     FROM DUAL
    UNION ALL SELECT 1, 6, 'SELECT tab, cnt FROM ('                         FROM DUAL
    UNION ALL
    SELECT 2, ROWNUM,
           'SELECT ''' || owner || '.' || table_name || ''' tab, COUNT(*) cnt FROM "'
           || owner || '"."' || table_name || '" UNION ALL'
      FROM ( SELECT owner, table_name FROM all_tables
              WHERE owner IN ('AIMS_DEV','AIMSC_DEV','AIMS_EX')
              ORDER BY owner, table_name )
    UNION ALL SELECT 3, 0, 'SELECT ''~~END~~'' tab, -1 cnt FROM DUAL'       FROM DUAL
    UNION ALL SELECT 3, 1, ') ORDER BY tab;'                                FROM DUAL
    UNION ALL SELECT 3, 2, 'SPOOL OFF'                                      FROM DUAL
    UNION ALL SELECT 3, 3, 'EXIT;'                                          FROM DUAL
) ORDER BY s1, s2;

SPOOL OFF

-- ---------------------------------------------------------------
-- (4) 타겟 뷰 건수 스크립트 생성 (02 와 동일 로직)
-- ---------------------------------------------------------------
SPOOL 05_gen_view_counts.sql

SELECT txt FROM (
    SELECT 1 AS s1, 0 AS s2, 'SET PAGESIZE 0'                       AS txt FROM DUAL
    UNION ALL SELECT 1, 1, 'SET HEADING OFF'                               FROM DUAL
    UNION ALL SELECT 1, 2, 'SET FEEDBACK OFF'                              FROM DUAL
    UNION ALL SELECT 1, 3, 'SET LINESIZE 200'                              FROM DUAL
    UNION ALL SELECT 1, 4, 'SET TRIMSPOOL ON'                              FROM DUAL
    UNION ALL SELECT 1, 5, 'WHENEVER SQLERROR CONTINUE'                    FROM DUAL
    UNION ALL SELECT 1, 6, 'SPOOL 05_target_view_counts.log'               FROM DUAL
    UNION ALL
    SELECT 2, ROWNUM,
           'SELECT ''' || owner || '.' || view_name || ''' || ''  '' || COUNT(*) FROM "'
           || owner || '"."' || view_name || '";'
      FROM ( SELECT owner, view_name FROM all_views
              WHERE owner IN ('AIMS_DEV','AIMSC_DEV','AIMS_EX')
              ORDER BY owner, view_name )
    UNION ALL SELECT 3, 0, 'SPOOL OFF'                                     FROM DUAL
    UNION ALL SELECT 3, 1, 'EXIT;'                                         FROM DUAL
) ORDER BY s1, s2;

SPOOL OFF

SET HEADING ON
SET FEEDBACK ON
SET PAGESIZE 200

PROMPT
PROMPT ================================================================
PROMPT 다음:
PROMPT   @05_gen_counts.sql       -> 05_target_counts.log
PROMPT   @05_gen_view_counts.sql  -> 05_target_view_counts.log
PROMPT 그 뒤 소스 로그와 함께 ./06_compare.sh 로 대조하세요.
PROMPT   ./06_compare.sh 02_baseline_counts.log 05_target_counts.log 02_baseline_meta.log 05_target_meta.log
PROMPT   ./06_compare.sh 02_baseline_view_counts.log 05_target_view_counts.log
PROMPT ================================================================

-- tbsql 이 SQL> 프롬프트에서 대기하지 않도록 반드시 종료한다.
-- (없으면 스크립트 실행 후 입력 대기 상태가 되어 멈춘 것처럼 보인다)
EXIT;
