-- ============================================================================
-- 機種別条件別集計クエリ
-- ============================================================================
-- 
-- アイランド秋葉原店のスロットデータを、指定期間内で機種ごと・条件ごとに集計
-- 
-- パラメータ:
--   @DATE_FROM     - 集計開始日 (YYYYMMDD形式)
--   @DATE_TO       - 集計終了日 (YYYYMMDD形式)
--
-- 出力カラム:
--   condition_type  - 条件カテゴリ (全期間, 曜日, 日種別, 下一桁, 日ゾロ目, 月日ゾロ, 周年日, 月初, 月末)
--   condition_value - 条件値 (月, 火, ..., 土日祝, 平日, 0-9, ゾロ目日, 月日ゾロ, 20日, 1日, 末日)
--   machine         - 機種名
--   period_from     - 集計期間開始日 (その機種の最初のデータ日付)
--   period_to       - 集計期間終了日 (その機種の最後のデータ日付)
--   sample_days     - サンプル日数 (COUNT DISTINCT date)
--   sample_units    - サンプル台数 (COUNT)
--   total_diff      - 合計差枚 (SUM diff)
--   avg_diff        - 平均差枚 (SUM/COUNT)
--   total_game      - 総回転数 (SUM game)
--   win_rate        - 勝率 (SUM win / COUNT)
--   payout_rate     - 出率 ((SUM(game)*3 + SUM(diff)) / (SUM(game)*3))
--
-- 条件カテゴリ一覧:
--   - 全期間: 全期間
--   - 曜日: 曜日ごと (月, 火, 水, 木, 金, 土, 日)
--   - 日種別: 土日祝 / 平日
--   - 下一桁: 日の下一桁 (0, 1, 2, ..., 9)
--   - 日ゾロ目: 日がゾロ目 (11日, 22日)
--   - 月日ゾロ: 月日ゾロ (1/1, 1/11, 2/2, 2/22, ..., 11/11, 12/12)
--   - 周年日: 月周年日 (毎月20日)
--   - 月初: 月初 (毎月1日)
--   - 月末: 月末 (月の最終日)
-- ============================================================================

-- ============================================================================
-- 1. パラメータ定義
-- ============================================================================
WITH params AS (
  SELECT
    CAST(@DATE_FROM AS STRING) AS date_from,
    CAST(@DATE_TO AS STRING) AS date_to,
    'アイランド秋葉原店' AS hole
),

-- ============================================================================
-- 2. アイランド秋葉原店 台番マッピング (2025/11/02以前 -> 2025/11/03以降)
-- ============================================================================
machine_number_mapping_island AS (
  SELECT old_number, new_number FROM UNNEST([
    STRUCT(600 AS old_number, 600 AS new_number),
    STRUCT(601, 601), STRUCT(602, 602), STRUCT(603, 603), STRUCT(605, 605),
    STRUCT(606, 606), STRUCT(607, 607), STRUCT(608, 608), STRUCT(610, 610),
    STRUCT(611, 611), STRUCT(612, 612), STRUCT(613, 613), STRUCT(615, 615),
    STRUCT(616, 616), STRUCT(617, 617), STRUCT(618, 618),
    STRUCT(620, 623), STRUCT(621, 625), STRUCT(622, 626), STRUCT(623, 627),
    STRUCT(625, 628), STRUCT(626, 630), STRUCT(627, 631), STRUCT(628, 632),
    STRUCT(630, 633), STRUCT(631, 635), STRUCT(632, 636), STRUCT(633, 637),
    STRUCT(635, 638), STRUCT(636, 650), STRUCT(637, 651), STRUCT(638, 652),
    STRUCT(650, 653), STRUCT(651, 655), STRUCT(652, 656), STRUCT(653, 657),
    STRUCT(655, 658), STRUCT(656, 660), STRUCT(657, 661), STRUCT(658, 662),
    STRUCT(660, 663), STRUCT(661, 665), STRUCT(662, 666), STRUCT(663, 667),
    STRUCT(665, 668), STRUCT(666, 670), STRUCT(667, 671), STRUCT(668, 672),
    STRUCT(670, 673), STRUCT(671, 675), STRUCT(672, 676), STRUCT(673, 677),
    STRUCT(675, 678), STRUCT(676, 680), STRUCT(677, 681), STRUCT(678, 682),
    STRUCT(680, 683), STRUCT(681, 685), STRUCT(682, 686), STRUCT(683, 687),
    STRUCT(685, 688), STRUCT(686, 700), STRUCT(687, 701), STRUCT(688, 702),
    STRUCT(700, 703), STRUCT(701, 705), STRUCT(702, 706), STRUCT(703, 707),
    STRUCT(705, 708), STRUCT(706, 710), STRUCT(707, 711), STRUCT(708, 712),
    STRUCT(710, 713), STRUCT(711, 715), STRUCT(712, 716), STRUCT(713, 717),
    STRUCT(715, 718), STRUCT(716, 720), STRUCT(717, 721), STRUCT(718, 722),
    STRUCT(720, 723), STRUCT(721, 725), STRUCT(722, 726), STRUCT(723, 727),
    STRUCT(725, 728), STRUCT(726, 730), STRUCT(727, 731), STRUCT(728, 732),
    STRUCT(730, 733), STRUCT(731, 735), STRUCT(732, 736), STRUCT(733, 737),
    STRUCT(735, 738), STRUCT(736, 750), STRUCT(737, 751), STRUCT(738, 752),
    STRUCT(750, 753), STRUCT(751, 755), STRUCT(752, 756), STRUCT(753, 757),
    STRUCT(755, 758), STRUCT(756, 760), STRUCT(757, 761), STRUCT(758, 762),
    STRUCT(760, 763), STRUCT(761, 765), STRUCT(762, 766), STRUCT(763, 767),
    STRUCT(765, 768), STRUCT(766, 770), STRUCT(767, 771), STRUCT(768, 772),
    STRUCT(770, 773), STRUCT(771, 775), STRUCT(772, 776), STRUCT(773, 777),
    STRUCT(775, 778), STRUCT(776, 780), STRUCT(777, 781), STRUCT(778, 782),
    STRUCT(780, 783), STRUCT(781, 785), STRUCT(782, 786), STRUCT(783, 787),
    STRUCT(785, 788), STRUCT(786, 800), STRUCT(787, 801), STRUCT(788, 802),
    STRUCT(800, 803), STRUCT(801, 805), STRUCT(802, 806), STRUCT(803, 807),
    STRUCT(805, 808), STRUCT(806, 810), STRUCT(807, 811), STRUCT(808, 812),
    STRUCT(810, 813), STRUCT(811, 815), STRUCT(812, 816), STRUCT(813, 817),
    STRUCT(815, 818), STRUCT(816, 820), STRUCT(817, 821), STRUCT(818, 822),
    STRUCT(820, 823), STRUCT(821, 825), STRUCT(822, 826), STRUCT(823, 827),
    STRUCT(825, 828), STRUCT(826, 830), STRUCT(827, 831), STRUCT(828, 832),
    STRUCT(830, 833), STRUCT(831, 835), STRUCT(832, 836), STRUCT(833, 837),
    STRUCT(835, 838), STRUCT(836, 850), STRUCT(837, 852), STRUCT(838, 853),
    STRUCT(850, 855), STRUCT(851, 856), STRUCT(852, 857), STRUCT(853, 858),
    STRUCT(855, 860), STRUCT(856, 861), STRUCT(857, 862), STRUCT(858, 863),
    STRUCT(860, 865), STRUCT(861, 866), STRUCT(862, 867), STRUCT(863, 868),
    STRUCT(865, 870), STRUCT(866, 871), STRUCT(867, 872), STRUCT(868, 873),
    STRUCT(870, 875), STRUCT(871, 876), STRUCT(872, 877), STRUCT(873, 878),
    STRUCT(875, 880), STRUCT(876, 881), STRUCT(877, 882), STRUCT(878, 883),
    STRUCT(880, 886), STRUCT(881, 887), STRUCT(882, 888), STRUCT(883, 1000),
    STRUCT(885, 1001), STRUCT(886, 1002), STRUCT(887, 1003), STRUCT(888, 1005),
    STRUCT(1000, 1006), STRUCT(1001, 1007), STRUCT(1002, 1008), STRUCT(1003, 1010),
    STRUCT(1005, 1011), STRUCT(1006, 1012), STRUCT(1007, 1013), STRUCT(1008, 1015),
    STRUCT(1010, 1016), STRUCT(1011, 1017), STRUCT(1012, 1018), STRUCT(1013, 1020),
    STRUCT(1015, 1021), STRUCT(1016, 1022), STRUCT(1017, 1023), STRUCT(1018, 1025),
    STRUCT(1020, 1026), STRUCT(1021, 1027), STRUCT(1022, 1028), STRUCT(1023, 1030),
    STRUCT(1025, 1031), STRUCT(1026, 1032), STRUCT(1027, 1033), STRUCT(1028, 1035),
    STRUCT(1030, 1036), STRUCT(1031, 1037), STRUCT(1032, 1038), STRUCT(1033, 1050),
    STRUCT(1035, 1051), STRUCT(1036, 1052), STRUCT(1037, 1053), STRUCT(1038, 1055),
    STRUCT(1050, 1056), STRUCT(1051, 1057), STRUCT(1052, 1058), STRUCT(1053, 1060),
    STRUCT(1055, 1061), STRUCT(1056, 1062), STRUCT(1057, 1063), STRUCT(1058, 1065),
    STRUCT(1060, 1066), STRUCT(1061, 1067), STRUCT(1062, 1068), STRUCT(1063, 1070),
    STRUCT(1065, 1071), STRUCT(1066, 1072), STRUCT(1067, 1073), STRUCT(1068, 1075),
    STRUCT(1070, 1076), STRUCT(1071, 1077), STRUCT(1072, 1078), STRUCT(1073, 1080),
    STRUCT(1075, 1081), STRUCT(1076, 1082), STRUCT(1077, 1083), STRUCT(1078, 1085),
    STRUCT(1080, 1086), STRUCT(1081, 1087), STRUCT(1082, 1088), STRUCT(1083, 1100),
    STRUCT(1085, 1101), STRUCT(1086, 1102), STRUCT(1087, 1103), STRUCT(1088, 1105),
    STRUCT(1100, 1106), STRUCT(1101, 1107), STRUCT(1102, 1108), STRUCT(1103, 1110),
    STRUCT(1105, 1111), STRUCT(1106, 1112), STRUCT(1107, 1113), STRUCT(1108, 1115),
    STRUCT(1110, 1116), STRUCT(1111, 1117), STRUCT(1112, 1118), STRUCT(1113, 1120),
    STRUCT(1115, 1121), STRUCT(1116, 1122), STRUCT(1117, 1123), STRUCT(1118, 1125),
    STRUCT(1120, 1126), STRUCT(1121, 1127), STRUCT(1122, 1128), STRUCT(1123, 1130),
    STRUCT(1125, 1131), STRUCT(1126, 1132), STRUCT(1127, 1133), STRUCT(1128, 1135),
    STRUCT(1130, 1136), STRUCT(1131, 1137), STRUCT(1132, 1138), STRUCT(1133, 1150),
    STRUCT(1135, 1151), STRUCT(1136, 1152), STRUCT(1137, 1153), STRUCT(1138, 1155),
    STRUCT(1150, 1156), STRUCT(1151, 1157), STRUCT(1152, 1158), STRUCT(1153, 1160),
    STRUCT(1155, 1161), STRUCT(1156, 1162), STRUCT(1157, 1163), STRUCT(1158, 1165),
    STRUCT(1160, 1166), STRUCT(1161, 1167), STRUCT(1162, 1168), STRUCT(1163, 1170),
    STRUCT(1165, 1171), STRUCT(1166, 1172), STRUCT(1167, 1173), STRUCT(1168, 1175),
    STRUCT(1170, 1176), STRUCT(1171, 1177), STRUCT(1172, 1178), STRUCT(1173, 1180),
    STRUCT(1175, 1181), STRUCT(1176, 1182), STRUCT(1177, 1183), STRUCT(1178, 1185),
    STRUCT(1180, 1186), STRUCT(1181, 1187), STRUCT(1182, 1188), STRUCT(1183, 1200),
    STRUCT(1185, 1201), STRUCT(1186, 1202), STRUCT(1187, 1203), STRUCT(1188, 1207),
    STRUCT(1200, 1208), STRUCT(1201, 1210), STRUCT(1202, 1211), STRUCT(1203, 1212),
    STRUCT(1205, 1213), STRUCT(1206, 1215), STRUCT(1207, 1216), STRUCT(1208, 1217),
    STRUCT(1210, 1218), STRUCT(1211, 1220), STRUCT(1212, 1221), STRUCT(1213, 1222),
    STRUCT(1215, 1223), STRUCT(1216, 1225), STRUCT(1217, 1226), STRUCT(1218, 1227),
    STRUCT(1220, 1228), STRUCT(1221, 1230), STRUCT(1222, 1231), STRUCT(1223, 1232),
    STRUCT(1225, 1233), STRUCT(1226, 1235), STRUCT(1227, 1236), STRUCT(1228, 1237),
    STRUCT(1230, 1238), STRUCT(1231, 1250), STRUCT(1232, 1251), STRUCT(1233, 1252),
    STRUCT(1235, 1253), STRUCT(1236, 1255), STRUCT(1237, 1256), STRUCT(1238, 1257),
    STRUCT(1250, 1258), STRUCT(1251, 1260), STRUCT(1252, 1261), STRUCT(1253, 1262),
    STRUCT(1255, 1263), STRUCT(1256, 1265), STRUCT(1257, 1266), STRUCT(1258, 1267),
    STRUCT(1260, 1268), STRUCT(1261, 1270), STRUCT(1262, 1271), STRUCT(1263, 1272),
    STRUCT(1265, 1273), STRUCT(1266, 1275), STRUCT(1267, 1276), STRUCT(1268, 1277),
    STRUCT(1270, 1278), STRUCT(1271, 1280), STRUCT(1272, 1281), STRUCT(1273, 1282),
    STRUCT(1275, 1283), STRUCT(1276, 1285), STRUCT(1277, 1286), STRUCT(1278, 1287),
    STRUCT(1280, 1288), STRUCT(1281, 1300), STRUCT(1282, 1301), STRUCT(1283, 1302),
    STRUCT(1285, 1303), STRUCT(1286, 1305), STRUCT(1287, 1306), STRUCT(1288, 1307),
    STRUCT(1300, 1308)
  ])
),

-- ============================================================================
-- 3. 祝日データ
-- ============================================================================
holidays AS (
  SELECT date AS holiday_date
  FROM params, UNNEST(GENERATE_DATE_ARRAY(
    PARSE_DATE('%Y%m%d', params.date_from), 
    PARSE_DATE('%Y%m%d', params.date_to)
  )) AS date
  WHERE bqfunc.holidays_in_japan__us.holiday_name(date) IS NOT NULL
),

-- ============================================================================
-- 4. 日別データ取得・重複排除・台番補正・日付フラグ生成
-- ============================================================================
base_data AS (
  SELECT
    d.date,
    d.hole,
    d.machine,
    -- 台番補正
    CASE
      WHEN d.hole = 'アイランド秋葉原店' 
        AND PARSE_DATE('%Y-%m-%d', d.date) <= DATE('2025-11-02')
      THEN COALESCE(m.new_number, d.machine_number)
      ELSE d.machine_number
    END AS machine_number,
    d.diff,
    d.game,
    d.win,
    PARSE_DATE('%Y-%m-%d', d.date) AS parsed_date,
    -- 曜日（日本語表記）
    CASE 
      WHEN EXTRACT(DAYOFWEEK FROM PARSE_DATE('%Y-%m-%d', d.date)) = 1 THEN '日'
      WHEN EXTRACT(DAYOFWEEK FROM PARSE_DATE('%Y-%m-%d', d.date)) = 2 THEN '月'
      WHEN EXTRACT(DAYOFWEEK FROM PARSE_DATE('%Y-%m-%d', d.date)) = 3 THEN '火'
      WHEN EXTRACT(DAYOFWEEK FROM PARSE_DATE('%Y-%m-%d', d.date)) = 4 THEN '水'
      WHEN EXTRACT(DAYOFWEEK FROM PARSE_DATE('%Y-%m-%d', d.date)) = 5 THEN '木'
      WHEN EXTRACT(DAYOFWEEK FROM PARSE_DATE('%Y-%m-%d', d.date)) = 6 THEN '金'
      WHEN EXTRACT(DAYOFWEEK FROM PARSE_DATE('%Y-%m-%d', d.date)) = 7 THEN '土'
    END AS day_of_week,
    -- 平日・週末・祝日（週末優先）
    CASE 
      WHEN EXTRACT(DAYOFWEEK FROM PARSE_DATE('%Y-%m-%d', d.date)) IN (1, 7) THEN '土日祝'
      WHEN h.holiday_date IS NOT NULL THEN '土日祝'
      ELSE '平日'
    END AS day_type,
    -- 日付の末尾の数字
    CAST(MOD(EXTRACT(DAY FROM PARSE_DATE('%Y-%m-%d', d.date)), 10) AS STRING) AS last_digit,
    -- 日がゾロ目（11, 22）
    EXTRACT(DAY FROM PARSE_DATE('%Y-%m-%d', d.date)) IN (11, 22) AS is_day_zorome,
    -- 月日ゾロ (月=日 OR 月と日がゾロ目で一致: 1/1, 1/11, 2/2, 2/22, ..., 11/11, 12/12)
    (EXTRACT(MONTH FROM PARSE_DATE('%Y-%m-%d', d.date)) = EXTRACT(DAY FROM PARSE_DATE('%Y-%m-%d', d.date)))
    OR (EXTRACT(MONTH FROM PARSE_DATE('%Y-%m-%d', d.date)) * 11 = EXTRACT(DAY FROM PARSE_DATE('%Y-%m-%d', d.date))) AS is_month_day_match,
    -- 月周年日（毎月20日）
    EXTRACT(DAY FROM PARSE_DATE('%Y-%m-%d', d.date)) = 20 AS is_anniversary,
    -- 月初（毎月1日）
    EXTRACT(DAY FROM PARSE_DATE('%Y-%m-%d', d.date)) = 1 AS is_first_day,
    -- 月末
    PARSE_DATE('%Y-%m-%d', d.date) = LAST_DAY(PARSE_DATE('%Y-%m-%d', d.date)) AS is_last_day,
    ROW_NUMBER() OVER (PARTITION BY d.id ORDER BY d.timestamp DESC) AS row_num
  FROM `yobun-450512.scraped_data.data_*` d
  CROSS JOIN params p
  LEFT JOIN machine_number_mapping_island m
    ON d.hole = 'アイランド秋葉原店'
    AND PARSE_DATE('%Y-%m-%d', d.date) <= DATE('2025-11-02')
    AND d.machine_number = m.old_number
  LEFT JOIN holidays h
    ON PARSE_DATE('%Y-%m-%d', d.date) = h.holiday_date
  WHERE d._TABLE_SUFFIX BETWEEN p.date_from AND p.date_to
    AND d.hole = p.hole
    AND d.game IS NOT NULL
    AND d.game > 0
),

-- ============================================================================
-- 5. 重複排除済みデータ
-- ============================================================================
filtered_data AS (
  SELECT * FROM base_data WHERE row_num = 1
),

-- ============================================================================
-- 6. 条件別集計
-- ============================================================================

-- 全期間集計
agg_all AS (
  SELECT
    '全期間' AS condition_type,
    '全期間' AS condition_value,
    machine,
    MIN(date) AS period_from,
    MAX(date) AS period_to,
    COUNT(DISTINCT date) AS sample_days,
    COUNT(*) AS sample_units,
    SUM(diff) AS total_diff,
    SAFE_DIVIDE(SUM(diff), COUNT(*)) AS avg_diff,
    SUM(game) AS total_game,
    SAFE_DIVIDE(SUM(win), COUNT(*)) AS win_rate,
    SAFE_DIVIDE(SUM(game) * 3 + SUM(diff), SUM(game) * 3) AS payout_rate
  FROM filtered_data
  GROUP BY machine
),

-- 曜日ごと集計
agg_day_of_week AS (
  SELECT
    '曜日' AS condition_type,
    day_of_week AS condition_value,
    machine,
    MIN(date) AS period_from,
    MAX(date) AS period_to,
    COUNT(DISTINCT date) AS sample_days,
    COUNT(*) AS sample_units,
    SUM(diff) AS total_diff,
    SAFE_DIVIDE(SUM(diff), COUNT(*)) AS avg_diff,
    SUM(game) AS total_game,
    SAFE_DIVIDE(SUM(win), COUNT(*)) AS win_rate,
    SAFE_DIVIDE(SUM(game) * 3 + SUM(diff), SUM(game) * 3) AS payout_rate
  FROM filtered_data
  GROUP BY day_of_week, machine
),

-- 平日・土日祝集計
agg_day_type AS (
  SELECT
    '日種別' AS condition_type,
    day_type AS condition_value,
    machine,
    MIN(date) AS period_from,
    MAX(date) AS period_to,
    COUNT(DISTINCT date) AS sample_days,
    COUNT(*) AS sample_units,
    SUM(diff) AS total_diff,
    SAFE_DIVIDE(SUM(diff), COUNT(*)) AS avg_diff,
    SUM(game) AS total_game,
    SAFE_DIVIDE(SUM(win), COUNT(*)) AS win_rate,
    SAFE_DIVIDE(SUM(game) * 3 + SUM(diff), SUM(game) * 3) AS payout_rate
  FROM filtered_data
  GROUP BY day_type, machine
),

-- 日の下一桁集計
agg_last_digit AS (
  SELECT
    '下一桁' AS condition_type,
    CONCAT(last_digit, 'のつく日') AS condition_value,
    machine,
    MIN(date) AS period_from,
    MAX(date) AS period_to,
    COUNT(DISTINCT date) AS sample_days,
    COUNT(*) AS sample_units,
    SUM(diff) AS total_diff,
    SAFE_DIVIDE(SUM(diff), COUNT(*)) AS avg_diff,
    SUM(game) AS total_game,
    SAFE_DIVIDE(SUM(win), COUNT(*)) AS win_rate,
    SAFE_DIVIDE(SUM(game) * 3 + SUM(diff), SUM(game) * 3) AS payout_rate
  FROM filtered_data
  GROUP BY last_digit, machine
),

-- 日がゾロ目集計
agg_day_zorome AS (
  SELECT
    '日ゾロ目' AS condition_type,
    'ゾロ目日(11,22)' AS condition_value,
    machine,
    MIN(date) AS period_from,
    MAX(date) AS period_to,
    COUNT(DISTINCT date) AS sample_days,
    COUNT(*) AS sample_units,
    SUM(diff) AS total_diff,
    SAFE_DIVIDE(SUM(diff), COUNT(*)) AS avg_diff,
    SUM(game) AS total_game,
    SAFE_DIVIDE(SUM(win), COUNT(*)) AS win_rate,
    SAFE_DIVIDE(SUM(game) * 3 + SUM(diff), SUM(game) * 3) AS payout_rate
  FROM filtered_data
  WHERE is_day_zorome = TRUE
  GROUP BY machine
),

-- 月日ゾロ集計
agg_month_day_match AS (
  SELECT
    '月日ゾロ' AS condition_type,
    '月日ゾロ' AS condition_value,
    machine,
    MIN(date) AS period_from,
    MAX(date) AS period_to,
    COUNT(DISTINCT date) AS sample_days,
    COUNT(*) AS sample_units,
    SUM(diff) AS total_diff,
    SAFE_DIVIDE(SUM(diff), COUNT(*)) AS avg_diff,
    SUM(game) AS total_game,
    SAFE_DIVIDE(SUM(win), COUNT(*)) AS win_rate,
    SAFE_DIVIDE(SUM(game) * 3 + SUM(diff), SUM(game) * 3) AS payout_rate
  FROM filtered_data
  WHERE is_month_day_match = TRUE
  GROUP BY machine
),

-- 月周年日（毎月20日）集計
agg_anniversary AS (
  SELECT
    '周年日' AS condition_type,
    '月周年日(20日)' AS condition_value,
    machine,
    MIN(date) AS period_from,
    MAX(date) AS period_to,
    COUNT(DISTINCT date) AS sample_days,
    COUNT(*) AS sample_units,
    SUM(diff) AS total_diff,
    SAFE_DIVIDE(SUM(diff), COUNT(*)) AS avg_diff,
    SUM(game) AS total_game,
    SAFE_DIVIDE(SUM(win), COUNT(*)) AS win_rate,
    SAFE_DIVIDE(SUM(game) * 3 + SUM(diff), SUM(game) * 3) AS payout_rate
  FROM filtered_data
  WHERE is_anniversary = TRUE
  GROUP BY machine
),

-- 月初（毎月1日）集計
agg_first_day AS (
  SELECT
    '月初' AS condition_type,
    '月初(1日)' AS condition_value,
    machine,
    MIN(date) AS period_from,
    MAX(date) AS period_to,
    COUNT(DISTINCT date) AS sample_days,
    COUNT(*) AS sample_units,
    SUM(diff) AS total_diff,
    SAFE_DIVIDE(SUM(diff), COUNT(*)) AS avg_diff,
    SUM(game) AS total_game,
    SAFE_DIVIDE(SUM(win), COUNT(*)) AS win_rate,
    SAFE_DIVIDE(SUM(game) * 3 + SUM(diff), SUM(game) * 3) AS payout_rate
  FROM filtered_data
  WHERE is_first_day = TRUE
  GROUP BY machine
),

-- 月末集計
agg_last_day AS (
  SELECT
    '月末' AS condition_type,
    '月末' AS condition_value,
    machine,
    MIN(date) AS period_from,
    MAX(date) AS period_to,
    COUNT(DISTINCT date) AS sample_days,
    COUNT(*) AS sample_units,
    SUM(diff) AS total_diff,
    SAFE_DIVIDE(SUM(diff), COUNT(*)) AS avg_diff,
    SUM(game) AS total_game,
    SAFE_DIVIDE(SUM(win), COUNT(*)) AS win_rate,
    SAFE_DIVIDE(SUM(game) * 3 + SUM(diff), SUM(game) * 3) AS payout_rate
  FROM filtered_data
  WHERE is_last_day = TRUE
  GROUP BY machine
)

-- ============================================================================
-- 7. 最終出力（UNION ALL）
-- ============================================================================
SELECT * FROM agg_all
UNION ALL
SELECT * FROM agg_day_of_week
UNION ALL
SELECT * FROM agg_day_type
UNION ALL
SELECT * FROM agg_last_digit
UNION ALL
SELECT * FROM agg_day_zorome
UNION ALL
SELECT * FROM agg_month_day_match
UNION ALL
SELECT * FROM agg_anniversary
UNION ALL
SELECT * FROM agg_first_day
UNION ALL
SELECT * FROM agg_last_day
ORDER BY condition_type, condition_value, machine;
