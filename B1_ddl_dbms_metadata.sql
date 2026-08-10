-- 경로 B-1: DBMS_METADATA 로 DDL 추출  (01_source_check.sql [5] 가 "사용 가능" 일 때)
--
-- 실행:  tbsql <user>/<pw>@SRC @B1_ddl_dbms_metadata.sql
--
-- 산출물 (파일 번호 = 적용 순서):
--   B1_out_1_tables.sql     CREATE TABLE (PK/UK/CHECK 포함, FK 제외)
--   B1_out_2_views.sql      CREATE OR REPLACE FORCE VIEW
--   B1_out_3_fk.sql         FK  <- 데이터 적재 "후" 에 실행
--   B1_out_4_indexes.sql    일반 인덱스 (제약조건 지원 인덱스 제외)
--   B1_out_5_comments.sql   테이블/뷰/컬럼 코멘트
--   B1_out_6_sequences.sql  시퀀스
--   B1_out_7_synonyms.sql   시노님 (AIMS_DEV/AIMSC_DEV 각 101개 -> AIMS_EX)
--   B1_out_8_packages.sql   패키지 P_AAAA_PRTT_TBL_MGMT
--
-- 적용 순서: 1_tables -> 2_views -> [데이터 전송] -> 3_fk -> 4_indexes -> 5_comments
--            -> 6_sequences -> 7_synonyms -> 8_packages -> 07_recompile_invalid.sql
--
-- ** 스키마 순서 **: AIMS_EX 를 먼저 만들어야 시노님이 유효해진다.
--
-- ** 파티션 주의 **: 소스에 RANGE 파티션 테이블이 162개 있다.
--    B2(딕셔너리 방식)로는 재현이 불가하므로 이 B1 또는 경로 A(tbExport)를 써야 한다.
--    B1 적용 후 all_part_tables 개수를 소스와 반드시 대조할 것.

SET LINESIZE 32767
SET LONG 2000000
SET LONGCHUNKSIZE 32767
SET PAGESIZE 0
SET HEADING OFF
SET FEEDBACK OFF
SET VERIFY OFF
SET TRIMSPOOL ON
SET TERMOUT ON

-- ---------------------------------------------------------------
-- 변환 옵션: 환경 의존적인 저장 절(테이블스페이스/STORAGE)을 제거해
-- 다른 서버에서도 그대로 실행되게 만든다.
-- 지원하지 않는 옵션은 개별적으로 무시한다.
-- ---------------------------------------------------------------
DECLARE
  PROCEDURE try_set(p_name VARCHAR2, p_val BOOLEAN) IS
  BEGIN
    DBMS_METADATA.SET_TRANSFORM_PARAM(DBMS_METADATA.SESSION_TRANSFORM, p_name, p_val);
  EXCEPTION WHEN OTHERS THEN
    DBMS_OUTPUT.PUT_LINE('-- transform param 미지원(무시): ' || p_name);
  END;
BEGIN
  try_set('SEGMENT_ATTRIBUTES', FALSE);   -- 테이블스페이스/저장 속성 제거
  try_set('STORAGE',            FALSE);
  try_set('TABLESPACE',         FALSE);
  try_set('REF_CONSTRAINTS',    FALSE);   -- FK 는 따로 뽑는다
  try_set('SQLTERMINATOR',      TRUE);    -- 문장 끝에 ; 부착
  try_set('PRETTY',             TRUE);
  try_set('FORCE',              TRUE);    -- 뷰를 FORCE 로 생성 (의존 순서 무시)
END;
/

-- ---------------------------------------------------------------
-- 1) CREATE TABLE
-- ---------------------------------------------------------------
SPOOL B1_out_1_tables.sql
SELECT '-- ===== ' || owner || '.' || table_name || ' =====' || CHR(10)
       || DBMS_METADATA.GET_DDL('TABLE', table_name, owner) || CHR(10)
  FROM all_tables
 WHERE owner IN ('AIMS_DEV','AIMSC_DEV','AIMS_EX')
 ORDER BY owner, table_name;
SPOOL OFF

-- ---------------------------------------------------------------
-- 2) VIEW
--    뷰가 다른 뷰를 참조할 수 있으므로 생성 순서를 보장할 수 없다.
--    FORCE 로 일단 전부 만든 뒤 07_recompile_invalid.sql 로 재컴파일한다.
-- ---------------------------------------------------------------
SPOOL B1_out_2_views.sql
SELECT '-- ===== ' || owner || '.' || view_name || ' =====' || CHR(10)
       || DBMS_METADATA.GET_DDL('VIEW', view_name, owner) || CHR(10)
  FROM all_views
 WHERE owner IN ('AIMS_DEV','AIMSC_DEV','AIMS_EX')
 ORDER BY owner, view_name;
SPOOL OFF

-- ---------------------------------------------------------------
-- 3) FK  (데이터 적재 후에 실행할 것)
-- ---------------------------------------------------------------
SPOOL B1_out_3_fk.sql
SELECT DBMS_METADATA.GET_DDL('REF_CONSTRAINT', constraint_name, owner) || CHR(10)
  FROM all_constraints
 WHERE owner IN ('AIMS_DEV','AIMSC_DEV','AIMS_EX') AND constraint_type = 'R'
 ORDER BY owner, table_name, constraint_name;
SPOOL OFF

-- ---------------------------------------------------------------
-- 4) 일반 인덱스
--    PK/UK 를 지원하는 인덱스는 CREATE TABLE 단계에서 자동 생성되므로 제외한다.
--    (제외하지 않으면 "이미 존재하는 이름" 오류가 난다)
-- ---------------------------------------------------------------
SPOOL B1_out_4_indexes.sql
SELECT DBMS_METADATA.GET_DDL('INDEX', i.index_name, i.owner) || CHR(10)
  FROM all_indexes i
 WHERE i.owner IN ('AIMS_DEV','AIMSC_DEV','AIMS_EX')
   AND i.index_type NOT LIKE 'LOB%'
   AND NOT EXISTS ( SELECT 1 FROM all_constraints c
                     WHERE c.owner = i.owner
                       AND c.index_name = i.index_name
                       AND c.constraint_type IN ('P','U') )
 ORDER BY i.owner, i.table_name, i.index_name;
SPOOL OFF

-- ---------------------------------------------------------------
-- 5) 코멘트 (딕셔너리에서 직접 생성 — 이쪽이 더 안정적)
--    all_tab_comments / all_col_comments 는 뷰도 함께 담고 있다.
-- ---------------------------------------------------------------
SPOOL B1_out_5_comments.sql
SELECT 'COMMENT ON TABLE "' || owner || '"."' || table_name || '" IS '''
       || REPLACE(comments, '''', '''''') || ''';'
  FROM all_tab_comments
 WHERE owner IN ('AIMS_DEV','AIMSC_DEV','AIMS_EX') AND comments IS NOT NULL
 ORDER BY owner, table_name;

SELECT 'COMMENT ON COLUMN "' || owner || '"."' || table_name || '"."' || column_name || '" IS '''
       || REPLACE(comments, '''', '''''') || ''';'
  FROM all_col_comments
 WHERE owner IN ('AIMS_DEV','AIMSC_DEV','AIMS_EX') AND comments IS NOT NULL
 ORDER BY owner, table_name, column_name;
SPOOL OFF

-- ---------------------------------------------------------------
-- 6) 시퀀스  (START WITH 는 현재값 기준으로 재계산됨)
-- ---------------------------------------------------------------
SPOOL B1_out_6_sequences.sql
SELECT DBMS_METADATA.GET_DDL('SEQUENCE', sequence_name, sequence_owner) || CHR(10)
  FROM all_sequences
 WHERE sequence_owner IN ('AIMS_DEV','AIMSC_DEV','AIMS_EX')
 ORDER BY sequence_owner, sequence_name;
SPOOL OFF

-- ---------------------------------------------------------------
-- 7) 시노님  (AIMS_DEV / AIMSC_DEV 에 각각 101개. 전부 AIMS_EX 를 가리킨다)
--    Tibero 의 ALL_SYNONYMS 는 ORG_OBJECT_OWNER / ORG_OBJECT_NAME 을 쓴다.
--    DB_LINK 컬럼 자체가 없다 = 원격 참조 없음.
--    딕셔너리에서 직접 만드는 편이 GET_DDL 보다 확실하다.
-- ---------------------------------------------------------------
SPOOL B1_out_7_synonyms.sql
SELECT 'CREATE OR REPLACE SYNONYM "' || owner || '"."' || synonym_name
       || '" FOR "' || org_object_owner || '"."' || org_object_name || '";'
  FROM all_synonyms
 WHERE owner IN ('AIMS_DEV','AIMSC_DEV','AIMS_EX')
 ORDER BY owner, synonym_name;
SPOOL OFF

-- ---------------------------------------------------------------
-- 8) 패키지  (P_AAAA_PRTT_TBL_MGMT — 파티션 테이블 관리. 양 스키마에 존재)
--    GET_DDL('PACKAGE') 는 스펙과 본문을 함께 반환한다.
--    본문에 세미콜론이 있으므로 각 객체 뒤에 / 를 붙여 실행 단위를 구분한다.
-- ---------------------------------------------------------------
SPOOL B1_out_8_packages.sql
SELECT '-- ===== ' || owner || '.' || object_name || ' =====' || CHR(10)
       || DBMS_METADATA.GET_DDL('PACKAGE', object_name, owner) || CHR(10) || '/' || CHR(10)
  FROM all_objects
 WHERE owner IN ('AIMS_DEV','AIMSC_DEV','AIMS_EX') AND object_type = 'PACKAGE'
 ORDER BY owner, object_name;
SPOOL OFF

SET HEADING ON
SET FEEDBACK ON
SET PAGESIZE 200

PROMPT
PROMPT ================================================================
PROMPT 생성 완료. 각 파일 앞뒤에 tbsql 프롬프트 잔여 줄이 붙었으면 지운 뒤 사용하세요.
PROMPT 적용 순서:
PROMPT   1_tables -> 2_views -> [데이터 전송] -> 3_fk -> 4_indexes -> 5_comments
PROMPT   -> 6_sequences -> 7_synonyms -> 8_packages -> 07_recompile_invalid.sql
PROMPT
PROMPT 각 파일 안에서는 AIMS_EX 를 먼저 적용하세요 (시노님 대상이 먼저 있어야 합니다).
PROMPT
PROMPT B2 는 파티션 테이블 162개를 재현하지 못하므로 대체재가 되지 못합니다.
PROMPT 이 스크립트가 실패하면 경로 A(tbExport)로 가야 합니다.
PROMPT ================================================================

-- tbsql 이 SQL> 프롬프트에서 대기하지 않도록 반드시 종료한다.
-- (없으면 스크립트 실행 후 입력 대기 상태가 되어 멈춘 것처럼 보인다)
EXIT;
