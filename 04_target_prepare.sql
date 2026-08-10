-- Phase 2-1: 타겟(docker tibero7) 준비  ** 변경 발생 **
--
-- 실행:  tbsql sys/<syspw> @04_target_prepare.sql
--        (tbsql 에는 --sysdba 옵션이 없다. DSN 없이 붙으면 컨테이너의 TB_SID 로 로컬 접속되고
--         sys 는 그 경로에서 sysdba 권한을 갖는다. 안 되면 tbsql 안에서 CONNECT sys/<pw> AS SYSDBA)
--
-- ** [0] 확인 구간만 먼저 실행하고, 데이터파일 경로를 환경에 맞게 고친 뒤 나머지를 실행할 것 **
--
-- 소스 실측값 (01b/01c 결과)
--   AIMS_DEV    127MB   테이블 158, 뷰 58, 시노님 101, 파티션 81, 패키지 1
--   AIMSC_DEV   104MB   테이블 157, 뷰 53, 시노님 101, 파티션 81, 패키지 1
--   AIMS_EX     954MB   테이블 101, 인덱스 16   <- 실데이터 대부분 (BLOB 186MB 포함)
--   합계      1,185MB
--
--   테이블스페이스별:  TS_AIMS_DATA 981MB / TS_AIMS_IDX 22MB
--                      TS_AIMS_HIST_DATA 82MB / TS_AIMS_HIST_IDX 100MB
--
--   소스와 같은 이름으로 만들면 DDL 의 TABLESPACE 절을 고칠 필요가 없다.

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

PROMPT -- 데이터파일 경로 (아래 CREATE TABLESPACE 의 경로를 이 디렉터리로 맞춘다)
SELECT file_name, ROUND(bytes/1024/1024) AS mb, autoextensible
  FROM dba_data_files ORDER BY tablespace_name;

PROMPT -- 이미 존재하는 대상 계정 (있으면 CREATE USER 는 건너뛴다)
SELECT username, account_status, default_tablespace FROM dba_users
 WHERE username IN ('AIMS_DEV','AIMSC_DEV','AIMS_EX');

PROMPT
PROMPT === 캐릭터셋  ** 소스와 반드시 일치해야 한다 ** ===
PROMPT -- 소스 실측: NLS_LANG_AT_BOOT = UTF8 , NLS_LENGTH_SEMANTICS = BYTE
COL parameter FORMAT A40
COL value     FORMAT A40
SELECT parameter, value FROM nls_database_parameters
 WHERE parameter IN ('NLS_LANG_AT_BOOT','NLS_LENGTH_SEMANTICS','NLS_LANGUAGE','NLS_TERRITORY');

PROMPT
PROMPT ** 위 NLS_LANG_AT_BOOT 이 UTF8 이 아니면 여기서 멈춘다.
PROMPT ** 캐릭터셋은 DB 생성 시점에 결정되며 사후 변경이 불가하다. 타겟 DB 재생성이 필요하다.
PROMPT

-- ================================================================
-- [1] 테이블스페이스 생성   ※ 경로를 [0] 결과에 맞게 수정할 것
-- ================================================================
-- 크기는 소스 실측치의 2배 이상 + AUTOEXTEND 로 잡았다.

-- CREATE TABLESPACE TS_AIMS_DATA
--   DATAFILE '/tibero/tibero7/database/tibero/ts_aims_data_01.dtf' SIZE 2G
--   AUTOEXTEND ON NEXT 256M MAXSIZE 20G;

-- CREATE TABLESPACE TS_AIMS_IDX
--   DATAFILE '/tibero/tibero7/database/tibero/ts_aims_idx_01.dtf' SIZE 512M
--   AUTOEXTEND ON NEXT 128M MAXSIZE 5G;

-- CREATE TABLESPACE TS_AIMS_HIST_DATA
--   DATAFILE '/tibero/tibero7/database/tibero/ts_aims_hist_data_01.dtf' SIZE 1G
--   AUTOEXTEND ON NEXT 128M MAXSIZE 10G;

-- CREATE TABLESPACE TS_AIMS_HIST_IDX
--   DATAFILE '/tibero/tibero7/database/tibero/ts_aims_hist_idx_01.dtf' SIZE 1G
--   AUTOEXTEND ON NEXT 128M MAXSIZE 10G;

-- ================================================================
-- [2] 계정 생성   (소스와 같은 스키마명 유지)
-- ================================================================
-- 소스의 DEFAULT_TABLESPACE 는 세 계정 모두 TS_AIMS_DATA 였다.

-- CREATE USER AIMS_DEV  IDENTIFIED BY "<비밀번호>" DEFAULT TABLESPACE TS_AIMS_DATA TEMPORARY TABLESPACE TEMP;
-- CREATE USER AIMSC_DEV IDENTIFIED BY "<비밀번호>" DEFAULT TABLESPACE TS_AIMS_DATA TEMPORARY TABLESPACE TEMP;
-- CREATE USER AIMS_EX   IDENTIFIED BY "<비밀번호>" DEFAULT TABLESPACE TS_AIMS_DATA TEMPORARY TABLESPACE TEMP;

-- ================================================================
-- [3] 권한 부여
-- ================================================================
-- GRANT CONNECT, RESOURCE TO AIMS_DEV, AIMSC_DEV, AIMS_EX;
-- GRANT CREATE VIEW, CREATE SEQUENCE, CREATE SYNONYM, CREATE PROCEDURE TO AIMS_DEV, AIMSC_DEV, AIMS_EX;
-- GRANT UNLIMITED TABLESPACE TO AIMS_DEV, AIMSC_DEV, AIMS_EX;

-- ** 중요 **  AIMS_DEV / AIMSC_DEV 의 시노님 101개가 각각 AIMS_EX 의 테이블을 가리킨다.
--            시노님이 동작하려면 AIMS_EX 객체에 대한 조회 권한이 필요하다.
--            소스에서 실제 부여된 권한을 확인해 그대로 옮기는 것이 정확하다:
--
--   [소스에서 실행]
--     SELECT grantee, owner, table_name, privilege FROM dba_tab_privs
--      WHERE owner = 'AIMS_EX' AND grantee IN ('AIMS_DEV','AIMSC_DEV');
--
--   결과가 테이블 단위로 많으면 아래처럼 일괄 부여도 가능하다(권한 범위가 넓어지는 점 유의):
--     GRANT SELECT ANY TABLE, INSERT ANY TABLE, UPDATE ANY TABLE, DELETE ANY TABLE
--        TO AIMS_DEV, AIMSC_DEV;

-- ================================================================
-- [4] 생성 후 확인
-- ================================================================
-- SELECT tablespace_name, ROUND(SUM(bytes)/1024/1024) AS mb FROM dba_data_files
--  GROUP BY tablespace_name ORDER BY 1;
-- SELECT username, default_tablespace FROM dba_users
--  WHERE username IN ('AIMS_DEV','AIMSC_DEV','AIMS_EX');

PROMPT
PROMPT ================================================================
PROMPT 다음: 03_export_import.sh pilot  (반드시 전량 실행 전에)
PROMPT 적재 순서는 AIMS_EX -> AIMS_DEV -> AIMSC_DEV 다.
PROMPT (시노님이 AIMS_EX 를 가리키므로 대상 테이블이 먼저 있어야 한다)
PROMPT ================================================================

-- tbsql 이 SQL> 프롬프트에서 대기하지 않도록 반드시 종료한다.
-- (없으면 스크립트 실행 후 입력 대기 상태가 되어 멈춘 것처럼 보인다)
EXIT;
