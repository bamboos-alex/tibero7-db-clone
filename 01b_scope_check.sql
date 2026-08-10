-- Phase 0-3: 이관 범위 확정 (읽기 전용)
--
-- 실행:  tbsql aims_dev/aims_dev@SRC @01b_scope_check.sql
--
-- 배경: 01_source_check.sql 결과로 아래가 드러났다.
--   - AIMS_DEV 는 테이블 158개 + 시노님 101개  (덤프 파일 259개와 정확히 일치)
--   - LOB 컬럼 조회 0건, T_TIPA_VMS_SYBL_01I 의 컬럼 조회도 0건
--   - 스키마 용량이 126MB / 104MB 뿐 (덤프는 1.2GB)
--   => 실제 데이터 대부분이 시노님 너머 다른 스키마에 있다.
--
-- 이 스크립트로 "무엇을 이관할지"를 확정한다.

SET LINESIZE 300
SET PAGESIZE 500
SET TRIMSPOOL ON
SET SERVEROUTPUT ON

SPOOL 01b_scope_check.log

PROMPT ================================================================
PROMPT [1] 시노님이 가리키는 스키마  ** 이관 범위의 핵심 **
PROMPT ================================================================
COL table_owner FORMAT A20
SELECT table_owner, COUNT(*) AS synonym_cnt, MAX(NVL(db_link,'(local)')) AS sample_dblink
  FROM all_synonyms
 WHERE owner IN ('AIMS_DEV','AIMSC_DEV')
 GROUP BY table_owner ORDER BY 2 DESC;

PROMPT
PROMPT -- DB LINK 를 타는 시노님이 있는가  ** 있으면 원격 DB라 이관 방식이 완전히 달라진다 **
COL synonym_name FORMAT A35
COL table_name   FORMAT A35
SELECT owner, synonym_name, table_owner, table_name, db_link
  FROM all_synonyms
 WHERE owner IN ('AIMS_DEV','AIMSC_DEV') AND db_link IS NOT NULL
 ORDER BY 1,2;
PROMPT -- (0건이면 모두 같은 DB 안의 다른 스키마다)

PROMPT
PROMPT -- 시노님 전체 목록
SELECT owner, synonym_name, table_owner, table_name
  FROM all_synonyms
 WHERE owner IN ('AIMS_DEV','AIMSC_DEV')
 ORDER BY owner, table_owner, synonym_name;

PROMPT
PROMPT ================================================================
PROMPT [2] 시노님 대상 스키마의 규모  ** 여기가 진짜 데이터 **
PROMPT ================================================================
COL owner FORMAT A20
SELECT owner, object_type, COUNT(*) AS cnt
  FROM all_objects
 WHERE owner IN ( SELECT DISTINCT table_owner FROM all_synonyms
                   WHERE owner IN ('AIMS_DEV','AIMSC_DEV') )
 GROUP BY owner, object_type ORDER BY 1,2;

PROMPT
PROMPT -- 대상 스키마 용량
SELECT owner, ROUND(SUM(bytes)/1024/1024) AS mb
  FROM dba_segments
 WHERE owner IN ( SELECT DISTINCT table_owner FROM all_synonyms
                   WHERE owner IN ('AIMS_DEV','AIMSC_DEV') )
 GROUP BY owner ORDER BY 2 DESC;

PROMPT
PROMPT ================================================================
PROMPT [3] 문제의 테이블들이 실제로 어느 스키마에 있는가
PROMPT ================================================================
SELECT owner, table_name, partitioned FROM all_tables
 WHERE table_name IN ('T_TIPA_VMS_SYBL_01I','T_TIPA_LCS_SYBL_01I','T_TIPB_VSL_PGRM_01I',
                      'T_TIPE_LCS_LCTRL_01M','T_TIPE_VMST_DDRF_PHSE_OBJ_01L')
 ORDER BY 1,2;

PROMPT
PROMPT -- 그 테이블들의 LOB/바이너리 컬럼 (owner 제한 없이)
COL column_name FORMAT A30
COL data_type   FORMAT A20
SELECT owner, table_name, column_name, data_type, data_length
  FROM all_tab_columns
 WHERE table_name IN ('T_TIPA_VMS_SYBL_01I','T_TIPA_LCS_SYBL_01I','T_TIPB_VSL_PGRM_01I',
                      'T_TIPE_LCS_LCTRL_01M','T_TIPE_VMST_DDRF_PHSE_OBJ_01L')
   AND data_type IN ('BLOB','CLOB','NCLOB','RAW','LONG','LONG RAW','BFILE')
 ORDER BY 1,2,column_id;

PROMPT
PROMPT ================================================================
PROMPT [4] 캐릭터셋 전체 출력  ** 타겟에서도 실행해 대조할 것 **
PROMPT     (Tibero 는 NLS_CHARACTERSET 이름을 쓰지 않는다)
PROMPT ================================================================
COL parameter FORMAT A40
COL value     FORMAT A40
SELECT parameter, value FROM nls_database_parameters ORDER BY parameter;

PROMPT
PROMPT ================================================================
PROMPT [5] 딕셔너리 뷰 컬럼 구조 확인
PROMPT     (all_views.text_length / all_dependencies.referenced_type 가 없어 쿼리가 실패했다)
PROMPT ================================================================
PROMPT -- ALL_VIEWS 컬럼
SELECT column_name, data_type FROM all_tab_columns
 WHERE table_name = 'ALL_VIEWS' ORDER BY column_id;

PROMPT
PROMPT -- ALL_DEPENDENCIES 컬럼
SELECT column_name, data_type FROM all_tab_columns
 WHERE table_name = 'ALL_DEPENDENCIES' ORDER BY column_id;

PROMPT
PROMPT -- all_tab_columns 자체가 정상 동작하는지 확인 (0 이면 딕셔너리 접근 방식을 바꿔야 한다)
SELECT owner, COUNT(*) AS column_cnt FROM all_tab_columns
 WHERE owner IN ('AIMS_DEV','AIMSC_DEV') GROUP BY owner ORDER BY 1;

PROMPT
PROMPT ================================================================
PROMPT [6] 파티션 구조  ** B2(딕셔너리 방식)로는 재현 불가. 경로 A 또는 B1 필요 **
PROMPT ================================================================
COL table_name FORMAT A40
SELECT owner, table_name, partitioning_type, partition_count
  FROM all_part_tables
 WHERE owner IN ('AIMS_DEV','AIMSC_DEV')
 ORDER BY 1,2;

PROMPT
PROMPT ================================================================
PROMPT [7] 테이블스페이스  ** 타겟에 같은 이름으로 만들면 DDL 수정이 불필요 **
PROMPT ================================================================
COL tablespace_name FORMAT A25
SELECT tablespace_name, COUNT(*) AS seg_cnt, ROUND(SUM(bytes)/1024/1024) AS mb
  FROM dba_segments
 WHERE owner IN ('AIMS_DEV','AIMSC_DEV')
 GROUP BY tablespace_name ORDER BY 1;

PROMPT
PROMPT ================================================================
PROMPT [8] 패키지 / 기타 객체  (이관 대상에 포함할지 판단)
PROMPT ================================================================
COL object_name FORMAT A40
SELECT owner, object_type, object_name, status FROM all_objects
 WHERE owner IN ('AIMS_DEV','AIMSC_DEV')
   AND object_type IN ('PACKAGE','PACKAGE BODY','PROCEDURE','FUNCTION','TRIGGER','SEQUENCE','TYPE')
 ORDER BY 1,2,3;

SPOOL OFF

PROMPT
PROMPT ================================================================
PROMPT 완료: 01b_scope_check.log
PROMPT 특히 [1] 과 [2] 결과에 따라 이관 대상 스키마 목록이 바뀝니다.
PROMPT ================================================================

-- tbsql 이 SQL> 프롬프트에서 대기하지 않도록 반드시 종료한다.
-- (없으면 스크립트 실행 후 입력 대기 상태가 되어 멈춘 것처럼 보인다)
EXIT;
