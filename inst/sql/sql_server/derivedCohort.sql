-- Parameters (SqlRender):
--   @cohort_database_schema  schema containing the derived cohort table
--   @cohortTableNew          derived cohort table
--   @output_cohort_id        cohort_definition_id of the derived cohort
--   @min_days, @max_days     window for target minus anchor index date (max optional)

DELETE FROM @cohort_database_schema.@cohortTableNew
WHERE cohort_definition_id = @output_cohort_id;

-- Derived cohort: index date is the target (later) event
INSERT INTO @cohort_database_schema.@cohortTableNew (cohort_definition_id, subject_id, cohort_start_date, cohort_end_date)
SELECT @output_cohort_id AS cohort_definition_id,
  subject_id,
  target_start_date AS cohort_start_date,
  target_end_date AS cohort_end_date
FROM #pair
WHERE day_diff >= @min_days
{@has_max_days} ? {  AND day_diff <= @max_days};
