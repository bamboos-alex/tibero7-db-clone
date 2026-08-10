-- Phase 0-4: 시노님 대상 스키마 확정 (읽기 전용)
--
-- 실행:  tbsql aims_dev/aims_dev@SRC @01c_synonym_scope.sql
--
-- 배경: 01b 에서 ALL_SYNONYMS 의 TABLE_OWNER / TABLE_NAME / DB_LINK 가 모두
--       "Invalid identifier" 로 실패했다. Tibero 의 딕셔너리 컬럼명이 Oracle 과 다르다.
--       (ALL_DEPENDENCIES 가 PARENT_OBJ_OWNER 를 쓰는 것과 같은 맥락)
--       먼저 컬럼 구조를 확인한 뒤, 시노님이 가리키는 스키마를 확정한다.
--
--       01b [3] 에서 BLOB 5개 테이블이 AIMS_EX 소유로 확인됐다.
--       AIMS_EX 외에 다른 스키마가 더 있는지가 이 스크립트의 목적이다.

SET LINESIZE 300
SET PAGESIZE 500
SET TRIMSPOOL ON
SET SERVEROUTPUT ON

SPOOL 01c_synonym_scope.log

PROMPT ================================================================
PROMPT [1] ALL_SYNONYMS 컬럼 구조  ** 여기서 올바른 컬럼명을 확인한다 **
PROMPT ================================================================
COL column_name FORMAT A30
COL data_type   FORMAT A20
SELECT column_name, data_type, data_length FROM all_tab_columns
 WHERE table_name = 'ALL_SYNONYMS' ORDER BY column_id;

PROMPT
PROMPT -- 실제 데이터 표본 (컬럼 헤더로 이름을 재확인)
SELECT * FROM all_synonyms WHERE owner = 'AIMS_DEV' AND ROWNUM <= 10;

PROMPT
PROMPT ================================================================
PROMPT [2] 이 DB 의 전체 스키마와 객체 수  ** 이관 대상 후보 전수 파악 **
PROMPT ================================================================
COL owner FORMAT A25
SELECT owner, COUNT(*) AS object_cnt FROM all_objects
 WHERE owner NOT IN ('SYS','SYSCAT','SYSGIS','SYSMASTER','OUTLN','PUBLIC','TIBERO','TIBERO1')
 GROUP BY owner ORDER BY 2 DESC;

PROMPT
PROMPT -- 계정 목록
COL username FORMAT A25
COL default_tablespace FORMAT A25
SELECT username, account_status, default_tablespace, created FROM dba_users
 WHERE username NOT IN ('SYS','SYSCAT','SYSGIS','SYSMASTER','OUTLN','TIBERO','TIBERO1')
 ORDER BY username;

PROMPT
PROMPT -- 스키마별 용량
SELECT owner, ROUND(SUM(bytes)/1024/1024) AS mb FROM dba_segments
 WHERE owner NOT IN ('SYS','SYSCAT','SYSGIS','SYSMASTER','OUTLN','TIBERO','TIBERO1')
 GROUP BY owner ORDER BY 2 DESC;

PROMPT
PROMPT ================================================================
PROMPT [3] AIMS_EX 상세  ** BLOB 테이블이 있는 스키마 **
PROMPT ================================================================
SELECT object_type, COUNT(*) AS cnt FROM all_objects
 WHERE owner = 'AIMS_EX' GROUP BY object_type ORDER BY 1;

PROMPT
PROMPT -- 테이블스페이스 분포
COL tablespace_name FORMAT A25
SELECT tablespace_name, COUNT(*) AS seg_cnt, ROUND(SUM(bytes)/1024/1024) AS mb
  FROM dba_segments WHERE owner = 'AIMS_EX' GROUP BY tablespace_name ORDER BY 1;

PROMPT
PROMPT -- 파티션 테이블 여부
COL table_name FORMAT A40
SELECT table_name, partitioning_type, partition_count FROM all_part_tables
 WHERE owner = 'AIMS_EX' ORDER BY 1;

PROMPT
PROMPT -- LOB 컬럼 전체
SELECT table_name, column_name, data_type FROM all_tab_columns
 WHERE owner = 'AIMS_EX'
   AND data_type IN ('BLOB','CLOB','NCLOB','RAW','LONG','LONG RAW','BFILE')
 ORDER BY table_name, column_id;

PROMPT
PROMPT -- LOB 실제 용량  ** 타겟 테이블스페이스 산정의 핵심 **
SELECT 'T_TIPA_VMS_SYBL_01I' AS tab, COUNT(*) AS rows_cnt,
       ROUND(SUM(DBMS_LOB.GETLENGTH(SYBL_IMG_FILE_CTNT)
               + DBMS_LOB.GETLENGTH(SYBL_RED_FILE_CTNT)
               + DBMS_LOB.GETLENGTH(SYBL_GRN_FILE_CTNT))/1024/1024) AS lob_mb
  FROM AIMS_EX.T_TIPA_VMS_SYBL_01I;

PROMPT
PROMPT ================================================================
PROMPT [4] 무효 객체 기준값  (소스에서 이미 무효인 것은 타겟에서도 무효가 정상)
PROMPT ================================================================
COL object_name FORMAT A40
SELECT owner, object_type, object_name FROM all_objects
 WHERE owner IN ('AIMS_DEV','AIMSC_DEV','AIMS_EX') AND status <> 'VALID'
 ORDER BY 1,2,3;

PROMPT
PROMPT ================================================================
PROMPT [5] 뷰가 다른 뷰를 참조하는가  (Tibero 컬럼명 PARENT_OBJ_* 로 수정)
PROMPT ================================================================
COL name FORMAT A40
COL parent_obj_name FORMAT A40
SELECT owner, name, parent_obj_owner, parent_obj_name
  FROM all_dependencies
 WHERE owner IN ('AIMS_DEV','AIMSC_DEV','AIMS_EX')
   AND type = 'VIEW' AND parent_obj_type = 'VIEW'
 ORDER BY 1,2;
PROMPT -- 결과가 있으면 뷰는 FORCE 생성 + 07_recompile_invalid.sql 재컴파일이 필요하다

PROMPT
PROMPT ================================================================
PROMPT [6] 뷰 정의문 길이  (Tibero ALL_VIEWS 에는 TEXT_LENGTH 가 없어 직접 잰다)
PROMPT     32767 초과 뷰는 B2 로 추출 불가 -> B1 또는 수동
PROMPT ================================================================
COL view_name FORMAT A40
DECLARE
  v_txt VARCHAR2(32767);
  v_cnt PLS_INTEGER := 0;
BEGIN
  FOR r IN ( SELECT owner, view_name, text FROM all_views
              WHERE owner IN ('AIMS_DEV','AIMSC_DEV','AIMS_EX')
              ORDER BY owner, view_name ) LOOP
    BEGIN
      v_txt := r.text;
      IF LENGTH(v_txt) > 8000 THEN
        DBMS_OUTPUT.PUT_LINE(RPAD(r.owner||'.'||r.view_name, 50) || LENGTH(v_txt));
      END IF;
    EXCEPTION WHEN OTHERS THEN
      v_cnt := v_cnt + 1;
      DBMS_OUTPUT.PUT_LINE('32767 초과(추출 불가): ' || r.owner || '.' || r.view_name);
    END;
  END LOOP;
  DBMS_OUTPUT.PUT_LINE('-- 32767 초과 뷰: ' || v_cnt || '개 (0 이면 B2 로도 전부 추출 가능)');
END;
/

SPOOL OFF

PROMPT
PROMPT ================================================================
PROMPT 완료: 01c_synonym_scope.log
PROMPT [1] 컬럼명과 [2] 스키마 목록이 이관 범위를 확정합니다.
PROMPT ================================================================

-- tbsql 이 SQL> 프롬프트에서 대기하지 않도록 반드시 종료한다.
-- (없으면 스크립트 실행 후 입력 대기 상태가 되어 멈춘 것처럼 보인다)
EXIT;
