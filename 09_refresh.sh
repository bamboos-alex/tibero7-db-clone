#!/usr/bin/env bash
# 소스에서 전량 재적재 (refresh)
#
# ┌─ 이 스크립트가 하는 일 ────────────────────────────────────────────────┐
# │ 타겟 스키마를 통째로 버리고, 소스의 특정 시점 모습으로 다시 만든다.    │
# │ "차이만 반영"하는 동기화가 아니라 **전량 교체**다.                     │
# └────────────────────────────────────────────────────────────────────────┘
#
# 실행 후 타겟은 "추출 시점(CONSISTENT=Y 스냅샷)의 소스와 동일한 상태"가 된다.
# 그 말은 곧 아래가 전부 사라진다는 뜻이다:
#
#   - UT 중 타겟에 입력·수정한 테스트 데이터
#   - 타겟에만 추가한 객체 (인덱스, 임시 테이블, 뷰 등)
#   - 타겟에서 바꾼 계정 비밀번호 (schema_pw() 값으로 재설정된다)
#   - 계정에 추가로 준 롤·권한 (CONNECT/RESOURCE/DBA 등 고정 집합으로 재설정된다)
#
# 반대로 얻는 것:
#   - 소스의 DDL 변경(컬럼·테이블 추가/삭제)이 자동으로 따라온다
#   - 결과가 건수로 증명된다 (416개 테이블 대조, 불일치 시 비정상 종료)
#   - 부분 적재나 누적 오염이 남지 않는다 — 매번 같은 출발점
#
# 실행 중 해당 스키마는 **비어 있는 구간**이 생긴다(DROP 직후 ~ 적재 완료).
# 앱이 붙어 있으면 그 시간 동안 오류가 난다. 사용자가 없는 시간에 돌릴 것.
#
# 되돌리기는 없다. 직전 상태로 복원하려면 그 시점의 덤프로 다시 적재해야 하고,
# work/ 에는 마지막 추출본만 남는다(--skip-export 로 재사용).
#
# 왜 전량인가:
#   AIMS_EX 는 테이블 101개 중 PK 가 7개뿐이고 FK 는 0건이다. 변경분을 식별할 키도,
#   누락을 잡아낼 참조 무결성도 없어서 증분 병합은 "맞다"를 증명할 수 없다.
#   전량 재적재는 실측 15분이면 끝나고 결과가 건수로 증명된다.
#
# 왜 계정 재생성인가:
#   TRUNCATE 후 재적재는 소스의 DDL 변경(컬럼·테이블 추가)을 반영하지 못한다.
#   소스가 개발 DB 라 구조가 바뀔 수 있으므로 DROP USER CASCADE -> 재생성이 안전하다.
#   테이블스페이스는 유지되므로 04b 를 다시 돌릴 필요는 없다.
#
# 사용법:
#   ./09_refresh.sh                                  계획만 출력 (DRYRUN)
#   DRYRUN=0 ./09_refresh.sh                         전량 갱신
#   DRYRUN=0 SCHEMAS="AIMS_DEV" ./09_refresh.sh      특정 스키마만
#   DRYRUN=0 ./09_refresh.sh --skip-export           기존 덤프로 재적재만
#
# cron 예 (매일 03:00, AIMS_DEV 만):
#   0 3 * * * cd ~/alex/tibero7_ut/migration && DRYRUN=0 SCHEMAS=AIMS_DEV ./09_refresh.sh >> refresh.cron.log 2>&1
#
# 종료 코드: 0 = 건수 전량 일치, 그 외 = 실패 (cron 에서 감지 가능)

set -uo pipefail

# ================= 대상 =================
CONTAINER="${CONTAINER:-tibero7_ut_tablename}"
# 순서 중요: 시노님이 AIMS_EX 를 가리키므로 먼저 만들어야 한다
SCHEMAS="${SCHEMAS:-AIMS_EX AIMS_DEV AIMSC_DEV}"
WORKDIR="${WORKDIR:-/tmp/tbmig}"
LOCALWORK="${LOCALWORK:-../work}"          # WORKDIR 의 호스트쪽 바인드 마운트

SRC_USER="${SRC_USER:-aims_dev}"
SRC_PASS="${SRC_PASS:-aims_dev}"
TGT_USER="${TGT_USER:-sys}"
TGT_PASS="${TGT_PASS:-tibero123}"

# 계정 재생성 시 사용할 비밀번호 (04b_target_create.sql 과 동일 규칙: 계정명 = 비밀번호)
# 연관배열(declare -A)은 bash 4+ 전용이라 case 로 둔다 — macOS 기본 bash 3.2 에서도 동작
schema_pw() {
  case "$1" in
    AIMS_EX)   echo "aims_ex"   ;;
    AIMS_DEV)  echo "aims_dev"  ;;
    AIMSC_DEV) echo "aimsc_dev" ;;
    *)         echo ""          ;;
  esac
}

# ---- 제외 테이블 ----
# 비워두면 전량. UT 에서 모니터링 이력이 불필요하면 아래를 켜면 추출이 크게 짧아진다.
#   T_ITSE_VMS_SYBL_01I     BLOB 195MB — 추출 13분의 대부분을 차지
#   T_ITSE_TBSP_STAT_01L    879,615행
#   T_ITSE_EMBR_STAT_01N    835,460행
#   T_ITSE_VDS_CWNO_HR_01S  486,744행
#   T_ITSE_DB_LOCK_01L      242,360행
# (2026-08-13 규약 변경 반영: T_TIP?_ -> T_ITSE_. 건수는 변경 전 실측값)
# ** EXCLUDE 파라미터 문법은 이 버전에서 미검증이다. 켜기 전에 소량으로 확인할 것:
#      docker exec tibero7_ut_tablename bash -lc 'tbexport -h' | grep -A3 EXCLUDE
#    import 쪽 EXCLUDE_TABLE 은 도움말에 명시돼 있어 더 안전하다.
EXCLUDE_TABLES="${EXCLUDE_TABLES:-}"

DRYRUN="${DRYRUN:-1}"
SKIP_EXPORT=0
[ "${1:-}" = "--skip-export" ] && SKIP_EXPORT=1

TS="$(date +%Y%m%d_%H%M%S)"
RUNLOG="refresh_${TS}.log"
LOCKFILE="/tmp/.tbrefresh.lock"

# =========================================================
hr()   { printf '\n========== %s ==========\n' "$1"; }
info() { printf '  %s\n' "$*"; }
die()  { printf '\n[실패] %s\n' "$*" >&2; exit 1; }

# ---- 비밀번호 마스킹 ----
# 이 스크립트의 출력은 refresh_*.log 로 그대로 남는다. 로그를 공유할 일이 있으므로
# 접속 비밀번호와 스키마 계정 비밀번호를 화면·로그에서 지운다.
# 계정명(AIMS_DEV)과 비밀번호(aims_dev)는 대소문자가 달라 치환이 겹치지 않는다.
# 다만 접속 계정명이 비밀번호와 같은 문자열이면(SRC_USER=SRC_PASS=aims_dev) 계정명도
# 함께 가려진다 — 로그 판독에는 지장이 없다.
_pw_list() {
  printf '%s\n' "${SRC_PASS:-}" "${TGT_PASS:-}" \
    "$(schema_pw AIMS_EX)" "$(schema_pw AIMS_DEV)" "$(schema_pw AIMSC_DEV)" \
    | awk 'NF' | sort -u
}
mask() {        # 문자열 인자 마스킹
  local s="$1" p
  while IFS= read -r p; do [ -n "$p" ] && s="${s//$p/********}"; done < <(_pw_list)
  printf '%s' "$s"
}
mask_stream() { # 표준입력 마스킹
  local expr="" p
  while IFS= read -r p; do [ -n "$p" ] && expr="$expr;s|$p|********|g"; done < <(_pw_list)
  if [ -n "$expr" ]; then sed "${expr#;}"; else cat; fi
}

# 한 행·한 컬럼을 돌려주는 조회. 읽기 전용이라 DRYRUN 과 무관하게 실행한다
#   — 상태를 보려고 부르는 것까지 막으면 DRYRUN 이 판단에 도움이 되지 않는다.
# 배너·프롬프트가 섞여 나오므로 값을 << >> 로 감싸 뽑는다.
sql1() {  # $1 = 값 식, $2 = FROM 뒤쪽
  docker exec -i "$CONTAINER" bash -lc "tbsql -s $TGT_USER/$TGT_PASS@TAIMS" 2>/dev/null <<SQL | sed -n 's/.*<<\(.*\)>>.*/\1/p' | head -1
SET HEADING OFF
SET FEEDBACK OFF
SELECT '<<' || TO_CHAR($1) || '>>' FROM $2;
EXIT;
SQL
}

# SCHEMAS 를 SQL IN 목록으로 ('AIMS_EX','AIMS_DEV',...)
schema_in_list() { echo "$SCHEMAS" | tr ' ' '\n' | awk 'NF{printf "%s'\''%s'\''", (n++?",":""), $0}'; }

runc() {  # 컨테이너에서 실행
  if [ "$DRYRUN" = "1" ]; then echo "  \$ $(mask "$1")"; return 0; fi
  docker exec "$CONTAINER" bash -lc "$1" | mask_stream
}
runsql() {  # 컨테이너의 tbsql 에 stdin 으로 SQL 투입
  if [ "$DRYRUN" = "1" ]; then
    echo "  \$ tbsql ${TGT_USER}/******** <<'SQL'"
    mask_stream | sed 's/^/      /'
    echo "      SQL"
    return 0
  fi
  docker exec -i "$CONTAINER" bash -lc "tbsql -s $TGT_USER/$TGT_PASS@TAIMS" | mask_stream
}

# ---------------------------------------------------------
# 0) 사전 점검
# ---------------------------------------------------------
preflight() {
  hr "0) 사전 점검"

  docker ps --filter "name=^/${CONTAINER}$" --format '{{.Names}}' | grep -qx "$CONTAINER" \
    || die "컨테이너가 실행 중이 아닙니다: $CONTAINER"
  info "컨테이너 $CONTAINER 실행 중"

  # 라이선스 만료 — 만료되면 재기동 시 DB 가 뜨지 않는다
  local end today
  end="$(docker exec "$CONTAINER" bash -lc 'grep -o "<end_date>[^<]*" $TB_HOME/license/license.xml | cut -d">" -f2' 2>/dev/null | tr -d '\r')"
  if [ -n "$end" ]; then
    today="$(date +%Y/%m/%d)"
    info "라이선스 만료일 $end (오늘 $today)"
    [[ "$today" > "$end" ]] && die "라이선스가 만료됐습니다. 갱신 후 재시도하세요."
    local days
    days=$(( ( $(date -d "${end//\//-}" +%s 2>/dev/null || echo 0) - $(date +%s) ) / 86400 ))
    [ "$days" -gt 0 ] && [ "$days" -le 7 ] && info "** 경고: 만료까지 ${days}일 남았습니다 **"
  fi

  # 소스 도달
  if [ "$SKIP_EXPORT" = "0" ]; then
    docker exec "$CONTAINER" bash -lc \
      "timeout 5 bash -c '</dev/tcp/121.137.106.217/58629'" >/dev/null 2>&1 \
      || die "소스 DB(121.137.106.217:58629)에 도달하지 못했습니다"
    info "소스 도달 확인"
  fi

  # ---- 대상 스키마에 붙어 있는 세션 ----
  # 세션이 있으면 DROP USER 가 TBR-7165(Unable to drop a user that is currently
  # connected) 로 실패한다. 1) 의 WHENEVER SQLERROR CONTINUE 가 그 실패를 삼키므로
  # 비워지지 않은 스키마에 적재가 일어나고, 이미 있는 객체는 TBR-7102 로 건너뛰어
  # **옛 데이터가 그대로 남는다.** 2026-09-08 에 실제로 이렇게 됐다 (AIMS_DEV 214개 중
  # 20개만 적재). 15분을 버리고 대조 단계에서 알게 되는 대신 여기서 끊는다.
  local busy
  busy="$(sql1 "COUNT(*)" "V\$SESSION WHERE USERNAME IN ($(schema_in_list))")"
  if [ "${busy:-0}" != "0" ]; then
    info "** 대상 스키마에 세션 ${busy}개가 붙어 있습니다 **"
    docker exec -i "$CONTAINER" bash -lc "tbsql -s $TGT_USER/$TGT_PASS@TAIMS" 2>/dev/null <<SQL | grep -E "^[A-Z]" | sed 's/^/      /'
SET LINESIZE 200
SELECT USERNAME, SID, PROG_NAME, MACHINE, OSUSER FROM V\$SESSION
 WHERE USERNAME IN ($(schema_in_list)) ORDER BY USERNAME, SID;
EXIT;
SQL
    if [ "$DRYRUN" = "1" ]; then
      info "(DRYRUN 이라 계속합니다. 실제 실행 전에 반드시 정리하세요)"
    else
      die "대상 스키마에 접속 중인 세션이 있습니다. DROP USER 가 실패합니다.
       앱을 내린 뒤 다시 실행하세요. 세션이 사라졌는지는 이 스크립트를 다시 돌리면 확인됩니다."
    fi
  else
    info "대상 스키마에 붙은 세션 없음"
  fi

  runc "df -h $WORKDIR | tail -1"

  hr "계획"
  cat <<EOF
  대상 스키마 : $SCHEMAS
  추출        : $([ "$SKIP_EXPORT" = "1" ] && echo "건너뜀 (기존 덤프 재사용)" || echo "수행")
  제외 테이블 : ${EXCLUDE_TABLES:-(없음 — 전량)}
  실행 로그   : $RUNLOG
  DRYRUN      : $DRYRUN
EOF
}

# ---------------------------------------------------------
# 1) 스키마 초기화 — DROP USER CASCADE 후 재생성
#    ** 되돌릴 수 없다. 타겟의 해당 스키마 내용이 전부 사라진다 **
# ---------------------------------------------------------
reset_schemas() {
  hr "1) 스키마 초기화 (DROP USER CASCADE -> 재생성)"
  for s in $SCHEMAS; do
    local pw; pw="$(schema_pw "$s")"
    [ -n "$pw" ] || die "$s 의 비밀번호가 schema_pw() 에 정의되지 않았습니다"
    info "$s 초기화"
    runsql <<SQL
WHENEVER SQLERROR CONTINUE
DROP USER $s CASCADE;
CREATE USER $s IDENTIFIED BY "$pw" DEFAULT TABLESPACE TS_AIMS_DATA TEMPORARY TABLESPACE TEMP;
GRANT CONNECT, RESOURCE TO $s;
GRANT CREATE VIEW, CREATE SEQUENCE, CREATE SYNONYM, CREATE PROCEDURE TO $s;
GRANT UNLIMITED TABLESPACE TO $s;
GRANT DBA TO $s;
EXIT;
SQL
  done
}

# ---------------------------------------------------------
# 1b) 초기화 검증 — 비었는지 눈으로 확인하지 말고 세어서 확인한다
#     DROP USER 가 실패해도 WHENEVER SQLERROR CONTINUE 때문에 1) 은 조용히 끝난다.
#     여기서 막지 않으면 오염된 스키마에 적재가 이어진다.
# ---------------------------------------------------------
verify_reset() {
  hr "1b) 초기화 검증"
  if [ "$DRYRUN" = "1" ]; then
    info "(DRYRUN — 초기화를 하지 않았으므로 건너뜁니다)"
    return 0
  fi
  for s in $SCHEMAS; do
    local n
    n="$(sql1 "COUNT(*)" "ALL_OBJECTS WHERE OWNER='$s'")"
    [ -n "$n" ] || die "$s 의 객체 수를 읽지 못했습니다. 수동 확인이 필요합니다."
    [ "$n" = "0" ] || die "$s 가 비어 있지 않습니다 (객체 ${n}개).
       DROP USER 가 실패했습니다. 위 1) 출력에서 TBR-7165(접속 중) 를 확인하세요.
       이대로 적재하면 이미 있는 객체가 TBR-7102 로 건너뛰어 옛 데이터가 남습니다."
    info "$s 비어 있음 확인"
  done
}

# ---------------------------------------------------------
# 2~3) 추출 / 적재 — 기존 03 스크립트에 위임
# ---------------------------------------------------------
do_export() {
  [ "$SKIP_EXPORT" = "1" ] && { hr "2) 추출 — 건너뜀"; return 0; }
  hr "2) 소스 추출"
  local opts="CONSISTENT=Y CONSTRAINT=Y INDEX=Y GRANT=Y COMPRESS=Y OVERWRITE=Y"
  [ -n "$EXCLUDE_TABLES" ] && opts="$opts EXCLUDE=$EXCLUDE_TABLES"
  DRYRUN="$DRYRUN" CONTAINER="$CONTAINER" SCHEMAS="$SCHEMAS" \
  SRC_USER="$SRC_USER" SRC_PASS="$SRC_PASS" EXP_OPTS="$opts" \
    ./03_export_import.sh export || die "추출 실패"
}

do_import() {
  hr "3) 타겟 적재"
  local opts="CONSTRAINT=Y INDEX=Y GRANT=Y IGNORE=N COMMIT=Y"
  [ -n "$EXCLUDE_TABLES" ] && opts="$opts EXCLUDE_TABLE=$EXCLUDE_TABLES"
  DRYRUN="$DRYRUN" CONTAINER="$CONTAINER" SCHEMAS="$SCHEMAS" \
  TGT_USER="$TGT_USER" TGT_PASS="$TGT_PASS" IMP_OPTS="$opts" \
    ./03_export_import.sh import || die "적재 실패"

  # 길이 초과는 문자셋 불일치의 신호다. 조용히 넘기면 데이터가 부분 적재된 채 남는다.
  if [ "$DRYRUN" != "1" ]; then
    local n
    n=$(docker exec "$CONTAINER" bash -lc "grep -c 'TBR-11048' $WORKDIR/*_imp.log 2>/dev/null | awk -F: '{s+=\$2} END{print s+0}'")
    [ "${n:-0}" -gt 0 ] && die "컬럼 길이 초과 ${n}건 — 타겟 캐릭터셋이 MSWIN949 인지 확인하세요"
    info "TBR-11048 0건"
  fi
}

# ---------------------------------------------------------
# 4) 뷰 재컴파일 — 뷰가 뷰를 참조(87건)해 생성 순서를 보장할 수 없다
# ---------------------------------------------------------
do_recompile() {
  hr "4) 뷰 재컴파일"
  runc "cd $WORKDIR && tbsql $TGT_USER/$TGT_PASS @07_recompile_invalid.sql" | tail -5
}

# ---------------------------------------------------------
# 5~6) 검증 — 추출 로그(CONSISTENT 스냅샷)를 기준으로 타겟과 대조
#      소스가 가동 중이라 이전 기준값은 이미 흘러가 있다
# ---------------------------------------------------------
do_verify() {
  hr "5) 타겟 실측"
  runc "cd $WORKDIR && tbsql $TGT_USER/$TGT_PASS @05_verify.sql"   >/dev/null
  runc "cd $WORKDIR && tbsql $TGT_USER/$TGT_PASS @05_gen_counts.sql" >/dev/null
  info "05_target_counts.log / 05_target_health.log 생성"

  hr "6) 대조"
  if [ "$DRYRUN" = "1" ]; then
    echo "  \$ ./08_expected_from_exportlog.sh && ./06_compare.sh 08_expected_counts.log $LOCALWORK/05_target_counts.log"
    return 0
  fi

  CONTAINER="$CONTAINER" WORKDIR="$WORKDIR" SCHEMAS="$SCHEMAS" \
    ./08_expected_from_exportlog.sh >/dev/null || die "기대 건수 산출 실패"

  # 05_gen_counts.sql 은 3개 스키마가 고정돼 있어 항상 416개를 센다.
  # 부분 스키마로 돌릴 때는 대상만 남겨야 대조가 성립한다.
  local tgt="$LOCALWORK/05_target_counts.log"
  local pat; pat="$(echo "$SCHEMAS" | tr ' ' '|')"
  grep -E "^($pat)\." "$tgt" > 09_target_counts_subset.log 2>/dev/null
  [ -s 09_target_counts_subset.log ] || die "타겟 건수를 읽지 못했습니다: $tgt"

  ./06_compare.sh 08_expected_counts.log 09_target_counts_subset.log

  grep -q "건수 기준 이상 없음" 06_compare_report.txt \
    || die "건수 불일치 — 06_compare_report.txt 를 확인하세요"

  # 뷰가 컴파일만 통과하고 조회에서 깨지는 경우를 잡는다
  local ng
  ng=$(grep -oE '뷰 조회 성공 [0-9]+건 / 실패 [0-9]+건' "$LOCALWORK/05_target_health.log" 2>/dev/null | grep -oE '실패 [0-9]+' | grep -oE '[0-9]+')
  if [ -n "$ng" ]; then
    info "뷰 조회 실패 ${ng}건"
    [ "$ng" -gt 0 ] && die "뷰 조회 실패 ${ng}건"
  fi
}

# =========================================================
main() {
  exec > >(tee -a "$RUNLOG") 2>&1
  echo "===== 동기화 시작 $(date '+%Y-%m-%d %H:%M:%S') ====="

  preflight

  if [ "$DRYRUN" = "1" ]; then
    hr "DRYRUN"
    echo "  실제로 실행하려면 DRYRUN=0 을 붙이세요."
    echo "  ** 1) 단계에서 타겟의 $SCHEMAS 스키마가 DROP 됩니다. 되돌릴 수 없습니다. **"
  fi

  reset_schemas
  verify_reset
  do_export
  do_import
  do_recompile
  do_verify

  hr "완료"
  echo "  $(date '+%Y-%m-%d %H:%M:%S')  로그: $RUNLOG"
  [ "$DRYRUN" = "1" ] && echo "  (DRYRUN — 실제 변경은 없었습니다)"
  exit 0
}

# 중복 실행 방지 — cron 에서 이전 회차가 아직 돌고 있을 수 있다.
# flock 이 없는 환경(macOS 등)에서는 잠금 없이 진행한다.
if command -v flock >/dev/null 2>&1; then
  exec 9>"$LOCKFILE"
  flock -n 9 || die "다른 동기화가 실행 중입니다 ($LOCKFILE)"
else
  echo "(flock 없음 — 중복 실행 방지 비활성)" >&2
fi

main
