#!/usr/bin/env bash
# 공유 풀 추이 감시 — 재발 방지                        [읽기 전용]
#
# 왜 필요한가:
#   Tibero 의 하위 할당자는 root 로 메모리를 반납하지 않는다(2026-09-03 실측).
#   그래서 사용량은 단조 증가한다. 어느 항목이 자라는지 추적하지 않으면
#   또 어느 날 갑자기 고갈되고, 그때는 무중단 복구가 불가능하다.
#
# ★ 무엇을 봐야 하는가 (2026-09-08 정정)
#   V$SGASTAT 의 'Free Space' 는 **이미 배분된 하위 풀 안의 여유**다. 이걸 보면 안 된다.
#   하위 풀은 모자라면 root 에서 더 받아오므로 이 값은 오르내린다.
#   진짜 헤드룸은 V$SGA 의 'SHARED POOL MEMORY' 행이다:
#       TOTAL(가변 영역 전체) - USED(하위 할당자에 배분된 양) = root 여유
#   2G 시절 이 값이 3.3MB 까지 떨어져 고갈됐고, 6G 로 올린 뒤 약 981MB 다.
#
# 무엇을 하는가:
#   1) 주요 항목을 CSV 한 줄로 누적한다      -> shmem_trend.csv
#   2) sys.log 에 OUT_OF_SHP 가 찍혔는지 본다
#   3) root 여유가 임계치 아래로 떨어지면 비정상 종료한다 (cron 이 감지)
#
# cron 등록 (매일 09시):
#   0 9 * * * cd ~/alex/tibero7_ut_tablename/migration && ./34_shmem_watch.sh >> shmem_watch.cron.log 2>&1
#
# 사용법:
#   ./34_shmem_watch.sh              # 측정 + 추이 출력
#   ./34_shmem_watch.sh trend        # 누적된 추이만 출력
#   WARN_ROOT_MB=300 ./34_shmem_watch.sh   # root 여유 임계치 조정 (기본 200MB)
#   CONTAINER=tibero7_ut CSV=trend_ut.csv ./34_shmem_watch.sh   # 다른 인스턴스

set -uo pipefail

CONTAINER="${CONTAINER:-tibero7_ut_tablename}"
SYS_USER="${SYS_USER:-sys}"
SYS_PASS="${SYS_PASS:-tibero123}"
CSV="${CSV:-shmem_trend.csv}"
WARN_ROOT_MB="${WARN_ROOT_MB:-200}"
HDR="측정시각,풀총MB,배분MB,root여유MB,내부여유MB,TCBUF,PP,WLIST,DD_CACHE,CSR,SC_PIN,세션,커서"

hr() { printf '\n===== %s =====\n' "$1"; }

show_trend() {
  [ -f "$CSV" ] || { echo "(추이 파일 없음: $CSV)"; return; }
  echo "-- 단위 MB. root여유MB 가 계속 줄기만 하면 래칫이 도는 것이다."
  column -t -s, "$CSV" 2>/dev/null || cat "$CSV"
}

if [ "${1:-}" = "trend" ]; then hr "공유 풀 추이 ($CSV)"; show_trend; exit 0; fi

hr "측정 $(date '+%F %T %Z')"

# 시각은 컨테이너(UTC)가 아니라 호스트(KST) 기준으로 남긴다 — 로그 대조가 쉬워진다
NOW="$(date '+%Y-%m-%d_%H:%M')"

RAW="$(docker exec -i "$CONTAINER" bash -lc "tbsql -s ${SYS_USER}/${SYS_PASS}" 2>&1 <<'SQL'
SET HEADING OFF
SET FEEDBACK OFF
SET PAGESIZE 0
SET LINESIZE 500
SELECT 'DATA,'
  || ROUND(NVL((SELECT "TOTAL" FROM V$SGA WHERE NAME='SHARED POOL MEMORY'),0)/1048576)
  || ',' || ROUND(NVL((SELECT "USED"  FROM V$SGA WHERE NAME='SHARED POOL MEMORY'),0)/1048576)
  || ',' || ROUND(NVL((SELECT "TOTAL"-"USED" FROM V$SGA WHERE NAME='SHARED POOL MEMORY'),0)/1048576)
  || ',' || ROUND(NVL((SELECT "SIZE" FROM V$SGASTAT WHERE NAME='Free Space'),0)/1048576)
  || ',' || ROUND(NVL((SELECT "SIZE" FROM V$SGASTAT WHERE NAME='SLAB_TCBUF'),0)/1048576)
  || ',' || ROUND(NVL((SELECT "SIZE" FROM V$SGASTAT WHERE NAME='PP'),0)/1048576)
  || ',' || ROUND(NVL((SELECT "SIZE" FROM V$SGASTAT WHERE NAME='SLAB_WLIST'),0)/1048576)
  || ',' || ROUND(NVL((SELECT "SIZE" FROM V$SGASTAT WHERE NAME='DD_CACHE'),0)/1048576)
  || ',' || ROUND(NVL((SELECT "SIZE" FROM V$SGASTAT WHERE NAME='SLAB_CSR'),0)/1048576)
  || ',' || ROUND(NVL((SELECT "SIZE" FROM V$SGASTAT WHERE NAME='SLAB_SC_PIN'),0)/1048576)
  || ',' || (SELECT COUNT(*) FROM V$SESSION)
  || ',' || (SELECT COUNT(*) FROM V$SQL)
FROM dual;
EXIT
SQL
)"

# 숫자만 뽑는다. 값 안에 공백이 없으므로 여기서 지워도 안전하다.
NUMS="$(printf '%s' "$RAW" | grep '^DATA,' | head -1 | sed 's/^DATA,//' | tr -d ' \r')"
RC=0

if [ -z "$NUMS" ]; then
  echo "** 측정 실패 — DB 가 응답하지 않거나 이미 메모리가 바닥났습니다. **"
  printf '%s\n' "$RAW" | head -10
  [ -f "$CSV" ] || echo "$HDR" > "$CSV"
  echo "${NOW},측정실패,,,,,,,,,,," >> "$CSV"
  RC=2
else
  [ -f "$CSV" ] || echo "$HDR" > "$CSV"
  echo "${NOW},${NUMS}" >> "$CSV"
  ROOT_FREE="$(printf '%s' "$NUMS" | cut -d, -f3)"
  INNER_FREE="$(printf '%s' "$NUMS" | cut -d, -f4)"
  echo "이번 측정: ${NOW},${NUMS}"
  echo "root 여유 : ${ROOT_FREE}MB   (임계치 ${WARN_ROOT_MB}MB)  ← 이게 진짜 헤드룸"
  echo "내부 여유 : ${INNER_FREE}MB  (배분된 하위 풀 안의 여유. 오르내리는 게 정상)"
  if [ "${ROOT_FREE:-0}" -lt "$WARN_ROOT_MB" ] 2>/dev/null; then
    echo "** 경고: root 여유가 임계치 아래입니다. 계획 재기동 또는 증설을 앞당기세요. **"
    RC=1
  fi
fi

hr "sys.log 의 OUT_OF_SHP"
docker exec "$CONTAINER" bash -lc '
  L=$TB_HOME/instance/$TB_SID/log/slog/sys.log
  N=$(grep -c "OUT_OF_SHP" "$L" 2>/dev/null) || N=0
  echo "누적 건수: ${N:-0}"
  if [ "${N:-0}" -gt 0 ]; then echo "--- 최근 3건 ---"; grep "OUT_OF_SHP" "$L" | tail -3; fi
  echo "(컨테이너 시각은 UTC 다. 호스트 KST 보다 9시간 빠르다)"' 2>&1

hr "추이"
show_trend

cat <<'EOF'

읽는 법:
  - root여유MB 가 꾸준히 준다        -> 래칫이 도는 중. 남은 일수를 계산해 둘 것.
                                        (예: 하루 5MB 씩 줄면 981MB 는 약 200일)
  - PP / DD_CACHE / CSR 이 오른다    -> 파싱·객체 접근이 늘고 있다. 수렴하면 정상.
  - TCBUF / WLIST 가 오른다          -> 부팅 고정분이 아니었다는 뜻. Tibero 기술지원 문의.
  - 내부여유MB 만 오르내린다          -> 정상. 하위 풀이 root 에서 받고 쓰는 과정이다.
  - 커서 수가 계속 는다              -> 리터럴 SQL 의심. 30_shmem_diag.sh 의 4-11 확인.
EOF
exit $RC
