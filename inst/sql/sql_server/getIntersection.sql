-- Parameters (SqlRender):
--   @cohort_database_schema  schema containing the cohort tables
--   @anchor_cohort_table     table holding the anchor cohort (cohortTable or cohortTableNew)
--   @target_cohort_table     table holding the target cohort (cohortTable or cohortTableNew)
--   @anchor_cohort_id, @target_cohort_id  cohort_definition_id values

IF OBJECT_ID('tempdb..#anchor_idx', 'U') IS NOT NULL DROP TABLE #anchor_idx;
IF OBJECT_ID('tempdb..#target_idx', 'U') IS NOT NULL DROP TABLE #target_idx;
IF OBJECT_ID('tempdb..#pair', 'U') IS NOT NULL DROP TABLE #pair;

-- One index row per person: the first cohort episode
SELECT subject_id, cohort_start_date AS anchor_start_date
INTO #anchor_idx
FROM (
  SELECT subject_id, cohort_start_date,
    ROW_NUMBER() OVER (PARTITION BY subject_id ORDER BY cohort_start_date, cohort_end_date DESC) AS rn
  FROM @cohort_database_schema.@anchor_cohort_table
  WHERE cohort_definition_id = @anchor_cohort_id
) a
WHERE rn = 1;

SELECT subject_id, cohort_start_date AS target_start_date, cohort_end_date AS target_end_date
INTO #target_idx
FROM (
  SELECT subject_id, cohort_start_date, cohort_end_date,
    ROW_NUMBER() OVER (PARTITION BY subject_id ORDER BY cohort_start_date, cohort_end_date DESC) AS rn
  FROM @cohort_database_schema.@target_cohort_table
  WHERE cohort_definition_id = @target_cohort_id
) t
WHERE rn = 1;

-- day_diff = target index date minus anchor index date
SELECT a.subject_id,
  a.anchor_start_date,
  t.target_start_date,
  t.target_end_date,
  DATEDIFF(day, a.anchor_start_date, t.target_start_date) AS day_diff
INTO #pair
FROM #anchor_idx a
INNER JOIN #target_idx t
  ON a.subject_id = t.subject_id;
