#!/usr/bin/env bash
# Tibero 라이선스 점검 · 배포 — 세 인스턴스 공통      [deploy 는 DRYRUN=1 기본]
#
# 세 컨테이너(개발 8629 / 1차 UT 18629 / 2차 UT 28629)는 같은 license.xml 을 쓴다.
# `identified_by_host=localhost` 이고 셋 다 compose 에 `hostname: localhost` 라 한 파일로 된다.
#
# 라이선스는 **기동 시점에만** 검사된다. 그래서:
#   - 만료돼도 이미 떠 있는 인스턴스는 계속 돈다
#   - 내리는 순간 다시 못 올라온다
#   - 파일만 미리 갈아두면 실행 중인 인스턴스에는 아무 영향이 없고, 다음 기동 때 새 것을 읽는다
#
# 발급받은 데모 라이선스는 duration=30 이라 매달 반복된다.
# status 를 cron 에 걸어두면 만료 전에 알 수 있다:
#   0 9 * * * cd ~/alex/tibero7_ut_tablename/migration && ./33_license_apply.sh status >> license.cron.log 2>&1
#
# 사용법 (사내 서버에서 실행):
#   ./33_license_apply.sh status                    # 세 인스턴스 현황        [읽기 전용]
#   ./33_license_apply.sh deploy ~/new_license.xml  # 배포 계획만 (DRYRUN)
#   DRYRUN=0 ./33_license_apply.sh deploy ~/new_license.xml   # 실제 배포 (재기동 없음)

set -uo pipefail

DRYRUN="${DRYRUN:-1}"
STAMP="$(date +%Y%m%d_%H%M%S)"
# "컨테이너명:compose폴더" — 환경이 바뀌면 여기만 고친다
TARGETS="${TARGETS:-tibero7:$HOME/alex/tibero7 tibero7_ut:$HOME/alex/tibero7_ut tibero7_ut_tablename:$HOME/alex/tibero7_ut_tablename}"

hr()  { printf '\n===== %s =====\n' "$1"; }
die() { echo; echo "중단: $*" >&2; exit 1; }

# XML 에서 한 태그 값 뽑기
xval() { grep -o "<$2\( [^>]*\)\?>[^<]*</$2>" "$1" 2>/dev/null | head -1 | sed 's/<[^>]*>//g' | tr -d '\r'; }

cmd_status() {
  local today; today="$(date +%Y%m%d)"
  hr "라이선스 현황  ($(date '+%F %T %Z'))"
  printf '%-24s %-12s %-10s %-22s %s\n' 컨테이너 만료일 남은일수 기동시각 "재기동하면"
  printf '%.0s-' {1..100}; echo
  for t in $TARGETS; do
    local c d f
    c="${t%%:*}"; d="${t#*:}"; f="$d/license/license.xml"
    local end="-" left="-" started="-" verdict="-"
    if [ -f "$f" ]; then
      end="$(xval "$f" end_date)"
      if [ -n "$end" ]; then
        local e; e="$(printf '%s' "$end" | tr -d '/-')"
        left=$(( ( $(date -d "${e:0:4}-${e:4:2}-${e:6:2}" +%s 2>/dev/null || echo 0) - $(date +%s) ) / 86400 ))
        if [ "$e" -ge "$today" ] 2>/dev/null; then verdict="정상 기동"; else verdict="** 기동 실패 **"; fi
      fi
    else
      end="(파일 없음)"; verdict="확인 불가"
    fi
    started="$(docker inspect -f '{{.State.StartedAt}}' "$c" 2>/dev/null | cut -c1-19)"
    [ -n "$started" ] || started="(미가동)"
    printf '%-24s %-12s %-10s %-22s %s\n' "$c" "$end" "$left" "$started" "$verdict"
  done
  echo
  echo "-- '재기동하면' 이 기동 실패인 컨테이너는 지금 떠 있어도 내리면 살아나지 않는다."
  echo "-- 데이터는 각 폴더의 ./data 볼륨에 있어 컨테이너가 죽어도 보존된다."
  hr "재기동 정책 (호스트 리부팅 시 자동으로 기동을 시도한다)"
  for t in $TARGETS; do
    local c="${t%%:*}"
    docker inspect -f "$c: 정책={{.HostConfig.RestartPolicy.Name}}  재시작={{.RestartCount}}회  상태={{.State.Status}}" "$c" 2>/dev/null || echo "$c: (없음)"
  done
}

cmd_deploy() {
  local NEW="${1:-}"
  [ -n "$NEW" ] || die "새 license.xml 경로를 지정하세요.  예: $0 deploy ~/new_license.xml"
  [ -f "$NEW" ] || die "파일이 없습니다: $NEW"

  hr "새 라이선스 검증"
  echo "파일: $NEW"
  local end host prod dur
  end="$(xval "$NEW" end_date)"; host="$(xval "$NEW" identified_by_host)"
  prod="$(xval "$NEW" product)"; dur="$(xval "$NEW" duration)"
  echo "  product            : ${prod:-?}"
  echo "  end_date           : ${end:-?}"
  echo "  duration           : ${dur:-?}일"
  echo "  identified_by_host : ${host:-?}"
  [ -n "$end" ] || die "end_date 를 읽지 못했습니다. 올바른 라이선스 파일인지 확인하세요."
  local e; e="$(printf '%s' "$end" | tr -d '/-')"
  [ "$e" -ge "$(date +%Y%m%d)" ] 2>/dev/null || die "새 라이선스도 이미 만료입니다 ($end)."
  [ "$host" = "localhost" ] || echo "  ※ 경고: identified_by_host 가 localhost 가 아닙니다. compose 의 hostname 과 맞아야 부팅됩니다."

  hr "배포 대상"
  for t in $TARGETS; do
    local c d
    c="${t%%:*}"; d="${t#*:}"
    echo "  $c  ->  $d/license/license.xml"
  done
  echo
  echo "※ 파일 교체만 합니다. 실행 중인 인스턴스는 재기동하지 않으며 영향도 없습니다."
  echo "  새 라이선스는 각 인스턴스의 **다음 기동** 때 적용됩니다."

  if [ "$DRYRUN" = "1" ]; then
    echo; echo "(DRYRUN) 실제 배포: DRYRUN=0 $0 deploy $NEW"; return 0
  fi

  hr "배포"
  for t in $TARGETS; do
    local c d f
    c="${t%%:*}"; d="${t#*:}"; f="$d/license/license.xml"
    if [ ! -d "$d/license" ]; then echo "  건너뜀 ($c): $d/license 없음"; continue; fi
    [ -f "$f" ] && cp -v "$f" "${f}.bak_${STAMP}"
    cp -v "$NEW" "$f"
  done

  hr "배포 후 확인"
  cmd_status
  cat <<'EOF'

다음:
  - 2차 UT(공유 풀 고갈로 사용 불가)는 이제 복구할 수 있습니다:
      DRYRUN=0 ./32_shmem_resize.sh apply      # 공유 풀 증설 + 재기동을 한 번에
  - 개발(8629) / 1차 UT(18629) 는 정상 가동 중이므로 **재기동하지 마세요.**
    파일만 갈아둔 것으로 충분하고, 다음에 어떤 이유로 내려가도 살아납니다.
EOF
}

case "${1:-}" in
  status) cmd_status ;;
  deploy) shift; cmd_deploy "${1:-}" ;;
  *) cat <<EOF
사용법: $0 {status|deploy <새 license.xml 경로>}

  status  세 인스턴스의 만료일·기동시각·재기동 가능 여부   [읽기 전용]
  deploy  새 라이선스를 세 폴더에 배포 (재기동 없음)       DRYRUN=1 기본

라이선스는 기동 시점에만 검사됩니다. 파일 교체는 실행 중인 DB에 영향을 주지 않습니다.
EOF
     exit 1 ;;
esac
