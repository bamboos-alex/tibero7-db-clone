-- AIMSC_DEV 신규 테이블 15개 — 현재 상태 실측 (읽기 전용)
--
-- 실행:
--   docker exec -it tibero7_ut_tablename bash -lc \
--     'cd /tmp/tbmig && tbsql sys/tibero123 @13_target_survey.sql'
--
-- 산출물: 13_target_survey.log
--
-- 왜 이 스크립트가 먼저인가
--   요청받은 15개 테이블의 컬럼 정의가 없다. 그런데 이 DB 는 시노님 계층
--   구조이고(AIMSC_DEV 는 시노님으로 다른 스키마의 실테이블을 본다),
--   2026-08-13 이관 이후 사용자가 AIMSC_DEV 에 테이블을 직접 추가했다.
--   따라서 각 이름이 지금 어떤 상태인지 — 없는가 / 실테이블인가 / 시노님인가,
--   있다면 파티션과 로컬 인덱스를 갖췄는가 — 를 먼저 재야 한다.
--   측정 없이 CREATE 를 쏘면 이름 충돌 아니면 데이터 이중화가 된다.
--
-- 이 스크립트로 가려는 것
--   A. 다른 스키마에 실물이 있다        -> 시노님으로 해결 가능
--   B. AIMSC_DEV 에 이미 있고 관례대로다 -> 할 일 없음
--   C. AIMSC_DEV 에 있으나 파티션이 없다 -> 재구축 (행 수가 방식을 가른다)
--   D. 어디에도 없다                    -> 컬럼 정의서를 받아야 만들 수 있다
--
-- Tibero 딕셔너리 주의 (실측으로 확인된 차이)
--   ALL_SYNONYMS       ORG_OBJECT_OWNER / ORG_OBJECT_NAME  (TABLE_OWNER 없음)
--   ALL_TAB_PARTITIONS TABLE_OWNER 없음  -> 파티션 정보는 ALL_PART_TABLES 로 본다
--   ALL_INDEXES        TABLE_OWNER 있음  (확인됨)
--   SET LONGCHUNKSIZE  tbsql 이 거부한다 -> 쓰지 않는다

SET LINESIZE 300
SET PAGESIZE 500
SET TRIMSPOOL ON
SET SERVEROUTPUT ON
SET LONG 200000

SPOOL 13_target_survey.log

PROMPT === 접속/시각 ===
SELECT USER AS connected_user, SYSDATE AS surveyed_at FROM DUAL;

COL owner           FORMAT A12
COL object_name     FORMAT A32
COL object_type     FORMAT A14
COL status          FORMAT A9
COL table_name      FORMAT A32
COL index_name      FORMAT A32
COL column_name     FORMAT A28
COL synonym_name    FORMAT A32
COL org_object_name FORMAT A32

PROMPT
PROMPT ================================================================
PROMPT [1] 요청 15개 이름 — 현재 누가 점유하고 있는가
PROMPT     같은 이름이 여러 스키마에 나오면 시노님/실테이블이 섞인 것이다.
PROMPT ================================================================
SELECT object_name, owner, object_type, status
  FROM all_objects
 WHERE object_name IN (
       'T_ITSE_AI_CCTV01M','T_ITSE_CCTV_01M','T_ITSE_SNSH_STUP01M',
       'T_ITSE_SNSH_GTHR01L','T_ITSE_SNSH_PRPG01L','T_ITSE_LBLL01L',
       'T_ITSE_ANNT01L','T_ITSE_DATST01M','T_ITSE_AI_DGNST01L',
       'T_ITSE_AI_MVPCT_DGNST01L','T_ITSE_AI_DRF_DGNST01L','T_ITSE_AI_MODL01M',
       'T_ITSE_HDQR_01M','T_ITSE_MTNOF_01M','T_ITSE_AI_MODL_OP01L')
 ORDER BY object_name, owner;

PROMPT
PROMPT -- 아래에 나오는 이름은 DB 어디에도 없다 = 컬럼 정의서가 필요한 것들
SELECT nm AS missing_name FROM (
  SELECT 'T_ITSE_AI_CCTV01M' nm FROM DUAL
  UNION ALL SELECT 'T_ITSE_CCTV_01M'          FROM DUAL
  UNION ALL SELECT 'T_ITSE_SNSH_STUP01M'      FROM DUAL
  UNION ALL SELECT 'T_ITSE_SNSH_GTHR01L'      FROM DUAL
  UNION ALL SELECT 'T_ITSE_SNSH_PRPG01L'      FROM DUAL
  UNION ALL SELECT 'T_ITSE_LBLL01L'           FROM DUAL
  UNION ALL SELECT 'T_ITSE_ANNT01L'           FROM DUAL
  UNION ALL SELECT 'T_ITSE_DATST01M'          FROM DUAL
  UNION ALL SELECT 'T_ITSE_AI_DGNST01L'       FROM DUAL
  UNION ALL SELECT 'T_ITSE_AI_MVPCT_DGNST01L' FROM DUAL
  UNION ALL SELECT 'T_ITSE_AI_DRF_DGNST01L'   FROM DUAL
  UNION ALL SELECT 'T_ITSE_AI_MODL01M'        FROM DUAL
  UNION ALL SELECT 'T_ITSE_HDQR_01M'          FROM DUAL
  UNION ALL SELECT 'T_ITSE_MTNOF_01M'         FROM DUAL
  UNION ALL SELECT 'T_ITSE_AI_MODL_OP01L'     FROM DUAL
) WHERE nm NOT IN (SELECT object_name FROM all_objects);

PROMPT
PROMPT ================================================================
PROMPT [2] 15개 중 시노님으로 잡힌 것 — 무엇을 가리키는가
PROMPT     여기 나오면 같은 이름의 실테이블을 그 스키마에 만들 수 없다.
PROMPT ================================================================
SELECT owner, synonym_name, org_object_owner, org_object_name
  FROM all_synonyms
 WHERE synonym_name IN (
       'T_ITSE_AI_CCTV01M','T_ITSE_CCTV_01M','T_ITSE_SNSH_STUP01M',
       'T_ITSE_SNSH_GTHR01L','T_ITSE_SNSH_PRPG01L','T_ITSE_LBLL01L',
       'T_ITSE_ANNT01L','T_ITSE_DATST01M','T_ITSE_AI_DGNST01L',
       'T_ITSE_AI_MVPCT_DGNST01L','T_ITSE_AI_DRF_DGNST01L','T_ITSE_AI_MODL01M',
       'T_ITSE_HDQR_01M','T_ITSE_MTNOF_01M','T_ITSE_AI_MODL_OP01L')
 ORDER BY owner, synonym_name;

PROMPT
PROMPT -- 스키마별 시노님 총계 (이관 직후 AIMS_DEV/AIMSC_DEV 각 100개였다)
SELECT owner, COUNT(*) AS synonyms FROM all_synonyms
 WHERE owner IN ('AIMS_EX','AIMS_DEV','AIMSC_DEV') GROUP BY owner ORDER BY owner;

PROMPT
PROMPT ================================================================
PROMPT [3] 유사 이름 탐색 — 개명·변형된 동일 테이블 찾기
PROMPT ================================================================
SELECT object_name, owner, object_type
  FROM all_objects
 WHERE owner IN ('AIMS_EX','AIMS_DEV','AIMSC_DEV')
   AND object_type IN ('TABLE','SYNONYM','VIEW')
   AND ( object_name LIKE '%CCTV%'  OR object_name LIKE '%HDQR%'
      OR object_name LIKE '%MTNOF%' OR object_name LIKE '%SNSH%'
      OR object_name LIKE '%LBLL%'  OR object_name LIKE '%ANNT%'
      OR object_name LIKE '%DATST%' OR object_name LIKE '%DGNST%'
      OR object_name LIKE '%MODL%' )
 ORDER BY object_name, owner;

PROMPT
PROMPT ================================================================
PROMPT [4] AIMSC_DEV 현재 전모 — 이관 이후 무엇이 추가됐나
PROMPT     이관 직후(2026-08-13)에는 테이블 0 / 시노님 100 / 패키지 1 이었다.
PROMPT ================================================================
SELECT object_type, COUNT(*) AS cnt FROM all_objects
 WHERE owner='AIMSC_DEV' GROUP BY object_type ORDER BY object_type;

PROMPT
PROMPT -- AIMSC_DEV 실테이블 전체
PROMPT    (ANSI LEFT JOIN 대신 두 쿼리로 나눴다. Tibero 딕셔너리에서 예상 밖의
PROMPT     컬럼명 차이를 여러 번 만났기 때문에 문법 위험을 줄인다.)
SELECT table_name, tablespace_name FROM all_tables
 WHERE owner='AIMSC_DEV' ORDER BY table_name;

PROMPT
PROMPT -- 그중 파티션 테이블인 것 (여기 없는 이력 테이블이 재구축 대상이다)
COL partitioning_type FORMAT A10
SELECT table_name, partitioning_type, partition_count
  FROM all_part_tables WHERE owner='AIMSC_DEV' ORDER BY table_name;

PROMPT
PROMPT -- 파티션 테이블의 파티션 키
COL name FORMAT A32
SELECT name, column_name, column_position
  FROM all_part_key_columns WHERE owner='AIMSC_DEV'
 ORDER BY name, column_position;

PROMPT
PROMPT -- AIMSC_DEV 인덱스: PARTITIONED=NO 인데 테이블이 파티션이면 GLOBAL 이다
COL uniqueness FORMAT A10
COL partitioned FORMAT A11
COL tablespace_name FORMAT A20
SELECT table_name, index_name, uniqueness, partitioned, tablespace_name
  FROM all_indexes WHERE table_owner='AIMSC_DEV'
 ORDER BY table_name, index_name;

PROMPT
PROMPT ================================================================
PROMPT [5] AIMSC_DEV 테이블 실제 행 수
PROMPT     0행이면 DROP 후 재생성이 가능하고, 행이 있으면 이관 절차가 필요하다.
PROMPT     num_rows(통계값)는 믿을 수 없으므로 실제로 센다.
PROMPT ================================================================
DECLARE
  v_cnt   NUMBER;
  v_total NUMBER := 0;
BEGIN
  FOR t IN (SELECT table_name FROM all_tables WHERE owner='AIMSC_DEV' ORDER BY table_name) LOOP
    BEGIN
      EXECUTE IMMEDIATE 'SELECT COUNT(*) FROM "AIMSC_DEV"."' || t.table_name || '"' INTO v_cnt;
      DBMS_OUTPUT.PUT_LINE(RPAD(t.table_name, 40) || LPAD(TO_CHAR(v_cnt), 12));
      v_total := v_total + v_cnt;
    EXCEPTION WHEN OTHERS THEN
      DBMS_OUTPUT.PUT_LINE(RPAD(t.table_name, 40) || '  <조회 실패: ' || SQLERRM || '>');
    END;
  END LOOP;
  DBMS_OUTPUT.PUT_LINE(RPAD('=== 합계', 40) || LPAD(TO_CHAR(v_total), 12));
END;
/

PROMPT
PROMPT ================================================================
PROMPT [6] 요청 15개 중 실재하는 것의 컬럼 정의
PROMPT     여기 나오는 테이블은 정의서 없이 그대로 복제할 수 있다.
PROMPT ================================================================
COL data_type FORMAT A14
COL nullable FORMAT A8
SELECT owner, table_name, column_id, column_name, data_type,
       data_length, data_precision, data_scale, nullable
  FROM all_tab_columns
 WHERE table_name IN (
       'T_ITSE_AI_CCTV01M','T_ITSE_CCTV_01M','T_ITSE_SNSH_STUP01M',
       'T_ITSE_SNSH_GTHR01L','T_ITSE_SNSH_PRPG01L','T_ITSE_LBLL01L',
       'T_ITSE_ANNT01L','T_ITSE_DATST01M','T_ITSE_AI_DGNST01L',
       'T_ITSE_AI_MVPCT_DGNST01L','T_ITSE_AI_DRF_DGNST01L','T_ITSE_AI_MODL01M',
       'T_ITSE_HDQR_01M','T_ITSE_MTNOF_01M','T_ITSE_AI_MODL_OP01L')
   AND owner IN ('AIMS_EX','AIMS_DEV','AIMSC_DEV')
 ORDER BY owner, table_name, column_id;

PROMPT
PROMPT ================================================================
PROMPT [7] 마스터 테이블(_01M)의 테이블스페이스 관례
PROMPT     신규 _01M 을 어디에 둘지 정하는 근거.
PROMPT ================================================================
SELECT tablespace_name, COUNT(*) AS tables
  FROM all_tables
 WHERE owner IN ('AIMS_DEV','AIMS_EX') AND table_name LIKE '%01M'
 GROUP BY tablespace_name ORDER BY 2 DESC;

SPOOL OFF

PROMPT
PROMPT ================================================================
PROMPT 결과 파일: 13_target_survey.log
PROMPT   ./sync.sh pull 로 회수해 주세요.
PROMPT ================================================================

-- tbsql 이 SQL> 프롬프트에서 대기하지 않도록 반드시 종료한다.
EXIT;
