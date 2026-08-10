#!/usr/bin/env bash
# Phase 4-0: 추출 로그에서 "기대 건수" 추출
#
# 왜 필요한가:
#   소스는 공동 작업 DB 라 계속 돌아간다. 아침에 뜬 02_baseline_counts.log 와
#   추출 시점(CONSISTENT=Y 스냅샷)의 건수가 이미 다르다. 실측 예:
#     AIMS_DEV.T_AAAA_CENR_PROCS_STAT01L   기준 4,107 -> 추출 6,099
#     AIMS_DEV.T_AAAA_SRVR_STAT01L         기준   744 -> 추출 1,105
#   따라서 타겟 검증의 기준은 "추출 로그에 찍힌 건수" 여야 한다.
#   (AIMS_EX 는 정적이라 기준값과 일치했다. 증가하는 것은 AIMS_DEV 의 로그성 테이블뿐)
#
# 사용법:
#   서버에서:  ./08_expected_from_exportlog.sh
#   결과:      08_expected_counts.log   ("SCHEMA.TABLE  건수" 형식, 06_compare.sh 가 그대로 읽는다)
#
# 대조:
#   ./06_compare.sh 08_expected_counts.log 05_target_counts.log

set -uo pipefail

CONTAINER="${CONTAINER:-tibero7_ut}"
WORKDIR="${WORKDIR:-/tmp/tbmig}"
SCHEMAS="${SCHEMAS:-AIMS_EX AIMS_DEV AIMSC_DEV}"
OUT="${OUT:-08_expected_counts.log}"

: > "$OUT"
total=0

for s in $SCHEMAS; do
  log="$WORKDIR/${s}_exp.log"
  if ! docker exec "$CONTAINER" test -f "$log"; then
    echo "건너뜀 (로그 없음): $log" >&2
    continue
  fi

  # 로그 형식 (앞에 '-- ' 가 붙는 경우도 있음):
  #       [0] AIMS_EX.IAM_USER                        16486 rows exported.
  #       [0] AIMS_EX.ITWM_CTRSTA_DTL                    no rows exported.
  n=$(docker exec "$CONTAINER" cat "$log" | awk '
    match($0, /\[[0-9]+\][ \t]+[A-Z0-9_$]+\.[A-Z0-9_$#]+[ \t]+/) {
      line = $0
      sub(/^.*\[[0-9]+\][ \t]+/, "", line)     # "[0] " 앞부분 제거
      split(line, f, /[ \t]+/)
      name = f[1]
      if (line ~ /no rows exported/)      { print name, 0 }
      else if (line ~ /[0-9]+ rows exported/) {
        cnt = line
        sub(/^[^ \t]+[ \t]+/, "", cnt)         # 테이블명 제거
        sub(/[ \t]*rows exported.*$/, "", cnt) # 뒤쪽 제거
        gsub(/[ \t]/, "", cnt)
        if (cnt ~ /^[0-9]+$/) print name, cnt
      }
    }
  ' | sort -u | tee -a "$OUT" | wc -l)

  printf "%-12s %s개 테이블\n" "$s" "$n"
  total=$((total + n))
done

sort -u -o "$OUT" "$OUT"

echo
echo "총 $total 개 테이블 -> $OUT"
echo
echo "합계 행수: $(awk '{s+=$2} END {print s}' "$OUT")"
echo
echo "다음:"
echo "  1) 적재 후 타겟에서 05_verify.sql + 05_gen_counts.sql 실행"
echo "  2) ./06_compare.sh $OUT 05_target_counts.log"
