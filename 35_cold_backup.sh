#!/usr/bin/env bash
# 2차 UT 물리 콜드 백업 / 복원                        [파괴적. DRYRUN=1 기본]
#
# ┌─ 무엇을 위한 것인가 ───────────────────────────────────────────────────┐
# │ 09_refresh.sh 는 DROP USER CASCADE 로 시작하고 되돌리기가 없다.        │
# │ 그 앞에 이 스크립트로 인스턴스를 통째로 떠 두면 언제든 돌아올 수 있다. │
# └────────────────────────────────────────────────────────────────────────┘
#
# 절차 전체는 35_ut_update_design.md 에 있다. 이 스크립트는 그 1) 과 되돌리기를 맡는다.
#
# ★★ 왜 컨테이너를 내리는가 ★★
#   가동 중에 데이터파일을 복사하면 쓰기 중인 블록이 섞여 들어가 복원되지 않는 tar 가
#   나온다. 콜드 백업이어야 복원이 성립한다. 정지 시간은 tar 시간만큼이다.
#
# ★★ 선행 조건: 유효한 라이선스 ★★
#   라이선스는 기동 시점에만 검사된다. 만료된 상태로 내리면 다시 올라오지 않는다.
#   backup/restore 는 만료 상태에서 거부한다 (LICENSE_OK=1 로만 우회).
#
# 백업에 담기는 것 (모두 $BASEDIR 아래의 볼륨):
#   data/     데이터파일·리두·컨트롤파일. 계정·권한·테이블스페이스·AQ 작업물 전부
#   config/   TAIMS.tip — 2차 UT 는 TOTAL_SHM_SIZE=6G 다. 빠지면 복원본이 2G 로 돈다
#   license/  license.xml — 그 시점에 기동 가능했던 라이선스
#
# 사용법 (사내 서버 bamboos@192.168.0.101 에서 실행):
#   ./35_cold_backup.sh check                       # 대상·라이선스·용량 확인  [읽기 전용]
#   ./35_cold_backup.sh list                        # 백업 목록                [읽기 전용]
#   DRYRUN=0 ./35_cold_backup.sh backup             # 정지 -> tar -> 재기동    [파괴적]
#   DRYRUN=0 ./35_cold_backup.sh restore <파일명>   # 정지 -> 교체 -> 재기동   [파괴적]
#
# 옵션:
#   COMPRESS=0    무압축. 디스크는 더 쓰지만 tar 시간이 짧아진다
#                 (압축은 gzip -1. pigz 가 설치돼 있으면 자동으로 병렬 압축한다)
#   LICENSE_OK=1  라이선스 차단 우회 (권하지 않는다)
#
# 다른 인스턴스에 적용:
#   CONTAINER=tibero7_ut BASEDIR=~/alex/tibero7_ut ./35_cold_backup.sh check
#
# ※ restore 는 data/ 를 지우지 않는다. data.old_<시각> 으로 옮겨 두고 새로 푼다.
#   복원이 잘못돼도 원본이 남는다. 대신 디스크가 한때 2배 필요하다 — check 가 본다.

set -uo pipefail

CONTAINER="${CONTAINER:-tibero7_ut_tablename}"
BASEDIR="${BASEDIR:-$HOME/alex/tibero7_ut_tablename}"
BACKUPDIR="${BACKUPDIR:-$BASEDIR/backup}"
SYS_USER="${SYS_USER:-sys}"
SYS_PASS="${SYS_PASS:-tibero123}"
COMPRESS="${COMPRESS:-1}"
DRYRUN="${DRYRUN:-1}"
LICENSE_OK="${LICENSE_OK:-0}"

# 백업에 담을 디렉터리. BASEDIR 기준 상대경로여야 한다 (tar -C 로 푼다)
VOLUMES="${VOLUMES:-data config license}"

STAMP="$(date +%Y%m%d_%H%M%S)"
LOG="${LOG:-35_cold_backup_${STAMP}.log}"
exec > >(tee -a "$LOG") 2>&1

hr()   { printf '\n===== %s =====\n' "$1"; }
info() { printf '  %s\n' "$*"; }
die()  { echo; echo "중단: $*" >&2; exit 1; }

# 비밀번호는 로그에 그대로 남는다. 화면·로그 양쪽에서 지운다.
mask() { local s="$1"; [ -n "$SYS_PASS" ] && s="${s//$SYS_PASS/********}"; printf '%s' "$s"; }

# ─────────────────────────────────────────────────────────────
# 공통
# ─────────────────────────────────────────────────────────────

# 존재하는 볼륨만 추린다. config 가 없는 구버전 구성도 있다
present_volumes() {
  local v out=""
  for v in $VOLUMES; do [ -e "$BASEDIR/$v" ] && out="$out $v"; done
  printf '%s' "${out# }"
}

container_running() {
  [ "$(docker inspect -f '{{.State.Running}}' "$CONTAINER" 2>/dev/null)" = "true" ]
}

# 라이선스 만료일 판정. 0=유효, 1=만료, 2=판독불가. LIC_END 에 만료일을 담는다
LIC_END=""
license_state() {
  local f="$BASEDIR/license/license.xml" end=""
  if [ -f "$f" ]; then
    end="$(grep -o '<end_date>[^<]*</end_date>' "$f" 2>/dev/null | head -1 | sed 's/<[^>]*>//g')"
  elif container_running; then
    end="$(docker exec "$CONTAINER" bash -lc 'grep -o "<end_date>[^<]*</end_date>" $TB_HOME/license/license.xml' 2>/dev/null | sed 's/<[^>]*>//g' | tr -d '\r')"
  fi
  LIC_END="$end"
  [ -n "$end" ] || return 2
  local e t
  e="$(printf '%s' "$end" | tr -d '/-')"
  t="$(date +%Y%m%d)"
  [ "$e" -ge "$t" ] 2>/dev/null && return 0 || return 1
}

require_license() {
  local st; license_state; st=$?
  case $st in
    0) info "라이선스 유효 (만료 $LIC_END) — 내렸다 올려도 다시 뜬다" ;;
    1) [ "$LICENSE_OK" = "1" ] \
         && info "** 라이선스 만료($LIC_END). LICENSE_OK=1 로 우회합니다 — 재기동에 실패할 수 있습니다 **" \
         || die "라이선스가 만료됐습니다($LIC_END). 지금 내리면 다시 올라오지 않습니다.
       33_license_apply.sh 로 갱신본을 넣은 뒤 다시 실행하세요." ;;
    *) [ "$LICENSE_OK" = "1" ] \
         && info "** 만료일 판독 실패. LICENSE_OK=1 로 진행합니다 **" \
         || die "라이선스 만료일을 읽지 못했습니다: $BASEDIR/license/license.xml
       확인 후 진행하거나 LICENSE_OK=1 로 우회하세요." ;;
  esac
}

# KB 단위. sparse 파일이라 실사용량(du)과 겉보기 크기가 크게 다르다
used_kb()  { du -sk  "$1" 2>/dev/null | awk '{print $1}'; }
avail_kb() { df -Pk "$1" 2>/dev/null | awk 'NR==2{print $4}'; }
human()    { awk -v k="${1:-0}" 'BEGIN{split("KB MB GB TB",u," ");i=1;while(k>=1024&&i<4){k/=1024;i++};printf "%.1f%s",k,u[i]}'; }

confirm() {   # $1 = 확인 문구
  local ans=""
  echo
  echo "$1"
  read -r -p "계속하려면 yes 입력: " ans || true
  [ "$ans" = "yes" ] || die "취소했습니다. 변경된 것은 없습니다."
}

# DB 가 실제로 응답할 때까지 기다린다.
#   docker logs 의 "Ready To Use" 는 이전 기동 때의 것이 그대로 남아 있어 기준으로 쓸 수 없다.
#   접속이 되는지를 직접 확인한다.
wait_db_ready() {
  local max="${1:-60}" i out
  for i in $(seq 1 "$max"); do
    if container_running; then
      out="$(docker exec -i "$CONTAINER" bash -lc "tbsql -s ${SYS_USER}/${SYS_PASS}" <<'SQL' 2>&1
SET HEADING OFF
SELECT 'TBREADY' FROM dual;
EXIT
SQL
)"
      case "$out" in *TBREADY*) echo; info "DB 응답 확인 (${i}회차)"; return 0 ;; esac
    fi
    sleep 5; printf '.'
  done
  echo
  [ -n "${out:-}" ] && { info "마지막 응답:"; printf '%s\n' "$(mask "$out")" | tail -10 | sed 's/^/    /'; }
  return 1
}

stop_instance() {
  hr "인스턴스 정지"
  info "tbdown immediate 를 먼저 시도합니다 (깨끗이 내려야 복원이 단순해집니다)"
  timeout 120 docker exec "$CONTAINER" bash -lc "tbdown immediate" 2>&1 || {
    info "immediate 실패/타임아웃 -> abort (기동 시 리두로 복구됩니다)"
    timeout 60 docker exec "$CONTAINER" bash -lc "tbdown abort" 2>&1 || info "abort 도 실패. compose stop 으로 진행합니다."
  }
  info "컨테이너 정지"
  ( cd "$BASEDIR" && docker compose stop ) 2>&1
  sleep 3
  container_running && die "컨테이너가 아직 실행 중입니다: $CONTAINER
       수동으로 확인하세요. 이 상태로 tar 를 뜨면 복원되지 않는 백업이 나옵니다."
  info "정지 확인 — 이제부터 파일이 안전합니다"
}

start_instance() {
  hr "기동"
  ( cd "$BASEDIR" && docker compose start ) 2>&1
  info "기동 대기 (최대 5분)"
  if wait_db_ready 60; then
    docker exec "$CONTAINER" bash -lc 'grep -E "TOTAL_SHM_SIZE|MEMORY_TARGET" $TB_HOME/config/$TB_SID.tip' 2>&1
    return 0
  fi
  docker logs --tail 40 "$CONTAINER" 2>&1
  return 1
}

# ─────────────────────────────────────────────────────────────
banner() {
  echo "대상 컨테이너 : $CONTAINER"
  echo "볼륨 경로     : $BASEDIR"
  echo "백업 보관     : $BACKUPDIR"
  echo "압축          : $([ "$COMPRESS" = 1 ] && echo 'gzip' || echo '없음')"
  echo "DRYRUN        : $DRYRUN  $([ "$DRYRUN" = 1 ] && echo '(출력만. 변경 없음)' || echo '*** 실제로 정지·재기동합니다 ***')"
  echo "기록 파일     : $LOG"
  echo "실행 시각     : $(date '+%F %T %Z')"
}

# ─────────────────────────────────────────────────────────────
# check  [읽기 전용]
# ─────────────────────────────────────────────────────────────
cmd_check() {
  hr "1. 대상 확인  ★ 인스턴스가 셋이다. 포트로만 구분된다"
  docker inspect -f '이름: {{.Name}}  기동: {{.State.StartedAt}}  실행중: {{.State.Running}}' "$CONTAINER" 2>&1
  docker port "$CONTAINER" 2>&1 | sed 's/^/  포트: /'
  info "8629=개발(건드리지 말 것) / 18629=1차 UT / 28629=2차 UT"
  container_running || info "** 컨테이너가 실행 중이 아닙니다 **"

  hr "2. 라이선스  ★ 내리기 전에 여기서 판정한다"
  local st; license_state; st=$?
  echo "  파일   : $BASEDIR/license/license.xml"
  echo "  만료일 : ${LIC_END:-(판독 실패)}   오늘: $(date +%F)"
  case $st in
    0) info "판정: 유효. 재기동해도 다시 올라온다" ;;
    1) info "판정: ** 만료 ** — 지금 내리면 다시 올라오지 않는다. backup 은 거부된다" ;;
    *) info "판정: 만료일을 읽지 못했다. 수동 확인 필요" ;;
  esac

  hr "3. 백업 대상 크기"
  local vols total=0 v u
  vols="$(present_volumes)"
  [ -n "$vols" ] || die "백업할 디렉터리가 없습니다: $BASEDIR ($VOLUMES)"
  for v in $vols; do
    u="$(used_kb "$BASEDIR/$v")"
    printf '  %-10s %10s\n' "$v/" "$(human "$u")"
    total=$(( total + u ))
  done
  [ "$vols" = "$VOLUMES" ] || info "** 없는 디렉터리는 건너뜁니다. 담기는 것: $vols **"
  printf '  %-10s %10s   (실사용량 기준)\n' "합계" "$(human "$total")"
  info "Tibero 데이터파일은 테이블스페이스 크기만큼 미리 잡혀 있어 빈 블록이 많습니다."
  info "tar --sparse 로 그 부분을 건너뛰므로 백업 파일은 이보다 작아집니다."

  hr "4. 디스크 여유"
  local av; av="$(avail_kb "$BASEDIR")"
  echo "  $BASEDIR 가 있는 파일시스템:"
  df -h "$BASEDIR" 2>&1 | sed 's/^/    /'
  printf '  여유           %10s\n' "$(human "$av")"
  printf '  backup 필요    %10s  (압축 전 기준, 실제로는 더 작다)\n' "$(human "$total")"
  printf '  restore 필요   %10s  (data.old 를 남기므로 한때 2배)\n' "$(human "$(( total * 2 ))")"
  if [ "${av:-0}" -lt "$total" ]; then
    info "** 여유가 백업 대상보다 작습니다. 이대로는 backup 이 실패할 수 있습니다 **"
  elif [ "${av:-0}" -lt "$(( total * 2 ))" ]; then
    info "backup 은 가능하지만 restore 시 공간이 빠듯합니다. 오래된 백업을 정리해 두세요."
  else
    info "backup·restore 모두 여유가 있습니다"
  fi

  hr "5. 기존 백업"
  cmd_list

  hr "판정"
  if [ $st = 0 ] && [ "${av:-0}" -ge "$total" ] && container_running; then
    echo "  진행 가능합니다:  DRYRUN=0 $0 backup"
  else
    echo "  위 경고를 먼저 해소하세요."
  fi
}

# ─────────────────────────────────────────────────────────────
# list  [읽기 전용]
# ─────────────────────────────────────────────────────────────
cmd_list() {
  [ -d "$BACKUPDIR" ] || { info "백업 폴더가 아직 없습니다: $BACKUPDIR"; return 0; }
  local n=0 f
  while IFS= read -r f; do
    [ -n "$f" ] || continue
    n=$(( n + 1 ))
    printf '  %-46s %8s  %s  %s\n' \
      "$(basename "$f")" \
      "$(human "$(used_kb "$f")")" \
      "$(date -r "$f" '+%F %H:%M' 2>/dev/null || echo '?')" \
      "$([ -f "$f.sha256" ] && echo 'sha256 있음' || echo '** sha256 없음 **')"
    # 곁딸린 .sha256 / .info 는 목록에 끼우지 않는다
  done < <(ls -1t "$BACKUPDIR"/ut_tablename_*.tar* 2>/dev/null | grep -Ev '\.(sha256|info)$')
  [ "$n" = 0 ] && info "백업이 없습니다."
  return 0
}

# ─────────────────────────────────────────────────────────────
# backup  [파괴적 — 정지·재기동]
# ─────────────────────────────────────────────────────────────
cmd_backup() {
  hr "0. 사전 판정"
  container_running || die "컨테이너가 실행 중이 아닙니다: $CONTAINER
       내려가 있는 이유를 먼저 확인하세요 (라이선스 만료일 수 있습니다)."
  require_license

  local vols total av tarf
  vols="$(present_volumes)"
  [ -n "$vols" ] || die "백업할 디렉터리가 없습니다: $BASEDIR ($VOLUMES)"
  total=0
  for v in $vols; do total=$(( total + $(used_kb "$BASEDIR/$v") )); done
  av="$(avail_kb "$BASEDIR")"
  info "담을 것: $vols   실사용 $(human "$total")   여유 $(human "$av")"
  [ "${av:-0}" -ge "$total" ] || die "디스크 여유가 부족합니다. './35_cold_backup.sh check' 를 보세요."

  if [ "$COMPRESS" = "1" ]; then tarf="$BACKUPDIR/ut_tablename_${STAMP}.tar.gz"
  else                           tarf="$BACKUPDIR/ut_tablename_${STAMP}.tar"; fi

  hr "계획"
  cat <<EOF
  1) tbdown immediate -> docker compose stop
  2) tar --sparse  $vols  ->  $tarf
  3) sha256 기록
  4) docker compose start -> DB 응답 확인

  정지 시간은 2) 의 tar 시간만큼입니다. 앱이 붙어 있으면 그동안 오류가 납니다.
EOF

  if [ "$DRYRUN" = "1" ]; then
    hr "DRYRUN"
    echo "  실제로 실행하려면: DRYRUN=0 $0 backup"
    return 0
  fi

  confirm "위 내용으로 **컨테이너를 내렸다 올립니다.** 라이선스 만료일: ${LIC_END:-?}"

  mkdir -p "$BACKUPDIR" || die "백업 폴더를 만들지 못했습니다: $BACKUPDIR"

  stop_instance

  hr "tar"
  local t0 t1
  t0="$(date +%s)"
  # 압축은 레벨 1 이다. 정지 시간을 줄이는 것이 우선이고, sparse 를 걷어낸 뒤라
  # 남는 것은 대부분 실데이터라 레벨을 올려도 크게 줄지 않는다.
  # pigz 가 있으면 코어를 쓴다 — 정지 시간이 그만큼 짧아진다.
  local ZIP=""
  if [ "$COMPRESS" = "1" ]; then
    if command -v pigz >/dev/null 2>&1; then ZIP="pigz -1"; info "pigz 사용 (병렬 압축)"
    else                                     ZIP="gzip -1"; fi
  fi
  if [ -n "$ZIP" ]; then
    tar --sparse -C "$BASEDIR" -cf - $vols | $ZIP > "$tarf"
  else
    tar --sparse -C "$BASEDIR" -cf "$tarf" $vols
  fi
  local rc=$?
  t1="$(date +%s)"
  if [ "$rc" != "0" ] || [ ! -s "$tarf" ]; then
    info "** tar 실패(rc=$rc). 컨테이너를 다시 올린 뒤 중단합니다 **"
    rm -f "$tarf"
    start_instance || info "** 기동도 실패했습니다. docker logs $CONTAINER 를 확인하세요 **"
    die "백업에 실패했습니다."
  fi
  info "완료 $(human "$(used_kb "$tarf")")  소요 $(( t1 - t0 ))초"

  hr "sha256"
  ( cd "$BACKUPDIR" && sha256sum "$(basename "$tarf")" > "$(basename "$tarf").sha256" ) 2>&1
  cat "$tarf.sha256" | sed 's/^/  /'

  # 무엇이 담겼는지 남긴다. 나중에 이 백업이 무엇인지 tar 를 풀지 않고 알 수 있어야 한다
  cat > "$tarf.info" <<EOF
컨테이너   : $CONTAINER
볼륨 경로  : $BASEDIR
담긴 것    : $vols
실사용량   : $(human "$total")
라이선스   : 만료 ${LIC_END:-?}
백업 시각  : $(date '+%F %T %Z')
tar 소요   : $(( t1 - t0 ))초
복원       : DRYRUN=0 $0 restore $(basename "$tarf")
EOF
  info "$tarf.info 기록"

  start_instance || die "** 기동 확인 실패 — docker logs $CONTAINER 를 확인하세요. 백업 파일은 남아 있습니다 **"

  hr "완료"
  cat <<EOF
  백업 : $tarf
  다음 : 09_refresh.sh 로 갱신합니다 (35_ut_update_design.md 의 3단계)

           DRYRUN=0 ./09_refresh.sh

         되돌리려면:  DRYRUN=0 $0 restore $(basename "$tarf")
EOF
}

# ─────────────────────────────────────────────────────────────
# restore  [파괴적 — 정지·교체·재기동]
# ─────────────────────────────────────────────────────────────
cmd_restore() {
  local name="${1:-}"
  [ -n "$name" ] || { hr "백업 목록"; cmd_list; die "복원할 파일명을 지정하세요.  예: DRYRUN=0 $0 restore ut_tablename_20260908_120000.tar.gz
       '가장 최근' 을 알아서 고르지 않습니다. 무엇을 덮는지 눈으로 확인해야 합니다."; }

  local tarf="$BACKUPDIR/$(basename "$name")"
  [ -f "$tarf" ] || die "백업 파일이 없습니다: $tarf"

  hr "0. 사전 판정"
  [ -f "$tarf.info" ] && sed 's/^/  /' "$tarf.info"
  require_license

  hr "1. 무결성 확인"
  if [ -f "$tarf.sha256" ]; then
    ( cd "$BACKUPDIR" && sha256sum -c "$(basename "$tarf").sha256" ) 2>&1 | sed 's/^/  /' \
      || die "sha256 불일치 — 이 파일로 복원하면 안 됩니다."
  else
    info "** sha256 파일이 없습니다. 무결성을 확인할 수 없습니다 **"
  fi
  info "tar 목록 판독 확인"
  local tflag=""; case "$tarf" in *.gz) tflag="z" ;; esac
  tar -${tflag}tf "$tarf" >/dev/null || die "tar 를 읽지 못했습니다 — 파일이 손상됐습니다."

  local vols; vols="$(present_volumes)"
  local av need
  av="$(avail_kb "$BASEDIR")"
  need=0
  for v in $vols; do need=$(( need + $(used_kb "$BASEDIR/$v") )); done
  info "현재 볼륨 $(human "$need") 를 .old 로 남기고 새로 풉니다. 여유 $(human "$av")"

  hr "계획"
  cat <<EOF
  1) tbdown immediate -> docker compose stop
  2) $vols  ->  <이름>.old_${STAMP}   (지우지 않고 이름만 바꿉니다)
  3) tar 해제  $tarf  ->  $BASEDIR
  4) docker compose start -> DB 응답 확인

  ** 지금 인스턴스에 들어 있는 내용은 .old 로 밀려납니다. **
  복원이 확인되면 .old 는 수동으로 지우세요 (디스크를 두 배로 씁니다).
EOF

  if [ "$DRYRUN" = "1" ]; then
    hr "DRYRUN"
    echo "  실제로 실행하려면: DRYRUN=0 $0 restore $(basename "$tarf")"
    return 0
  fi

  confirm "**$CONTAINER 를 $(basename "$tarf") 시점으로 되돌립니다.**"

  stop_instance

  hr "현재 볼륨 밀어내기"
  local v
  for v in $vols; do
    mv -v "$BASEDIR/$v" "$BASEDIR/${v}.old_${STAMP}" 2>&1 || die "$v 를 옮기지 못했습니다. 컨테이너는 내려가 있습니다 — 수동 확인 필요."
  done

  hr "해제"
  local t0 t1; t0="$(date +%s)"
  tar -C "$BASEDIR" -${tflag}xf "$tarf"    # --sparse 는 생성 전용. 해제는 아카이브의 sparse 정보를 그대로 따른다
  local rc=$?
  t1="$(date +%s)"
  if [ "$rc" != "0" ]; then
    info "** 해제 실패(rc=$rc). 밀어냈던 원본을 되돌립니다 **"
    for v in $vols; do rm -rf "${BASEDIR:?}/$v"; mv "$BASEDIR/${v}.old_${STAMP}" "$BASEDIR/$v"; done
    start_instance || info "** 기동도 실패했습니다. docker logs $CONTAINER 를 확인하세요 **"
    die "복원에 실패했습니다. 원본으로 되돌렸습니다."
  fi
  info "완료  소요 $(( t1 - t0 ))초"

  start_instance || die "** 기동 확인 실패 — docker logs $CONTAINER 를 확인하세요.
       밀어낸 원본이 $BASEDIR/*.old_${STAMP} 에 그대로 있습니다 **"

  hr "완료"
  cat <<EOF
  복원 : $(basename "$tarf") 시점
  잔여 : $BASEDIR/*.old_${STAMP}   — 확인 후 직접 지우세요

           rm -rf $BASEDIR/*.old_${STAMP}
EOF
}

# ─────────────────────────────────────────────────────────────
banner
case "${1:-}" in
  check)   cmd_check ;;
  list)    hr "백업 목록"; cmd_list ;;
  backup)  cmd_backup ;;
  restore) shift; cmd_restore "${1:-}" ;;
  *) cat <<EOF

사용법: $0 {check|list|backup|restore <파일명>}

  check    대상·라이선스·용량 확인                     [읽기 전용]  ★먼저
  list     백업 목록                                   [읽기 전용]
  backup   정지 -> tar -> 재기동                       [파괴적]
  restore  정지 -> 볼륨 교체 -> 재기동                 [파괴적]

backup·restore 는 DRYRUN=0 + 'yes' 입력을 요구하고, 라이선스가 만료면 거부합니다.
전체 절차는 35_ut_update_design.md 를 보세요.
EOF
     exit 1 ;;
esac
