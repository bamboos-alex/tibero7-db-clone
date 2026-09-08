#!/usr/bin/env bash
# 공유 풀 확장 — .tip 상향 + 재기동                   [파괴적. DRYRUN=1 기본]
#
# ┌─ 왜 재기동인가 (30/31 로 실측한 근거) ─────────────────────────────────┐
# │   root alloc: available=292,831,232 (279MB)  used=289,406,976         │
# │   -> FLUSH SHARED_POOL 실행 전후 이 수치가 완전히 동일했다.           │
# │      하위 할당자(SLAB/DD)가 가져간 청크는 root 로 반납되지 않는다.     │
# │      flush 도 세션 kill 도 root 여유를 늘리지 못한다.                  │
# │   TOTAL_SHM_SIZE=2G 중 가변 영역이 279MB(14%)뿐인 것이 근본 원인이다.  │
# └────────────────────────────────────────────────────────────────────────┘
#
# ★★ 선행 조건: 유효한 라이선스 ★★
#   2026-09-03 확인 결과 end_date=2026/08/19 로 **이미 만료**다.
#   컨테이너는 만료 하루 전(2026-08-18)에 기동돼 지금까지 떠 있을 뿐이다.
#   지금 내리면 다시 올라오지 않는다. 새 license.xml 을 확보한 뒤에 apply 한다.
#   이 스크립트는 만료 상태에서 apply 를 거부한다 (LICENSE_OK=1 로만 우회 가능).
#
# .tip 은 ./config 가 볼륨 마운트돼 있으므로 호스트에 남는다 (check 에서 확인).
# 데이터는 ./data 볼륨에 있어 컨테이너를 재생성해도 보존된다.
#
# 사용법 (사내 서버에서 실행):
#   ./32_shmem_resize.sh check      # 라이선스·설정·엔트리포인트 확인   [읽기 전용]
#   ./32_shmem_resize.sh baseline   # V$SGASTAT 기준선 저장             [읽기 전용]
#   ./32_shmem_resize.sh plan       # 바뀔 내용만 출력                  [읽기 전용]
#   DRYRUN=0 ./32_shmem_resize.sh apply     # 적용 + 재기동             [파괴적]
#   DRYRUN=0 ./32_shmem_resize.sh rollback  # 백업으로 되돌리고 재기동
#
# 값 조정:
#   NEW_TOTAL_SHM=8G NEW_MEMORY_TARGET=10G NEW_DOCKER_SHM=9gb DRYRUN=0 ./32_shmem_resize.sh apply
#
# ※ 크기를 키우는 것은 "시간을 버는" 조치다. 근본 해결은 아니다.
#   Tibero 의 하위 할당자는 root 에 메모리를 반납하지 않으므로, 아래 셋 중 하나가 있으면
#   아무리 크게 잡아도 언젠가 찬다. 증설 후 34_shmem_watch.sh 로 2~3주 추이를 볼 것.
#     - 리터럴 SQL (바인드 변수 미사용) -> 라이브러리 캐시가 수렴하지 않는다
#     - 상시 DDL (객체 생성/삭제 반복)  -> 딕셔너리 캐시가 수렴하지 않는다
#     - 커서 close() 누락               -> SC_PIN 이 누적된다
#   추이가 평평해지면 단순 저사양이었던 것이고 재기동은 다시 필요 없다.
#
# 다른 인스턴스에 적용:
#   CONTAINER=tibero7_ut COMPOSE_DIR=~/alex/tibero7_ut ./32_shmem_resize.sh check

set -uo pipefail

CONTAINER="${CONTAINER:-tibero7_ut_tablename}"
COMPOSE_DIR="${COMPOSE_DIR:-$HOME/alex/tibero7_ut_tablename}"
SYS_USER="${SYS_USER:-sys}"
SYS_PASS="${SYS_PASS:-tibero123}"
DRYRUN="${DRYRUN:-1}"
LICENSE_OK="${LICENSE_OK:-0}"              # 1 = 라이선스 차단을 의도적으로 우회

# 기본값을 넉넉하게 잡는 이유: 재기동은 자주 할 수 없으므로 한 번에 끝내야 한다.
# 실측 (2026-09-08, 6G 로 올린 뒤 V$SGA 로 확인) — 비율은 선형이 아니다
#   2G -> root 292,831,232 (279MB, 13.6%)   ... 고갈됨
#   6G -> root 1,431,502,848 (1.33GB, 22.2%) ... 4.9배. SLAB max 도 140MB -> 683MB
# 호스트 62GB / 여유 37GB. 세 컨테이너를 모두 6G 로 올려도 18GB 로 감당된다.
NEW_TOTAL_SHM="${NEW_TOTAL_SHM:-6G}"
NEW_MEMORY_TARGET="${NEW_MEMORY_TARGET:-8G}"   # PGA 포함 상한. TOTAL_SHM 보다 커야 한다
NEW_DOCKER_SHM="${NEW_DOCKER_SHM:-7gb}"        # TOTAL_SHM_SIZE 보다 커야 한다

STAMP="$(date +%Y%m%d_%H%M%S)"
LOG="${LOG:-32_shmem_resize_${STAMP}.log}"
exec > >(tee -a "$LOG") 2>&1

hr()  { printf '\n===== %s =====\n' "$1"; }
die() { echo; echo "중단: $*" >&2; exit 1; }

SID=""
resolve_sid() {
  SID="$(docker exec "$CONTAINER" bash -lc 'echo $TB_SID' 2>/dev/null | tr -d '\r\n')"
  [ -n "$SID" ] || SID="TAIMS"
}

# 라이선스 만료일을 읽어 오늘과 비교한다. 0=유효, 1=만료, 2=판독불가
license_state() {
  local f="$COMPOSE_DIR/license/license.xml" end
  [ -f "$f" ] || f=""
  if [ -n "$f" ]; then
    end="$(grep -o '<end_date>[^<]*</end_date>' "$f" 2>/dev/null | head -1 | sed 's/<[^>]*>//g')"
  else
    end="$(docker exec "$CONTAINER" bash -lc 'grep -o "<end_date>[^<]*</end_date>" $TB_HOME/license/license.xml' 2>/dev/null | sed 's/<[^>]*>//g' | tr -d '\r')"
  fi
  LIC_END="$end"
  [ -n "$end" ] || return 2
  local e t
  e="$(printf '%s' "$end" | tr -d '/-')"
  t="$(date +%Y%m%d)"
  [ "$e" -ge "$t" ] 2>/dev/null && return 0 || return 1
}

# compose 에 ./config 볼륨을 추가한다 (없는 구성용)
add_config_volume() {
  local yml="$1"
  if grep -q ':/opt/tibero7/config' "$yml"; then echo "  (이미 마운트돼 있음)"; return 0; fi
  if grep -q 'license\.xml:/opt/tibero7/license/license\.xml' "$yml"; then
    sed -i 's#\(.*license\.xml:/opt/tibero7/license/license\.xml\)#\1\n      - ./config:/opt/tibero7/config#' "$yml"
  else
    awk '{print} /^[[:space:]]*volumes:[[:space:]]*$/ && !d {print "      - ./config:/opt/tibero7/config"; d=1}' \
      "$yml" > "${yml}.tmp$$" && mv "${yml}.tmp$$" "$yml"
  fi
  grep -n ':/opt/tibero7/config' "$yml" || return 1
}

banner() {
  echo "대상 컨테이너 : $CONTAINER"
  echo "compose 경로  : $COMPOSE_DIR"
  echo "DRYRUN        : $DRYRUN  $([ "$DRYRUN" = 1 ] && echo '(출력만. 변경 없음)' || echo '*** 실제로 재기동합니다 ***')"
  echo "적용할 값     : TOTAL_SHM_SIZE=$NEW_TOTAL_SHM  MEMORY_TARGET=$NEW_MEMORY_TARGET  shm_size=$NEW_DOCKER_SHM"
  echo "기록 파일     : $LOG"
  echo "실행 시각     : $(date '+%F %T %Z')"
}

# ─────────────────────────────────────────────────────────────
# check  [읽기 전용]
# ─────────────────────────────────────────────────────────────
cmd_check() {
  resolve_sid
  hr "1. 라이선스  ★ 재기동 가능 여부를 여기서 판정한다"
  local st; license_state; st=$?
  echo "호스트 파일 : $COMPOSE_DIR/license/license.xml"
  echo "만료일      : ${LIC_END:-(판독 실패)}"
  echo "오늘        : $(date +%F)"
  docker inspect -f '컨테이너 기동: {{.State.StartedAt}}  (재시작 {{.RestartCount}}회)' "$CONTAINER" 2>&1
  case $st in
    0) echo "판정        : 유효. 재기동해도 다시 올라온다." ;;
    1) cat <<EOF
판정        : ** 만료 ** — 지금 내리면 다시 올라오지 않는다.
              컨테이너가 만료 전에 기동돼 떠 있을 뿐이다.
              apply 는 차단된다. 새 license.xml 을 ./license/ 에 넣은 뒤 다시 실행할 것.

              ※ restart: unless-stopped 가 걸려 있어 호스트 리부팅이나
                docker 데몬 재시작만으로도 자동 재기동 -> 기동 실패가 된다.
                이 서버의 세 컨테이너 모두 같은 위험에 있는지 확인할 것:
                  for c in tibero7 tibero7_ut tibero7_ut_tablename; do
                    echo "== \$c"; docker inspect -f '{{.State.StartedAt}}' \$c 2>/dev/null; done
EOF
       ;;
    *) echo "판정        : 만료일을 읽지 못했다. 수동 확인 필요." ;;
  esac

  hr "2. 현재 .tip"
  echo "컨테이너 경로: /opt/tibero7/config/${SID}.tip"
  echo "호스트  경로 : $COMPOSE_DIR/config/${SID}.tip"
  if [ -f "$COMPOSE_DIR/config/${SID}.tip" ]; then
    echo "-> ./config 가 볼륨 마운트돼 있어 **호스트에서 직접 수정**하면 된다. (권장 경로)"
  else
    echo "-> 호스트에 없다. apply 가 자동으로 처리한다:"
    echo "     docker cp 로 config 를 통째로 꺼내고 compose 에 ./config 볼륨을 추가한다."
  fi
  docker exec "$CONTAINER" bash -lc "grep -vE '^\s*#|^\s*$' \$TB_HOME/config/\$TB_SID.tip" 2>&1

  hr "3. 엔트리포인트가 기동마다 .tip 을 다시 만드는가"
  echo "-- 다시 만든다면 우리가 고친 값이 부팅 때 덮어써진다. 그때는 tip.template 도 같이 고쳐야 한다."
  docker exec "$CONTAINER" bash -lc '
    E=/opt/entrypoint.sh
    if [ -f "$E" ]; then
      echo "--- $E 에서 tip / SHM / MEMORY 관련 행 ---"
      grep -nE "tip|TOTAL_SHM|MEMORY_TARGET|template" "$E" | head -40
    else
      echo "(/opt/entrypoint.sh 없음)"
    fi
    echo
    echo "--- tip.template 존재 여부 ---"
    ls -l $TB_HOME/config/tip.template 2>/dev/null || echo "(없음)"
    grep -nE "TOTAL_SHM_SIZE|MEMORY_TARGET" $TB_HOME/config/tip.template 2>/dev/null' 2>&1

  hr "4. 호스트 여유"
  free -h 2>&1
  df -h "$COMPOSE_DIR" 2>&1

  hr "다음"
  cat <<EOF
  라이선스가 유효하면 :  ./32_shmem_resize.sh baseline
                     ->  ./32_shmem_resize.sh plan
                     ->  DRYRUN=0 ./32_shmem_resize.sh apply
  만료 상태면        :  새 license.xml 확보가 먼저다. 그때까지 아무 컨테이너도 내리지 말 것.
EOF
}

# ─────────────────────────────────────────────────────────────
# baseline — 나중에 "새는지" 판단할 기준선 [읽기 전용]
# ─────────────────────────────────────────────────────────────
cmd_baseline() {
  local OUT="sgastat_${STAMP}.txt"
  hr "V\$SGASTAT 기준선 -> $OUT"
  echo "-- 기동 직후와 며칠 뒤를 비교하면 어느 항목이 자라는지 드러난다."
  echo "-- 이번 건의 최대 소비자였던 SLAB_TCBUF(65MB) / SLAB_WLIST(34MB) 를 주시할 것."
  docker exec -i "$CONTAINER" bash -lc "tbsql -s ${SYS_USER}/${SYS_PASS}" > "$OUT" 2>&1 <<'SQL'
SET LINESIZE 200
SET PAGESIZE 5000
SELECT SYSDATE AS 측정시각 FROM dual;
SELECT NAME, "SIZE" FROM V$SGASTAT WHERE "SIZE" > 0 ORDER BY "SIZE" DESC;
SELECT SUM("SIZE") AS 합계 FROM V$SGASTAT;
EXIT
SQL
  echo "저장 완료: $OUT"; head -25 "$OUT"
}

# ─────────────────────────────────────────────────────────────
cmd_plan() {
  resolve_sid
  hr "바뀌는 것"
  cat <<EOF
  [1] $COMPOSE_DIR/config/${SID}.tip
        TOTAL_SHM_SIZE : 2G  ->  $NEW_TOTAL_SHM
        MEMORY_TARGET  : 4G  ->  $NEW_MEMORY_TARGET
        (./config 가 이미 볼륨이므로 호스트에서 고치면 그대로 유지된다)

  [2] $COMPOSE_DIR/config/tip.template   ← 있고 값이 박혀 있을 때만
        엔트리포인트가 .tip 을 재생성해도 새 값이 나오도록 같이 고친다.

  [3] $COMPOSE_DIR/docker-compose.yml
        shm_size : 2gb -> $NEW_DOCKER_SHM     (SGA 보다 커야 한다)

  [4] 재기동
        tbdown immediate (실패 시 abort) -> docker compose down -> up -d

  백업은 *.bak_$STAMP 로 남는다. rollback 으로 되돌릴 수 있다.

기대 효과:
  가변 영역(root allocator) 279MB -> 1.33GB (2026-09-08 실측, 4.9배).
  root 여유가 3.3MB -> 약 981MB 가 된다.
  구조적 고정분(TCBUF/WLIST/TX_L1CL/SLAB_CSR)은 약 165MB 로 비중이 47% -> 12% 로 떨어진다.

  ※ 실제 값은 7. 검증 단계의 V$SGA 'SHARED POOL MEMORY' 행에서 확인한다.
EOF
  echo; echo "실제 적용:  DRYRUN=0 $0 apply"
}

# ─────────────────────────────────────────────────────────────
cmd_apply() {
  resolve_sid
  local CFG="$COMPOSE_DIR/config"
  local TIP="$CFG/${SID}.tip"
  local TPL="$CFG/tip.template"
  local YML="$COMPOSE_DIR/docker-compose.yml"

  hr "0. 사전 확인"
  [ -f "$YML" ] || die "docker-compose.yml 이 없습니다: $YML"

  local st; license_state; st=$?
  echo "라이선스 만료일: ${LIC_END:-(판독 실패)}   오늘: $(date +%F)"
  if [ $st -ne 0 ]; then
    if [ "$LICENSE_OK" = "1" ]; then
      echo "** 라이선스가 유효하지 않지만 LICENSE_OK=1 로 강행합니다. **"
    else
      die "라이선스가 만료(또는 판독 불가)입니다. 지금 내리면 다시 올라오지 않습니다.
     새 license.xml 을 $COMPOSE_DIR/license/ 에 넣고 다시 실행하세요.
     그래도 강행하려면 LICENSE_OK=1 을 붙이세요 (권장하지 않음)."
    fi
  else
    echo "라이선스 유효 — 진행합니다."
  fi

  NEED_MOUNT=0
  if [ ! -f "$TIP" ]; then
    NEED_MOUNT=1
    echo
    echo "-- ./config 볼륨이 없는 구성입니다 (.tip 이 호스트에 없음)."
    echo "   컨테이너의 config 디렉터리를 통째로 꺼내고 compose 에 볼륨을 추가합니다."
    echo "   ※ tbdsn.tbr, tip.template, tb_wallet 등이 함께 나오므로 내용은 보존됩니다."
  fi

  if [ "$DRYRUN" = "1" ]; then
    echo; echo "(DRYRUN) 아래 순서로 실행됩니다. 실제 적용: DRYRUN=0 $0 apply"
    cmd_plan; return 0
  fi

  hr "1. 백업"
  cp -v "$YML" "${YML}.bak_${STAMP}"

  if [ "$NEED_MOUNT" = "1" ]; then
    hr "1b. 컨테이너 config 디렉터리 반출 + 볼륨 추가"
    mkdir -p "$CFG"
    docker cp "$CONTAINER:/opt/tibero7/config/." "$CFG/" || die "config 반출 실패"
    ls -la "$CFG" | head -20
    [ -f "$TIP" ] || die "반출했는데도 ${SID}.tip 이 없습니다. 경로를 확인하세요."
    add_config_volume "$YML" || die "compose 에 config 볼륨을 추가하지 못했습니다. 수동으로 넣으세요:
       volumes:
         - ./config:/opt/tibero7/config"
  fi

  cp -v "$TIP" "${TIP}.bak_${STAMP}"
  [ -f "$TPL" ] && cp -v "$TPL" "${TPL}.bak_${STAMP}"

  hr "2. .tip 수정"
  sed -i -E "s/^TOTAL_SHM_SIZE=.*/TOTAL_SHM_SIZE=${NEW_TOTAL_SHM}/" "$TIP"
  sed -i -E "s/^MEMORY_TARGET=.*/MEMORY_TARGET=${NEW_MEMORY_TARGET}/"  "$TIP"
  grep -q '^TOTAL_SHM_SIZE=' "$TIP" || echo "TOTAL_SHM_SIZE=${NEW_TOTAL_SHM}"   >> "$TIP"
  grep -q '^MEMORY_TARGET='  "$TIP" || echo "MEMORY_TARGET=${NEW_MEMORY_TARGET}" >> "$TIP"
  grep -nE "TOTAL_SHM_SIZE|MEMORY_TARGET" "$TIP"

  if [ -f "$TPL" ] && grep -qE "^TOTAL_SHM_SIZE=|^MEMORY_TARGET=" "$TPL"; then
    hr "2b. tip.template 도 수정 (재생성 대비)"
    sed -i -E "s/^TOTAL_SHM_SIZE=.*/TOTAL_SHM_SIZE=${NEW_TOTAL_SHM}/" "$TPL"
    sed -i -E "s/^MEMORY_TARGET=.*/MEMORY_TARGET=${NEW_MEMORY_TARGET}/"  "$TPL"
    grep -nE "TOTAL_SHM_SIZE|MEMORY_TARGET" "$TPL"
  fi

  hr "3. docker-compose.yml 의 shm_size 수정"
  sed -i -E "s/^([[:space:]]*)shm_size:.*/\\1shm_size: ${NEW_DOCKER_SHM}/" "$YML"
  grep -nE "shm_size" "$YML" || die "shm_size 행을 찾지 못했습니다. 수동 확인 필요."

  echo
  echo "위 내용으로 **재기동**합니다. 라이선스 만료일: ${LIC_END:-?}"
  read -r -p "계속하려면 yes 입력: " ans
  [ "$ans" = "yes" ] || die "취소했습니다. 파일 수정은 남아 있습니다 — '$0 rollback' 으로 되돌리세요."

  hr "4. 인스턴스 정지"
  echo "-- 공유 풀이 바닥나 정상 종료가 실패할 수 있습니다. immediate -> abort 순으로 시도합니다."
  timeout 90 docker exec "$CONTAINER" bash -lc "tbdown immediate" 2>&1 || {
    echo "-- immediate 실패/타임아웃 -> abort (기동 시 리두로 복구됩니다)"
    timeout 60 docker exec "$CONTAINER" bash -lc "tbdown abort" 2>&1 || echo "-- abort 도 실패. compose down 으로 진행합니다."
  }

  hr "5. 컨테이너 재생성 (shm_size 변경은 재생성이 필요하다)"
  ( cd "$COMPOSE_DIR" && docker compose down && docker compose up -d ) 2>&1

  hr "6. 기동 대기 (최대 5분)"
  local ok=0
  for i in $(seq 1 60); do
    if docker logs "$CONTAINER" 2>&1 | grep -q "Ready To Use"; then ok=1; echo "기동 완료"; break; fi
    sleep 5; printf '.'
  done
  echo
  docker logs "$CONTAINER" 2>&1 | tail -25
  [ "$ok" = "1" ] || { echo; echo "** 기동 확인 실패 — 위 로그를 확인하세요. 되돌리려면: DRYRUN=0 $0 rollback **"; exit 1; }

  hr "7. 검증"
  docker exec "$CONTAINER" bash -lc 'grep -E "TOTAL_SHM_SIZE|MEMORY_TARGET" $TB_HOME/config/$TB_SID.tip; df -h /dev/shm; ipcs -m 2>/dev/null | head -5' 2>&1
  docker exec -i "$CONTAINER" bash -lc "tbsql -s ${SYS_USER}/${SYS_PASS}" <<'SQL' 2>&1
SET LINESIZE 200
SELECT 'DB 접속 정상' AS 결과 FROM dual;
SELECT NAME, "SIZE" FROM V$SGASTAT WHERE NAME IN ('Free Space','SLAB_TCBUF','SLAB_WLIST','SLAB_SC_PIN');
EXIT
SQL
  hr "8. 기준선 저장"
  cmd_baseline
  cat <<'EOF'

앱을 다시 붙여 JDBC-3018 이 사라졌는지 확인하세요.
며칠 뒤 baseline 을 다시 떠서 어느 항목이 자라는지 비교하면 누수 여부가 드러납니다.
되돌리기: DRYRUN=0 ./32_shmem_resize.sh rollback
EOF
}

# ─────────────────────────────────────────────────────────────
cmd_rollback() {
  resolve_sid
  local YML="$COMPOSE_DIR/docker-compose.yml"
  local TIP="$COMPOSE_DIR/config/${SID}.tip"
  hr "백업 목록"
  ls -1t "${YML}".bak_* 2>/dev/null || die "백업이 없습니다."
  local BY BT
  BY="$(ls -1t "${YML}".bak_* | head -1)"
  BT="$(ls -1t "${TIP}".bak_* 2>/dev/null | head -1)"
  echo "compose 복원: $BY"; echo ".tip 복원   : ${BT:-(없음)}"
  if [ "$DRYRUN" = "1" ]; then echo "(DRYRUN) 실제 실행: DRYRUN=0 $0 rollback"; return 0; fi
  cp -v "$BY" "$YML"
  [ -n "$BT" ] && cp -v "$BT" "$TIP"
  ( cd "$COMPOSE_DIR" && docker compose down && docker compose up -d ) 2>&1
  sleep 20; docker logs "$CONTAINER" 2>&1 | tail -25
}

banner
case "${1:-}" in
  check)    cmd_check ;;
  baseline) cmd_baseline ;;
  plan)     cmd_plan ;;
  apply)    cmd_apply ;;
  rollback) cmd_rollback ;;
  *) cat <<EOF

사용법: $0 {check|baseline|plan|apply|rollback}

  check     라이선스·.tip·엔트리포인트 확인           [읽기 전용]  ★먼저
  baseline  V\$SGASTAT 스냅샷 저장 (누수 추적용)      [읽기 전용]
  plan      바뀔 내용만 출력                          [읽기 전용]
  apply     .tip/compose 수정 + 재기동                [파괴적]
  rollback  백업으로 되돌리고 재기동                  [파괴적]

apply 는 DRYRUN=0 + 'yes' 입력을 요구하고, 라이선스가 만료면 거부합니다.
EOF
     exit 1 ;;
esac
