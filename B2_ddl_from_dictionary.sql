-- 경로 B-2: 딕셔너리 뷰로 DDL 직접 생성  (DBMS_METADATA 를 못 쓸 때의 대체)
--
-- 실행:  tbsql <user>/<pw>@SRC @B2_ddl_from_dictionary.sql
--
-- 산출물 (생성 순서 = 적용 순서):
--   B2_out_1_tables.sql     CREATE TABLE + NOT NULL
--   B2_out_2_pk_uk.sql      PK / UNIQUE
--   B2_out_3_default_check.sql  DEFAULT 절, CHECK 제약  (LONG 컬럼이라 PL/SQL 로 처리)
--   B2_out_4_views.sql      CREATE OR REPLACE FORCE VIEW  (LONG 컬럼이라 PL/SQL 로 처리)
--   B2_out_5_fk.sql         FK  <- 데이터 적재 "후"
--   B2_out_6_indexes.sql    일반 인덱스
--   B2_out_7_comments.sql   코멘트 (테이블/뷰/컬럼)
--   B2_out_8_sequences.sql  시퀀스
--
-- 적용 순서:
--   1_tables -> 2_pk_uk -> 3_default_check -> 4_views -> [데이터 전송]
--   -> 5_fk -> 6_indexes -> 7_comments -> 8_sequences -> 07_recompile_invalid.sql

SET LINESIZE 500
SET PAGESIZE 0
SET HEADING OFF
SET FEEDBACK OFF
SET VERIFY OFF
SET TRIMSPOOL ON
SET SERVEROUTPUT ON

-- =================================================================
-- 1) CREATE TABLE
-- =================================================================
SPOOL B2_out_1_tables.sql

SELECT txt FROM (
    -- 헤더
    SELECT t.owner AS ow, t.table_name AS tb, 0 AS seq,
           'CREATE TABLE "' || t.owner || '"."' || t.table_name || '" (' AS txt
      FROM all_tables t
     WHERE t.owner IN ('AIMS_DEV','AIMSC_DEV')
    UNION ALL
    -- 컬럼
    SELECT c.owner, c.table_name, c.column_id,
           '  "' || c.column_name || '" ' ||
           CASE
             WHEN c.data_type IN ('VARCHAR2','VARCHAR','CHAR','NVARCHAR2','NCHAR')
               THEN c.data_type || '(' ||
                    CASE WHEN c.char_used = 'C' THEN TO_CHAR(c.char_length) || ' CHAR'
                         ELSE TO_CHAR(c.data_length) END || ')'
             WHEN c.data_type = 'NUMBER'
               THEN CASE WHEN c.data_precision IS NULL THEN 'NUMBER'
                         ELSE 'NUMBER(' || c.data_precision ||
                              CASE WHEN NVL(c.data_scale,0) = 0 THEN '' ELSE ',' || c.data_scale END || ')'
                    END
             WHEN c.data_type = 'FLOAT' THEN 'FLOAT(' || c.data_precision || ')'
             WHEN c.data_type = 'RAW'   THEN 'RAW('   || c.data_length    || ')'
             ELSE c.data_type          -- DATE, CLOB, BLOB, TIMESTAMP(n), LONG 등은 그대로
           END ||
           CASE WHEN c.nullable = 'N' THEN ' NOT NULL' ELSE '' END ||
           CASE WHEN c.column_id = ( SELECT MAX(c2.column_id) FROM all_tab_columns c2
                                      WHERE c2.owner = c.owner AND c2.table_name = c.table_name )
                THEN '' ELSE ',' END
      FROM all_tab_columns c
     WHERE c.owner IN ('AIMS_DEV','AIMSC_DEV')
       AND EXISTS ( SELECT 1 FROM all_tables t2
                     WHERE t2.owner = c.owner AND t2.table_name = c.table_name )
    UNION ALL
    -- 푸터
    SELECT t.owner, t.table_name, 999999, ');'
      FROM all_tables t
     WHERE t.owner IN ('AIMS_DEV','AIMSC_DEV')
) ORDER BY ow, tb, seq;

SPOOL OFF

-- =================================================================
-- 2) PK / UNIQUE
-- =================================================================
SPOOL B2_out_2_pk_uk.sql

SELECT txt FROM (
    SELECT c.owner AS ow, c.constraint_name AS cn, 0 AS seq,
           'ALTER TABLE "' || c.owner || '"."' || c.table_name || '" ADD CONSTRAINT "'
           || c.constraint_name || '" '
           || CASE c.constraint_type WHEN 'P' THEN 'PRIMARY KEY (' ELSE 'UNIQUE (' END AS txt
      FROM all_constraints c
     WHERE c.owner IN ('AIMS_DEV','AIMSC_DEV') AND c.constraint_type IN ('P','U')
    UNION ALL
    SELECT cc.owner, cc.constraint_name, cc.position,
           '  "' || cc.column_name || '"' ||
           CASE WHEN cc.position = ( SELECT MAX(cc2.position) FROM all_cons_columns cc2
                                      WHERE cc2.owner = cc.owner
                                        AND cc2.constraint_name = cc.constraint_name )
                THEN '' ELSE ',' END
      FROM all_cons_columns cc
     WHERE cc.owner IN ('AIMS_DEV','AIMSC_DEV')
       AND EXISTS ( SELECT 1 FROM all_constraints c2
                     WHERE c2.owner = cc.owner AND c2.constraint_name = cc.constraint_name
                       AND c2.constraint_type IN ('P','U') )
    UNION ALL
    SELECT c.owner, c.constraint_name, 999999, ');'
      FROM all_constraints c
     WHERE c.owner IN ('AIMS_DEV','AIMSC_DEV') AND c.constraint_type IN ('P','U')
) ORDER BY ow, cn, seq;

SPOOL OFF

-- =================================================================
-- 3) DEFAULT 절 + CHECK 제약
--    ALL_TAB_COLUMNS.DATA_DEFAULT 와 ALL_CONSTRAINTS.SEARCH_CONDITION 은 LONG 타입이라
--    SQL 문자열 연결이 불가능하다. PL/SQL 로 읽어서 출력한다.
-- =================================================================
SPOOL B2_out_3_default_check.sql

DECLARE
  v_def  VARCHAR2(32767);
  v_cond VARCHAR2(32767);
BEGIN
  -- DEFAULT
  FOR r IN ( SELECT owner, table_name, column_name, data_default
               FROM all_tab_columns
              WHERE owner IN ('AIMS_DEV','AIMSC_DEV')
              ORDER BY owner, table_name, column_id ) LOOP
    v_def := r.data_default;
    IF v_def IS NOT NULL AND TRIM(v_def) IS NOT NULL THEN
      DBMS_OUTPUT.PUT_LINE('ALTER TABLE "' || r.owner || '"."' || r.table_name
        || '" MODIFY ("' || r.column_name || '" DEFAULT ' || TRIM(v_def) || ');');
    END IF;
  END LOOP;

  -- CHECK  (NOT NULL 은 이미 CREATE TABLE 에 반영했으므로 제외)
  FOR r IN ( SELECT owner, table_name, constraint_name, search_condition
               FROM all_constraints
              WHERE owner IN ('AIMS_DEV','AIMSC_DEV') AND constraint_type = 'C'
              ORDER BY owner, table_name, constraint_name ) LOOP
    v_cond := r.search_condition;
    IF v_cond IS NOT NULL
       AND UPPER(REPLACE(v_cond,' ','')) NOT LIKE '%ISNOTNULL' THEN
      DBMS_OUTPUT.PUT_LINE('ALTER TABLE "' || r.owner || '"."' || r.table_name
        || '" ADD CONSTRAINT "' || r.constraint_name || '" CHECK (' || v_cond || ');');
    END IF;
  END LOOP;
END;
/

SPOOL OFF

-- =================================================================
-- 4) VIEW
--    ALL_VIEWS.TEXT 도 LONG 이라 PL/SQL 로 읽는다.
--    딕셔너리에는 SELECT 본문만 저장되므로 컬럼 목록을 직접 붙여 별칭을 보존한다.
--    뷰가 뷰를 참조할 수 있으므로 FORCE 로 만들고 나중에 재컴파일한다.
--    문장 종결자는 ; 대신 / 를 쓴다 (본문에 세미콜론이 있어도 안전).
-- =================================================================
SPOOL B2_out_4_views.sql

DECLARE
  v_txt   VARCHAR2(32767);
  v_cols  VARCHAR2(32767);
  v_pos   PLS_INTEGER;
  v_nl    PLS_INTEGER;
  v_line  VARCHAR2(32767);
  v_fail  PLS_INTEGER := 0;
  v_total PLS_INTEGER := 0;
BEGIN
  FOR r IN ( SELECT owner, view_name, text
               FROM all_views
              WHERE owner IN ('AIMS_DEV','AIMSC_DEV')
              ORDER BY owner, view_name ) LOOP

    v_total := v_total + 1;

    -- LONG -> VARCHAR2 변환. 32767자를 넘으면 여기서 예외가 난다.
    BEGIN
      v_txt := r.text;
    EXCEPTION WHEN OTHERS THEN
      v_txt := NULL;
      v_fail := v_fail + 1;
      DBMS_OUTPUT.PUT_LINE('-- !! 정의문이 32767자를 초과하여 추출 실패: '
        || r.owner || '.' || r.view_name || '  -> B1 또는 수동 추출 필요');
    END;

    IF v_txt IS NOT NULL THEN
      -- 뷰 컬럼 목록
      v_cols := NULL;
      FOR c IN ( SELECT column_name FROM all_tab_columns
                  WHERE owner = r.owner AND table_name = r.view_name
                  ORDER BY column_id ) LOOP
        v_cols := v_cols || CASE WHEN v_cols IS NULL THEN '' ELSE ', ' END
                  || '"' || c.column_name || '"';
      END LOOP;

      DBMS_OUTPUT.PUT_LINE('-- ===== ' || r.owner || '.' || r.view_name || ' =====');
      DBMS_OUTPUT.PUT_LINE('CREATE OR REPLACE FORCE VIEW "' || r.owner || '"."' || r.view_name || '" ('
        || v_cols || ') AS');

      -- 본문을 개행 단위로 출력 (긴 한 줄이 잘리는 것을 방지)
      v_pos := 1;
      LOOP
        EXIT WHEN v_pos > LENGTH(v_txt);
        v_nl := INSTR(v_txt, CHR(10), v_pos);
        IF v_nl = 0 THEN
          v_line := SUBSTR(v_txt, v_pos);
          v_pos  := LENGTH(v_txt) + 1;
        ELSE
          v_line := SUBSTR(v_txt, v_pos, v_nl - v_pos);
          v_pos  := v_nl + 1;
        END IF;
        DBMS_OUTPUT.PUT_LINE(RTRIM(v_line, CHR(13)));
      END LOOP;

      DBMS_OUTPUT.PUT_LINE('/');
      DBMS_OUTPUT.PUT_LINE('');
    END IF;
  END LOOP;

  DBMS_OUTPUT.PUT_LINE('-- 뷰 총 ' || v_total || '개 중 ' || v_fail || '개 추출 실패');
END;
/

SPOOL OFF

-- =================================================================
-- 5) FK   (데이터 적재 후에 실행)
-- =================================================================
SPOOL B2_out_5_fk.sql

SELECT txt FROM (
    SELECT c.owner AS ow, c.constraint_name AS cn, 0 AS seq,
           'ALTER TABLE "' || c.owner || '"."' || c.table_name || '" ADD CONSTRAINT "'
           || c.constraint_name || '" FOREIGN KEY (' AS txt
      FROM all_constraints c
     WHERE c.owner IN ('AIMS_DEV','AIMSC_DEV') AND c.constraint_type = 'R'
    UNION ALL
    SELECT cc.owner, cc.constraint_name, cc.position,
           '  "' || cc.column_name || '"' ||
           CASE WHEN cc.position = ( SELECT MAX(cc2.position) FROM all_cons_columns cc2
                                      WHERE cc2.owner = cc.owner
                                        AND cc2.constraint_name = cc.constraint_name )
                THEN '' ELSE ',' END
      FROM all_cons_columns cc
     WHERE cc.owner IN ('AIMS_DEV','AIMSC_DEV')
       AND EXISTS ( SELECT 1 FROM all_constraints c2
                     WHERE c2.owner = cc.owner AND c2.constraint_name = cc.constraint_name
                       AND c2.constraint_type = 'R' )
    UNION ALL
    SELECT c.owner, c.constraint_name, 500000,
           ') REFERENCES "' || rc.owner || '"."' || rc.table_name || '" ('
      FROM all_constraints c
      JOIN all_constraints rc ON rc.owner = c.r_owner AND rc.constraint_name = c.r_constraint_name
     WHERE c.owner IN ('AIMS_DEV','AIMSC_DEV') AND c.constraint_type = 'R'
    UNION ALL
    SELECT c.owner, c.constraint_name, 500000 + rcc.position,
           '  "' || rcc.column_name || '"' ||
           CASE WHEN rcc.position = ( SELECT MAX(rcc2.position) FROM all_cons_columns rcc2
                                       WHERE rcc2.owner = c.r_owner
                                         AND rcc2.constraint_name = c.r_constraint_name )
                THEN '' ELSE ',' END
      FROM all_constraints c
      JOIN all_cons_columns rcc ON rcc.owner = c.r_owner
                               AND rcc.constraint_name = c.r_constraint_name
     WHERE c.owner IN ('AIMS_DEV','AIMSC_DEV') AND c.constraint_type = 'R'
    UNION ALL
    SELECT c.owner, c.constraint_name, 999999,
           ')' || CASE WHEN c.delete_rule = 'CASCADE' THEN ' ON DELETE CASCADE'
                       WHEN c.delete_rule = 'SET NULL' THEN ' ON DELETE SET NULL'
                       ELSE '' END || ';'
      FROM all_constraints c
     WHERE c.owner IN ('AIMS_DEV','AIMSC_DEV') AND c.constraint_type = 'R'
) ORDER BY ow, cn, seq;

SPOOL OFF

-- =================================================================
-- 6) 일반 인덱스  (PK/UK 지원 인덱스는 제외 — 중복 생성 오류 방지)
-- =================================================================
SPOOL B2_out_6_indexes.sql

SELECT txt FROM (
    SELECT i.owner AS ow, i.index_name AS ix, 0 AS seq,
           'CREATE ' || CASE WHEN i.uniqueness = 'UNIQUE' THEN 'UNIQUE ' ELSE '' END
           || 'INDEX "' || i.owner || '"."' || i.index_name || '" ON "'
           || i.table_owner || '"."' || i.table_name || '" (' AS txt
      FROM all_indexes i
     WHERE i.owner IN ('AIMS_DEV','AIMSC_DEV')
       AND i.index_type NOT LIKE 'LOB%'
       AND NOT EXISTS ( SELECT 1 FROM all_constraints c
                         WHERE c.owner = i.owner AND c.index_name = i.index_name
                           AND c.constraint_type IN ('P','U') )
    UNION ALL
    SELECT ic.index_owner, ic.index_name, ic.column_position,
           '  "' || ic.column_name || '" ' || ic.descend ||
           CASE WHEN ic.column_position = ( SELECT MAX(ic2.column_position) FROM all_ind_columns ic2
                                             WHERE ic2.index_owner = ic.index_owner
                                               AND ic2.index_name = ic.index_name )
                THEN '' ELSE ',' END
      FROM all_ind_columns ic
     WHERE ic.index_owner IN ('AIMS_DEV','AIMSC_DEV')
       AND EXISTS ( SELECT 1 FROM all_indexes i2
                     WHERE i2.owner = ic.index_owner AND i2.index_name = ic.index_name
                       AND i2.index_type NOT LIKE 'LOB%'
                       AND NOT EXISTS ( SELECT 1 FROM all_constraints c2
                                         WHERE c2.owner = i2.owner AND c2.index_name = i2.index_name
                                           AND c2.constraint_type IN ('P','U') ) )
    UNION ALL
    SELECT i.owner, i.index_name, 999999, ');'
      FROM all_indexes i
     WHERE i.owner IN ('AIMS_DEV','AIMSC_DEV')
       AND i.index_type NOT LIKE 'LOB%'
       AND NOT EXISTS ( SELECT 1 FROM all_constraints c
                         WHERE c.owner = i.owner AND c.index_name = i.index_name
                           AND c.constraint_type IN ('P','U') )
) ORDER BY ow, ix, seq;

SPOOL OFF

-- =================================================================
-- 7) 코멘트  (all_tab_comments / all_col_comments 는 뷰도 함께 담고 있다)
-- =================================================================
SPOOL B2_out_7_comments.sql

SELECT 'COMMENT ON TABLE "' || owner || '"."' || table_name || '" IS '''
       || REPLACE(comments, '''', '''''') || ''';'
  FROM all_tab_comments
 WHERE owner IN ('AIMS_DEV','AIMSC_DEV') AND comments IS NOT NULL
 ORDER BY owner, table_name;

SELECT 'COMMENT ON COLUMN "' || owner || '"."' || table_name || '"."' || column_name || '" IS '''
       || REPLACE(comments, '''', '''''') || ''';'
  FROM all_col_comments
 WHERE owner IN ('AIMS_DEV','AIMSC_DEV') AND comments IS NOT NULL
 ORDER BY owner, table_name, column_name;

SPOOL OFF

-- =================================================================
-- 8) 시퀀스  (현재 last_number 부터 시작하도록 생성)
-- =================================================================
SPOOL B2_out_8_sequences.sql

SELECT 'CREATE SEQUENCE "' || sequence_owner || '"."' || sequence_name || '"'
       || ' START WITH ' || last_number
       || ' INCREMENT BY ' || increment_by
       || ' MINVALUE ' || min_value
       || ' MAXVALUE ' || max_value
       || CASE WHEN cycle_flag = 'Y' THEN ' CYCLE' ELSE ' NOCYCLE' END
       || CASE WHEN NVL(cache_size,0) > 0 THEN ' CACHE ' || cache_size ELSE ' NOCACHE' END
       || ';'
  FROM all_sequences
 WHERE sequence_owner IN ('AIMS_DEV','AIMSC_DEV')
 ORDER BY sequence_owner, sequence_name;

SPOOL OFF

SET HEADING ON
SET FEEDBACK ON
SET PAGESIZE 200

PROMPT
PROMPT ================================================================
PROMPT 생성 완료. 각 파일 앞뒤의 tbsql 잔여 줄을 정리한 뒤 아래 순서로 적용하세요.
PROMPT   1_tables -> 2_pk_uk -> 3_default_check -> 4_views -> [데이터 전송]
PROMPT   -> 5_fk -> 6_indexes -> 7_comments -> 8_sequences -> 07_recompile_invalid.sql
PROMPT
PROMPT 주의사항:
PROMPT  - 이 방식은 파티션/IOT/가상컬럼/LOB 저장절을 재현하지 않습니다.
PROMPT  - 뷰 정의문이 32767자를 넘으면 4_views 파일에 "추출 실패" 주석이 남습니다.
PROMPT    해당 뷰는 B1(DBMS_METADATA) 이나 수동으로 별도 추출해야 합니다.
PROMPT    (대상 뷰는 01_source_check.sql 의 text_length 정렬 결과로 미리 알 수 있습니다)
PROMPT ================================================================
