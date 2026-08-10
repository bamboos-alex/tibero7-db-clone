#!/usr/bin/env bash
# 파일 동기화:  맥  <->  사내 서버  <->  docker tibero7 컨테이너
#
# 경로 구조
#   맥      : ./                       (스크립트 원본, 결과는 ./results/ 로 받는다)
#   서버    : ~/alex/tibero7_ut/migration (실행 위치)
#   컨테이너: /tmp/tbmig               (tbsql 이 실행되는 곳 = tibero7_ut)
#
# 사용법
#   ./sync.sh up      맥 -> 서버        스크립트 전송
#   ./sync.sh in      서버 -> 컨테이너   SQL 투입
#   ./sync.sh out     컨테이너 -> 서버   로그/생성물 회수
#   ./sync.sh down    서버 -> 맥        결과를 ./results/ 로 회수
#   ./sync.sh push    up + in           (배포 한 번에)
#   ./sync.sh pull    out + down        (회수 한 번에)
#
# 기본값 DRYRUN=1 — rsync 는 -n 으로 돌고 docker cp 는 출력만 한다.
# 확인 후 DRYRUN=0 을 붙여 실제 실행한다.
#
#   REMOTE=bamboos@<서버주소> DRYRUN=0 ./sync.sh push
#
# 서버에서 직접 실행할 때는 REMOTE 를 비운다:  REMOTE= ./sync.sh in

set -uo pipefail

REMOTE="${REMOTE:-bamboos@192.168.0.101}"        # 비우면 로컬(서버)에서 실행하는 것으로 간주
RPATH="${RPATH:-alex/tibero7_ut/migration}"  # 서버 홈 기준 상대경로
CONTAINER="${CONTAINER:-tibero7_ut}"
CPATH="${CPATH:-/tmp/tbmig}"                 # 컨테이너 작업 경로
LOCAL="${LOCAL:-$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)}"
RESULTS="${RESULTS:-$LOCAL/results}"
DRYRUN="${DRYRUN:-1}"

hr() { printf '\n===== %s =====\n' "$1"; }
die() { echo "오류: $*" >&2; exit 1; }

# ---------------------------------------------------------------
# SSH 연결 재사용 (ControlMaster)
#   sync 한 번에 ssh/rsync 연결이 여러 번 생긴다. 다중화하지 않으면
#   비밀번호를 그 횟수만큼 묻는다. 첫 연결이 마스터가 되고 나머지는 재사용된다.
#   ControlPersist 로 세션이 끝난 뒤에도 10분간 유지된다.
# ---------------------------------------------------------------
CM_DIR="${CM_DIR:-$HOME/.ssh/cm}"
mkdir -p "$CM_DIR" 2>/dev/null
SSH_OPTS="${SSH_OPTS:--o ControlMaster=auto -o ControlPath=$CM_DIR/%r@%h:%p -o ControlPersist=10m}"

# 서버에서 명령 실행 (REMOTE 가 비면 로컬 실행)
sh_run() {
  local cmd="$1"
  if [ -n "$REMOTE" ]; then
    echo "\$ ssh $REMOTE \"$cmd\""
    [ "$DRYRUN" = "1" ] && { echo "  (DRYRUN)"; return 0; }
    ssh $SSH_OPTS "$REMOTE" "$cmd"
  else
    echo "\$ $cmd"
    [ "$DRYRUN" = "1" ] && { echo "  (DRYRUN)"; return 0; }
    bash -lc "$cmd"
  fi
}

rsync_opt() {
  local o="-avz --human-readable"
  [ "$DRYRUN" = "1" ] && o="$o -n"
  printf '%s' "$o"
}

# 마스터 연결을 미리 연다 — 비밀번호를 여기서 한 번만 입력하면 된다.
open_master() {
  [ -n "$REMOTE" ] || return 0
  if ssh $SSH_OPTS -O check "$REMOTE" >/dev/null 2>&1; then
    echo "(SSH 연결 재사용 중: $REMOTE)"
  else
    echo "SSH 마스터 연결을 엽니다. 비밀번호는 이번 한 번만 입력하면 됩니다."
    ssh $SSH_OPTS -o ControlPersist=10m -N -f "$REMOTE" \
      || die "SSH 연결 실패 — REMOTE=$REMOTE 를 확인하세요"
  fi
}

# ---------------------------------------------------------------
# up : 맥 -> 서버   (스크립트만. 서버에서 생성된 로그를 덮어쓰지 않도록 --delete 는 쓰지 않는다)
# ---------------------------------------------------------------
cmd_up() {
  [ -n "$REMOTE" ] || die "up 은 맥에서 실행합니다. REMOTE 를 지정하세요."
  open_master
  hr "맥 -> 서버  ($REMOTE:$RPATH)"
  sh_run "mkdir -p ~/$RPATH"
  echo "\$ rsync $(rsync_opt) [스크립트] $REMOTE:~/$RPATH/"
  rsync $(rsync_opt) -e "ssh $SSH_OPTS" \
    --include='*.sh' --include='*.sql' --include='*.md' \
    --exclude='results/***' --exclude='*.log' --exclude='*_out_*' --exclude='*' \
    "$LOCAL"/ "$REMOTE:$RPATH/"
  echo
  echo ">> 서버에서 실행 권한 부여:"
  sh_run "chmod +x ~/$RPATH/*.sh"
}

# ---------------------------------------------------------------
# in : 서버 -> 컨테이너   (SQL 과 셸 스크립트 투입)
# ---------------------------------------------------------------
cmd_in() {
  open_master
  hr "서버 -> 컨테이너  ($CONTAINER:$CPATH)"
  sh_run "docker exec $CONTAINER bash -lc 'mkdir -p $CPATH'"
  sh_run "cd ~/$RPATH && for f in *.sql; do docker cp \"\$f\" $CONTAINER:$CPATH/ ; done && echo '투입 완료' && docker exec $CONTAINER bash -lc 'ls -l $CPATH'"
  echo
  echo ">> 컨테이너 안에서 실행:"
  echo "   docker exec -it $CONTAINER bash -lc 'cd $CPATH && tbsql <user>/<pw>@SRC @01_source_check.sql'"
}

# ---------------------------------------------------------------
# out : 컨테이너 -> 서버   (로그와 생성된 SQL 회수)
# ---------------------------------------------------------------
cmd_out() {
  open_master
  hr "컨테이너 -> 서버"
  sh_run "mkdir -p ~/$RPATH/results"
  sh_run "docker cp $CONTAINER:$CPATH ~/$RPATH/results/container_tmp && echo '회수 완료' && ls -l ~/$RPATH/results/container_tmp"
  echo
  echo "※ docker cp 는 디렉터리 통째로 가져옵니다. 원본 SQL 도 같이 딸려오지만 results/ 안이라 무해합니다."
}

# ---------------------------------------------------------------
# down : 서버 -> 맥   (결과만 ./results/ 로)
# ---------------------------------------------------------------
cmd_down() {
  [ -n "$REMOTE" ] || die "down 은 맥에서 실행합니다. REMOTE 를 지정하세요."
  open_master
  hr "서버 -> 맥  ($RESULTS)"
  mkdir -p "$RESULTS"
  echo "\$ rsync $(rsync_opt) $REMOTE:~/$RPATH/{로그,생성물} $RESULTS/"
  rsync $(rsync_opt) -e "ssh $SSH_OPTS" \
    --include='results/***' \
    --include='*.log' --include='*.txt' \
    --include='*_out_*.sql' --include='*_gen_*.sql' --include='*_help.txt' \
    --exclude='*' \
    "$REMOTE:$RPATH/" "$RESULTS/"
  echo
  echo ">> 받은 파일:"
  ls -R "$RESULTS" 2>/dev/null | head -40
}

case "${1:-}" in
  up)   cmd_up ;;
  in)   cmd_in ;;
  out)  cmd_out ;;
  down) cmd_down ;;
  push) cmd_up; cmd_in ;;
  pull) cmd_out; cmd_down ;;
  login) open_master ;;
  close)
    [ -n "$REMOTE" ] && ssh $SSH_OPTS -O exit "$REMOTE" 2>/dev/null && echo "SSH 마스터 연결 종료"
    ;;
  *) cat <<EOF
사용법: $0 {up|in|out|down|push|pull|login|close}

  up    맥 -> 서버        스크립트 전송
  in    서버 -> 컨테이너   SQL 투입
  out   컨테이너 -> 서버   로그 회수
  down  서버 -> 맥        결과를 ./results/ 로 회수
  push  up + in
  pull  out + down
  login SSH 마스터 연결만 미리 열기 (비밀번호 1회)
  close 마스터 연결 종료

기본값 DRYRUN=1 (실제로 옮기지 않고 목록만 보여줍니다).

  REMOTE=bamboos@<서버주소> DRYRUN=0 $0 push
  REMOTE=bamboos@<서버주소> DRYRUN=0 $0 pull

현재 설정:
  REMOTE=${REMOTE:-<로컬실행>}
  RPATH=~/$RPATH
  CONTAINER=$CONTAINER
  CPATH=$CPATH
  LOCAL=$LOCAL
EOF
     exit 1 ;;
esac
