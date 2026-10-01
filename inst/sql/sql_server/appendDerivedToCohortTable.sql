-- Copy the derived cohorts (101-107) from @cohortTableNew into the base
-- @cohort_table so that population and outcome cohorts share one table, as
-- required by the time-to-event SQL (which joins population and outcome inside
-- a single @cohort_table).
--
-- cohort_end_date is reset to the END OF CONTINUOUS OBSERVATION: the
-- observation_period_end_date of the observation period that contains the
-- cohort_start_date. This makes follow-up for these populations run to the end
-- of available observation. Persons whose cohort_start_date is not covered by an
-- observation period are dropped (INNER JOIN), consistent with the time-to-event
-- SQL, which also requires observation at cohort entry.
--
-- Parameters (SqlRender):
--   @cohort_database_schema  schema containing the cohort tables
--   @cdm_database_schema     schema containing the OMOP CDM (observation_period)
--   @cohort_table            base cohort table (holds outcomes; derived cohorts appended here)
--   @cohortTableNew          derived cohort table

-- Idempotency: remove any prior copy of the derived ids from the base table
DELETE FROM @cohort_database_schema.@cohort_table
WHERE cohort_definition_id IN (
  SELECT DISTINCT cohort_definition_id
  FROM @cohort_database_schema.@cohortTableNew
);

INSERT INTO @cohort_database_schema.@cohort_table
  (cohort_definition_id, subject_id, cohort_start_date, cohort_end_date)
SELECT
  n.cohort_definition_id,
  n.subject_id,
  n.cohort_start_date,
  op.observation_period_end_date AS cohort_end_date   -- end of continuous observation
FROM @cohort_database_schema.@cohortTableNew n
INNER JOIN @cdm_database_schema.observation_period op
  ON  op.person_id                     = n.subject_id
  AND op.observation_period_start_date <= n.cohort_start_date
  AND op.observation_period_end_date   >= n.cohort_start_date
;
