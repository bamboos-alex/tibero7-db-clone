#!/usr/bin/env bash
# Phase 2: 경로 A — tbExport 7.2 → tbImport 7.2
#
# 00_env_check.sh 결과 반영:
#   - tbexport/tbimport 는 DSN 을 쓰지 않는다. IP / PORT / SID 파라미터로 직접 접속한다.
#   - 문법은 `parameter=value` 나열식이다.
#   - 컨테이너: tibero7, TB_HOME=/opt/tibero7, 타겟 DB_NAME=tibero, PORT=8629, edition=standard
#
# 사용법:
#   ./03_export_import.sh validate   # 내가 쓰는 파라미터명이 이 버전에 실재하는지 대조
#   ./03_export_import.sh check      # 접속/디스크 확인
#   ./03_export_import.sh pilot      # 작은 테이블 1개로 왕복 검증 (반드시 먼저)
#   ./03_export_import.sh export     # 스키마 전량 추출
#   ./03_export_import.sh import     # 타겟 적재
#
# 기본값 DRYRUN=1 — 명령만 출력한다. 확인 후 DRYRUN=0 을 붙여 실제 실행한다.

set -uo pipefail

# ================= 소스 (공동 작업 DB) =================
SRC_IP="${SRC_IP:-121.137.106.217}"
SRC_PORT="${SRC_PORT:-58629}"
SRC_SID="${SRC_SID:-}"          # ** DBeaver JDBC URL 의 마지막 항목(DB_NAME). 확인 필요 **
SRC_USER="${SRC_USER:-}"
SRC_PASS="${SRC_PASS:-}"

# ================= 타겟 (docker tibero7) =================
TGT_IP="${TGT_IP:-localhost}"
TGT_PORT="${TGT_PORT:-8629}"
TGT_SID="${TGT_SID:-tibero}"
TGT_USER="${TGT_USER:-}"
TGT_PASS="${TGT_PASS:-}"

# ================= 공통 =================
CONTAINER="${CONTAINER:-tibero7}"
SCHEMAS="${SCHEMAS:-AIMS_DEV AIMSC_DEV}"
WORKDIR="${WORKDIR:-/tmp/tbmig}"
PILOT_SCHEMA="${PILOT_SCHEMA:-AIMS_DEV}"
PILOT_TABLE="${PILOT_TABLE:-T_AAAA_CMMN01C}"
DRYRUN="${DRYRUN:-1}"

# 스키마명을 소스와 다르게 바꿔 적재하려면 지정 (예: TOUSER="AIMS_UT")
TOUSER="${TOUSER:-}"

# ---- 추출 옵션 ----
#  CONSISTENT=Y : 공동 작업 DB 라 추출 중에도 갱신이 일어난다. 일관된 시점 스냅샷을 뜬다.
#  COMPRESS=Y   : 384MB LOB 테이블 때문에 덤프가 커진다.
#  GRANT=Y      : 권한 정보는 담아 두고, 적재 시점에 뺀다(타겟에 없는 계정 참조 방지).
EXP_OPTS="${EXP_OPTS:-CONSISTENT=Y CONSTRAINT=Y INDEX=Y GRANT=Y COMPRESS=Y OVERWRITE=Y}"

# ---- 적재 옵션 ----
#  GRANT=N  : 타겟에 존재하지 않는 계정으로의 GRANT 실패를 피한다.
#  IGNORE=N : 이미 있는 객체가 있으면 조용히 넘어가지 않고 드러나게 한다.
IMP_OPTS="${IMP_OPTS:-CONSTRAINT=Y INDEX=Y GRANT=N IGNORE=N COMMIT=Y}"

# 이 스크립트가 사용하는 파라미터명 (validate 로 실재 여부를 대조한다)
USED_EXP_PARAMS="USERNAME PASSWORD IP PORT SID USER TABLE FILE LOG CONSISTENT CONSTRAINT INDEX GRANT COMPRESS OVERWRITE"
USED_IMP_PARAMS="USERNAME PASSWORD IP PORT SID USER FROMUSER TOUSER TABLE FILE LOG CONSTRAINT INDEX GRANT IGNORE COMMIT"

# =========================================================
die() { echo "오류: $*" >&2; exit 1; }
hr()  { printf '\n===== %s =====\n' "$1"; }

mask() {
  local s="$1"
  [ -n "$SRC_PASS" ] && s="${s//$SRC_PASS/********}"
  [ -n "$TGT_PASS" ] && s="${s//$TGT_PASS/********}"
  printf '%s' "$s"
}

runc() {
  local cmd="$1"
  echo "\$ docker exec $CONTAINER bash -lc \"$(mask "$cmd")\""
  if [ "$DRYRUN" = "1" ]; then
    echo "  (DRYRUN — 실행하지 않음. DRYRUN=0 으로 재실행하면 수행됩니다)"
    return 0
  fi
  docker exec "$CONTAINER" bash -lc "$cmd"
}

need_src() {
  [ -n "$SRC_SID" ]  || die "SRC_SID 미설정 — DBeaver 연결의 JDBC URL 마지막 항목(DB_NAME)을 확인하세요"
  [ -n "$SRC_USER" ] || die "SRC_USER 미설정"
  [ -n "$SRC_PASS" ] || die "SRC_PASS 미설정"
}
need_tgt() {
  [ -n "$TGT_USER" ] || die "TGT_USER 미설정 (04_target_prepare.sql 로 계정 생성 후 지정)"
  [ -n "$TGT_PASS" ] || die "TGT_PASS 미설정"
}

# ---------------------------------------------------------
# validate: 도움말과 파라미터명을 대조한다.
#   버전마다 이름이 달라 추정이 위험하므로, 실제 -h 출력에 없는 이름을 쓰면 여기서 걸러진다.
# ---------------------------------------------------------
cmd_validate() {
  hr "tbexport 파라미터 대조"
  local help_exp help_imp missing=0
  help_exp="$(docker exec "$CONTAINER" bash -lc 'tbexport -h 2>&1')" || die "tbexport 실행 실패"
  for p in $USED_EXP_PARAMS; do
    if grep -qE "^[[:space:]]*${p}[[:space:]]" <<<"$help_exp"; then
      printf '  OK   %s\n' "$p"
    else
      printf '  없음 %s   <-- 스크립트 수정 필요\n' "$p"; missing=1
    fi
  done

  hr "tbimport 파라미터 대조"
  help_imp="$(docker exec "$CONTAINER" bash -lc 'tbimport -h 2>&1')" || die "tbimport 실행 실패"
  for p in $USED_IMP_PARAMS; do
    if grep -qE "^[[:space:]]*${p}[[:space:]]" <<<"$help_imp"; then
      printf '  OK   %s\n' "$p"
    else
      printf '  없음 %s   <-- 스크립트 수정 필요\n' "$p"; missing=1
    fi
  done

  hr "결과"
  if [ "$missing" = "0" ]; then
    echo "모든 파라미터명이 이 버전에 존재합니다. check 로 진행하세요."
  else
    echo "'없음' 으로 표시된 파라미터가 있습니다. 도움말 전문을 보고 이름을 고치세요:"
    echo "  docker exec $CONTAINER bash -lc 'tbexport -h' | less"
  fi
}

cmd_check() {
  need_src
  hr "설정"
  cat <<EOF
컨테이너 : $CONTAINER
소스     : $SRC_USER@$SRC_IP:$SRC_PORT/$SRC_SID
타겟     : ${TGT_USER:-<미설정>}@$TGT_IP:$TGT_PORT/$TGT_SID
스키마   : $SCHEMAS
작업경로 : $WORKDIR
DRYRUN   : $DRYRUN
EOF
  hr "작업 디렉터리 / 디스크"
  runc "mkdir -p $WORKDIR && df -h $WORKDIR"

  hr "소스 접속 및 버전 확인"
  echo "-- 소스가 Tibero 7 이 아니면 tbimport 의 EXP_SERVER_VER 조정이 필요할 수 있습니다."
  runc "echo \"SELECT * FROM v\\\$version;\" | tbsql -s $SRC_USER/$SRC_PASS@$SRC_IP:$SRC_PORT:$SRC_SID"

  hr "타겟 접속 확인"
  if [ -n "$TGT_USER" ]; then
    runc "echo \"SELECT USER FROM dual;\" | tbsql -s $TGT_USER/$TGT_PASS@$TGT_IP:$TGT_PORT:$TGT_SID"
  else
    echo "(TGT_USER 미설정 — 04_target_prepare.sql 로 계정을 만든 뒤 지정하세요)"
  fi
  echo
  echo "※ tbsql 이 host:port:sid 형식을 받지 않으면 tbdsn.tbr 에 DSN 을 등록해야 합니다."
  echo "   (tbexport/tbimport 자체는 DSN 없이 IP/PORT/SID 로 동작하므로 이관에는 지장 없습니다)"
}

cmd_pilot() {
  need_src; need_tgt
  hr "선검증: $PILOT_SCHEMA.$PILOT_TABLE 만 왕복"
  echo "목적: 전량 실행 전에 한글·날짜·자료형이 온전히 넘어가는지 확인한다."
  runc "mkdir -p $WORKDIR"

  local f="$WORKDIR/pilot_${PILOT_TABLE}.dat"
  runc "cd $WORKDIR && tbexport USERNAME=$SRC_USER PASSWORD=$SRC_PASS IP=$SRC_IP PORT=$SRC_PORT SID=$SRC_SID \
USER=$PILOT_SCHEMA TABLE=$PILOT_TABLE FILE=$f LOG=$WORKDIR/pilot_exp.log $EXP_OPTS"

  local imp_user="USER=$PILOT_SCHEMA"
  [ -n "$TOUSER" ] && imp_user="FROMUSER=$PILOT_SCHEMA TOUSER=$TOUSER"
  runc "cd $WORKDIR && tbimport USERNAME=$TGT_USER PASSWORD=$TGT_PASS IP=$TGT_IP PORT=$TGT_PORT SID=$TGT_SID \
$imp_user TABLE=$PILOT_TABLE FILE=$f LOG=$WORKDIR/pilot_imp.log $IMP_OPTS"

  hr "적재 결과 — 한글이 깨지지 않았는지 육안 확인"
  local chk_schema="${TOUSER:-$PILOT_SCHEMA}"
  runc "echo \"SELECT CD_ID, CD_NM, DUMP(CD_NM,16) FROM $chk_schema.$PILOT_TABLE WHERE ROWNUM<=5;\" \
| tbsql -s $TGT_USER/$TGT_PASS@$TGT_IP:$TGT_PORT:$TGT_SID"
  echo
  echo ">> CD_NM 이 정상 한글이면 export 단계로 넘어가세요."
}

cmd_export() {
  need_src
  runc "mkdir -p $WORKDIR"
  for s in $SCHEMAS; do
    hr "추출: $s"
    runc "cd $WORKDIR && tbexport USERNAME=$SRC_USER PASSWORD=$SRC_PASS IP=$SRC_IP PORT=$SRC_PORT SID=$SRC_SID \
USER=$s FILE=$WORKDIR/${s}.dat LOG=$WORKDIR/${s}_exp.log $EXP_OPTS"
    runc "ls -lh $WORKDIR/${s}.dat* 2>/dev/null; echo '--- 로그 끝 ---'; tail -30 $WORKDIR/${s}_exp.log 2>/dev/null"
  done
  echo
  echo ">> 확인 사항:"
  echo "   - 로그에 ERROR / SKIP 이 없는가"
  echo "   - VIEW 가 실제로 포함됐는가 (USER 모드는 뷰·시퀀스·제약조건을 함께 담는다)"
  echo "   - 테이블 개수가 소스 기준(02_baseline_meta.log)과 맞는가"
}

cmd_import() {
  need_tgt
  for s in $SCHEMAS; do
    hr "적재: $s"
    local imp_user="USER=$s"
    [ -n "$TOUSER" ] && imp_user="FROMUSER=$s TOUSER=$TOUSER"
    runc "cd $WORKDIR && tbimport USERNAME=$TGT_USER PASSWORD=$TGT_PASS IP=$TGT_IP PORT=$TGT_PORT SID=$TGT_SID \
$imp_user FILE=$WORKDIR/${s}.dat LOG=$WORKDIR/${s}_imp.log $IMP_OPTS"
    runc "tail -40 $WORKDIR/${s}_imp.log 2>/dev/null"
  done
  echo
  echo ">> 다음: 07_recompile_invalid.sql (뷰 재컴파일) -> 05_verify.sql -> 06_compare.sh"
  echo ">> 적재 로그에 버전 관련 경고가 있으면 tbimport 에 EXP_SERVER_VER 를 소스 버전에 맞춰 지정하세요."
}

case "${1:-}" in
  validate) cmd_validate ;;
  check)    cmd_check ;;
  pilot)    cmd_pilot ;;
  export)   cmd_export ;;
  import)   cmd_import ;;
  *) cat <<EOF
사용법: $0 {validate|check|pilot|export|import}

권장 순서:
  validate -> check -> pilot -> (한글 확인) -> export -> import
  -> 07_recompile_invalid.sql -> 05_verify.sql -> 06_compare.sh

자격증명은 환경변수로 전달하세요:
  SRC_SID=<소스DB명> SRC_USER=... SRC_PASS=... \\
  TGT_USER=... TGT_PASS=... DRYRUN=0 $0 pilot
EOF
     exit 1 ;;
esac
