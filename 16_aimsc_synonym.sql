-- AIMSC_DEV 에 T_ITSE_CCTV_01M 시노님 추가  ** 실제 변경이 일어난다 **
--
-- 실행:
--   docker exec -it tibero7_ut_tablename bash -lc \
--     'cd /tmp/tbmig && tbsql sys/tibero123 @16_aimsc_synonym.sql'
--
-- 왜 시노님인가
--   실측 결과 T_ITSE_CCTV_01M 의 실테이블은 AIMS_EX 에 있고(42컬럼),
--   AIMS_DEV 는 그것을 시노님으로 본다. AIMSC_DEV 에는 둘 다 없다.
--
--   같은 이름의 실테이블을 AIMSC_DEV 에 새로 만들면 CCTV 원장이 둘이 되어
--   동기화 문제가 생긴다. 이 DB 는 원래 시노님 계층 구조이고
--   (AIMSC_DEV 의 기존 시노님 100개가 전부 AIMS_EX 를 가리킨다),
--   본사/지사 테이블도 이미 같은 방식으로 처리돼 있다:
--       AIMSC_DEV.T_ITSE_HDQR_01M  -> AIMS_EX.T_ITSE_HDQR_01M
--       AIMSC_DEV.T_ITSE_MTNOF_01M -> AIMS_EX.T_ITSE_MTNOF_01M
--   CCTV 만 빠져 있어 같은 규칙으로 채운다.
--
--   앱 용도가 "CAMR_ID 와 MTNOF_ID 를 조회" 라 읽기 전용이므로
--   시노님으로 충분하다.

SET LINESIZE 300
SET PAGESIZE 100

PROMPT ================================================================
PROMPT [1] 생성 전 확인 — AIMS_EX 에 실테이블이 있는가
PROMPT ================================================================
COL owner FORMAT A12
COL object_name FORMAT A24
COL object_type FORMAT A12
SELECT owner, object_name, object_type, status FROM all_objects
 WHERE object_name = 'T_ITSE_CCTV_01M' ORDER BY owner;

PROMPT
PROMPT ================================================================
PROMPT [2] 시노님 생성
PROMPT ================================================================
CREATE SYNONYM AIMSC_DEV.T_ITSE_CCTV_01M FOR AIMS_EX.T_ITSE_CCTV_01M;

PROMPT
PROMPT ================================================================
PROMPT [3] 확인 — 기존 HDQR/MTNOF 와 같은 모양이어야 한다
PROMPT ================================================================
COL synonym_name FORMAT A24
COL org_object_owner FORMAT A12
COL org_object_name FORMAT A24
SELECT owner, synonym_name, org_object_owner, org_object_name
  FROM all_synonyms
 WHERE owner='AIMSC_DEV'
   AND synonym_name IN ('T_ITSE_CCTV_01M','T_ITSE_HDQR_01M','T_ITSE_MTNOF_01M')
 ORDER BY synonym_name;

PROMPT
PROMPT -- 실제로 조회되는가 (aimsc_dev 계정이 AIMS_EX 를 읽을 수 있어야 한다)
SELECT COUNT(*) AS cctv_rows FROM AIMSC_DEV.T_ITSE_CCTV_01M;

PROMPT
PROMPT ================================================================
PROMPT 위 COUNT 가 권한 오류로 실패하면 aimsc_dev 에 DBA 롤이 빠진 것이다.
PROMPT   GRANT DBA TO AIMSC_DEV;
PROMPT (04b_target_create.sql / 09_refresh.sh 에 이미 반영돼 있다)
PROMPT ================================================================

-- tbsql 이 SQL> 프롬프트에서 대기하지 않도록 반드시 종료한다.
EXIT;
