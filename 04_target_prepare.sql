-- Phase 2-1: 타겟(docker tibero7) 준비
--
-- 실행:  tbsql sys/<syspw>@TGT --sysdba @04_target_prepare.sql
--
-- ** 실행 전 반드시 아래 [0] 확인 구간만 먼저 돌려보고, 경로/크기를 환경에 맞게 고칠 것 **
-- 이 스크립트는 계정과 테이블스페이스를 "생성"하므로 되돌리기 번거롭다.

SET LINESIZE 300
SET PAGESIZE 200
SET SERVEROUTPUT ON

PROMPT ================================================================
PROMPT [0] 현재 상태 확인 (여기까지 먼저 실행)
PROMPT ================================================================
COL tablespace_name FORMAT A25
COL file_name       FORMAT A70
SELECT tablespace_name, ROUND(SUM(bytes)/1024/1024) AS mb, COUNT(*) AS files
  FROM dba_data_files GROUP BY tablespace_name ORDER BY 1;

SELECT file_name, ROUND(bytes/1024/1024) AS mb, autoextensible
  FROM dba_data_files ORDER BY tablespace_name;

PROMPT -- 이미 존재하는 대상 계정 (있으면 아래 CREATE USER 는 건너뛴다)
SELECT username, account_status, default_tablespace FROM dba_users
 WHERE username IN ('AIMS_DEV','AIMSC_DEV');

PROMPT
PROMPT ** 소스 용량(01_source_check.sql [8])보다 넉넉하게 잡을 것.
PROMPT ** 384MB LOB 테이블이 있으므로 데이터파일 여유가 부족하면 여기서 멈추고 확보한다.
PROMPT

-- ================================================================
-- [1] 테이블스페이스 생성   ※ 경로와 크기를 환경에 맞게 수정
-- ================================================================
-- 데이터파일 경로는 위 dba_data_files 의 기존 경로를 참고해 같은 디렉터리로 맞춘다.

-- CREATE TABLESPACE TS_AIMS
--   DATAFILE '/tibero/tibero7/database/tibero/ts_aims_01.dtf' SIZE 2G
--   AUTOEXTEND ON NEXT 256M MAXSIZE 20G;

-- CREATE TABLESPACE TS_AIMS_LOB
--   DATAFILE '/tibero/tibero7/database/tibero/ts_aims_lob_01.dtf' SIZE 2G
--   AUTOEXTEND ON NEXT 256M MAXSIZE 20G;

-- ================================================================
-- [2] 계정 생성
-- ================================================================
-- 소스와 같은 스키마명을 유지한다 (AIMS_DEV -> AIMS_DEV).

-- CREATE USER AIMS_DEV  IDENTIFIED BY "<비밀번호>" DEFAULT TABLESPACE TS_AIMS TEMPORARY TABLESPACE TEMP;
-- CREATE USER AIMSC_DEV IDENTIFIED BY "<비밀번호>" DEFAULT TABLESPACE TS_AIMS TEMPORARY TABLESPACE TEMP;

-- ALTER USER AIMS_DEV  QUOTA UNLIMITED ON TS_AIMS;
-- ALTER USER AIMSC_DEV QUOTA UNLIMITED ON TS_AIMS;

-- ================================================================
-- [3] 권한 부여
-- ================================================================
-- GRANT CONNECT, RESOURCE TO AIMS_DEV, AIMSC_DEV;
-- GRANT CREATE VIEW, CREATE SEQUENCE, CREATE SYNONYM, CREATE PROCEDURE TO AIMS_DEV, AIMSC_DEV;
-- GRANT UNLIMITED TABLESPACE TO AIMS_DEV, AIMSC_DEV;

-- 두 스키마가 서로를 참조한다면 상호 조회 권한도 필요할 수 있다 (소스에서 확인 후):
-- SELECT grantee, owner, table_name, privilege FROM dba_tab_privs
--  WHERE owner IN ('AIMS_DEV','AIMSC_DEV');   <-- 소스에서 실행해 결과를 옮긴다

-- ================================================================
-- [4] 캐릭터셋 재확인  ** 소스와 다르면 여기서 멈춘다 **
-- ================================================================
SELECT parameter, value FROM nls_database_parameters
 WHERE parameter LIKE '%CHARACTERSET%';

PROMPT
PROMPT ================================================================
PROMPT 소스의 [2] 캐릭터셋 결과와 값이 동일한지 확인하세요.
PROMPT 다르면 이관을 진행하지 말고 타겟 DB를 소스와 같은 캐릭터셋으로 재생성해야 합니다.
PROMPT (캐릭터셋은 DB 생성 시점에 결정되며 사후 변경이 사실상 불가합니다)
PROMPT ================================================================
