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
SRC_SID="${SRC_SID:-TAIMS}"     # DBeaver JDBC URL 의 마지막 항목(DB_NAME)
SRC_USER="${SRC_USER:-}"
SRC_PASS="${SRC_PASS:-}"
SRC_DSN="${SRC_DSN:-SRC}"       # tbsql 전용. tbsql 은 host:port:sid 형식을 받지 않는다(확인됨)

# ================= 타겟 (docker tibero7_ut_tablename, 호스트 28629) =================
# 기존 tibero7 컨테이너의 AIMS_DEV 는 개발용이라 보존해야 하므로, 별도 인스턴스를 새로 만들었다.
# 이 스크립트는 tibero7_ut_tablename 컨테이너 "안에서" 실행된다:
#   - 타겟은 자기 자신이라 localhost:8629
#   - 소스는 외부 IP 라 그대로 닿는다
# (tibero7 컨테이너에서 실행하면 localhost 가 자기 자신을 가리켜 타겟에 닿지 않는다)
TGT_IP="${TGT_IP:-localhost}"
TGT_PORT="${TGT_PORT:-8629}"
TGT_SID="${TGT_SID:-TAIMS}"
TGT_USER="${TGT_USER:-}"
TGT_PASS="${TGT_PASS:-}"
TGT_DSN="${TGT_DSN:-TAIMS}"     # gen_tip.sh 가 TB_SID 로 만든 기본 DSN

TBDSN="${TBDSN:-/opt/tibero7/client/config/tbdsn.tbr}"

# ================= 공통 =================
CONTAINER="${CONTAINER:-tibero7_ut_tablename}"
# 순서 중요: AIMS_DEV/AIMSC_DEV 의 시노님 101개가 AIMS_EX 를 가리킨다.
# 대상 테이블이 먼저 있어야 시노님이 유효해지므로 AIMS_EX 를 앞에 둔다.
SCHEMAS="${SCHEMAS:-AIMS_EX AIMS_DEV AIMSC_DEV}"
WORKDIR="${WORKDIR:-/tmp/tbmig}"
PILOT_SCHEMA="${PILOT_SCHEMA:-AIMS_DEV}"
PILOT_TABLE="${PILOT_TABLE:-T_AAAA_CMMN01C}"
DRYRUN="${DRYRUN:-1}"

# tbexport/tbimport 앞에 붙일 환경변수.
#   실측: 지정하지 않으면 "Export character set: MSWIN949" 로 나간다.
#   소스도 타겟도 UTF8 이므로 덤프도 UTF8 로 맞춰야 바이트가 보존된다.
#   (CP949 로 표현 못 하는 문자와, 소스에 이미 들어있는 비정상 바이트가 변환에서 뭉개진다)
#   값이 안 먹으면 TBENV= 로 비우고 실행해 기존 동작으로 되돌릴 수 있다.
TBENV="${TBENV:-TB_NLS_LANG=UTF8}"

# 스키마명을 소스와 다르게 바꿔 적재하려면 지정 (예: TOUSER="AIMS_UT")
TOUSER="${TOUSER:-}"

# ---- 추출 옵션 ----
#  CONSISTENT=Y : 공동 작업 DB 라 추출 중에도 갱신이 일어난다. 일관된 시점 스냅샷을 뜬다.
#  COMPRESS=Y   : 384MB LOB 테이블 때문에 덤프가 커진다.
#  GRANT=Y      : 권한 정보는 담아 두고, 적재 시점에 뺀다(타겟에 없는 계정 참조 방지).
EXP_OPTS="${EXP_OPTS:-CONSISTENT=Y CONSTRAINT=Y INDEX=Y GRANT=Y COMPRESS=Y OVERWRITE=Y}"

# ---- 적재 옵션 ----
#  GRANT=Y  : 소스의 계정이 AIMS_EX/AIMS_DEV/AIMSC_DEV 뿐이고 타겟에 셋 다 만들었으므로
#             객체 권한을 그대로 옮기는 편이 정확하다. 시노님 101개가 AIMS_EX 를 참조하는데,
#             그 권한이 없으면 뷰가 열리지 않는다.
#             적재 로그에 GRANT 실패가 쌓이면 GRANT=N 으로 바꾸고 04b 의 주석 처리된
#             'GRANT SELECT ANY TABLE ...' 을 대신 부여한다.
#  IGNORE=N : 이미 있는 객체가 있으면 조용히 넘어가지 않고 드러나게 한다.
IMP_OPTS="${IMP_OPTS:-CONSTRAINT=Y INDEX=Y GRANT=Y IGNORE=N COMMIT=Y}"

# 이 스크립트가 사용하는 파라미터명 (validate 로 실재 여부를 대조한다)
# FULL / USER / TABLE 은 "모드" 라 동시에 줄 수 없다 (Mode confliction).
#   스키마 전량 -> USER=<스키마>
#   테이블 단위 -> TABLE=<스키마>.<테이블>
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

# 읽기 전용 조회는 DRYRUN 과 무관하게 실행한다.
# (상태를 보려고 부르는 명령까지 막으면 DRYRUN 이 판단에 도움이 되지 않는다)
runc_ro() {
  docker exec "$CONTAINER" bash -lc "$1"
}

need_src() {
  [ -n "$SRC_SID" ]  || die "SRC_SID 미설정"
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

# ---------------------------------------------------------
# dsn: tbsql 용 SRC DSN 등록 (없을 때만 추가. 여러 번 실행해도 안전)
#      tbexport/tbimport 는 DSN 없이 IP/PORT/SID 로 동작하므로 이 단계와 무관하다.
# ---------------------------------------------------------
cmd_dsn() {
  hr "tbdsn.tbr 현재 내용"
  runc_ro "cat $TBDSN"

  hr "$SRC_DSN 항목 등록"
  if docker exec "$CONTAINER" grep -qE "^[[:space:]]*${SRC_DSN}=" "$TBDSN" 2>/dev/null; then
    echo "이미 등록돼 있습니다. 추가하지 않습니다."
    return 0
  fi

  echo "다음 내용을 $TBDSN 끝에 추가합니다:"
  cat <<EOF

$SRC_DSN=(
    (INSTANCE=(HOST=$SRC_IP)
              (PORT=$SRC_PORT)
              (DB_NAME=$SRC_SID)
    )
)
EOF
  if [ "$DRYRUN" = "1" ]; then
    echo
    echo "  (DRYRUN — 추가하지 않음. DRYRUN=0 으로 재실행하면 기록됩니다)"
    return 0
  fi

  docker exec "$CONTAINER" cp "$TBDSN" "${TBDSN}.bak.$(date +%Y%m%d%H%M%S)" \
    || die "백업 실패"
  docker exec -i "$CONTAINER" bash -c "cat >> $TBDSN" <<EOF

$SRC_DSN=(
    (INSTANCE=(HOST=$SRC_IP)
              (PORT=$SRC_PORT)
              (DB_NAME=$SRC_SID)
    )
)
EOF
  echo "등록 완료 (원본은 .bak 으로 백업)"
  docker exec "$CONTAINER" tail -12 "$TBDSN"
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

  hr "DSN 등록 여부"
  if docker exec "$CONTAINER" grep -qE "^[[:space:]]*${SRC_DSN}=" "$TBDSN" 2>/dev/null; then
    echo "$SRC_DSN : 등록됨"
  else
    echo "$SRC_DSN : 미등록  ->  먼저 '$0 dsn' 을 실행하세요 (tbsql 은 host:port:sid 형식을 받지 않습니다)"
  fi

  hr "소스 접속 및 버전 확인  (tbsql 은 DSN 사용)"
  echo "-- 소스가 Tibero 7 이 아니면 tbimport 의 EXP_SERVER_VER 조정이 필요할 수 있습니다."
  runc "echo \"SELECT * FROM v\\\$version;\" | tbsql -s $SRC_USER/$SRC_PASS@$SRC_DSN"

  hr "타겟 접속 확인"
  if [ -n "$TGT_USER" ]; then
    runc "echo \"SELECT USER FROM dual;\" | tbsql -s $TGT_USER/$TGT_PASS@$TGT_DSN"
  else
    echo "(TGT_USER 미설정 — 04_target_prepare.sql 로 계정을 만든 뒤 지정하세요)"
  fi
  echo
  echo "※ tbexport/tbimport 는 DSN 없이 IP/PORT/SID 로 동작합니다. DSN 은 tbsql 전용입니다."
}

cmd_pilot() {
  need_src; need_tgt
  hr "선검증: $PILOT_SCHEMA.$PILOT_TABLE 만 왕복"
  echo "목적: 전량 실행 전에 한글·날짜·자료형이 온전히 넘어가는지 확인한다."
  runc "mkdir -p $WORKDIR"

  # tbexport 의 FULL / USER / TABLE 은 상호 배타적인 "모드"다.
  # USER= 와 TABLE= 을 같이 주면 "Mode confliction" 으로 실패한다(실측).
  # 테이블 단위는 TABLE=스키마.테이블 하나만 준다.
  local f="$WORKDIR/pilot_${PILOT_TABLE}.dat"
  runc "cd $WORKDIR && ${TBENV:+env $TBENV} tbexport USERNAME=$SRC_USER PASSWORD=$SRC_PASS IP=$SRC_IP PORT=$SRC_PORT SID=$SRC_SID \
TABLE=$PILOT_SCHEMA.$PILOT_TABLE FILE=$f LOG=$WORKDIR/pilot_exp.log $EXP_OPTS"

  # 추출이 실패했는데 적재로 넘어가면 원인이 가려진다. 덤프 파일 유무로 끊는다.
  if [ "$DRYRUN" != "1" ]; then
    if ! docker exec "$CONTAINER" test -f "$f"; then
      hr "추출 로그"
      runc_ro "tail -40 $WORKDIR/pilot_exp.log 2>/dev/null || echo '(로그 없음)'"
      die "덤프 파일이 생성되지 않았습니다: $f — 위 로그를 확인하세요"
    fi
    runc_ro "ls -lh $f"
  fi

  local imp_tgt="TABLE=$PILOT_SCHEMA.$PILOT_TABLE"
  [ -n "$TOUSER" ] && imp_tgt="FROMUSER=$PILOT_SCHEMA TOUSER=$TOUSER"
  runc "cd $WORKDIR && ${TBENV:+env $TBENV} tbimport USERNAME=$TGT_USER PASSWORD=$TGT_PASS IP=$TGT_IP PORT=$TGT_PORT SID=$TGT_SID \
$imp_tgt FILE=$f LOG=$WORKDIR/pilot_imp.log $IMP_OPTS"

  hr "적재 결과 — 한글이 깨지지 않았는지 육안 확인"
  local chk_schema="${TOUSER:-$PILOT_SCHEMA}"
  runc "echo \"SELECT CD_ID, CD_NM, DUMP(CD_NM,16) FROM $chk_schema.$PILOT_TABLE WHERE ROWNUM<=5;\" \
| tbsql -s $TGT_USER/$TGT_PASS@$TGT_DSN"
  echo
  echo ">> CD_NM 이 정상 한글이면 export 단계로 넘어가세요."
}

cmd_export() {
  need_src
  runc "mkdir -p $WORKDIR"
  for s in $SCHEMAS; do
    hr "추출: $s"
    runc "cd $WORKDIR && ${TBENV:+env $TBENV} tbexport USERNAME=$SRC_USER PASSWORD=$SRC_PASS IP=$SRC_IP PORT=$SRC_PORT SID=$SRC_SID \
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
    runc "cd $WORKDIR && ${TBENV:+env $TBENV} tbimport USERNAME=$TGT_USER PASSWORD=$TGT_PASS IP=$TGT_IP PORT=$TGT_PORT SID=$TGT_SID \
$imp_user FILE=$WORKDIR/${s}.dat LOG=$WORKDIR/${s}_imp.log $IMP_OPTS"
    runc "tail -40 $WORKDIR/${s}_imp.log 2>/dev/null"
  done
  echo
  echo ">> 다음: 07_recompile_invalid.sql (뷰 재컴파일) -> 05_verify.sql -> 06_compare.sh"
  echo ">> 적재 로그에 버전 관련 경고가 있으면 tbimport 에 EXP_SERVER_VER 를 소스 버전에 맞춰 지정하세요."
}

case "${1:-}" in
  validate) cmd_validate ;;
  dsn)      cmd_dsn ;;
  check)    cmd_check ;;
  pilot)    cmd_pilot ;;
  export)   cmd_export ;;
  import)   cmd_import ;;
  *) cat <<EOF
사용법: $0 {validate|dsn|check|pilot|export|import}

권장 순서:
  validate -> dsn -> check -> pilot -> (한글 확인) -> export -> import
  -> 07_recompile_invalid.sql -> 05_verify.sql -> 06_compare.sh

  dsn : tbsql 용 SRC DSN 을 tbdsn.tbr 에 등록 (tbexport/tbimport 에는 불필요)

자격증명은 환경변수로 전달하세요:
  SRC_SID=<소스DB명> SRC_USER=... SRC_PASS=... \\
  TGT_USER=... TGT_PASS=... DRYRUN=0 $0 pilot
EOF
     exit 1 ;;
esac
