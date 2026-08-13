-- Phase 1: 기준 스냅샷 생성 (읽기 전용)
--
-- 실행:  tbsql <user>/<pw>@SRC @02_baseline_snapshot.sql
--
-- 산출물:
--   02_baseline_meta.log     테이블/컬럼/제약조건/인덱스 개수 + LOB 총량
--   02_gen_counts.sql        테이블별 실제 건수를 세는 스크립트 (자동 생성)
--   02_baseline_counts.log   위 스크립트를 실행한 결과 (건수 대조표)
--
-- 이 3개 파일이 Phase 4 검증의 기준값이다. 이관 후 타겟에서 동일하게 뽑아 대조한다.

SET LINESIZE 300
SET PAGESIZE 200
SET TRIMSPOOL ON
SET SERVEROUTPUT ON

-- ---------------------------------------------------------------
-- (1) 메타 개수 스냅샷
-- ---------------------------------------------------------------
SPOOL 02_baseline_meta.log

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
PROMPT -- P=PK, U=Unique, R=FK, C=Check/NotNull

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
-- (2) 테이블별 건수 스크립트 자동 생성
-- ---------------------------------------------------------------
SET HEADING OFF
SET FEEDBACK OFF
SET PAGESIZE 0
SET LINESIZE 500
SET VERIFY OFF

SPOOL 02_gen_counts.sql

SELECT txt FROM (
    SELECT 1 AS s1, 0 AS s2, 'SET PAGESIZE 5000'                     AS txt FROM DUAL
    UNION ALL SELECT 1, 1, 'SET LINESIZE 200'                               FROM DUAL
    UNION ALL SELECT 1, 2, 'SET FEEDBACK OFF'                               FROM DUAL
    UNION ALL SELECT 1, 3, 'SET TRIMSPOOL ON'                               FROM DUAL
    UNION ALL SELECT 1, 4, 'COL tab FORMAT A45'                             FROM DUAL
    UNION ALL SELECT 1, 5, 'SPOOL 02_baseline_counts.log'                   FROM DUAL
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
-- (3) 뷰 건수 스크립트 생성 (선택)
--     뷰마다 독립 SELECT 로 만든다. 무효 뷰 하나가 실패해도 나머지는 계속 실행된다.
--     (테이블처럼 UNION ALL 로 묶으면 뷰 하나가 깨질 때 전체가 중단된다)
-- ---------------------------------------------------------------
SPOOL 02_gen_view_counts.sql

SELECT txt FROM (
    SELECT 1 AS s1, 0 AS s2, 'SET PAGESIZE 0'                       AS txt FROM DUAL
    UNION ALL SELECT 1, 1, 'SET HEADING OFF'                               FROM DUAL
    UNION ALL SELECT 1, 2, 'SET FEEDBACK OFF'                              FROM DUAL
    UNION ALL SELECT 1, 3, 'SET LINESIZE 200'                              FROM DUAL
    UNION ALL SELECT 1, 4, 'SET TRIMSPOOL ON'                              FROM DUAL
    UNION ALL SELECT 1, 5, 'WHENEVER SQLERROR CONTINUE'                    FROM DUAL
    UNION ALL SELECT 1, 6, 'SPOOL 02_baseline_view_counts.log'             FROM DUAL
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
PROMPT 02_gen_counts.sql / 02_gen_view_counts.sql 생성 완료.
PROMPT 파일 앞뒤에 tbsql 프롬프트 잔여 줄이 붙었으면 지운 뒤 실행하세요:
PROMPT     @02_gen_counts.sql        -> 02_baseline_counts.log       (테이블 건수)
PROMPT     @02_gen_view_counts.sql   -> 02_baseline_view_counts.log  (뷰 건수, 선택)
PROMPT ================================================================

-- tbsql 이 SQL> 프롬프트에서 대기하지 않도록 반드시 종료한다.
-- (없으면 스크립트 실행 후 입력 대기 상태가 되어 멈춘 것처럼 보인다)
EXIT;
