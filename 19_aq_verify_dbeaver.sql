-- ============================================================================
--  AQ 앱 테이블 12개 — 생성 결과 확인  (DBeaver 실행, 읽기 전용)
--  대상: 121.137.106.217:58629 / TAIMS / AIMS_DEV
-- ============================================================================
--
--  [요약] 한 번만 실행하면 합격 여부가 갈린다. VERDICT 가 전부 OK 여야 한다.
--  아래 상세 쿼리들은 OK 가 아닌 항목이 있을 때 원인을 찾는 용도다.
--
--  ** 이력 테이블의 핵심은 PARTITIONED='YES' 다. **
--  'NO' 로 나오면 로컬이 아니라 글로벌 인덱스가 만들어진 것이다.
-- ============================================================================

-- ---- [요약] 기대값 대조 -----------------------------------------------------
SELECT item, expected, actual,
       CASE WHEN expected = actual THEN 'OK' ELSE '** 확인 필요 **' END AS verdict
  FROM (
  SELECT 1 AS seq, '테이블 12개 생성' AS item, 12 AS expected, COUNT(*) AS actual
    FROM all_tables WHERE owner='AIMS_DEV' AND table_name IN (
       'T_ITSE_AI_CCTV01M','T_ITSE_AI_MODL01M','T_ITSE_DATST01M',
       'T_ITSE_SNSH_STUP01M','T_ITSE_SNSH_GTHR01L','T_ITSE_SNSH_PRPG01L',
       'T_ITSE_LBLL01L','T_ITSE_ANNT01L','T_ITSE_AI_DGNST01L',
       'T_ITSE_AI_MVPCT_DGNST01L','T_ITSE_AI_DRF_DGNST01L','T_ITSE_AI_MODL_OP01L')
  UNION ALL
  SELECT 2, '이력 8개가 파티션 테이블', 8, COUNT(*)
    FROM all_part_tables WHERE owner='AIMS_DEV' AND table_name IN (
       'T_ITSE_SNSH_GTHR01L','T_ITSE_SNSH_PRPG01L','T_ITSE_LBLL01L',
       'T_ITSE_ANNT01L','T_ITSE_AI_DGNST01L','T_ITSE_AI_MVPCT_DGNST01L',
       'T_ITSE_AI_DRF_DGNST01L','T_ITSE_AI_MODL_OP01L')
  UNION ALL
  SELECT 3, '파티션 총 24개 (8x3)', 24, NVL(SUM(partition_count),0)
    FROM all_part_tables WHERE owner='AIMS_DEV' AND table_name IN (
       'T_ITSE_SNSH_GTHR01L','T_ITSE_SNSH_PRPG01L','T_ITSE_LBLL01L',
       'T_ITSE_ANNT01L','T_ITSE_AI_DGNST01L','T_ITSE_AI_MVPCT_DGNST01L',
       'T_ITSE_AI_DRF_DGNST01L','T_ITSE_AI_MODL_OP01L')
  UNION ALL
  SELECT 4, '이력 인덱스가 로컬 유니크', 8, COUNT(*)
    FROM all_indexes WHERE table_owner='AIMS_DEV'
     AND partitioned='YES' AND uniqueness='UNIQUE' AND table_name IN (
       'T_ITSE_SNSH_GTHR01L','T_ITSE_SNSH_PRPG01L','T_ITSE_LBLL01L',
       'T_ITSE_ANNT01L','T_ITSE_AI_DGNST01L','T_ITSE_AI_MVPCT_DGNST01L',
       'T_ITSE_AI_DRF_DGNST01L','T_ITSE_AI_MODL_OP01L')
  UNION ALL
  SELECT 5, 'PK 제약 12개 ENABLED', 12, COUNT(*)
    FROM all_constraints WHERE owner='AIMS_DEV' AND constraint_type='P'
     AND status='ENABLED' AND table_name IN (
       'T_ITSE_AI_CCTV01M','T_ITSE_AI_MODL01M','T_ITSE_DATST01M',
       'T_ITSE_SNSH_STUP01M','T_ITSE_SNSH_GTHR01L','T_ITSE_SNSH_PRPG01L',
       'T_ITSE_LBLL01L','T_ITSE_ANNT01L','T_ITSE_AI_DGNST01L',
       'T_ITSE_AI_MVPCT_DGNST01L','T_ITSE_AI_DRF_DGNST01L','T_ITSE_AI_MODL_OP01L')
  UNION ALL
  SELECT 6, '무효 객체 없음', 0, COUNT(*)
    FROM all_objects WHERE owner='AIMS_DEV' AND status <> 'VALID'
     AND object_name IN (
       'T_ITSE_AI_CCTV01M','T_ITSE_AI_MODL01M','T_ITSE_DATST01M',
       'T_ITSE_SNSH_STUP01M','T_ITSE_SNSH_GTHR01L','T_ITSE_SNSH_PRPG01L',
       'T_ITSE_LBLL01L','T_ITSE_ANNT01L','T_ITSE_AI_DGNST01L',
       'T_ITSE_AI_MVPCT_DGNST01L','T_ITSE_AI_DRF_DGNST01L','T_ITSE_AI_MODL_OP01L')
) ORDER BY seq;


-- ---- [상세 1] 이력 8개의 인덱스 — PARTITIONED 가 전부 YES 여야 한다 ---------
SELECT table_name, index_name, uniqueness, partitioned, tablespace_name
  FROM all_indexes
 WHERE table_owner='AIMS_DEV' AND table_name IN (
       'T_ITSE_SNSH_GTHR01L','T_ITSE_SNSH_PRPG01L','T_ITSE_LBLL01L',
       'T_ITSE_ANNT01L','T_ITSE_AI_DGNST01L','T_ITSE_AI_MVPCT_DGNST01L',
       'T_ITSE_AI_DRF_DGNST01L','T_ITSE_AI_MODL_OP01L')
 ORDER BY table_name;


-- ---- [상세 2] 파티션 구성 — 8개 x RANGE 3 -----------------------------------
SELECT table_name, partitioning_type, partition_count
  FROM all_part_tables
 WHERE owner='AIMS_DEV' AND table_name IN (
       'T_ITSE_SNSH_GTHR01L','T_ITSE_SNSH_PRPG01L','T_ITSE_LBLL01L',
       'T_ITSE_ANNT01L','T_ITSE_AI_DGNST01L','T_ITSE_AI_MVPCT_DGNST01L',
       'T_ITSE_AI_DRF_DGNST01L','T_ITSE_AI_MODL_OP01L')
 ORDER BY table_name;


-- ---- [상세 3] 파티션 키 -----------------------------------------------------
--  기대값
--    T_ITSE_SNSH_GTHR01L        STRT_DTTM
--    T_ITSE_SNSH_PRPG01L        PRPG_STRT_DTTM
--    T_ITSE_LBLL01L             INFO_CRET_DTTM
--    T_ITSE_ANNT01L             INFO_CRET_DTTM
--    T_ITSE_AI_DGNST01L         STRT_DTTM
--    T_ITSE_AI_MVPCT_DGNST01L   AI_DGNST_DTTM
--    T_ITSE_AI_DRF_DGNST01L     AI_DGNST_DTTM
--    T_ITSE_AI_MODL_OP01L       MNTG_STRT_DTTM   (파티션 없는 대안을 썼다면 안 나온다)
SELECT name, column_name, column_position
  FROM all_part_key_columns
 WHERE owner='AIMS_DEV' AND name IN (
       'T_ITSE_SNSH_GTHR01L','T_ITSE_SNSH_PRPG01L','T_ITSE_LBLL01L',
       'T_ITSE_ANNT01L','T_ITSE_AI_DGNST01L','T_ITSE_AI_MVPCT_DGNST01L',
       'T_ITSE_AI_DRF_DGNST01L','T_ITSE_AI_MODL_OP01L')
 ORDER BY name, column_position;


-- ---- [상세 4] 파티션 이름과 경계 — P202608 / P202609 / PMAX -----------------
--  ALL_TAB_PARTITIONS 에는 TABLE_OWNER 컬럼이 없다(Tibero). 이름으로만 거른다.
SELECT table_name, partition_name, partition_position, high_value
  FROM all_tab_partitions
 WHERE table_name IN (
       'T_ITSE_SNSH_GTHR01L','T_ITSE_SNSH_PRPG01L','T_ITSE_LBLL01L',
       'T_ITSE_ANNT01L','T_ITSE_AI_DGNST01L','T_ITSE_AI_MVPCT_DGNST01L',
       'T_ITSE_AI_DRF_DGNST01L','T_ITSE_AI_MODL_OP01L')
 ORDER BY table_name, partition_position;


-- ---- [상세 5] PK 제약 — ENABLED / VALIDATED --------------------------------
SELECT table_name, constraint_name, status, validated
  FROM all_constraints
 WHERE owner='AIMS_DEV' AND constraint_type='P' AND table_name IN (
       'T_ITSE_AI_CCTV01M','T_ITSE_AI_MODL01M','T_ITSE_DATST01M',
       'T_ITSE_SNSH_STUP01M','T_ITSE_SNSH_GTHR01L','T_ITSE_SNSH_PRPG01L',
       'T_ITSE_LBLL01L','T_ITSE_ANNT01L','T_ITSE_AI_DGNST01L',
       'T_ITSE_AI_MVPCT_DGNST01L','T_ITSE_AI_DRF_DGNST01L','T_ITSE_AI_MODL_OP01L')
 ORDER BY table_name;


-- ---- [상세 6] PK 컬럼 구성 — 이력은 (업무ID, 파티션키) 복합키여야 한다 ------
SELECT c.table_name, c.constraint_name, cc.position, cc.column_name
  FROM all_constraints c, all_cons_columns cc
 WHERE c.owner='AIMS_DEV' AND c.constraint_type='P'
   AND cc.owner=c.owner AND cc.constraint_name=c.constraint_name
   AND c.table_name IN (
       'T_ITSE_AI_CCTV01M','T_ITSE_AI_MODL01M','T_ITSE_DATST01M',
       'T_ITSE_SNSH_STUP01M','T_ITSE_SNSH_GTHR01L','T_ITSE_SNSH_PRPG01L',
       'T_ITSE_LBLL01L','T_ITSE_ANNT01L','T_ITSE_AI_DGNST01L',
       'T_ITSE_AI_MVPCT_DGNST01L','T_ITSE_AI_DRF_DGNST01L','T_ITSE_AI_MODL_OP01L')
 ORDER BY c.table_name, cc.position;


-- ---- [상세 7] 테이블스페이스 배치 -------------------------------------------
--  마스터 4개 -> TS_AIMS_DATA / 이력 8개 -> TS_AIMS_HIST_DATA
SELECT table_name, tablespace_name, partitioned
  FROM all_tables
 WHERE owner='AIMS_DEV' AND table_name IN (
       'T_ITSE_AI_CCTV01M','T_ITSE_AI_MODL01M','T_ITSE_DATST01M',
       'T_ITSE_SNSH_STUP01M','T_ITSE_SNSH_GTHR01L','T_ITSE_SNSH_PRPG01L',
       'T_ITSE_LBLL01L','T_ITSE_ANNT01L','T_ITSE_AI_DGNST01L',
       'T_ITSE_AI_MVPCT_DGNST01L','T_ITSE_AI_DRF_DGNST01L','T_ITSE_AI_MODL_OP01L')
 ORDER BY tablespace_name, table_name;


-- ---- [상세 8] 컬럼 수 대조 — UT(28629) AIMSC_DEV 와 같아야 한다 -------------
--  기대값: AI_CCTV01M 9 / AI_MODL01M 19 / DATST01M 14 / SNSH_STUP01M 7
--          SNSH_GTHR01L 7 / SNSH_PRPG01L 4 / LBLL01L 7 / ANNT01L 7
--          AI_DGNST01L 5 / AI_MVPCT_DGNST01L 11 / AI_DRF_DGNST01L 11
--          AI_MODL_OP01L 12
SELECT table_name, COUNT(*) AS columns
  FROM all_tab_columns
 WHERE owner='AIMS_DEV' AND table_name IN (
       'T_ITSE_AI_CCTV01M','T_ITSE_AI_MODL01M','T_ITSE_DATST01M',
       'T_ITSE_SNSH_STUP01M','T_ITSE_SNSH_GTHR01L','T_ITSE_SNSH_PRPG01L',
       'T_ITSE_LBLL01L','T_ITSE_ANNT01L','T_ITSE_AI_DGNST01L',
       'T_ITSE_AI_MVPCT_DGNST01L','T_ITSE_AI_DRF_DGNST01L','T_ITSE_AI_MODL_OP01L')
 GROUP BY table_name ORDER BY table_name;
