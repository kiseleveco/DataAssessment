runTte <- function(db, ..., minCellCount = 0, outputFolder = tempfile()) {
  args <- list(connection = db$connection, cohortDatabaseSchema = db$cohortDatabaseSchema,
               cohortTable = db$cohortTable, cohortTableNew = db$cohortTableNew)
  do.call(createDerivedCohorts, args)
  do.call(appendDerivedCohortsToBase, c(args, list(cdmDatabaseSchema = db$cdmDatabaseSchema)))
  runTimeToEventAnalysis(
    connection = db$connection, cdmDatabaseSchema = db$cdmDatabaseSchema,
    cohortDatabaseSchema = db$cohortDatabaseSchema, cohortTable = db$cohortTable,
    databaseId = "test", minCellCount = minCellCount, outputFolder = outputFolder, ...
  )
}

test_that("derived cohorts are appended with the end of observation as cohort end date", {
  db <- makeTestDatabase()
  on.exit(DatabaseConnector::disconnect(db$connection))
  runTte(db, targetCohortIds = 101, outcomeCohortIds = 10)
  q <- DatabaseConnector::querySql(
    db$connection,
    "SELECT subject_id, cohort_end_date FROM main.cohort WHERE cohort_definition_id = 101"
  )
  names(q) <- tolower(names(q))
  expect_equal(as.Date(q$cohort_end_date[q$subject_id == 1]), as.Date("2023-12-31"))
  expect_equal(as.Date(q$cohort_end_date[q$subject_id == 2]), as.Date("2020-06-01"))
})

test_that("Kaplan-Meier table and estimates match survival::survfit on the same data", {
  db <- makeTestDatabase()
  on.exit(DatabaseConnector::disconnect(db$connection))
  res <- runTte(db, targetCohortIds = 101, outcomeCohortIds = 10)

  # 101 = persons 1,2,4,5,6,7. Hypertension: person 1 event after 97 days; person 2's event is
  # after the end of observation (censored at day 132); the others are censored at observation end.
  km <- res$kmTable
  expect_equal(nrow(km), 6)
  expect_equal(km$time[1], 97)
  expect_equal(km$n_risk[1], 6)
  expect_equal(km$n_event[1], 1)
  expect_equal(km$surv[1], 5 / 6)

  tteData <- data.frame(
    timeToEvent = c(97, 132, 1550, 1464, 1465, 1455),
    event = c(1, 0, 0, 0, 0, 0)
  )
  fit <- survival::survfit(survival::Surv(timeToEvent, event) ~ 1, data = tteData)
  expect_equal(km$time, fit$time)
  expect_equal(km$surv, fit$surv)
  expect_equal(km$ci_lower, fit$lower)
  expect_equal(km$ci_upper, fit$upper)

  est <- res$kmEstimates
  expect_equal(est$cumulative_incidence_1yr, 1 / 6)
  expect_equal(est$cumulative_incidence_3yr, 1 / 6)
  expect_equal(est$surv_5yr, 5 / 6) # last KM estimate on or before 1825 days
})

test_that("outcomes after the end of follow-up are censored, except death", {
  db <- makeTestDatabase()
  on.exit(DatabaseConnector::disconnect(db$connection))
  res <- runTte(db, targetCohortIds = 101, outcomeCohortIds = 10)
  # person 2: hypertension 2020-07-19 is after the observation end 2020-06-01 -> censored
  expect_equal(sum(res$kmTable$n_event), 1)

  res <- runTte(db, targetCohortIds = 101, outcomeCohortIds = c(11, 12))
  hosp <- res$kmTable[res$kmTable$outcome == "Hospitalization", ]
  death <- res$kmTable[res$kmTable$outcome == "Death", ]
  expect_equal(sum(hosp$n_event), 0)
  # person 2 dies on 2020-07-19, after observation end 2020-06-01: counted as an event at day 180
  expect_equal(sum(death$n_event), 1)
  expect_equal(death$time[death$n_event == 1], 180)
  expect_equal(death$surv[death$n_event == 1], 5 / 6)
  est <- res$kmEstimates
  expect_equal(est$cumulative_incidence_1yr[est$outcome == "Death"], 1 / 6)
  expect_equal(est$cumulative_incidence_1yr[est$outcome == "Hospitalization"], 0)
})

test_that("chronic outcomes exclude prevalent cases", {
  db <- makeTestDatabase()
  on.exit(DatabaseConnector::disconnect(db$connection))
  get <- function(file) {
    querySqlFile(
      db$connection, file, "DataAssessment",
      cohort_database_schema = db$cohortDatabaseSchema, cdm_database_schema = db$cdmDatabaseSchema,
      cohort_table = db$cohortTable, target_cohort_id = 1, outcome_cohort_id = 10, cap_at_observation_end = TRUE
    )
  }
  expect_equal(nrow(get("getTimeToEvent.sql")), 11)        # 10 persons, person 1 has two entries
  # person 3 (outcome before index) and person 1's second entry (outcome before that entry) are excluded
  expect_equal(nrow(get("getTimeToEventChronic.sql")), 9)
})

test_that("small counts are censored in the KM table", {
  db <- makeTestDatabase()
  on.exit(DatabaseConnector::disconnect(db$connection))
  folder <- tempfile()
  runTte(db, targetCohortIds = 101, outcomeCohortIds = 10, minCellCount = 5, outputFolder = folder)
  km <- read.csv(file.path(folder, "timeToEventAnalysis", "kmTable.csv"))
  expect_equal(km$n_event[1], -5)
  expect_equal(km$n_risk[1], 6)
  expect_true(file.exists(file.path(folder, "timeToEventAnalysis", "kmEstimates.csv")))
})
