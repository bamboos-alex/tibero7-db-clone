-- Phase 3-말: 뷰 재컴파일  ** 타겟에서 실행, 변경 발생 **
--
-- 실행:  tbsql <user>/<pw>@TGT @07_recompile_invalid.sql
--
-- 왜 필요한가:
--   뷰가 다른 뷰를 참조하면 생성 순서를 보장할 수 없다. B1/B2 는 FORCE 로 일단 전부 만들기
--   때문에 참조 대상이 아직 없던 뷰는 INVALID 상태로 남는다. 여기서 반복 컴파일해 해소한다.
--
-- 안전성: ALTER ... COMPILE 은 객체 정의를 바꾸지 않는다. 데이터에 영향이 없다.

SET LINESIZE 300
SET PAGESIZE 200
SET SERVEROUTPUT ON
SET FEEDBACK ON

SPOOL 07_recompile.log

PROMPT === 재컴파일 전 무효 객체 ===
COL object_name FORMAT A40
SELECT owner, object_type, object_name FROM all_objects
 WHERE owner IN ('AIMS_DEV','AIMSC_DEV','AIMS_EX') AND status <> 'VALID'
 ORDER BY 1,2,3;

DECLARE
  v_before PLS_INTEGER;
  v_after  PLS_INTEGER;
  v_pass   PLS_INTEGER := 0;
BEGIN
  LOOP
    v_pass := v_pass + 1;

    SELECT COUNT(*) INTO v_before FROM all_objects
     WHERE owner IN ('AIMS_DEV','AIMSC_DEV','AIMS_EX') AND status <> 'VALID';

    EXIT WHEN v_before = 0 OR v_pass > 5;

    FOR r IN ( SELECT owner, object_type, object_name FROM all_objects
                WHERE owner IN ('AIMS_DEV','AIMSC_DEV','AIMS_EX') AND status <> 'VALID'
                  AND object_type IN ('VIEW','SYNONYM','PROCEDURE','FUNCTION','PACKAGE','TRIGGER') ) LOOP
      BEGIN
        EXECUTE IMMEDIATE 'ALTER ' || r.object_type || ' "' || r.owner || '"."'
                          || r.object_name || '" COMPILE';
      EXCEPTION WHEN OTHERS THEN
        NULL;  -- 이번 패스에서 못 풀리면 다음 패스에서 재시도
      END;
    END LOOP;

    SELECT COUNT(*) INTO v_after FROM all_objects
     WHERE owner IN ('AIMS_DEV','AIMSC_DEV','AIMS_EX') AND status <> 'VALID';

    DBMS_OUTPUT.PUT_LINE('pass ' || v_pass || ': 무효 ' || v_before || ' -> ' || v_after);

    EXIT WHEN v_after = 0 OR v_after = v_before;  -- 더 줄지 않으면 중단
  END LOOP;
END;
/

PROMPT
PROMPT === 재컴파일 후 남은 무효 객체  ** 0건이어야 정상 ** ===
SELECT owner, object_type, object_name FROM all_objects
 WHERE owner IN ('AIMS_DEV','AIMSC_DEV','AIMS_EX') AND status <> 'VALID'
 ORDER BY 1,2,3;

PROMPT
PROMPT === 남은 것이 있으면 원인 확인 ===
PROMPT -- 아래 쿼리로 개별 뷰를 컴파일해 실제 오류 메시지를 본다:
PROMPT --   ALTER VIEW "AIMS_DEV"."<뷰명>" COMPILE;
PROMPT --   SELECT * FROM all_errors WHERE owner='AIMS_DEV' AND name='<뷰명>';
PROMPT -- 흔한 원인: 참조 테이블 누락, 다른 스키마 객체에 대한 권한 부족, 소스에서도 무효였던 뷰

SELECT owner, name, type, line, position, text FROM all_errors
 WHERE owner IN ('AIMS_DEV','AIMSC_DEV','AIMS_EX') ORDER BY owner, name, sequence;

SPOOL OFF

PROMPT
PROMPT ================================================================
PROMPT 소스에서도 무효였던 객체는 01_source_check.sql [4] 의 "무효 객체" 목록과 대조하세요.
PROMPT 소스에서 이미 무효였다면 타겟에서 무효인 것이 정상입니다.
PROMPT ================================================================

-- tbsql 이 SQL> 프롬프트에서 대기하지 않도록 반드시 종료한다.
-- (없으면 스크립트 실행 후 입력 대기 상태가 되어 멈춘 것처럼 보인다)
EXIT;
