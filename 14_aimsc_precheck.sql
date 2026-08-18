-- AIMSC_DEV 이력 테이블 재구축 — 사전 안전 점검 (읽기 전용)
--
-- 실행:
--   docker exec -it tibero7_ut_tablename bash -lc \
--     'cd /tmp/tbmig && tbsql sys/tibero123 @14_aimsc_precheck.sql'
--
-- 15_aimsc_hist_rebuild.sql 은 이력 테이블 8개를 DROP 후 재생성한다.
-- DROP 은 테이블만 지우는 것이 아니라 그 테이블에 딸린 제약조건·인덱스·
-- 부여된 권한을 함께 없애고, 그것을 참조하던 객체를 무효로 만든다.
-- 무엇이 딸려 있는지 먼저 확인한다.
--
-- ** [1]~[4] 가 전부 0건이어야 그대로 진행할 수 있다. **
-- 하나라도 나오면 15 를 실행하기 전에 알려 주세요. 복원 구문을 넣어야 한다.

SET LINESIZE 300
SET PAGESIZE 300
SET TRIMSPOOL ON
SET SERVEROUTPUT ON

SPOOL 14_aimsc_precheck.log

PROMPT === 점검 시각 ===
SELECT USER AS connected_user, SYSDATE AS checked_at FROM DUAL;

COL table_name       FORMAT A28
COL constraint_name  FORMAT A30
COL owner            FORMAT A12
COL name             FORMAT A32
COL type             FORMAT A14
COL grantee          FORMAT A16
COL privilege        FORMAT A16
COL tablespace_name  FORMAT A22

PROMPT
PROMPT ================================================================
PROMPT [1] 이 테이블들을 참조하는 외래키 (자식 테이블)
PROMPT     있으면 DROP 이 막히거나 참조 무결성이 끊긴다.
PROMPT ================================================================
SELECT c.owner, c.table_name, c.constraint_name, c.r_constraint_name
  FROM all_constraints c
 WHERE c.constraint_type = 'R'
   AND c.r_constraint_name IN (
       SELECT constraint_name FROM all_constraints
        WHERE owner='AIMSC_DEV' AND constraint_type='P' AND table_name LIKE '%01L')
 ORDER BY 1,2;
PROMPT   (아무것도 없으면 정상)

PROMPT
PROMPT ================================================================
PROMPT [2] 이 테이블들을 참조하는 뷰 / 시노님 / 프로시저
PROMPT     DROP 하면 무효(INVALID)가 된다. 재생성 후 재컴파일이 필요할 수 있다.
PROMPT ================================================================
SELECT owner, name, type, parent_obj_owner, parent_obj_name
  FROM all_dependencies
 WHERE parent_obj_owner = 'AIMSC_DEV'
   AND parent_obj_name LIKE '%01L'
 ORDER BY owner, name;
PROMPT   (아무것도 없으면 정상)

PROMPT
PROMPT -- 다른 스키마에서 이 테이블들을 가리키는 시노님
SELECT owner, synonym_name, org_object_owner, org_object_name
  FROM all_synonyms
 WHERE org_object_owner = 'AIMSC_DEV' AND org_object_name LIKE '%01L'
 ORDER BY owner, synonym_name;
PROMPT   (아무것도 없으면 정상)

PROMPT
PROMPT ================================================================
PROMPT [3] 이 테이블들에 부여된 객체 권한
PROMPT     DROP 하면 사라진다. 있으면 재생성 후 다시 GRANT 해야 한다.
PROMPT ================================================================
-- Tibero 의 ALL_TAB_PRIVS 에는 Oracle 의 TABLE_SCHEMA 컬럼이 없다 (TBR-8026 확인).
-- 컬럼명을 추측하지 않기 위해 구조를 먼저 찍고, 조회는 SELECT * 로 한다.
COL column_name FORMAT A24
SELECT column_name, data_type FROM all_tab_columns
 WHERE table_name = 'ALL_TAB_PRIVS' ORDER BY column_id;

PROMPT
SELECT * FROM all_tab_privs WHERE table_name LIKE '%01L';
PROMPT   (아무것도 없으면 정상)

PROMPT
PROMPT ================================================================
PROMPT [4] 백업 테이블 이름이 이미 쓰이고 있는가
PROMPT     15 가 T_..._BAK 을 만든다. 같은 이름이 있으면 실패한다.
PROMPT ================================================================
SELECT table_name FROM all_tables
 WHERE owner='AIMSC_DEV' AND table_name LIKE '%\_BAK' ESCAPE '\'
 ORDER BY table_name;
PROMPT   (아무것도 없으면 정상)

PROMPT
PROMPT ================================================================
PROMPT [5] 파티션 키로 쓸 컬럼의 NULL — 실행 직전 재확인
PROMPT     NULL 이 1건이라도 있으면 그 테이블의 데이터 복원이 실패한다.
PROMPT     (PK 컬럼은 NOT NULL 이어야 하기 때문)
PROMPT ================================================================
DECLARE
  v_tot NUMBER; v_null NUMBER; v_bad NUMBER := 0;
BEGIN
  DBMS_OUTPUT.PUT_LINE(RPAD('테이블.파티션키', 50) || LPAD('전체',8) || LPAD('NULL',8) || '  판정');
  DBMS_OUTPUT.PUT_LINE(RPAD('-', 80, '-'));
  -- Tibero 는 PL/SQL RECORD 생성자 t_rec(...) 를 지원하지 않는다 (TBR-15048 확인).
  -- 목록은 인라인 커서로 만든다.
  FOR r IN (
              SELECT 'T_ITSE_AI_DGNST01L'  AS tab, 'STRT_DTTM' AS col FROM DUAL
    UNION ALL SELECT 'T_ITSE_AI_DRF_DGNST01L',   'AI_DGNST_DTTM'      FROM DUAL
    UNION ALL SELECT 'T_ITSE_AI_MODL_OP01L',     'MNTG_STRT_DTTM'     FROM DUAL
    UNION ALL SELECT 'T_ITSE_AI_MVPCT_DGNST01L', 'AI_DGNST_DTTM'      FROM DUAL
    UNION ALL SELECT 'T_ITSE_ANNT01L',           'INFO_CRET_DTTM'     FROM DUAL
    UNION ALL SELECT 'T_ITSE_LBLL01L',           'INFO_CRET_DTTM'     FROM DUAL
    UNION ALL SELECT 'T_ITSE_SNSH_GTHR01L',      'STRT_DTTM'          FROM DUAL
    UNION ALL SELECT 'T_ITSE_SNSH_PRPG01L',      'PRPG_STRT_DTTM'     FROM DUAL )
  LOOP
    EXECUTE IMMEDIATE
      'SELECT COUNT(*), COUNT(*) - COUNT("' || r.col || '") FROM "AIMSC_DEV"."' || r.tab || '"'
      INTO v_tot, v_null;
    IF v_null > 0 THEN v_bad := v_bad + 1; END IF;
    DBMS_OUTPUT.PUT_LINE(RPAD(r.tab || '.' || r.col, 50)
      || LPAD(TO_CHAR(v_tot), 8) || LPAD(TO_CHAR(v_null), 8)
      || CASE WHEN v_null = 0 THEN '  OK' ELSE '  ** NULL 있음 - 이 테이블은 진행 불가 **' END);
  END LOOP;
  DBMS_OUTPUT.PUT_LINE(' ');
  IF v_bad = 0 THEN
    DBMS_OUTPUT.PUT_LINE('=> 8개 전부 이상 없음. 15_aimsc_hist_rebuild.sql 진행 가능.');
  ELSE
    DBMS_OUTPUT.PUT_LINE('=> ' || v_bad || '개 테이블에 NULL 이 있다. 값을 메우거나 파티션 키를 바꿔야 한다.');
  END IF;
END;
/

PROMPT
PROMPT ================================================================
PROMPT [6] 대상 테이블스페이스 여유
PROMPT     데이터가 79행뿐이라 문제될 일은 없지만 존재 여부는 확인한다.
PROMPT ================================================================
SELECT tablespace_name, ROUND(SUM(bytes)/1024/1024) AS mb, COUNT(*) AS files
  FROM dba_data_files
 WHERE tablespace_name IN ('TS_AIMS_HIST_DATA','TS_AIMS_HIST_IDX','TS_AIMS_DATA','TS_AIMS_IDX')
 GROUP BY tablespace_name ORDER BY 1;

SPOOL OFF

PROMPT
PROMPT ================================================================
PROMPT [1]~[4] 가 전부 비어 있고 [5] 가 "8개 전부 이상 없음" 이면
PROMPT 15_aimsc_hist_rebuild.sql 을 그대로 실행하면 된다.
PROMPT ================================================================

-- tbsql 이 SQL> 프롬프트에서 대기하지 않도록 반드시 종료한다.
EXIT;
