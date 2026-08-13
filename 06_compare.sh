#!/usr/bin/env bash
# Phase 4-2: 소스 기준값 vs 타겟 결과 대조
#
# 사용법:
#   ./06_compare.sh 02_baseline_counts.log 05_target_counts.log [02_baseline_meta.log 05_target_meta.log]
#
# 출력: 06_compare_report.txt
#   - 소스에만 있는 테이블 / 타겟에만 있는 테이블
#   - 건수 불일치 테이블 (소스, 타겟, 차이)
#   - 메타 개수 diff

set -uo pipefail

SRC_COUNTS="${1:-02_baseline_counts.log}"
TGT_COUNTS="${2:-05_target_counts.log}"
SRC_META="${3:-02_baseline_meta.log}"
TGT_META="${4:-05_target_meta.log}"
REPORT="06_compare_report.txt"

[ -f "$SRC_COUNTS" ] || { echo "없음: $SRC_COUNTS"; exit 1; }
[ -f "$TGT_COUNTS" ] || { echo "없음: $TGT_COUNTS"; exit 1; }

# tbsql 로그에서 "스키마.테이블  건수" 형태만 뽑아 정규화
norm() {
  awk '
    /^[A-Z][A-Z0-9_$]*\.[A-Z][A-Z0-9_$#]*[ \t]+[0-9]+[ \t]*$/ {
      gsub(/[ \t]+$/, "", $0); print $1, $2
    }
  ' "$1" | sort -u
}

norm "$SRC_COUNTS" > /tmp/.cmp_src.$$
norm "$TGT_COUNTS" > /tmp/.cmp_tgt.$$

SRC_N=$(wc -l < /tmp/.cmp_src.$$ | tr -d ' ')
TGT_N=$(wc -l < /tmp/.cmp_tgt.$$ | tr -d ' ')

{
  echo "================================================================"
  echo " Tibero 이관 대조 리포트   $(date '+%Y-%m-%d %H:%M:%S')"
  echo "================================================================"
  echo "소스 로그: $SRC_COUNTS  (객체 $SRC_N 개)"
  echo "타겟 로그: $TGT_COUNTS  (객체 $TGT_N 개)"
  echo

  if [ "$SRC_N" -eq 0 ] || [ "$TGT_N" -eq 0 ]; then
    echo "!! 파싱된 객체가 0건입니다. 로그 형식을 확인하세요."
    echo "   (tbsql 출력 폭이 좁아 줄바꿈되면 파싱이 안 됩니다 -> SET LINESIZE 를 늘려 재실행)"
  fi

  echo "---------------- [1] 소스에만 있는 객체 ----------------"
  comm -23 <(cut -d' ' -f1 /tmp/.cmp_src.$$) <(cut -d' ' -f1 /tmp/.cmp_tgt.$$) \
    | sed 's/^/  누락: /' || true
  echo "  (위에 아무것도 없으면 정상)"
  echo

  echo "---------------- [2] 타겟에만 있는 객체 ----------------"
  comm -13 <(cut -d' ' -f1 /tmp/.cmp_src.$$) <(cut -d' ' -f1 /tmp/.cmp_tgt.$$) \
    | sed 's/^/  잉여: /' || true
  echo "  (위에 아무것도 없으면 정상)"
  echo

  echo "---------------- [3] 건수 불일치 ----------------"
  join /tmp/.cmp_src.$$ /tmp/.cmp_tgt.$$ \
    | awk '$2 != $3 { printf "  %-45s 소스=%-12s 타겟=%-12s 차이=%s\n", $1, $2, $3, ($2-$3) }'
  echo "  (위에 아무것도 없으면 전 객체 건수 일치)"
  echo

  echo "---------------- [4] 요약 ----------------"
  MATCH=$(join /tmp/.cmp_src.$$ /tmp/.cmp_tgt.$$ | awk '$2==$3' | wc -l | tr -d ' ')
  DIFF=$(join /tmp/.cmp_src.$$ /tmp/.cmp_tgt.$$ | awk '$2!=$3' | wc -l | tr -d ' ')
  ONLY_S=$(comm -23 <(cut -d' ' -f1 /tmp/.cmp_src.$$) <(cut -d' ' -f1 /tmp/.cmp_tgt.$$) | wc -l | tr -d ' ')
  ONLY_T=$(comm -13 <(cut -d' ' -f1 /tmp/.cmp_src.$$) <(cut -d' ' -f1 /tmp/.cmp_tgt.$$) | wc -l | tr -d ' ')
  echo "  건수 일치      : $MATCH"
  echo "  건수 불일치    : $DIFF"
  echo "  소스에만 존재  : $ONLY_S"
  echo "  타겟에만 존재  : $ONLY_T"
  echo
  if [ "$DIFF" = "0" ] && [ "$ONLY_S" = "0" ] && [ "$ONLY_T" = "0" ] && [ "$SRC_N" -gt 0 ]; then
    echo "  => 건수 기준 이상 없음"
  else
    echo "  => 불일치 있음. 위 [1][2][3] 항목을 확인하세요."
  fi
  echo

  if [ -f "$SRC_META" ] && [ -f "$TGT_META" ]; then
    echo "---------------- [5] 메타 개수 diff (소스 < , 타겟 > ) ----------------"
    diff <(grep -vE 'CONNECTED_USER|SNAPSHOT_AT|^-{3,}|^$' "$SRC_META") \
         <(grep -vE 'CONNECTED_USER|SNAPSHOT_AT|^-{3,}|^$' "$TGT_META") \
      || true
    echo "  (차이가 없으면 아무것도 출력되지 않습니다)"
  fi

  echo
  echo "---------------- [6] 수동 확인 항목 ----------------"
  cat <<'EOF'
  □ 05_target_health.log 의 무효 객체 / 비활성 제약조건 / 사용 불가 인덱스가 모두 0건인가
  □ 05_target_health.log 의 "뷰 조회 실패" 가 0건인가
  □ 뷰 건수도 대조했는가
      ./06_compare.sh 02_baseline_view_counts.log 05_target_view_counts.log
  □ 한글 표본의 DUMP(...,16) 이 소스와 바이트 단위로 동일한가 (05_verify.sql 의 KOR_TAB)
  □ LOB 보유 테이블의 행수·바이트가 소스와 일치하는가 (05_target_health.log 하단)
  □ 애플리케이션 화면에서 한글이 정상 표시되는가
EOF
} | tee "$REPORT"

rm -f /tmp/.cmp_src.$$ /tmp/.cmp_tgt.$$
echo
echo "리포트 저장: $REPORT"
