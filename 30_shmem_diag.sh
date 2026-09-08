#!/usr/bin/env bash
# 공유 풀(shared pool) 고갈 진단 — JDBC-3018 / SLAB_SC_PIN     [읽기 전용]
#
# 증상:
#   java.sql.SQLException: JDBC-3018:Out of memory
#     (unable to allocate 4552 bytes of shared pool memory for SLAB_SC_PIN)
#
# 이건 JDBC 드라이버나 WAS 힙 문제가 아니라 **Tibero 서버 SGA 안의 공유 풀**이
# 바닥난 것이다. SC = Shared Cursor, PIN = 세션이 그 커서를 붙들고 있는 구조체.
# 즉 "공유 커서를 붙들 자리조차 없다".
#
# 이 스크립트는 아무것도 바꾸지 않는다. 조치는 31_shmem_relief.sh 에 있다.
#
# 사용법 (사내 서버 bamboos@192.168.0.101 에서 실행):
#   ./30_shmem_diag.sh                        # 2차 UT (28629, tibero7_ut_tablename)
#   CONTAINER=tibero7_ut ./30_shmem_diag.sh   # 1차 UT (18629)
#   CONTAINER=tibero7    ./30_shmem_diag.sh   # 개발   (8629)  ※ 건드리지 말 것
#
# 결과는 화면과 30_shmem_diag_<시각>.log 에 동시에 남는다.
# 맥으로 회수:  DRYRUN=0 ./sync.sh down

set -uo pipefail

CONTAINER="${CONTAINER:-tibero7_ut_tablename}"
SYS_USER="${SYS_USER:-sys}"
SYS_PASS="${SYS_PASS:-tibero123}"
LOG="${LOG:-30_shmem_diag_$(date +%Y%m%d_%H%M%S).log}"

exec > >(tee -a "$LOG") 2>&1

hr()  { printf '\n===== %s =====\n' "$1"; }
run() { docker exec "$CONTAINER" bash -lc "$*" 2>&1; }
sql() { docker exec -i "$CONTAINER" bash -lc "tbsql -s ${SYS_USER}/${SYS_PASS}" 2>&1; }

echo "대상 컨테이너: $CONTAINER"
echo "기록 파일    : $LOG"
echo "실행 시각    : $(date '+%F %T')"

# ─────────────────────────────────────────────────────────────
# 0. 재기동 위험 확인 — 라이선스가 만료됐다면 내리는 순간 못 올라온다
# ─────────────────────────────────────────────────────────────
hr "0. 라이선스 전문 (재기동 가능 여부를 여기서 판정한다)"
run 'cat $TB_HOME/license/license.xml 2>/dev/null || echo "(license.xml 읽기 실패)"'
echo "-- 오늘: $(date +%F)"
echo "-- 판정: 위 XML 의 만료일 필드가 오늘 이후면 재기동해도 다시 올라온다."
echo "--       만료일이 지났으면 내리는 순간 기동 불가 -> 무중단 조치만 가능."

hr "0b. 컨테이너 상태 / 정확한 기동 시각"
docker ps --filter "name=^/${CONTAINER}$" --format 'name={{.Names}}  status={{.Status}}  image={{.Image}}'
docker inspect -f '기동 시각: {{.State.StartedAt}}   재시작 횟수: {{.RestartCount}}' "$CONTAINER" 2>&1
echo "-- 기동 시각이 라이선스 만료일보다 뒤면, 그 라이선스로 부팅에 성공했다는 뜻이다(= 갱신됨)."

# ─────────────────────────────────────────────────────────────
# 1. 호스트·컨테이너 메모리 — SGA 는 여기 위에 얹혀 있다
# ─────────────────────────────────────────────────────────────
hr "1. 컨테이너 메모리 사용량"
docker stats --no-stream --format 'name={{.Name}}  mem={{.MemUsage}} ({{.MemPerc}})' "$CONTAINER"

hr "1b. /dev/shm (SGA 상한. docker-compose 의 shm_size 값)"
run 'df -h /dev/shm 2>&1; echo "---"; ls -l /dev/shm 2>/dev/null | head -20'

hr "1c. 공유 메모리 세그먼트"
run 'command -v ipcs >/dev/null && ipcs -m 2>&1 | head -20 || echo "(ipcs 없음 — 건너뜀)"'

hr "1d. 호스트 전체 여유 메모리 (인스턴스 3개가 한 서버에 있다)"
free -h 2>/dev/null || vm_stat 2>/dev/null | head -8

# ─────────────────────────────────────────────────────────────
# 2. .tip — 공유 풀 크기를 결정하는 파일. 여기 값은 기동 시에만 반영된다
# ─────────────────────────────────────────────────────────────
hr "2. \$TB_HOME/config/\$TB_SID.tip (메모리 관련 행만)"
run 'F=$TB_HOME/config/$TB_SID.tip; echo "파일: $F"; grep -iE "MEMORY|SHM|POOL|CACHE|CURSOR|SESSION|PROCESS|BUFFER" $F 2>/dev/null || cat $F 2>/dev/null'

# ─────────────────────────────────────────────────────────────
# 3. 서버 로그 — 서버쪽 원본 에러와 메모리 덤프가 남는다
# ─────────────────────────────────────────────────────────────
hr "3-0. 메모리 부족이 언제부터 시작됐는가 (원인 사건과 대조할 시각)"
run 'L=$TB_HOME/instance/$TB_SID/log/slog/sys.log;
     echo "파일: $L"; echo "--- 최초 5건 ---";
     grep -n "OUT_OF_SHP\|ERROR_OUT_OF_SHP" "$L" 2>/dev/null | head -5;
     echo "--- 최후 2건 ---";
     grep -n "OUT_OF_SHP\|ERROR_OUT_OF_SHP" "$L" 2>/dev/null | tail -2;
     echo "--- 총 건수 ---";
     grep -c "OUT_OF_SHP\|ERROR_OUT_OF_SHP" "$L" 2>/dev/null;
     echo "--- 로그 파일 자체의 시작 시각 (로테이션되면 그 이전은 안 남는다) ---";
     head -1 "$L" 2>/dev/null; ls -l $TB_HOME/instance/$TB_SID/log/slog/ 2>/dev/null'

hr "3. 최근 서버 로그에서 공유 풀 관련 기록"
run 'for f in $(find $TB_HOME/instance -type f -name "*.log" -mtime -3 2>/dev/null | head -10); do
       n=$(grep -icE "shared pool|out of memory|SLAB|OOM" "$f" 2>/dev/null)
       [ "${n:-0}" -gt 0 ] && { echo "--- $f  (일치 $n 건, 마지막 20줄) ---"; grep -inE "shared pool|out of memory|SLAB|OOM" "$f" | tail -20; }
     done; echo "(끝)"'

# ─────────────────────────────────────────────────────────────
# 4. DB 내부 — 여기가 본론
#    Tibero 빌드마다 있는 뷰가 다르므로 "먼저 무엇이 있는지 찾고" 조회한다.
#    없는 뷰를 물으면 그 문장만 에러 나고 나머지는 계속 실행된다.
# ─────────────────────────────────────────────────────────────
hr "4. DB 내부 조회 (tbsql)"
sql <<'SQL'
SET LINESIZE 250
SET PAGESIZE 2000
SET FEEDBACK ON

PROMPT
PROMPT ##### 4-1. 인스턴스 #####
SELECT * FROM V$INSTANCE;

PROMPT
PROMPT ##### 4-2. 메모리·커서 관련 파라미터 (현재 적용값) #####
SELECT NAME, VALUE
  FROM V$PARAMETER
 WHERE UPPER(NAME) LIKE '%MEM%'    OR UPPER(NAME) LIKE '%SHM%'
    OR UPPER(NAME) LIKE '%POOL%'   OR UPPER(NAME) LIKE '%CACHE%'
    OR UPPER(NAME) LIKE '%CURSOR%' OR UPPER(NAME) LIKE '%SESSION%'
    OR UPPER(NAME) LIKE '%BUFFER%'
 ORDER BY NAME;

PROMPT
PROMPT ##### 4-3. 이 빌드에 실제로 있는 메모리/커서 관련 뷰 #####
PROMPT ##### (아래 질의 중 실패한 게 있으면 여기 목록을 보고 대체한다)
SELECT view_name FROM all_views
 WHERE view_name LIKE 'V$%'
   AND (view_name LIKE '%MEM%'    OR view_name LIKE '%SHM%'
     OR view_name LIKE '%POOL%'   OR view_name LIKE '%SGA%'
     OR view_name LIKE '%CURSOR%' OR view_name LIKE '%SQL%')
 ORDER BY view_name;

PROMPT -- (위가 비었으면 아래 대체 조회)
SELECT table_name FROM dict
 WHERE table_name LIKE 'V$%'
   AND (table_name LIKE '%MEM%' OR table_name LIKE '%POOL%' OR table_name LIKE '%CURSOR%')
 ORDER BY table_name;

PROMPT
PROMPT ##### 4-4. SGA / 공유 풀 사용량 #####
SELECT * FROM V$SGA;
SELECT * FROM V$SGASTAT;

PROMPT
PROMPT ##### 4-4b. 메모리 관리자 상세 (이 빌드에 존재 확인된 뷰) #####
SELECT * FROM V$MEM_MGR;
SELECT * FROM V$SSVR_MEMSTAT;

PROMPT
PROMPT ##### 4-5. V$SESSION 컬럼 구조 (아래 질의가 실패하면 여기를 보고 고친다) #####
DESC V$SESSION

PROMPT
PROMPT ##### 4-6. 세션 총수 #####
SELECT COUNT(*) AS 총세션수 FROM V$SESSION;

PROMPT
PROMPT ##### 4-7. 접속 출처별 세션 — 커넥션 풀이 몇 개 붙어 있는지 #####
PROMPT ##### 풀 크기 x 인스턴스 수 만큼 세션이 있고, 세션마다 커서를 캐시한다
SELECT USERNAME, MACHINE, STATUS, COUNT(*) AS 세션수
  FROM V$SESSION
 GROUP BY USERNAME, MACHINE, STATUS
 ORDER BY 4 DESC;

PROMPT
PROMPT ##### 4-8. 세션별 열린 커서 수 상위 20 — 커서 누수의 결정적 증거 #####
PROMPT ##### 한두 세션만 수백~수천이면 close() 누락이다
SELECT * FROM (
  SELECT SID, COUNT(*) AS 커서수
    FROM V$OPEN_CURSOR
   GROUP BY SID
   ORDER BY 2 DESC
) WHERE ROWNUM <= 20;

PROMPT
PROMPT ##### 4-9. V$SQL 컬럼 구조 #####
DESC V$SQL

PROMPT
PROMPT ##### 4-10. 공유 풀에 올라온 커서 총수 #####
SELECT COUNT(*) AS 공유커서수 FROM V$SQL;

PROMPT
PROMPT ##### 4-11. 리터럴 SQL 탐지 — 바인드 변수 미사용의 결정적 증거 #####
PROMPT ##### 같은 머리 60자를 가진 커서가 수십~수백 개면 그 SQL 이 범인이다
SELECT * FROM (
  SELECT COUNT(*) AS 커서수, SUBSTR(SQL_TEXT,1,60) AS SQL머리
    FROM V$SQL
   GROUP BY SUBSTR(SQL_TEXT,1,60)
  HAVING COUNT(*) > 5
   ORDER BY 1 DESC
) WHERE ROWNUM <= 25;

PROMPT
PROMPT ##### 4-12. 실행 1회짜리 커서 비율 — 높으면 공유가 전혀 안 되고 있다 #####
SELECT COUNT(*) AS 전체, SUM(CASE WHEN EXECUTIONS <= 1 THEN 1 ELSE 0 END) AS 실행1회이하
  FROM V$SQL;

PROMPT
PROMPT ##### 4-13. 파싱 통계 — 하드 파싱이 많으면 공유 풀이 계속 깎인다 #####
SELECT NAME, VALUE FROM V$SYSSTAT
 WHERE UPPER(NAME) LIKE '%PARSE%' OR UPPER(NAME) LIKE '%CURSOR%'
    OR UPPER(NAME) LIKE '%SESSION%'
 ORDER BY NAME;

EXIT
SQL

hr "다음 단계"
cat <<'EOF'
읽는 법 — 4-8 / 4-11 이 판정 기준이다.

  (A) 4-8 에서 특정 SID 몇 개만 커서가 수백~수천
      -> 앱 커서 누수. PreparedStatement/ResultSet 를 안 닫고 있다.
         FLUSH 로는 회수 안 된다(pin 이 걸려 있으므로 = SLAB_SC_PIN 에러의 정체).
         조치: 31 의 sessions -> kill, 또는 WAS 롤링 재기동. 근본은 코드 수정.

  (B) 4-11 에서 같은 머리를 가진 커서가 수십~수백 개
      -> 바인드 변수 미사용. 값을 문자열로 붙여 만든 SQL 이 매번 새 커서가 된다.
         조치: 31 의 flush 로 즉시 완화. 근본은 해당 SQL 을 바인드 변수로 변경.

  (C) 4-7 의 세션 수가 과하다 (예: 3개 인스턴스 x 풀 50 = 150 세션)
      -> 세션당 커서 캐시가 곱해진다. 풀 최대치를 줄이고 재활용.

  (D) 위 셋 다 정상인데 부족하다
      -> 공유 풀이 워크로드 대비 그냥 작다. 2 의 .tip 값을 점검 창에 상향.
         (기동 시에만 반영되므로 지금은 못 한다)

조치 스크립트:  ./31_shmem_relief.sh
EOF
