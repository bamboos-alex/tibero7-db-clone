#!/usr/bin/env bash
# Phase 0-1: docker tibero7 컨테이너 환경 점검 (읽기 전용)
#
# 사용법:  ./00_env_check.sh <컨테이너명> [소스호스트] [소스포트]
# 예:      ./00_env_check.sh tibero7 10.10.20.30 8629
#
# 목적: tbsql / tbexport / tbimport 실제 존재 여부와 명칭·옵션을 "확인"한다.
#       버전마다 유틸리티 이름이 다르므로 추정하지 않고 여기서 확정한 뒤 03 스크립트를 채운다.

set -uo pipefail

CONTAINER="${1:-}"
SRC_HOST="${2:-}"
SRC_PORT="${3:-}"

if [ -z "$CONTAINER" ]; then
  echo "사용법: $0 <컨테이너명> [소스호스트] [소스포트]"
  echo
  echo "--- 실행 중인 컨테이너 ---"
  docker ps --format '{{.Names}}\t{{.Image}}\t{{.Status}}' 2>&1
  exit 1
fi

hr() { printf '\n===== %s =====\n' "$1"; }
run() { docker exec "$CONTAINER" bash -lc "$*" 2>&1; }

hr "컨테이너 확인"
docker ps --filter "name=^/${CONTAINER}$" --format 'name={{.Names}}  image={{.Image}}  status={{.Status}}' 2>&1

hr "TB_HOME / 버전"
run 'echo "TB_HOME=$TB_HOME"; echo "TB_SID=$TB_SID"; echo "PATH=$PATH"'
run 'tbsql -h 2>&1 | head -5; echo "---"; cat $TB_HOME/license/license.xml 2>/dev/null | grep -iE "edition|expiry" | head -5'

hr "유틸리티 목록 (client/bin)"
run 'ls -1 $TB_HOME/client/bin 2>/dev/null'

hr "유틸리티 목록 (bin)"
run 'ls -1 $TB_HOME/bin 2>/dev/null'

hr "export/import/loader 계열 실제 파일명"
run 'ls -1 $TB_HOME/client/bin $TB_HOME/bin 2>/dev/null | sort -u | grep -iE "exp|imp|load|migrat|pack" || echo "(해당 없음 → 경로 B로 진행)"'

hr "tbExport 사용법 (전문 — 잘라내지 않는다. 파라미터명을 여기서 확정한다)"
run 'command -v tbexport >/dev/null 2>&1 && tbexport -h 2>&1 || echo "(tbexport 없음)"'

hr "tbImport 사용법 (전문)"
run 'command -v tbimport >/dev/null 2>&1 && tbimport -h 2>&1 || echo "(tbimport 없음)"'

hr "현재 tbdsn.tbr 내용"
run 'cat $TB_HOME/client/config/tbdsn.tbr 2>/dev/null || echo "(파일 없음)"'

hr "디스크 여유 공간 (384MB LOB 테이블 대비)"
run 'df -h $TB_HOME 2>&1'

if [ -n "$SRC_HOST" ] && [ -n "$SRC_PORT" ]; then
  hr "소스 DB 네트워크 도달 확인 ${SRC_HOST}:${SRC_PORT}"
  run "(command -v nc >/dev/null && nc -z -w3 ${SRC_HOST} ${SRC_PORT} && echo '도달 가능') \
       || (timeout 3 bash -c '</dev/tcp/${SRC_HOST}/${SRC_PORT}' && echo '도달 가능') \
       || echo '도달 불가 — 방화벽/네트워크 확인 필요'"
else
  hr "소스 DB 네트워크 도달 확인"
  echo "(건너뜀: 소스호스트/포트를 인자로 주면 확인합니다)"
fi

hr "다음 단계"
cat <<'EOF'
1) 위 "export/import/loader 계열" 결과를 보고 유틸리티 존재 여부를 확정한다.
     있음 → 03_export_import.sh 의 상단 변수와 옵션을 실제 -h 출력에 맞춰 채운다.
     없음 → 경로 B(04a/04b + DBeaver DB→DB)로 진행한다.
2) tbdsn.tbr 에 소스/타겟 DSN을 등록한다 (아래 형식):

   SRC=(
     (INSTANCE=(HOST=<소스호스트>)(PORT=<소스포트>)(DB_NAME=<소스DB명>))
   )
   TGT=(
     (INSTANCE=(HOST=localhost)(PORT=8629)(DB_NAME=<타겟DB명>))
   )

   등록 방법: docker exec -it <컨테이너> bash 로 들어가 $TB_HOME/client/config/tbdsn.tbr 편집
3) 접속 확인:  tbsql <user>/<pw>@SRC   /   tbsql <user>/<pw>@TGT
4) 01_source_check.sql 실행
EOF
