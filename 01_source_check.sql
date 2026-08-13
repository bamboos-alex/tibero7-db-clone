-- Phase 0-2: 소스 DB 점검 (읽기 전용)
--
-- 실행:  tbsql <user>/<pw>@SRC @01_source_check.sql
-- 결과:  01_source_check.log 로 저장됨
--
-- 타겟에서도 같은 파일을 실행해 두 결과를 대조한다 (특히 캐릭터셋).
--   tbsql <user>/<pw>@TGT @01_source_check.sql

SET LINESIZE 300
SET PAGESIZE 200
SET FEEDBACK ON
SET TRIMSPOOL ON
SET SERVEROUTPUT ON

SPOOL 01_source_check.log

PROMPT ================================================================
PROMPT [1] 접속 정보
PROMPT ================================================================
SELECT USER AS connected_user, SYSDATE AS now FROM DUAL;

PROMPT
PROMPT ================================================================
PROMPT [2] 캐릭터셋  ** 소스/타겟이 다르면 한글이 깨진다. 반드시 대조 **
PROMPT ================================================================
COL parameter FORMAT A40
COL value     FORMAT A40
SELECT parameter, value FROM nls_database_parameters
 WHERE parameter LIKE '%CHARACTERSET%' OR parameter LIKE '%NLS_LANG%';

PROMPT -- 세션 NLS (참고)
SELECT parameter, value FROM nls_session_parameters
 WHERE parameter IN ('NLS_DATE_FORMAT','NLS_TIMESTAMP_FORMAT','NLS_LANGUAGE','NLS_TERRITORY');

PROMPT
PROMPT ================================================================
PROMPT [3] 권한  ** 스키마 전체 추출 가능 여부를 좌우 **
PROMPT ================================================================
COL privilege FORMAT A45
SELECT * FROM session_roles;
SELECT * FROM session_privs
 WHERE privilege LIKE '%ANY%' OR privilege LIKE '%EXPORT%' OR privilege LIKE '%DBA%';

PROMPT
PROMPT ================================================================
PROMPT [4] 대상 스키마 규모
PROMPT ================================================================
COL owner FORMAT A20
SELECT owner, COUNT(*) AS table_cnt
  FROM all_tables WHERE owner IN ('AIMS_DEV','AIMSC_DEV','AIMS_EX') GROUP BY owner ORDER BY owner;

SELECT owner, object_type, COUNT(*) AS cnt
  FROM all_objects WHERE owner IN ('AIMS_DEV','AIMSC_DEV','AIMS_EX')
 GROUP BY owner, object_type ORDER BY owner, object_type;

PROMPT -- 무효 객체 (이관 전 기준값)
SELECT owner, object_type, object_name FROM all_objects
 WHERE owner IN ('AIMS_DEV','AIMSC_DEV','AIMS_EX') AND status <> 'VALID' ORDER BY 1,2,3;

PROMPT
PROMPT === 뷰 목록 ===
PROMPT -- Tibero 의 ALL_VIEWS 는 OWNER / VIEW_NAME / TEXT 뿐이다 (TEXT_LENGTH 없음).
PROMPT -- 정의문 길이는 01c_synonym_scope.sql [6] 에서 PL/SQL 로 잰다.
COL view_name FORMAT A40
SELECT owner, view_name FROM all_views
 WHERE owner IN ('AIMS_DEV','AIMSC_DEV','AIMS_EX') ORDER BY owner, view_name;

PROMPT
PROMPT === 뷰가 다른 뷰를 참조하는가 (적용 순서에 영향) ===
PROMPT -- Tibero 의 ALL_DEPENDENCIES 는 PARENT_OBJ_* 를 쓴다 (REFERENCED_* 아님)
COL name FORMAT A40
COL parent_obj_name FORMAT A40
SELECT owner, name, parent_obj_owner, parent_obj_name
  FROM all_dependencies
 WHERE owner IN ('AIMS_DEV','AIMSC_DEV','AIMS_EX')
   AND type = 'VIEW' AND parent_obj_type = 'VIEW'
 ORDER BY 1,2;
PROMPT -- 결과가 있으면 뷰 생성은 FORCE + 재컴파일 방식이 필요하다 (07_recompile_invalid.sql)

PROMPT
PROMPT ================================================================
PROMPT [5] DBMS_METADATA 사용 가능 여부  ** 경로 B(04a) 전제 **
PROMPT ================================================================
SET LONG 20000
DECLARE
  v CLOB;
BEGIN
  v := DBMS_METADATA.GET_DDL('TABLE','T_ITSE_CMMN01C','AIMS_DEV');
  DBMS_OUTPUT.PUT_LINE('DBMS_METADATA 사용 가능. 길이=' || DBMS_LOB.GETLENGTH(v));
  DBMS_OUTPUT.PUT_LINE(SUBSTR(v,1,3000));
EXCEPTION WHEN OTHERS THEN
  DBMS_OUTPUT.PUT_LINE('DBMS_METADATA 사용 불가 -> 04b(딕셔너리 기반) 사용');
  DBMS_OUTPUT.PUT_LINE(SQLERRM);
END;
/

PROMPT
PROMPT ================================================================
PROMPT [6] LOB/바이너리 컬럼 전수 조사
PROMPT     (기존 덤프에서 0x 리터럴로 깨져 나온 5개 테이블의 실제 자료형 확인)
PROMPT ================================================================
COL table_name  FORMAT A35
COL column_name FORMAT A30
COL data_type   FORMAT A20
SELECT owner, table_name, column_name, data_type, data_length
  FROM all_tab_columns
 WHERE owner IN ('AIMS_DEV','AIMSC_DEV','AIMS_EX')
   AND data_type IN ('BLOB','CLOB','NCLOB','RAW','LONG','LONG RAW','BFILE')
 ORDER BY owner, table_name, column_id;

PROMPT
PROMPT ================================================================
PROMPT [7] 한글 깨짐 원인 규명  ** 핵심 **
PROMPT     소스 원본이 이미 깨져 있으면 -> tbExport가 그대로 옮기므로 손실 없음
PROMPT     소스가 정상이면            -> DBeaver 추출 단계의 문자셋 문제로 확정
PROMPT ================================================================
COL sybl_nm FORMAT A40
COL raw_bytes FORMAT A120
SELECT SYBL_NM, DUMP(SYBL_NM,16) AS raw_bytes
  FROM AIMS_EX.T_ITSE_VMS_SYBL_01I
 WHERE ROWNUM <= 5;

PROMPT -- 판독법:
PROMPT --   EC/EB/EA 로 시작하는 3바이트 묶음  -> 정상 UTF-8 한글 (소스 정상)
PROMPT --   B0~C8 대역 2바이트 묶음            -> EUC-KR/CP949 (소스가 다른 캐릭터셋)
PROMPT --   3f 가 섞여 있음                    -> 원본에서 이미 '?' 로 소실

SELECT column_name, data_type, data_length, char_used
  FROM all_tab_columns
 WHERE owner='AIMS_EX' AND table_name='T_ITSE_VMS_SYBL_01I'
 ORDER BY column_id;

PROMPT
PROMPT ================================================================
PROMPT [8] 용량 추정 (타겟 테이블스페이스 산정용)
PROMPT ================================================================
SELECT owner, SUM(bytes)/1024/1024 AS mb
  FROM dba_segments WHERE owner IN ('AIMS_DEV','AIMSC_DEV','AIMS_EX') GROUP BY owner;
-- 위 쿼리가 권한 부족으로 실패하면 아래 사용:
-- SELECT SUM(bytes)/1024/1024 AS mb FROM user_segments;

SPOOL OFF

PROMPT
PROMPT 완료. 01_source_check.log 를 확인하고, 특히 [2] 캐릭터셋과 [7] 결과를 공유해 주세요.

-- tbsql 이 SQL> 프롬프트에서 대기하지 않도록 반드시 종료한다.
-- (없으면 스크립트 실행 후 입력 대기 상태가 되어 멈춘 것처럼 보인다)
EXIT;
