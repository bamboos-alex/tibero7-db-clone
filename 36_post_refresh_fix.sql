-- ============================================================================
--  갱신 후 보정 — tbimport 가 만들지 못한 객체 2개    ** 실제 변경이 일어난다 **
--  대상: 2차 UT  192.168.0.101:28629 / TAIMS / 스키마 AIMS_DEV
-- ============================================================================
--
--  2026-09-08 refresh(refresh_20260908_190326.log) 결과: 건수 324/324 일치.
--  다만 아래 두 객체는 적재 중 생성이 실패해 타겟에 없다. 이 스크립트가 채운다.
--
--  실행 (반드시 AIMS_DEV 로 접속할 것 — MV 본문이 이름을 수식 없이 참조한다):
--    docker exec -it tibero7_ut_tablename bash -lc \
--      'cd /tmp/tbmig && tbsql aims_dev/aims_dev@TAIMS @36_post_refresh_fix.sql'
--
--  ** 이 스크립트에는 DROP 이 한 줄도 없다. ** 순수 추가만 한다.
--  이미 있으면 그 문장만 "이미 있음" 으로 실패하고 나머지는 계속 진행된다.
--
-- ----------------------------------------------------------------------------
--  [1] T_ITSE_EQPM_SOP_STPG01L  —  왜 실패했나
-- ----------------------------------------------------------------------------
--    적재 오류: TBR-7163: Specified partition values are incorrect.
--
--    파티션 키 SOP_STPG_DTTM 의 타입이 **VARCHAR2(14)** 인데, 원천의 파티션 경계가
--    TO_DATE(...) 즉 DATE 값으로 잡혀 있다. 문자열 키에 날짜 경계라 Tibero 가
--    CREATE 를 거부한다. 원천 실측(2026-09-08):
--
--      SOP_STPG_DTTM  VARCHAR2(14) NOT NULL      <- 키
--      P202607  VALUES LESS THAN (TO_DATE('20260801','YYYYMMDD'))
--      P202608  VALUES LESS THAN (TO_DATE('20260901000000','YYYYMMDDHH24MISS'))
--      P202609  VALUES LESS THAN (TO_DATE('20261001000000','YYYYMMDDHH24MISS'))
--      PMAX     VALUES LESS THAN (MAXVALUE)
--
--    원천에는 이 상태로 테이블이 존재한다(행 0건). 어떤 경로로 만들어졌는지는 알 수
--    없으나, 같은 DDL 을 다시 실행하면 이 버전에서는 통과하지 못한다.
--    => 경계를 키 타입에 맞춰 **문자열**로 바꾼다. 'YYYYMMDDHH24MISS' 는 자리수가
--       고정이라 사전순 = 시간순이므로 의도한 구간이 그대로 유지된다.
--
--    ** 원천 쪽 정의가 어긋나 있다는 뜻이다. 담당자에게 알릴 것. **
--
--    tbimport 는 CREATE 가 실패하면서 이 테이블의 PK·NOT NULL 도 만들지 못했다.
--    원천 DBMS_METADATA 실측대로 함께 넣는다.
--
-- ----------------------------------------------------------------------------
--  [2] MV_ITSE_CCTV_STAT01N  —  왜 실패했나
-- ----------------------------------------------------------------------------
--    적재 오류: TBR-8088: View V_ITSE_CCTV01M has errors.
--
--    생성 순서 문제다. 이 MV 는 뷰 V_ITSE_CCTV01M 을 참조하는데, 적재 시점에 그 뷰가
--    아직 무효였다. 뷰가 뷰를 참조하는 구조(87건)라 tbimport 는 순서를 보장하지 못한다.
--    적재 후 07_recompile_invalid.sql 이 뷰를 되살리지만, MV 는 애초에 만들어지지
--    않았으므로 재컴파일로는 복구되지 않는다.
--
--    2026-09-08 현재 V_ITSE_CCTV01M 은 VALID 다. 지금 만들면 된다.
--    아래 본문은 적재 로그에 남은 문장 그대로다 (수정하지 않았다).
--
-- ----------------------------------------------------------------------------
--  손대지 않는 것
-- ----------------------------------------------------------------------------
--    무효 객체 2개 — AIMS_DEV.V_ITSE_PCTR_CNTR_STAT01L (뷰),
--                    AIMSC_DEV.P_AAAA_PRTT_TBL_MGMT (패키지 바디)
--      => **원천에도 똑같이 무효다.** 충실히 복제된 것이라 여기서 고칠 일이 아니다.
--
--    GRANT READ/WRITE ON DIRECTORY "USER_PATH" 실패 (TBR-7071)
--      => 타겟에 DIRECTORY 객체가 없어서다. 2026-08-13 이관 때도 같았고 그동안
--         UT 사용에 문제가 없었다. 필요해지면 SYS 로 DIRECTORY 를 만들어야 한다.
-- ============================================================================

SET LINESIZE 300
SET PAGESIZE 200


PROMPT ================================================================
PROMPT [0] 사전 확인 — 없는 것이 맞는지 본다 (나오면 이미 있는 것)
PROMPT ================================================================
COL OBJECT_NAME FORMAT A32
COL OBJECT_TYPE FORMAT A20
SELECT OBJECT_NAME, OBJECT_TYPE, STATUS
  FROM ALL_OBJECTS
 WHERE OWNER = 'AIMS_DEV'
   AND OBJECT_NAME IN ('T_ITSE_EQPM_SOP_STPG01L', 'MV_ITSE_CCTV_STAT01N')
 ORDER BY OBJECT_NAME;

PROMPT -- 참조 대상 뷰가 VALID 여야 [2] 가 성공한다
SELECT OBJECT_NAME, STATUS FROM ALL_OBJECTS
 WHERE OWNER = 'AIMS_DEV' AND OBJECT_NAME = 'V_ITSE_CCTV01M';


PROMPT ================================================================
PROMPT [1] T_ITSE_EQPM_SOP_STPG01L  (파티션 경계를 문자열로)
PROMPT ================================================================

CREATE TABLE T_ITSE_EQPM_SOP_STPG01L
(
	"SOP_STPG_DTTM"   VARCHAR(14 BYTE)   NOT NULL,
	"EQPM_ID"         VARCHAR(50 BYTE)   NOT NULL,
	"SOP_STAT_CD"     VARCHAR(2 BYTE)    NOT NULL,
	"SOP_STPG_RESN"   VARCHAR(1000 BYTE),
	"SOP_RSPT_DTTM"   VARCHAR(14 BYTE),
	"LSTTM_MODFR_ID"  VARCHAR(30 BYTE)   NOT NULL,
	"LSTTM_ALTR_DTTM" DATE               NOT NULL,
	CONSTRAINT "PK_ITSE_EQPM_SOP_STPG01L" PRIMARY KEY ("SOP_STPG_DTTM", "EQPM_ID")
		USING INDEX TABLESPACE "TS_AIMS_HIST_IDX" PCTFREE 10 INITRANS 2
)
TABLESPACE "TS_AIMS_HIST_DATA"
PCTFREE 10
INITRANS 2
PARTITION BY RANGE("SOP_STPG_DTTM")
(
	PARTITION "P202607" VALUES LESS THAN ('20260801000000') TABLESPACE "TS_AIMS_HIST_DATA",
	PARTITION "P202608" VALUES LESS THAN ('20260901000000') TABLESPACE "TS_AIMS_HIST_DATA",
	PARTITION "P202609" VALUES LESS THAN ('20261001000000') TABLESPACE "TS_AIMS_HIST_DATA",
	PARTITION "PMAX"    VALUES LESS THAN (MAXVALUE)         TABLESPACE "TS_AIMS_HIST_DATA"
);


PROMPT ================================================================
PROMPT [2] MV_ITSE_CCTV_STAT01N  (적재 로그 원문 그대로)
PROMPT ================================================================

CREATE MATERIALIZED VIEW "MV_ITSE_CCTV_STAT01N" 
(
	"EQPM_ID",
	"TRFC_INSR_NO_CTNT",
	"TRFC_FCLTS_TYPE_CD",
	"TRFC_FCLTS_TYPE_NM",
	"TRFC_EQPM_TYPE_CD",
	"TRFC_EQPM_TYPE_NM",
	"MGMT_HDQR_ID",
	"MGMT_HDQR_NM",
	"MGMT_MTNOF_ID",
	"MGMT_MTNOF_NM",
	"ROUTE_NO",
	"ROUTE_NM",
	"DRVE_DRCT_CD",
	"ROUTE_DSTNC",
	"LTTD",
	"LGTD",
	"INFO_GTHR_DTTM",
	"CMNC_STAT_CLSS_CD",
	"CMNC_STAT_CLSS_NM",
	"AC_NRML_YN",
	"FRDOR_OPNG_YN",
	"BKDR_OPNG_YN",
	"FAN_OPRN_YN",
	"UPS_BTRY_NRML_YN",
	"HTR_MOVMT_YN",
	"UPS_NRML_YN",
	"VIDEO_INPUT_NRML_YN",
	"TMPRT_HMDT_SNSR_NRML_YN",
	"VDS_CMNC_ABNR_YN",
	"RWIS_CMNC_ABNR_YN",
	"CAMR_CMNC_ABNR_YN",
	"UADO_CTRL_MOVMT_YN",
	"LFRT_CTRL_MOVMT_YN",
	"FCUS_CTRL_MOVMT_YN",
	"ENCLS_INSD_TMPRT_VAL",
	"CCTV_INPUT_VLTG_VAL",
	"UPS_BTRY_RSQN_VAL",
	"UPS_LOAD_AMNT_VAL",
	"UPS_OTPT_VLTG_VAL",
	"UPS_INPUT_FRQC_VAL",
	"UPS_OTPT_FRQC_VAL",
	"EXTL_TMPRT_VAL",
	"EXTL_HMDT_VAL",
	"WTHR_INFO_WDDR_VAL",
	"WTHR_INFO_WDSD_VAL",
	"VBLE_DSTNE",
	"WTHR_INFO_DALY_PCTT",
	"WTHR_INFO_DALY_SNAU",
	"GGUP_AVG_SPED",
	"DWNW_AVG_SPED",
	"CAMR_LFRT_RTTN_VAL",
	"CAMR_UADO_INCLN_VAL",
	"CAMR_ZOOM_VAL",
	"CAMR_FCUS_VAL",
	"DGTL_INPUT_VAL",
	"ODN1_ANLG_INPUT_VAL",
	"ODN2_ANLG_INPUT_VAL",
	"LSTTM_MODFR_ID",
	"LSTTM_ALTR_DTTM"
)
NOPARALLEL 
BUILD IMMEDIATE 
REFRESH FORCE ON DEMAND 
DISABLE QUERY REWRITE 
AS SELECT
  A.EQPM_ID,
  A.TRFC_INSR_NO_CTNT,
  A.TRFC_FCLTS_TYPE_CD,
  A.TRFC_FCLTS_TYPE_NM,
  A.TRFC_EQPM_TYPE_CD,
  A.TRFC_EQPM_TYPE_NM,
  A.MGMT_HDQR_ID,
  A.MGMT_HDQR_NM,
  A.MGMT_MTNOF_ID,
  A.MGMT_MTNOF_NM,
  A.ROUTE_NO,
  A.ROUTE_NM,
  A.DRVE_DRCT_CD,
  A.ROUTE_DSTNC,
  A.LTTD,
  A.LGTD,
  S.INFO_GTHR_DTTM,
--  CASE
--    WHEN S.INFO_GTHR_DTTM >= TO_CHAR(SYSDATE-5/24/60,'YYYYMMDDHH24MISS') THEN '1'
--    ELSE '0' 
--  END AS CMNC_STAT_CLSS_CD,
  CASE WHEN A.EQPM_ID='1000CTX00100' THEN '0' ELSE '1' END AS CMNC_STAT_CLSS_CD,
--  CASE
--    WHEN S.INFO_GTHR_DTTM >= TO_CHAR(SYSDATE-5/24/60,'YYYYMMDDHH24MISS') THEN '정상'
--    ELSE '불량'
--  END AS CMNC_STAT_CLSS_NM,
  CASE WHEN A.EQPM_ID='1000CTX00100' THEN '불량' ELSE '정상' END AS CMNC_STAT_CLSS_NM,
  S.AC_NRML_YN,
  S.FRDOR_OPNG_YN,
  S.BKDR_OPNG_YN,
  S.FAN_OPRN_YN,
  S.UPS_BTRY_NRML_YN,
  S.HTR_MOVMT_YN,
  S.UPS_NRML_YN,
  S.VIDEO_INPUT_NRML_YN,
  S.TMPRT_HMDT_SNSR_NRML_YN,
  S.VDS_CMNC_ABNR_YN,
  S.RWIS_CMNC_ABNR_YN,
  S.CAMR_CMNC_ABNR_YN,
  S.UADO_CTRL_MOVMT_YN,
  S.LFRT_CTRL_MOVMT_YN,
  S.FCUS_CTRL_MOVMT_YN,
  S.ENCLS_INSD_TMPRT_VAL,
  S.CCTV_INPUT_VLTG_VAL,
  S.UPS_BTRY_RSQN_VAL,
  S.UPS_LOAD_AMNT_VAL,
  S.UPS_OTPT_VLTG_VAL,
  S.UPS_INPUT_FRQC_VAL,
  S.UPS_OTPT_FRQC_VAL,
  S.EXTL_TMPRT_VAL,
  S.EXTL_HMDT_VAL,
  S.WTHR_INFO_WDDR_VAL,
  S.WTHR_INFO_WDSD_VAL,
  S.VBLE_DSTNE,
  S.WTHR_INFO_DALY_PCTT,
  S.WTHR_INFO_DALY_SNAU,
  S.GGUP_AVG_SPED,
  S.DWNW_AVG_SPED,
  S.CAMR_LFRT_RTTN_VAL,
  S.CAMR_UADO_INCLN_VAL,
  S.CAMR_ZOOM_VAL,
  S.CAMR_FCUS_VAL,
  S.DGTL_INPUT_VAL,
  S.ODN1_ANLG_INPUT_VAL,
  S.ODN2_ANLG_INPUT_VAL,
  S.LSTTM_MODFR_ID,
  S.LSTTM_ALTR_DTTM
FROM V_ITSE_CCTV01M A
JOIN T_ITSE_CCTV_STAT_01N S ON (A.EQPM_ID = S.CCTV_ID)
;


PROMPT ================================================================
PROMPT [3] 확인 — 아래가 전부 나와야 한다
PROMPT ================================================================

PROMPT -- 3-1) 두 객체가 생겼고 VALID 인가 (2행)
SELECT OBJECT_NAME, OBJECT_TYPE, STATUS
  FROM ALL_OBJECTS
 WHERE OWNER = 'AIMS_DEV'
   AND OBJECT_NAME IN ('T_ITSE_EQPM_SOP_STPG01L', 'MV_ITSE_CCTV_STAT01N')
 ORDER BY OBJECT_NAME;

PROMPT -- 3-2) 파티션 4개와 그 경계 (P202607/P202608/P202609/PMAX)
COL PARTITION_NAME FORMAT A16
COL BOUND FORMAT A24
SELECT PARTITION_NO, PARTITION_NAME, BOUND
  FROM ALL_TAB_PARTITIONS
 WHERE OWNER = 'AIMS_DEV' AND TABLE_NAME = 'T_ITSE_EQPM_SOP_STPG01L'
 ORDER BY PARTITION_NO;

PROMPT -- 3-3) PK 가 ENABLED 인가 (1행)
COL CONSTRAINT_NAME FORMAT A32
SELECT CONSTRAINT_NAME, CONSTRAINT_TYPE, STATUS
  FROM ALL_CONSTRAINTS
 WHERE OWNER = 'AIMS_DEV' AND TABLE_NAME = 'T_ITSE_EQPM_SOP_STPG01L'
   AND CONSTRAINT_TYPE = 'P';

PROMPT -- 3-4) MV 에 데이터가 실렸는가 (BUILD IMMEDIATE 라 0 이면 확인 필요)
SELECT COUNT(*) AS MV_건수 FROM MV_ITSE_CCTV_STAT01N;

PROMPT -- 3-5) 무효 객체 — 원천과 같은 2개만 남아야 한다
SELECT OWNER, OBJECT_TYPE, OBJECT_NAME
  FROM ALL_OBJECTS
 WHERE OWNER IN ('AIMS_EX','AIMS_DEV','AIMSC_DEV') AND STATUS <> 'VALID'
 ORDER BY OWNER, OBJECT_NAME;

PROMPT ================================================================
PROMPT 끝. 다음은 4단계 AQ 재생성 (17_aq_tables_ddl.sql)
PROMPT ================================================================
EXIT;
