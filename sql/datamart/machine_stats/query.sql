-- データマート: 台番別統計データ
-- 実行方法: BigQuery スケジュールクエリで @run_time パラメータを使用
-- 宛先テーブル: yobun-450512.datamart.machine_stats (日付パーティション)
-- 
-- 注意: @run_time は実行時刻（TIMESTAMP型）。集計日は実行日の1日前
--       DATE(@run_time,'Asia/Tokyo') でJSTの日付を取得
--       例: 12/25に実行 → 集計日は12/24
--
-- 集計期間:
--   当日から（当日を含む）: d1, d2, d3, d4, d5, d6, d7, d14, d28, mtd, all
--   前日から（当日を含まない）: prev_d1, prev_d2, prev_d3, prev_d4, prev_d5, prev_d6, prev_d7, prev_d14, prev_d28, prev_mtd, prev_all
--
-- 日付カラム:
--   target_year, target_month, target_day, target_day_last_digit
--   is_month_day_repdigit (月と日がゾロ目: 01/01, 02/02, ..., 12/12)
--   is_day_repdigit (日がゾロ目: 11, 22)
--   day_of_week_jp (曜日: 月,火,水,木,金,土,日)
--   day_type (平日/週末/祝日)
--
-- MERGE文により、同じ日付のデータは上書き、異なる日付のデータは追加される

MERGE INTO `yobun-450512.datamart.machine_stats` AS target
USING (
  -- ============================================================================
  -- 1. 重複排除: 同じ日付・店舗・台番のデータはtimestamp最新を採用
  -- ============================================================================
  WITH deduplicated_data AS (
    SELECT
      date,
      hole,
      machine,
      machine_number,
      diff,
      game,
      big,
      reg,
      combined_rate,
      max_my,
      max_mdia,
      win,
      timestamp,
      ROW_NUMBER() OVER (
        PARTITION BY date, hole, machine_number
        ORDER BY timestamp DESC
      ) AS rn
    FROM `yobun-450512.scraped_data.data_*`
    -- 集計日から最大31日前までのデータを取得（当月対応）
    -- @run_time からJSTの日付を取得して計算（_TABLE_SUFFIXはJST基準）
    WHERE _TABLE_SUFFIX BETWEEN FORMAT_DATE('%Y%m%d', DATE_SUB(DATE(@run_time, 'Asia/Tokyo'), INTERVAL 32 DAY))
                            AND FORMAT_DATE('%Y%m%d', DATE_SUB(DATE(@run_time, 'Asia/Tokyo'), INTERVAL 1 DAY))
  ),

  -- ============================================================================
  -- 2. アイランド秋葉原店 台番マッピング (2025/11/02以前 -> 2025/11/03以降)
  -- ============================================================================
  machine_number_mapping AS (
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
  -- 3. 正規化データ: 台番マッピングを適用
  --    - アイランド秋葉原店: 2025/11/02以前はマッピングテーブルで変換
  --    - エスパス秋葉原駅前店: 2025/04/20以前の2020番台以降は+2
  -- ============================================================================
  normalized_data AS (
    SELECT
      PARSE_DATE('%Y-%m-%d', d.date) AS date,
      d.hole,
      d.machine,
      -- 台番補正
      CASE
        -- アイランド秋葉原店: 2025/11/02以前はマッピングテーブルで変換
        WHEN d.hole = 'アイランド秋葉原店' 
             AND PARSE_DATE('%Y-%m-%d', d.date) <= DATE('2025-11-02')
        THEN COALESCE(m.new_number, d.machine_number)
        -- エスパス秋葉原駅前店: 2025/04/20以前の2020番台以降は+2
        WHEN d.hole = 'エスパス秋葉原駅前店' 
             AND PARSE_DATE('%Y-%m-%d', d.date) <= DATE('2025-04-20')
             AND d.machine_number >= 2020 
             AND d.machine_number < 3000
        THEN d.machine_number + 2
        -- その他: そのまま
        ELSE d.machine_number
      END AS machine_number,
      d.diff,
      d.game,
      d.win
    FROM deduplicated_data d
    LEFT JOIN machine_number_mapping m
      ON d.hole = 'アイランド秋葉原店'
      AND PARSE_DATE('%Y-%m-%d', d.date) <= DATE('2025-11-02')
      AND d.machine_number = m.old_number
    WHERE d.rn = 1
  ),

  -- ============================================================================
  -- 4. 集計日の定義（実行日の1日前、JST基準）
  -- ============================================================================
  target_date_def AS (
    SELECT DATE_SUB(DATE(@run_time, 'Asia/Tokyo'), INTERVAL 1 DAY) AS target_date
  ),

  -- ============================================================================
  -- 4.1 祝日データ（日付カラム用）
  -- ============================================================================
  holidays AS (
    SELECT date AS holiday_date
    FROM target_date_def t,
    UNNEST([t.target_date]) AS date
    WHERE bqfunc.holidays_in_japan__us.holiday_name(date) IS NOT NULL
  ),

  -- ============================================================================
  -- 5. 当日のデータから機種名を取得 (集計日の機種が基準)
  -- ============================================================================
  current_day_machines AS (
    SELECT
      n.hole,
      n.machine_number,
      n.machine
    FROM normalized_data n, target_date_def t
    WHERE n.date = t.target_date
  ),

  -- ============================================================================
  -- 6. 機種変更検出: 各台番の集計開始日を算出
  -- ============================================================================
  machine_periods AS (
    SELECT
      n.hole,
      n.machine_number,
      c.machine,
      MIN(n.date) AS start_date,
      t.target_date AS end_date
    FROM normalized_data n
    INNER JOIN current_day_machines c
      ON n.hole = c.hole
      AND n.machine_number = c.machine_number
      AND n.machine = c.machine
    CROSS JOIN target_date_def t
    GROUP BY n.hole, n.machine_number, c.machine, t.target_date
  ),

  -- ============================================================================
  -- 7. 当日データ (d1)
  -- ============================================================================
  stats_d1 AS (
    SELECT
      n.hole,
      n.machine_number,
      n.diff AS d1_diff,
      n.game AS d1_game,
      SAFE_DIVIDE(n.game * 3 + n.diff, n.game * 3) AS d1_payout_rate
    FROM normalized_data n, target_date_def t
    WHERE n.date = t.target_date
  ),

  -- ============================================================================
  -- 8. 当日から過去N日間（当日を含む）
  -- ============================================================================
  stats_d2 AS (
    SELECT n.hole, n.machine_number,
      SUM(n.diff) AS d2_diff, SUM(n.game) AS d2_game,
      SAFE_DIVIDE(SUM(n.win), COUNT(*)) AS d2_win_rate,
      SAFE_DIVIDE(SUM(n.game) * 3 + SUM(n.diff), SUM(n.game) * 3) AS d2_payout_rate
    FROM normalized_data n
    INNER JOIN current_day_machines c ON n.hole = c.hole AND n.machine_number = c.machine_number AND n.machine = c.machine
    CROSS JOIN target_date_def t
    WHERE n.date BETWEEN DATE_SUB(t.target_date, INTERVAL 1 DAY) AND t.target_date
    GROUP BY n.hole, n.machine_number
  ),

  stats_d3 AS (
    SELECT n.hole, n.machine_number,
      SUM(n.diff) AS d3_diff, SUM(n.game) AS d3_game,
      SAFE_DIVIDE(SUM(n.win), COUNT(*)) AS d3_win_rate,
      SAFE_DIVIDE(SUM(n.game) * 3 + SUM(n.diff), SUM(n.game) * 3) AS d3_payout_rate
    FROM normalized_data n
    INNER JOIN current_day_machines c ON n.hole = c.hole AND n.machine_number = c.machine_number AND n.machine = c.machine
    CROSS JOIN target_date_def t
    WHERE n.date BETWEEN DATE_SUB(t.target_date, INTERVAL 2 DAY) AND t.target_date
    GROUP BY n.hole, n.machine_number
  ),

  stats_d4 AS (
    SELECT n.hole, n.machine_number,
      SUM(n.diff) AS d4_diff, SUM(n.game) AS d4_game,
      SAFE_DIVIDE(SUM(n.win), COUNT(*)) AS d4_win_rate,
      SAFE_DIVIDE(SUM(n.game) * 3 + SUM(n.diff), SUM(n.game) * 3) AS d4_payout_rate
    FROM normalized_data n
    INNER JOIN current_day_machines c ON n.hole = c.hole AND n.machine_number = c.machine_number AND n.machine = c.machine
    CROSS JOIN target_date_def t
    WHERE n.date BETWEEN DATE_SUB(t.target_date, INTERVAL 3 DAY) AND t.target_date
    GROUP BY n.hole, n.machine_number
  ),

  stats_d5 AS (
    SELECT n.hole, n.machine_number,
      SUM(n.diff) AS d5_diff, SUM(n.game) AS d5_game,
      SAFE_DIVIDE(SUM(n.win), COUNT(*)) AS d5_win_rate,
      SAFE_DIVIDE(SUM(n.game) * 3 + SUM(n.diff), SUM(n.game) * 3) AS d5_payout_rate
    FROM normalized_data n
    INNER JOIN current_day_machines c ON n.hole = c.hole AND n.machine_number = c.machine_number AND n.machine = c.machine
    CROSS JOIN target_date_def t
    WHERE n.date BETWEEN DATE_SUB(t.target_date, INTERVAL 4 DAY) AND t.target_date
    GROUP BY n.hole, n.machine_number
  ),

  stats_d6 AS (
    SELECT n.hole, n.machine_number,
      SUM(n.diff) AS d6_diff, SUM(n.game) AS d6_game,
      SAFE_DIVIDE(SUM(n.win), COUNT(*)) AS d6_win_rate,
      SAFE_DIVIDE(SUM(n.game) * 3 + SUM(n.diff), SUM(n.game) * 3) AS d6_payout_rate
    FROM normalized_data n
    INNER JOIN current_day_machines c ON n.hole = c.hole AND n.machine_number = c.machine_number AND n.machine = c.machine
    CROSS JOIN target_date_def t
    WHERE n.date BETWEEN DATE_SUB(t.target_date, INTERVAL 5 DAY) AND t.target_date
    GROUP BY n.hole, n.machine_number
  ),

  stats_d7 AS (
    SELECT n.hole, n.machine_number,
      SUM(n.diff) AS d7_diff, SUM(n.game) AS d7_game,
      SAFE_DIVIDE(SUM(n.win), COUNT(*)) AS d7_win_rate,
      SAFE_DIVIDE(SUM(n.game) * 3 + SUM(n.diff), SUM(n.game) * 3) AS d7_payout_rate
    FROM normalized_data n
    INNER JOIN current_day_machines c ON n.hole = c.hole AND n.machine_number = c.machine_number AND n.machine = c.machine
    CROSS JOIN target_date_def t
    WHERE n.date BETWEEN DATE_SUB(t.target_date, INTERVAL 6 DAY) AND t.target_date
    GROUP BY n.hole, n.machine_number
  ),

  stats_d14 AS (
    SELECT n.hole, n.machine_number,
      SUM(n.diff) AS d14_diff, SUM(n.game) AS d14_game,
      SAFE_DIVIDE(SUM(n.win), COUNT(*)) AS d14_win_rate,
      SAFE_DIVIDE(SUM(n.game) * 3 + SUM(n.diff), SUM(n.game) * 3) AS d14_payout_rate
    FROM normalized_data n
    INNER JOIN current_day_machines c ON n.hole = c.hole AND n.machine_number = c.machine_number AND n.machine = c.machine
    CROSS JOIN target_date_def t
    WHERE n.date BETWEEN DATE_SUB(t.target_date, INTERVAL 13 DAY) AND t.target_date
    GROUP BY n.hole, n.machine_number
  ),

  stats_d28 AS (
    SELECT n.hole, n.machine_number,
      SUM(n.diff) AS d28_diff, SUM(n.game) AS d28_game,
      SAFE_DIVIDE(SUM(n.win), COUNT(*)) AS d28_win_rate,
      SAFE_DIVIDE(SUM(n.game) * 3 + SUM(n.diff), SUM(n.game) * 3) AS d28_payout_rate
    FROM normalized_data n
    INNER JOIN current_day_machines c ON n.hole = c.hole AND n.machine_number = c.machine_number AND n.machine = c.machine
    CROSS JOIN target_date_def t
    WHERE n.date BETWEEN DATE_SUB(t.target_date, INTERVAL 27 DAY) AND t.target_date
    GROUP BY n.hole, n.machine_number
  ),

  stats_mtd AS (
    SELECT n.hole, n.machine_number,
      SUM(n.diff) AS mtd_diff, SUM(n.game) AS mtd_game,
      SAFE_DIVIDE(SUM(n.win), COUNT(*)) AS mtd_win_rate,
      SAFE_DIVIDE(SUM(n.game) * 3 + SUM(n.diff), SUM(n.game) * 3) AS mtd_payout_rate
    FROM normalized_data n
    INNER JOIN current_day_machines c ON n.hole = c.hole AND n.machine_number = c.machine_number AND n.machine = c.machine
    CROSS JOIN target_date_def t
    WHERE n.date BETWEEN DATE_TRUNC(t.target_date, MONTH) AND t.target_date
    GROUP BY n.hole, n.machine_number
  ),

  stats_all AS (
    SELECT n.hole, n.machine_number,
      SUM(n.diff) AS all_diff, SUM(n.game) AS all_game,
      SAFE_DIVIDE(SUM(n.win), COUNT(*)) AS all_win_rate,
      SAFE_DIVIDE(SUM(n.game) * 3 + SUM(n.diff), SUM(n.game) * 3) AS all_payout_rate,
      COUNT(*) AS all_days
    FROM normalized_data n
    INNER JOIN current_day_machines c ON n.hole = c.hole AND n.machine_number = c.machine_number AND n.machine = c.machine
    CROSS JOIN target_date_def t
    WHERE n.date <= t.target_date
    GROUP BY n.hole, n.machine_number
  ),

  -- ============================================================================
  -- 9. 前日から過去N日間（当日を含まない）
  -- ============================================================================
  stats_prev_d1 AS (
    SELECT n.hole, n.machine_number,
      n.diff AS prev_d1_diff, n.game AS prev_d1_game,
      SAFE_DIVIDE(n.game * 3 + n.diff, n.game * 3) AS prev_d1_payout_rate
    FROM normalized_data n
    INNER JOIN current_day_machines c ON n.hole = c.hole AND n.machine_number = c.machine_number AND n.machine = c.machine
    CROSS JOIN target_date_def t
    WHERE n.date = DATE_SUB(t.target_date, INTERVAL 1 DAY)
  ),

  stats_prev_d2 AS (
    SELECT n.hole, n.machine_number,
      SUM(n.diff) AS prev_d2_diff, SUM(n.game) AS prev_d2_game,
      SAFE_DIVIDE(SUM(n.win), COUNT(*)) AS prev_d2_win_rate,
      SAFE_DIVIDE(SUM(n.game) * 3 + SUM(n.diff), SUM(n.game) * 3) AS prev_d2_payout_rate
    FROM normalized_data n
    INNER JOIN current_day_machines c ON n.hole = c.hole AND n.machine_number = c.machine_number AND n.machine = c.machine
    CROSS JOIN target_date_def t
    WHERE n.date BETWEEN DATE_SUB(t.target_date, INTERVAL 2 DAY) AND DATE_SUB(t.target_date, INTERVAL 1 DAY)
    GROUP BY n.hole, n.machine_number
  ),

  stats_prev_d3 AS (
    SELECT n.hole, n.machine_number,
      SUM(n.diff) AS prev_d3_diff, SUM(n.game) AS prev_d3_game,
      SAFE_DIVIDE(SUM(n.win), COUNT(*)) AS prev_d3_win_rate,
      SAFE_DIVIDE(SUM(n.game) * 3 + SUM(n.diff), SUM(n.game) * 3) AS prev_d3_payout_rate
    FROM normalized_data n
    INNER JOIN current_day_machines c ON n.hole = c.hole AND n.machine_number = c.machine_number AND n.machine = c.machine
    CROSS JOIN target_date_def t
    WHERE n.date BETWEEN DATE_SUB(t.target_date, INTERVAL 3 DAY) AND DATE_SUB(t.target_date, INTERVAL 1 DAY)
    GROUP BY n.hole, n.machine_number
  ),

  stats_prev_d4 AS (
    SELECT n.hole, n.machine_number,
      SUM(n.diff) AS prev_d4_diff, SUM(n.game) AS prev_d4_game,
      SAFE_DIVIDE(SUM(n.win), COUNT(*)) AS prev_d4_win_rate,
      SAFE_DIVIDE(SUM(n.game) * 3 + SUM(n.diff), SUM(n.game) * 3) AS prev_d4_payout_rate
    FROM normalized_data n
    INNER JOIN current_day_machines c ON n.hole = c.hole AND n.machine_number = c.machine_number AND n.machine = c.machine
    CROSS JOIN target_date_def t
    WHERE n.date BETWEEN DATE_SUB(t.target_date, INTERVAL 4 DAY) AND DATE_SUB(t.target_date, INTERVAL 1 DAY)
    GROUP BY n.hole, n.machine_number
  ),

  stats_prev_d5 AS (
    SELECT n.hole, n.machine_number,
      SUM(n.diff) AS prev_d5_diff, SUM(n.game) AS prev_d5_game,
      SAFE_DIVIDE(SUM(n.win), COUNT(*)) AS prev_d5_win_rate,
      SAFE_DIVIDE(SUM(n.game) * 3 + SUM(n.diff), SUM(n.game) * 3) AS prev_d5_payout_rate
    FROM normalized_data n
    INNER JOIN current_day_machines c ON n.hole = c.hole AND n.machine_number = c.machine_number AND n.machine = c.machine
    CROSS JOIN target_date_def t
    WHERE n.date BETWEEN DATE_SUB(t.target_date, INTERVAL 5 DAY) AND DATE_SUB(t.target_date, INTERVAL 1 DAY)
    GROUP BY n.hole, n.machine_number
  ),

  stats_prev_d6 AS (
    SELECT n.hole, n.machine_number,
      SUM(n.diff) AS prev_d6_diff, SUM(n.game) AS prev_d6_game,
      SAFE_DIVIDE(SUM(n.win), COUNT(*)) AS prev_d6_win_rate,
      SAFE_DIVIDE(SUM(n.game) * 3 + SUM(n.diff), SUM(n.game) * 3) AS prev_d6_payout_rate
    FROM normalized_data n
    INNER JOIN current_day_machines c ON n.hole = c.hole AND n.machine_number = c.machine_number AND n.machine = c.machine
    CROSS JOIN target_date_def t
    WHERE n.date BETWEEN DATE_SUB(t.target_date, INTERVAL 6 DAY) AND DATE_SUB(t.target_date, INTERVAL 1 DAY)
    GROUP BY n.hole, n.machine_number
  ),

  stats_prev_d7 AS (
    SELECT n.hole, n.machine_number,
      SUM(n.diff) AS prev_d7_diff, SUM(n.game) AS prev_d7_game,
      SAFE_DIVIDE(SUM(n.win), COUNT(*)) AS prev_d7_win_rate,
      SAFE_DIVIDE(SUM(n.game) * 3 + SUM(n.diff), SUM(n.game) * 3) AS prev_d7_payout_rate
    FROM normalized_data n
    INNER JOIN current_day_machines c ON n.hole = c.hole AND n.machine_number = c.machine_number AND n.machine = c.machine
    CROSS JOIN target_date_def t
    WHERE n.date BETWEEN DATE_SUB(t.target_date, INTERVAL 7 DAY) AND DATE_SUB(t.target_date, INTERVAL 1 DAY)
    GROUP BY n.hole, n.machine_number
  ),

  stats_prev_d14 AS (
    SELECT n.hole, n.machine_number,
      SUM(n.diff) AS prev_d14_diff, SUM(n.game) AS prev_d14_game,
      SAFE_DIVIDE(SUM(n.win), COUNT(*)) AS prev_d14_win_rate,
      SAFE_DIVIDE(SUM(n.game) * 3 + SUM(n.diff), SUM(n.game) * 3) AS prev_d14_payout_rate
    FROM normalized_data n
    INNER JOIN current_day_machines c ON n.hole = c.hole AND n.machine_number = c.machine_number AND n.machine = c.machine
    CROSS JOIN target_date_def t
    WHERE n.date BETWEEN DATE_SUB(t.target_date, INTERVAL 14 DAY) AND DATE_SUB(t.target_date, INTERVAL 1 DAY)
    GROUP BY n.hole, n.machine_number
  ),

  stats_prev_d28 AS (
    SELECT n.hole, n.machine_number,
      SUM(n.diff) AS prev_d28_diff, SUM(n.game) AS prev_d28_game,
      SAFE_DIVIDE(SUM(n.win), COUNT(*)) AS prev_d28_win_rate,
      SAFE_DIVIDE(SUM(n.game) * 3 + SUM(n.diff), SUM(n.game) * 3) AS prev_d28_payout_rate
    FROM normalized_data n
    INNER JOIN current_day_machines c ON n.hole = c.hole AND n.machine_number = c.machine_number AND n.machine = c.machine
    CROSS JOIN target_date_def t
    WHERE n.date BETWEEN DATE_SUB(t.target_date, INTERVAL 28 DAY) AND DATE_SUB(t.target_date, INTERVAL 1 DAY)
    GROUP BY n.hole, n.machine_number
  ),

  stats_prev_mtd AS (
    SELECT n.hole, n.machine_number,
      SUM(n.diff) AS prev_mtd_diff, SUM(n.game) AS prev_mtd_game,
      SAFE_DIVIDE(SUM(n.win), COUNT(*)) AS prev_mtd_win_rate,
      SAFE_DIVIDE(SUM(n.game) * 3 + SUM(n.diff), SUM(n.game) * 3) AS prev_mtd_payout_rate
    FROM normalized_data n
    INNER JOIN current_day_machines c ON n.hole = c.hole AND n.machine_number = c.machine_number AND n.machine = c.machine
    CROSS JOIN target_date_def t
    WHERE n.date BETWEEN DATE_TRUNC(t.target_date, MONTH) AND DATE_SUB(t.target_date, INTERVAL 1 DAY)
    GROUP BY n.hole, n.machine_number
  ),

  stats_prev_all AS (
    SELECT n.hole, n.machine_number,
      SUM(n.diff) AS prev_all_diff, SUM(n.game) AS prev_all_game,
      SAFE_DIVIDE(SUM(n.win), COUNT(*)) AS prev_all_win_rate,
      SAFE_DIVIDE(SUM(n.game) * 3 + SUM(n.diff), SUM(n.game) * 3) AS prev_all_payout_rate,
      COUNT(*) AS prev_all_days
    FROM normalized_data n
    INNER JOIN current_day_machines c ON n.hole = c.hole AND n.machine_number = c.machine_number AND n.machine = c.machine
    CROSS JOIN target_date_def t
    WHERE n.date < t.target_date
    GROUP BY n.hole, n.machine_number
  )

  -- ============================================================================
  -- 10. ソースデータ生成
  -- ============================================================================
  SELECT
    mp.end_date AS target_date,
    mp.hole,
    mp.machine_number,
    mp.machine,
    mp.start_date,
    mp.end_date,
    -- 日付関連カラム
    EXTRACT(YEAR FROM t.target_date) AS target_year,
    EXTRACT(MONTH FROM t.target_date) AS target_month,
    EXTRACT(DAY FROM t.target_date) AS target_day,
    MOD(EXTRACT(DAY FROM t.target_date), 10) AS target_day_last_digit,
    CASE 
      WHEN EXTRACT(MONTH FROM t.target_date) = EXTRACT(DAY FROM t.target_date) THEN TRUE
      ELSE FALSE
    END AS is_month_day_repdigit,
    CASE 
      WHEN EXTRACT(DAY FROM t.target_date) IN (11, 22) THEN TRUE
      ELSE FALSE
    END AS is_day_repdigit,
    CASE EXTRACT(DAYOFWEEK FROM t.target_date)
      WHEN 1 THEN '日' WHEN 2 THEN '月' WHEN 3 THEN '火'
      WHEN 4 THEN '水' WHEN 5 THEN '木' WHEN 6 THEN '金' WHEN 7 THEN '土'
    END AS day_of_week_jp,
    CASE
      WHEN EXTRACT(DAYOFWEEK FROM t.target_date) IN (1, 7) THEN '週末'
      WHEN h.holiday_date IS NOT NULL THEN '祝日'
      ELSE '平日'
    END AS day_type,
    -- 当日データ
    d1.d1_diff, d1.d1_game, d1.d1_payout_rate,
    -- 当日から過去N日間
    d2.d2_diff, d2.d2_game, d2.d2_win_rate, d2.d2_payout_rate,
    d3.d3_diff, d3.d3_game, d3.d3_win_rate, d3.d3_payout_rate,
    d4.d4_diff, d4.d4_game, d4.d4_win_rate, d4.d4_payout_rate,
    d5.d5_diff, d5.d5_game, d5.d5_win_rate, d5.d5_payout_rate,
    d6.d6_diff, d6.d6_game, d6.d6_win_rate, d6.d6_payout_rate,
    d7.d7_diff, d7.d7_game, d7.d7_win_rate, d7.d7_payout_rate,
    d14.d14_diff, d14.d14_game, d14.d14_win_rate, d14.d14_payout_rate,
    d28.d28_diff, d28.d28_game, d28.d28_win_rate, d28.d28_payout_rate,
    mtd.mtd_diff, mtd.mtd_game, mtd.mtd_win_rate, mtd.mtd_payout_rate,
    a.all_diff, a.all_game, a.all_win_rate, a.all_payout_rate, a.all_days,
    -- 前日から過去N日間
    pd1.prev_d1_diff, pd1.prev_d1_game, pd1.prev_d1_payout_rate,
    pd2.prev_d2_diff, pd2.prev_d2_game, pd2.prev_d2_win_rate, pd2.prev_d2_payout_rate,
    pd3.prev_d3_diff, pd3.prev_d3_game, pd3.prev_d3_win_rate, pd3.prev_d3_payout_rate,
    pd4.prev_d4_diff, pd4.prev_d4_game, pd4.prev_d4_win_rate, pd4.prev_d4_payout_rate,
    pd5.prev_d5_diff, pd5.prev_d5_game, pd5.prev_d5_win_rate, pd5.prev_d5_payout_rate,
    pd6.prev_d6_diff, pd6.prev_d6_game, pd6.prev_d6_win_rate, pd6.prev_d6_payout_rate,
    pd7.prev_d7_diff, pd7.prev_d7_game, pd7.prev_d7_win_rate, pd7.prev_d7_payout_rate,
    pd14.prev_d14_diff, pd14.prev_d14_game, pd14.prev_d14_win_rate, pd14.prev_d14_payout_rate,
    pd28.prev_d28_diff, pd28.prev_d28_game, pd28.prev_d28_win_rate, pd28.prev_d28_payout_rate,
    pmtd.prev_mtd_diff, pmtd.prev_mtd_game, pmtd.prev_mtd_win_rate, pmtd.prev_mtd_payout_rate,
    pa.prev_all_diff, pa.prev_all_game, pa.prev_all_win_rate, pa.prev_all_payout_rate, pa.prev_all_days
  FROM machine_periods mp
  CROSS JOIN target_date_def t
  LEFT JOIN holidays h ON t.target_date = h.holiday_date
  LEFT JOIN stats_d1 d1 ON mp.hole = d1.hole AND mp.machine_number = d1.machine_number
  LEFT JOIN stats_d2 d2 ON mp.hole = d2.hole AND mp.machine_number = d2.machine_number
  LEFT JOIN stats_d3 d3 ON mp.hole = d3.hole AND mp.machine_number = d3.machine_number
  LEFT JOIN stats_d4 d4 ON mp.hole = d4.hole AND mp.machine_number = d4.machine_number
  LEFT JOIN stats_d5 d5 ON mp.hole = d5.hole AND mp.machine_number = d5.machine_number
  LEFT JOIN stats_d6 d6 ON mp.hole = d6.hole AND mp.machine_number = d6.machine_number
  LEFT JOIN stats_d7 d7 ON mp.hole = d7.hole AND mp.machine_number = d7.machine_number
  LEFT JOIN stats_d14 d14 ON mp.hole = d14.hole AND mp.machine_number = d14.machine_number
  LEFT JOIN stats_d28 d28 ON mp.hole = d28.hole AND mp.machine_number = d28.machine_number
  LEFT JOIN stats_mtd mtd ON mp.hole = mtd.hole AND mp.machine_number = mtd.machine_number
  LEFT JOIN stats_all a ON mp.hole = a.hole AND mp.machine_number = a.machine_number
  LEFT JOIN stats_prev_d1 pd1 ON mp.hole = pd1.hole AND mp.machine_number = pd1.machine_number
  LEFT JOIN stats_prev_d2 pd2 ON mp.hole = pd2.hole AND mp.machine_number = pd2.machine_number
  LEFT JOIN stats_prev_d3 pd3 ON mp.hole = pd3.hole AND mp.machine_number = pd3.machine_number
  LEFT JOIN stats_prev_d4 pd4 ON mp.hole = pd4.hole AND mp.machine_number = pd4.machine_number
  LEFT JOIN stats_prev_d5 pd5 ON mp.hole = pd5.hole AND mp.machine_number = pd5.machine_number
  LEFT JOIN stats_prev_d6 pd6 ON mp.hole = pd6.hole AND mp.machine_number = pd6.machine_number
  LEFT JOIN stats_prev_d7 pd7 ON mp.hole = pd7.hole AND mp.machine_number = pd7.machine_number
  LEFT JOIN stats_prev_d14 pd14 ON mp.hole = pd14.hole AND mp.machine_number = pd14.machine_number
  LEFT JOIN stats_prev_d28 pd28 ON mp.hole = pd28.hole AND mp.machine_number = pd28.machine_number
  LEFT JOIN stats_prev_mtd pmtd ON mp.hole = pmtd.hole AND mp.machine_number = pmtd.machine_number
  LEFT JOIN stats_prev_all pa ON mp.hole = pa.hole AND mp.machine_number = pa.machine_number
) AS source
ON target.target_date = source.target_date 
   AND target.hole = source.hole 
   AND target.machine_number = source.machine_number

-- 既存データがあれば更新
WHEN MATCHED THEN
  UPDATE SET
    machine = source.machine,
    start_date = source.start_date,
    end_date = source.end_date,
    -- 日付関連カラム
    target_year = source.target_year,
    target_month = source.target_month,
    target_day = source.target_day,
    target_day_last_digit = source.target_day_last_digit,
    is_month_day_repdigit = source.is_month_day_repdigit,
    is_day_repdigit = source.is_day_repdigit,
    day_of_week_jp = source.day_of_week_jp,
    day_type = source.day_type,
    -- 当日データ
    d1_diff = source.d1_diff,
    d1_game = source.d1_game,
    d1_payout_rate = source.d1_payout_rate,
    -- 当日から過去N日間
    d2_diff = source.d2_diff,
    d2_game = source.d2_game,
    d2_win_rate = source.d2_win_rate,
    d2_payout_rate = source.d2_payout_rate,
    d3_diff = source.d3_diff,
    d3_game = source.d3_game,
    d3_win_rate = source.d3_win_rate,
    d3_payout_rate = source.d3_payout_rate,
    d4_diff = source.d4_diff,
    d4_game = source.d4_game,
    d4_win_rate = source.d4_win_rate,
    d4_payout_rate = source.d4_payout_rate,
    d5_diff = source.d5_diff,
    d5_game = source.d5_game,
    d5_win_rate = source.d5_win_rate,
    d5_payout_rate = source.d5_payout_rate,
    d6_diff = source.d6_diff,
    d6_game = source.d6_game,
    d6_win_rate = source.d6_win_rate,
    d6_payout_rate = source.d6_payout_rate,
    d7_diff = source.d7_diff,
    d7_game = source.d7_game,
    d7_win_rate = source.d7_win_rate,
    d7_payout_rate = source.d7_payout_rate,
    d14_diff = source.d14_diff,
    d14_game = source.d14_game,
    d14_win_rate = source.d14_win_rate,
    d14_payout_rate = source.d14_payout_rate,
    d28_diff = source.d28_diff,
    d28_game = source.d28_game,
    d28_win_rate = source.d28_win_rate,
    d28_payout_rate = source.d28_payout_rate,
    mtd_diff = source.mtd_diff,
    mtd_game = source.mtd_game,
    mtd_win_rate = source.mtd_win_rate,
    mtd_payout_rate = source.mtd_payout_rate,
    all_diff = source.all_diff,
    all_game = source.all_game,
    all_win_rate = source.all_win_rate,
    all_payout_rate = source.all_payout_rate,
    all_days = source.all_days,
    -- 前日から過去N日間
    prev_d1_diff = source.prev_d1_diff,
    prev_d1_game = source.prev_d1_game,
    prev_d1_payout_rate = source.prev_d1_payout_rate,
    prev_d2_diff = source.prev_d2_diff,
    prev_d2_game = source.prev_d2_game,
    prev_d2_win_rate = source.prev_d2_win_rate,
    prev_d2_payout_rate = source.prev_d2_payout_rate,
    prev_d3_diff = source.prev_d3_diff,
    prev_d3_game = source.prev_d3_game,
    prev_d3_win_rate = source.prev_d3_win_rate,
    prev_d3_payout_rate = source.prev_d3_payout_rate,
    prev_d4_diff = source.prev_d4_diff,
    prev_d4_game = source.prev_d4_game,
    prev_d4_win_rate = source.prev_d4_win_rate,
    prev_d4_payout_rate = source.prev_d4_payout_rate,
    prev_d5_diff = source.prev_d5_diff,
    prev_d5_game = source.prev_d5_game,
    prev_d5_win_rate = source.prev_d5_win_rate,
    prev_d5_payout_rate = source.prev_d5_payout_rate,
    prev_d6_diff = source.prev_d6_diff,
    prev_d6_game = source.prev_d6_game,
    prev_d6_win_rate = source.prev_d6_win_rate,
    prev_d6_payout_rate = source.prev_d6_payout_rate,
    prev_d7_diff = source.prev_d7_diff,
    prev_d7_game = source.prev_d7_game,
    prev_d7_win_rate = source.prev_d7_win_rate,
    prev_d7_payout_rate = source.prev_d7_payout_rate,
    prev_d14_diff = source.prev_d14_diff,
    prev_d14_game = source.prev_d14_game,
    prev_d14_win_rate = source.prev_d14_win_rate,
    prev_d14_payout_rate = source.prev_d14_payout_rate,
    prev_d28_diff = source.prev_d28_diff,
    prev_d28_game = source.prev_d28_game,
    prev_d28_win_rate = source.prev_d28_win_rate,
    prev_d28_payout_rate = source.prev_d28_payout_rate,
    prev_mtd_diff = source.prev_mtd_diff,
    prev_mtd_game = source.prev_mtd_game,
    prev_mtd_win_rate = source.prev_mtd_win_rate,
    prev_mtd_payout_rate = source.prev_mtd_payout_rate,
    prev_all_diff = source.prev_all_diff,
    prev_all_game = source.prev_all_game,
    prev_all_win_rate = source.prev_all_win_rate,
    prev_all_payout_rate = source.prev_all_payout_rate,
    prev_all_days = source.prev_all_days

-- 新規データは挿入
WHEN NOT MATCHED THEN
  INSERT (
    target_date, hole, machine_number, machine, start_date, end_date,
    -- 日付関連カラム
    target_year, target_month, target_day, target_day_last_digit,
    is_month_day_repdigit, is_day_repdigit, day_of_week_jp, day_type,
    -- 当日データ
    d1_diff, d1_game, d1_payout_rate,
    -- 当日から過去N日間
    d2_diff, d2_game, d2_win_rate, d2_payout_rate,
    d3_diff, d3_game, d3_win_rate, d3_payout_rate,
    d4_diff, d4_game, d4_win_rate, d4_payout_rate,
    d5_diff, d5_game, d5_win_rate, d5_payout_rate,
    d6_diff, d6_game, d6_win_rate, d6_payout_rate,
    d7_diff, d7_game, d7_win_rate, d7_payout_rate,
    d14_diff, d14_game, d14_win_rate, d14_payout_rate,
    d28_diff, d28_game, d28_win_rate, d28_payout_rate,
    mtd_diff, mtd_game, mtd_win_rate, mtd_payout_rate,
    all_diff, all_game, all_win_rate, all_payout_rate, all_days,
    -- 前日から過去N日間
    prev_d1_diff, prev_d1_game, prev_d1_payout_rate,
    prev_d2_diff, prev_d2_game, prev_d2_win_rate, prev_d2_payout_rate,
    prev_d3_diff, prev_d3_game, prev_d3_win_rate, prev_d3_payout_rate,
    prev_d4_diff, prev_d4_game, prev_d4_win_rate, prev_d4_payout_rate,
    prev_d5_diff, prev_d5_game, prev_d5_win_rate, prev_d5_payout_rate,
    prev_d6_diff, prev_d6_game, prev_d6_win_rate, prev_d6_payout_rate,
    prev_d7_diff, prev_d7_game, prev_d7_win_rate, prev_d7_payout_rate,
    prev_d14_diff, prev_d14_game, prev_d14_win_rate, prev_d14_payout_rate,
    prev_d28_diff, prev_d28_game, prev_d28_win_rate, prev_d28_payout_rate,
    prev_mtd_diff, prev_mtd_game, prev_mtd_win_rate, prev_mtd_payout_rate,
    prev_all_diff, prev_all_game, prev_all_win_rate, prev_all_payout_rate, prev_all_days
  )
  VALUES (
    source.target_date, source.hole, source.machine_number, source.machine, source.start_date, source.end_date,
    -- 日付関連カラム
    source.target_year, source.target_month, source.target_day, source.target_day_last_digit,
    source.is_month_day_repdigit, source.is_day_repdigit, source.day_of_week_jp, source.day_type,
    -- 当日データ
    source.d1_diff, source.d1_game, source.d1_payout_rate,
    -- 当日から過去N日間
    source.d2_diff, source.d2_game, source.d2_win_rate, source.d2_payout_rate,
    source.d3_diff, source.d3_game, source.d3_win_rate, source.d3_payout_rate,
    source.d4_diff, source.d4_game, source.d4_win_rate, source.d4_payout_rate,
    source.d5_diff, source.d5_game, source.d5_win_rate, source.d5_payout_rate,
    source.d6_diff, source.d6_game, source.d6_win_rate, source.d6_payout_rate,
    source.d7_diff, source.d7_game, source.d7_win_rate, source.d7_payout_rate,
    source.d14_diff, source.d14_game, source.d14_win_rate, source.d14_payout_rate,
    source.d28_diff, source.d28_game, source.d28_win_rate, source.d28_payout_rate,
    source.mtd_diff, source.mtd_game, source.mtd_win_rate, source.mtd_payout_rate,
    source.all_diff, source.all_game, source.all_win_rate, source.all_payout_rate, source.all_days,
    -- 前日から過去N日間
    source.prev_d1_diff, source.prev_d1_game, source.prev_d1_payout_rate,
    source.prev_d2_diff, source.prev_d2_game, source.prev_d2_win_rate, source.prev_d2_payout_rate,
    source.prev_d3_diff, source.prev_d3_game, source.prev_d3_win_rate, source.prev_d3_payout_rate,
    source.prev_d4_diff, source.prev_d4_game, source.prev_d4_win_rate, source.prev_d4_payout_rate,
    source.prev_d5_diff, source.prev_d5_game, source.prev_d5_win_rate, source.prev_d5_payout_rate,
    source.prev_d6_diff, source.prev_d6_game, source.prev_d6_win_rate, source.prev_d6_payout_rate,
    source.prev_d7_diff, source.prev_d7_game, source.prev_d7_win_rate, source.prev_d7_payout_rate,
    source.prev_d14_diff, source.prev_d14_game, source.prev_d14_win_rate, source.prev_d14_payout_rate,
    source.prev_d28_diff, source.prev_d28_game, source.prev_d28_win_rate, source.prev_d28_payout_rate,
    source.prev_mtd_diff, source.prev_mtd_game, source.prev_mtd_win_rate, source.prev_mtd_payout_rate,
    source.prev_all_diff, source.prev_all_game, source.prev_all_win_rate, source.prev_all_payout_rate, source.prev_all_days
  );
