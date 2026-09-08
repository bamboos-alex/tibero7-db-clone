#!/usr/bin/env bash
# 공유 풀 고갈 조치 — 재기동 없이                    [변경 발생. DRYRUN=1 기본]
#
# 먼저 ./30_shmem_diag.sh 로 원인을 확정한 뒤 여기로 온다.
#
# ┌─ 재기동 없이 할 수 있는 것 / 없는 것 ──────────────────────────────────┐
# │ 공유 풀 "크기 확대"   : 불가. TOTAL_SHM_SIZE 는 기동 시 고정이고,      │
# │                         shm_size 를 넘기면 컨테이너 재생성까지 필요.   │
# │ 공유 풀 "비우기"      : 가능 (flush). 단 pin 안 걸린 커서만 해제된다.  │
# │ 커서 붙든 세션 정리   : 가능 (kill). DB 는 그대로 두고 세션만 끊는다.  │
# └────────────────────────────────────────────────────────────────────────┘
#
# SLAB_SC_PIN 에러가 났다는 건 "세션이 붙들고 있는 커서"가 많다는 뜻이다.
# 그건 flush 로 회수되지 않는다. flush 후 곧 재발하면 원인은 앱 쪽이다.
#
# 사용법 (사내 서버에서 실행):
#   ./31_shmem_relief.sh status                 # 현재 상태 요약        [읽기 전용]
#   ./31_shmem_relief.sh sessions               # kill 후보 목록        [읽기 전용]
#   ./31_shmem_relief.sh flush                  # 계획만 출력 (DRYRUN)
#   DRYRUN=0 ./31_shmem_relief.sh flush         # 공유 풀 비우기        [변경]
#   ./31_shmem_relief.sh kill-idle              # 끊을 세션 목록 생성   [읽기 전용]
#   DRYRUN=0 ./31_shmem_relief.sh kill-idle     # INACTIVE 세션 끊기    [변경]
#   DRYRUN=0 ./31_shmem_relief.sh kill 123,45   # 특정 세션 하나 끊기   [변경]
#
# 대상 지정:
#   CONTAINER=tibero7_ut ./31_shmem_relief.sh status      # 1차 UT
#   TARGET_USER=AIMSC_DEV ./31_shmem_relief.sh kill-idle  # 특정 계정만
#   TARGET_MACHINE=was01  ./31_shmem_relief.sh kill-idle  # 특정 WAS 만

set -uo pipefail

CONTAINER="${CONTAINER:-tibero7_ut_tablename}"
SYS_USER="${SYS_USER:-sys}"
SYS_PASS="${SYS_PASS:-tibero123}"
DRYRUN="${DRYRUN:-1}"
TARGET_USER="${TARGET_USER:-}"        # 비우면 SYS 를 제외한 전체
TARGET_MACHINE="${TARGET_MACHINE:-}"  # 비우면 전체
LOG="${LOG:-31_shmem_relief_$(date +%Y%m%d_%H%M%S).log}"

exec > >(tee -a "$LOG") 2>&1

hr()  { printf '\n===== %s =====\n' "$1"; }
sql() { docker exec -i "$CONTAINER" bash -lc "tbsql -s ${SYS_USER}/${SYS_PASS}" 2>&1; }

# 세션 필터 — kill 대상을 좁히는 WHERE 절을 만든다
where_filter() {
  local w=""
  [ -n "$TARGET_USER" ]    && w="$w AND UPPER(USERNAME) = UPPER('$TARGET_USER')"
  [ -n "$TARGET_MACHINE" ] && w="$w AND UPPER(MACHINE) LIKE UPPER('%$TARGET_MACHINE%')"
  printf '%s' "$w"
}

banner() {
  echo "대상 컨테이너 : $CONTAINER"
  echo "DRYRUN        : $DRYRUN  $([ "$DRYRUN" = 1 ] && echo '(계획만 출력. 실제 변경 없음)' || echo '*** 실제로 변경합니다 ***')"
  [ -n "$TARGET_USER" ]    && echo "대상 계정     : $TARGET_USER"
  [ -n "$TARGET_MACHINE" ] && echo "대상 머신     : $TARGET_MACHINE"
  echo "기록 파일     : $LOG"
  echo "실행 시각     : $(date '+%F %T')"
}

# ─────────────────────────────────────────────────────────────
# status — 조치 전후 비교용 요약 (읽기 전용)
# ─────────────────────────────────────────────────────────────
cmd_status() {
  hr "현재 상태"
  sql <<'SQL'
SET LINESIZE 250
SET PAGESIZE 200
SELECT COUNT(*) AS 총세션수 FROM V$SESSION;
SELECT STATUS, COUNT(*) AS 세션수 FROM V$SESSION GROUP BY STATUS ORDER BY 2 DESC;
SELECT COUNT(*) AS 공유커서수 FROM V$SQL;
SELECT COUNT(*) AS 열린커서수 FROM V$OPEN_CURSOR;
SELECT * FROM V$SGA;
EXIT
SQL
}

# ─────────────────────────────────────────────────────────────
# sessions — kill 후보 (읽기 전용)
# ─────────────────────────────────────────────────────────────
cmd_sessions() {
  hr "세션 목록 (가벼운 조회 — 메모리가 바닥이면 이것만 성공한다)"
  sql <<'SQL'
SET LINESIZE 250
SET PAGESIZE 200
COLUMN USERNAME FORMAT A15
COLUMN MACHINE  FORMAT A25
SELECT SID, SERIAL#, USERNAME, MACHINE, STATUS,
       TO_CHAR(LOGON_TIME,'MM-DD HH24:MI') AS 접속시각
  FROM V$SESSION ORDER BY LOGON_TIME;
EXIT
SQL

  hr "세션 목록 — 열린 커서가 많은 순 (메모리 여유가 있어야 성공)"
  echo "커서수가 유독 큰 SID 가 있으면 그 세션이 공유 풀을 붙들고 있는 것이다."
  local W; W="$(where_filter)"
  sql <<SQL
SET LINESIZE 250
SET PAGESIZE 300
COLUMN USERNAME FORMAT A15
COLUMN MACHINE  FORMAT A25
COLUMN PROGRAM  FORMAT A25
SELECT s.SID, s.SERIAL#, s.USERNAME, s.MACHINE, s.PROGRAM, s.STATUS,
       TO_CHAR(s.LOGON_TIME,'MM-DD HH24:MI') AS 접속시각,
       NVL(c.CNT,0) AS 열린커서
  FROM V\$SESSION s
  LEFT JOIN (SELECT SID, COUNT(*) CNT FROM V\$OPEN_CURSOR GROUP BY SID) c
    ON c.SID = s.SID
 WHERE NVL(UPPER(s.USERNAME),'-') <> 'SYS' $W
 ORDER BY NVL(c.CNT,0) DESC, s.LOGON_TIME;
EXIT
SQL
  cat <<'EOF'

다음:
  - 특정 세션만 끊기 :  DRYRUN=0 ./31_shmem_relief.sh kill <SID>,<SERIAL#>
  - 유휴 세션 일괄   :  DRYRUN=0 ./31_shmem_relief.sh kill-idle
EOF
}

# ─────────────────────────────────────────────────────────────
# flush — 공유 풀 비우기 [변경]
# ─────────────────────────────────────────────────────────────
cmd_flush() {
  hr "ALTER SYSTEM FLUSH SHARED_POOL  [변경]"
  cat <<'EOF'
무엇이 일어나는가:
  공유 풀에 캐시된 커서 중 **아무도 붙들고 있지 않은 것**을 해제한다.
  DB 는 내려가지 않고 세션도 끊기지 않는다.

부작용:
  직후 모든 SQL 이 하드 파싱을 다시 한다 -> 수십 초~수 분간 CPU 상승과 응답 지연.
  UT 환경이면 감수할 만하다. 사용자 몰리는 시간대는 피하는 게 좋다.

한계 (중요):
  pin 이 걸린 커서(= 세션이 지금 쥐고 있는 커서)는 해제되지 않는다.
  SLAB_SC_PIN 에러가 났다는 건 바로 그 pin 이 문제라는 뜻이므로,
  flush 후 곧 재발하면 원인은 DB 가 아니라 앱이다. kill-idle 로 넘어간다.
EOF
  echo
  if [ "$DRYRUN" = "1" ]; then
    echo "\$ (DRYRUN) tbsql sys/**** -> ALTER SYSTEM FLUSH SHARED_POOL;"
    echo "  실제 실행: DRYRUN=0 $0 flush"
    return 0
  fi

  echo "--- 실행 전 ---"; cmd_status
  hr "FLUSH 실행"
  sql <<'SQL'
SET LINESIZE 200
ALTER SYSTEM FLUSH SHARED_POOL;
EXIT
SQL
  local rc=$?
  cat <<'EOF'

※ 위에서 문법/권한 에러가 났다면 이 빌드가 해당 구문을 지원하지 않는 것이다.
  그때는 kill-idle 로 넘어간다 (세션을 끊으면 그 세션의 커서가 함께 해제된다).
EOF
  echo "--- 실행 후 ---"; cmd_status
  return $rc
}

# ─────────────────────────────────────────────────────────────
# kill-idle — 유휴 세션 일괄 정리 [변경]
# ─────────────────────────────────────────────────────────────
cmd_kill_idle() {
  hr "유휴(READY) 세션 정리  [변경]"
  cat <<'EOF'
무엇이 일어나는가:
  지금 아무 작업도 하지 않는 세션을 끊는다. 세션이 끊기면 그 세션이 붙들고 있던
  커서 pin 이 전부 해제된다 -> flush 로는 못 비우던 공간이 회수된다.

앱에 미치는 영향:
  커넥션 풀(HikariCP 등)은 끊긴 커넥션을 감지하고 새로 만든다. 보통 무해하지만,
  풀이 막 꺼내 쓰려던 커넥션이 끊기면 그 요청 한 건이 실패할 수 있다.
  connection-test-query / validationQuery 가 설정돼 있으면 그 위험도 사라진다.

진행 중인 세션(RUNNING)은 대상에서 제외한다.
※ Tibero 의 V$SESSION.STATUS 는 READY(유휴)/RUNNING(작업중) 이다. INACTIVE 가 아니다.
EOF
  echo
  local W; W="$(where_filter)"

  hr "1) 끊을 세션 확인"
  sql <<SQL
SET LINESIZE 250
SET PAGESIZE 300
COLUMN USERNAME FORMAT A15
COLUMN MACHINE  FORMAT A25
SELECT s.SID, s.SERIAL#, s.USERNAME, s.MACHINE, s.STATUS,
       TO_CHAR(s.LOGON_TIME,'MM-DD HH24:MI') AS 접속시각,
       NVL(c.CNT,0) AS 열린커서
  FROM V\$SESSION s
  LEFT JOIN (SELECT SID, COUNT(*) CNT FROM V\$OPEN_CURSOR GROUP BY SID) c
    ON c.SID = s.SID
 WHERE s.STATUS IN ('READY','IDLE','INACTIVE')
   AND NVL(UPPER(s.USERNAME),'-') <> 'SYS' $W
 ORDER BY NVL(c.CNT,0) DESC;
EXIT
SQL

  hr "2) 실행될 명령 생성"
  sql <<SQL
SET HEADING OFF
SET FEEDBACK OFF
SET PAGESIZE 0
SET LINESIZE 200
SPOOL /tmp/_kill_idle.sql
SELECT 'ALTER SYSTEM KILL SESSION ''' || SID || ',' || SERIAL# || ''';'
  FROM V\$SESSION
 WHERE STATUS IN ('READY','IDLE','INACTIVE')
   AND NVL(UPPER(USERNAME),'-') <> 'SYS' $W;
SPOOL OFF
EXIT
SQL
  docker exec "$CONTAINER" bash -lc \
    "grep -i '^ALTER SYSTEM KILL' /tmp/_kill_idle.sql > /tmp/_kill_idle_clean.sql 2>/dev/null;
     echo 'EXIT' >> /tmp/_kill_idle_clean.sql;
     echo '--- 생성된 명령 ---'; grep -c '^ALTER' /tmp/_kill_idle_clean.sql | xargs -I{} echo '총 {} 건'; cat /tmp/_kill_idle_clean.sql" 2>&1

  if [ "$DRYRUN" = "1" ]; then
    echo
    echo "(DRYRUN) 위 명령은 실행하지 않았습니다."
    echo "  실제 실행: DRYRUN=0 $0 kill-idle"
    echo "  일부만 끊고 싶으면: DRYRUN=0 $0 kill <SID>,<SERIAL#>"
    return 0
  fi

  hr "3) 실행"
  docker exec "$CONTAINER" bash -lc \
    "tbsql -s ${SYS_USER}/${SYS_PASS} @/tmp/_kill_idle_clean.sql" 2>&1

  hr "4) 실행 후 상태"
  cmd_status
}

# ─────────────────────────────────────────────────────────────
# kill — 특정 세션 하나 [변경]
# ─────────────────────────────────────────────────────────────
cmd_kill() {
  local target="${1:-}"
  if ! printf '%s' "$target" | grep -qE '^[0-9]+,[0-9]+$'; then
    echo "사용법: $0 kill <SID>,<SERIAL#>     예: $0 kill 123,45"
    echo "  SID/SERIAL# 은 '$0 sessions' 로 확인합니다."
    return 1
  fi
  hr "세션 $target 종료  [변경]"
  if [ "$DRYRUN" = "1" ]; then
    echo "\$ (DRYRUN) ALTER SYSTEM KILL SESSION '$target';"
    echo "  실제 실행: DRYRUN=0 $0 kill $target"
    return 0
  fi
  sql <<SQL
ALTER SYSTEM KILL SESSION '$target';
EXIT
SQL
}

# ─────────────────────────────────────────────────────────────
# revive — 메모리가 바닥나 flush 조차 실패하는 상태에서의 순서 [변경]
# ─────────────────────────────────────────────────────────────
cmd_revive() {
  hr "긴급 회복 절차  [변경]"
  cat <<'EOF'
왜 이 순서인가:
  공유 풀이 완전히 바닥나면 ALTER SYSTEM 문장 자체가 파싱·실행할 메모리를 못 얻어
  TBR-3002 로 실패한다. (실제로 어젯밤 ALTER SYSTEM DUMP SHARED POOL 이 그렇게 실패했다.)
  그래서 flush 를 먼저 때리면 아무 일도 일어나지 않는다.

  1) 유휴 세션을 먼저 끊는다  -> 세션이 쥔 커서·pin·트랜잭션 구조체가 즉시 해제된다
  2) 그렇게 생긴 여유로 flush 를 실행한다 -> 라이브러리 캐시가 반환된다
  3) 상태를 다시 잰다

세션이 몇 개 없다면 1) 의 회수량도 적다. 그때는 재기동 외에 방법이 없을 수 있다.
EOF
  echo
  if [ "$DRYRUN" = "1" ]; then
    echo "(DRYRUN) 실제 실행: DRYRUN=0 $0 revive"
    cmd_sessions
    return 0
  fi
  hr "[1/4] 기준선"        ; cmd_status
  hr "[2/4] 유휴 세션 정리"; cmd_kill_idle
  hr "[3/4] 공유 풀 flush" ; cmd_flush
  hr "[4/4] 최종 상태"     ; cmd_status
}

# ─────────────────────────────────────────────────────────────
banner
case "${1:-}" in
  revive)     cmd_revive ;;
  status)     cmd_status ;;
  sessions)   cmd_sessions ;;
  flush)      cmd_flush ;;
  kill-idle)  cmd_kill_idle ;;
  kill)       cmd_kill "${2:-}" ;;
  *)
    cat <<EOF

사용법: $0 {revive|status|sessions|flush|kill-idle|kill <SID>,<SERIAL#>}

  revive     유휴 세션 정리 -> flush -> 재측정 을 올바른 순서로  [변경]  ★권장

  status     현재 세션·커서·SGA 요약                       [읽기 전용]
  sessions   커서 많이 쥔 순서로 세션 목록                  [읽기 전용]
  flush      ALTER SYSTEM FLUSH SHARED_POOL                 [변경]
  kill-idle  유휴 세션을 끊어 커서 pin 회수                 [변경]
  kill       특정 세션 하나만 끊기                          [변경]

권장 순서:
  1) ./30_shmem_diag.sh          원인 확정
  2) $0 sessions                 끊어도 되는 세션인지 눈으로 확인
  3) $0 revive                   계획 확인 (DRYRUN)
  4) DRYRUN=0 $0 revive          실행

  주의: 공유 풀이 완전히 바닥나면 flush 문장 자체가 TBR-3002 로 실패한다.
        그래서 flush 단독이 아니라 revive(세션 정리 -> flush) 순서로 돌린다.

DRYRUN 기본값은 1 이라 변경 명령은 출력만 됩니다. DRYRUN=0 을 붙여야 실행됩니다.
EOF
    exit 1 ;;
esac
