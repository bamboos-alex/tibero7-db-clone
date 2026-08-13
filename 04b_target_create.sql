-- Phase 2-2: 타겟 테이블스페이스 + 계정 생성  ** 실제 변경이 일어난다 **
--
-- 실행:  docker exec -it tibero7_ut bash -lc 'cd /tmp/tbmig && tbsql sys/tibero123 @04b_target_create.sql'
--
-- 04_target_prepare.sql [0] 실측 반영:
--   데이터파일 경로  /opt/tibero7/database/TAIMS/
--   기존 TS         SYSTEM 100M / SYSSUB 60M / UNDO 1024M / USR 100M
--   대상 계정       없음 (깨끗한 상태)
--   캐릭터셋        UTF8 / BYTE / KOREAN — 소스와 일치
--
-- 크기 산정 (소스 실측)
--   TS_AIMS_DATA       981MB  -> 2G  (AIMS_EX 953 + DEV/CDEV 28)
--   TS_AIMS_IDX         22MB  -> 512M
--   TS_AIMS_HIST_DATA   82MB  -> 1G
--   TS_AIMS_HIST_IDX   100MB  -> 1G
--   전부 AUTOEXTEND 이므로 부족하면 자동으로 늘어난다.
--
-- ** 비밀번호 **: 아래는 소스와 같은 규칙(계정명 = 비밀번호)으로 넣었다.
--                 바꾸려면 IDENTIFIED BY 뒤 세 곳만 고치면 된다.

SET LINESIZE 300
SET PAGESIZE 200
SET SERVEROUTPUT ON

PROMPT ================================================================
PROMPT [1] 사전 확인 — TEMP 테이블스페이스 이름
PROMPT     (dba_data_files 에는 안 나온다. CREATE USER 의 TEMPORARY TABLESPACE 에 쓸 이름)
PROMPT ================================================================
COL tablespace_name FORMAT A25
COL file_name FORMAT A60
SELECT tablespace_name, file_name, ROUND(bytes/1024/1024) AS mb FROM dba_temp_files;

PROMPT
PROMPT -- 위 결과의 이름이 TEMP 가 아니면 아래 CREATE USER 의 TEMPORARY TABLESPACE 를 고칠 것

PROMPT
PROMPT ================================================================
PROMPT [2] 테이블스페이스 생성
PROMPT ================================================================

CREATE TABLESPACE TS_AIMS_DATA
  DATAFILE '/opt/tibero7/database/TAIMS/ts_aims_data_01.dtf' SIZE 2G
  AUTOEXTEND ON NEXT 256M MAXSIZE 20G;

CREATE TABLESPACE TS_AIMS_IDX
  DATAFILE '/opt/tibero7/database/TAIMS/ts_aims_idx_01.dtf' SIZE 512M
  AUTOEXTEND ON NEXT 128M MAXSIZE 5G;

CREATE TABLESPACE TS_AIMS_HIST_DATA
  DATAFILE '/opt/tibero7/database/TAIMS/ts_aims_hist_data_01.dtf' SIZE 1G
  AUTOEXTEND ON NEXT 128M MAXSIZE 10G;

CREATE TABLESPACE TS_AIMS_HIST_IDX
  DATAFILE '/opt/tibero7/database/TAIMS/ts_aims_hist_idx_01.dtf' SIZE 1G
  AUTOEXTEND ON NEXT 128M MAXSIZE 10G;

PROMPT
PROMPT ================================================================
PROMPT [3] 계정 생성  (소스와 동일한 스키마명 유지)
PROMPT ================================================================

CREATE USER AIMS_EX   IDENTIFIED BY "aims_ex"   DEFAULT TABLESPACE TS_AIMS_DATA TEMPORARY TABLESPACE TEMP;
CREATE USER AIMS_DEV  IDENTIFIED BY "aims_dev"  DEFAULT TABLESPACE TS_AIMS_DATA TEMPORARY TABLESPACE TEMP;
CREATE USER AIMSC_DEV IDENTIFIED BY "aimsc_dev" DEFAULT TABLESPACE TS_AIMS_DATA TEMPORARY TABLESPACE TEMP;

PROMPT
PROMPT ================================================================
PROMPT [4] 권한 부여
PROMPT ================================================================

GRANT CONNECT, RESOURCE TO AIMS_EX, AIMS_DEV, AIMSC_DEV;
GRANT CREATE VIEW, CREATE SEQUENCE, CREATE SYNONYM, CREATE PROCEDURE TO AIMS_EX, AIMS_DEV, AIMSC_DEV;
GRANT UNLIMITED TABLESPACE TO AIMS_EX, AIMS_DEV, AIMSC_DEV;

-- ** DBA ** 소스 실측: 세 계정 모두 DBA 를 갖고 있다(dba_role_privs).
-- 이게 없으면 앱·DBeaver 에서 다른 스키마가 보이지 않아 "소스에선 되는데 UT에선 안 되는"
-- 현상이 생긴다. EXP_FULL_DATABASE / SELECT_CATALOG_ROLE 등은 DBA 에 딸려 온다.
GRANT DBA TO AIMS_EX, AIMS_DEV, AIMSC_DEV;

-- 시노님 101개가 AIMS_DEV/AIMSC_DEV -> AIMS_EX 를 가리킨다.
-- tbimport 를 GRANT=Y 로 돌리면 소스의 객체 권한이 그대로 넘어온다.
-- 그래도 뷰가 안 열리면 아래를 임시로 부여한다 (UT 환경이라 범위를 넓게 잡아도 무방).
-- GRANT SELECT ANY TABLE, INSERT ANY TABLE, UPDATE ANY TABLE, DELETE ANY TABLE
--    TO AIMS_DEV, AIMSC_DEV;

PROMPT
PROMPT ================================================================
PROMPT [5] 생성 결과 확인
PROMPT ================================================================
SELECT tablespace_name, ROUND(SUM(bytes)/1024/1024) AS mb, COUNT(*) AS files
  FROM dba_data_files GROUP BY tablespace_name ORDER BY 1;

-- Tibero 의 DBA_USERS 에는 TEMPORARY_TABLESPACE 컬럼이 없다 (TBR-8026 으로 확인).
COL username FORMAT A20
COL default_tablespace FORMAT A25
SELECT username, account_status, default_tablespace
  FROM dba_users WHERE username IN ('AIMS_EX','AIMS_DEV','AIMSC_DEV') ORDER BY 1;

PROMPT -- 롤 (소스와 동일해야 한다: 각 계정에 CONNECT / RESOURCE / DBA)
COL grantee FORMAT A15
COL granted_role FORMAT A25
SELECT grantee, granted_role FROM dba_role_privs
 WHERE grantee IN ('AIMS_EX','AIMS_DEV','AIMSC_DEV') ORDER BY 1,2;

PROMPT
PROMPT ================================================================
PROMPT 다음: 03_export_import.sh dsn -> check -> pilot
PROMPT   SRC_USER=aims_dev SRC_PASS=aims_dev TGT_USER=sys TGT_PASS=tibero123 \
PROMPT     DRYRUN=0 ./03_export_import.sh pilot
PROMPT
PROMPT UNDO 가 1024M 이고 AUTOEXTEND 가 NO 다. 대량 적재 중 undo 부족 오류가 나면:
PROMPT   ALTER TABLESPACE UNDO ADD DATAFILE '/opt/tibero7/database/TAIMS/undo002.dtf'
PROMPT     SIZE 1G AUTOEXTEND ON NEXT 256M MAXSIZE 8G;
PROMPT ================================================================

-- tbsql 이 SQL> 프롬프트에서 대기하지 않도록 반드시 종료한다.
-- (없으면 스크립트 실행 후 입력 대기 상태가 되어 멈춘 것처럼 보인다)
EXIT;
