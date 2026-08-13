#!/usr/bin/env bash
# 소스 현재 구조 vs 기존 UT(2026-08-10 시점) 대조 — 무엇이 어떻게 바뀌었나
#
# 소스의 테이블명이 규약에 따라 변경됐다. 기존 UT 인스턴스(tibero7_ut, 18629)는
# 변경 전 스냅샷을 그대로 갖고 있으므로, 그것과 대조하면 변경 내역이 그대로 나온다.
#
# 사용법:
#   ./11_name_diff.sh
#
# 선행: 10_source_inventory.sql 을 소스에 실행해 10_source_tables.log 가 있어야 한다.
#
# 산출물: 11_name_diff.txt
#   - 사라진 이름 / 새로 생긴 이름 / 유지된 이름
#   - 접미사·접두사 규칙이 일정하면 매핑 후보까지 제시

set -uo pipefail

OLD_CONTAINER="${OLD_CONTAINER:-tibero7_ut}"   # 변경 전 스냅샷을 가진 1차 UT (기본값 유지)
WORKDIR="${WORKDIR:-/tmp/tbmig}"
SRC_LIST="${SRC_LIST:-../work/10_source_tables.log}"
OUT="11_name_diff.txt"

TMP="$(mktemp -d)"; trap 'rm -rf "$TMP"' EXIT

[ -f "$SRC_LIST" ] || {
  echo "없음: $SRC_LIST" >&2
  echo "먼저 10_source_inventory.sql 을 소스에 실행하세요." >&2
  exit 1
}

# 소스 목록 정규화 (tbsql 잔여 줄 제거)
grep -oE '^[A-Z][A-Z0-9_$]*\.[A-Z][A-Z0-9_$#]*$' "$SRC_LIST" | sort -u > "$TMP/src.txt"

# 기존 UT 에서 같은 형식으로 뽑는다
docker exec -i "$OLD_CONTAINER" bash -lc 'tbsql -s sys/tibero123' <<'SQL' > "$TMP/old.raw" 2>/dev/null
SET HEADING OFF
SET FEEDBACK OFF
SET PAGESIZE 0
SET LINESIZE 200
SELECT owner || '.' || table_name FROM all_tables
 WHERE owner NOT IN ('SYS','SYSCAT','SYSGIS','SYSMASTER','OUTLN','PUBLIC',
                     'TIBERO','TIBERO1','LBACSYS','SYSBACKUP')
 ORDER BY owner, table_name;
EXIT;
SQL
grep -oE '^[A-Z][A-Z0-9_$]*\.[A-Z][A-Z0-9_$#]*$' "$TMP/old.raw" | sort -u > "$TMP/old.txt"

s_n=$(wc -l < "$TMP/src.txt" | tr -d ' ')
o_n=$(wc -l < "$TMP/old.txt" | tr -d ' ')
[ "$o_n" -gt 0 ] || { echo "기존 UT 목록을 읽지 못했습니다 ($OLD_CONTAINER)" >&2; exit 1; }

comm -13 "$TMP/old.txt" "$TMP/src.txt" > "$TMP/added.txt"    # 소스에만 = 새 이름
comm -23 "$TMP/old.txt" "$TMP/src.txt" > "$TMP/removed.txt"  # UT에만  = 사라진 이름
comm -12 "$TMP/old.txt" "$TMP/src.txt" > "$TMP/kept.txt"

{
  echo "================================================================"
  echo " 소스 vs 기존 UT 테이블명 대조   $(date '+%Y-%m-%d %H:%M:%S')"
  echo "================================================================"
  printf "  소스(현재)   %s개\n" "$s_n"
  printf "  UT(변경 전)  %s개\n" "$o_n"
  echo
  printf "  유지          %s개\n" "$(wc -l < "$TMP/kept.txt" | tr -d ' ')"
  printf "  새 이름       %s개\n" "$(wc -l < "$TMP/added.txt" | tr -d ' ')"
  printf "  사라진 이름   %s개\n" "$(wc -l < "$TMP/removed.txt" | tr -d ' ')"
  echo

  echo "---------------- [1] 스키마별 증감 ----------------"
  printf "  %-14s %8s %8s %8s %8s\n" "스키마" "소스" "UT" "새이름" "사라짐"
  for sc in $(cut -d. -f1 "$TMP/src.txt" "$TMP/old.txt" | sort -u); do
    printf "  %-14s %8s %8s %8s %8s\n" "$sc" \
      "$(grep -c "^$sc\." "$TMP/src.txt")" \
      "$(grep -c "^$sc\." "$TMP/old.txt")" \
      "$(grep -c "^$sc\." "$TMP/added.txt")" \
      "$(grep -c "^$sc\." "$TMP/removed.txt")"
  done
  echo

  echo "---------------- [2] 매핑 후보 ----------------"
  echo "  사라진 이름과 새 이름을 접두사/접미사를 떼고 맞춰본다."
  echo "  (한 줄에 하나씩 대응되면 규약 변경이 기계적이라는 뜻)"
  echo
  # 구분자·언더스코어를 없앤 정규형으로 짝을 찾는다
  norm() { tr -d '_' | tr '[:upper:]' '[:lower:]'; }
  paste -d'\t' <(cut -d. -f2 "$TMP/removed.txt") <(cut -d. -f2 "$TMP/removed.txt" | norm) \
    2>/dev/null | sort -k2 > "$TMP/rm.key"
  paste -d'\t' <(cut -d. -f2 "$TMP/added.txt")   <(cut -d. -f2 "$TMP/added.txt"   | norm) \
    2>/dev/null | sort -k2 > "$TMP/ad.key"
  matched=$(join -1 2 -2 2 -o 1.1,2.1 "$TMP/rm.key" "$TMP/ad.key" 2>/dev/null | sort -u)
  if [ -n "$matched" ]; then
    echo "$matched" | awk '{printf "  %-42s ->  %s\n", $1, $2}'
    echo
    echo "  위는 언더스코어만 다른 경우다. 그 외는 아래 원본 목록에서 눈으로 대조할 것."
  else
    echo "  (언더스코어 차이로 맞는 짝 없음 — 이름 규칙이 더 크게 바뀐 듯)"
  fi
  echo

  echo "---------------- [3] 사라진 이름 (변경 전) ----------------"
  sed 's/^/  /' "$TMP/removed.txt"
  echo
  echo "---------------- [4] 새 이름 (변경 후) ----------------"
  sed 's/^/  /' "$TMP/added.txt"
  echo
  echo "---------------- [5] 스크립트에 박힌 이름 점검 ----------------"
  echo "  아래 이름이 '사라진 이름'에 있으면 해당 스크립트를 고쳐야 한다."
  for t in T_AAAA_CMMN01C T_TIPA_VMS_SYBL_01I T_TIPA_LCS_SYBL_01I \
           T_TIPB_VSL_PGRM_01I T_TIPE_LCS_LCTRL_01M T_TIPE_VMST_DDRF_PHSE_OBJ_01L; do
    if grep -q "\.$t$" "$TMP/src.txt"; then
      printf "  유지   %-34s\n" "$t"
    else
      printf "  변경!  %-34s  <- 02/03/05 수정 필요\n" "$t"
    fi
  done
} | tee "$OUT"

echo
echo "리포트 저장: $OUT"
