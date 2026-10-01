SELECT
  (SELECT COUNT(*) FROM #anchor_idx) AS anchor_n,
  (SELECT COUNT(*) FROM #target_idx) AS target_n,
  (SELECT COUNT(*) FROM #pair) AS intersection_n;
