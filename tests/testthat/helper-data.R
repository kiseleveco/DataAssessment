# Synthetic cohort + observation_period tables in an in-memory-like DuckDB file.
# Index date of cohort 1 is 2020-01-01 for persons 1-10 (person 1 has a later 2nd episode).
makeTestDatabase <- function() {
  skip_if_not_installed("duckdb")
  databaseFile <- tempfile(fileext = ".duckdb")
  connectionDetails <- DatabaseConnector::createConnectionDetails(dbms = "duckdb", server = databaseFile)
  connection <- DatabaseConnector::connect(connectionDetails)

  d0 <- as.Date("2020-01-01")
  rows <- list()
  add <- function(cohortId, person, offset, base = d0, length = 30) {
    rows[[length(rows) + 1]] <<- data.frame(
      cohort_definition_id = cohortId, subject_id = person,
      cohort_start_date = base + offset, cohort_end_date = base + offset + length
    )
  }
  # Cohort 1: persons 1-10, person 1 also has a later second episode
  # (cohort 1 runs to the end of observation, like an ATLAS first-event cohort)
  for (p in 1:10) add(1, p, 0, length = 5000)
  add(1, 1, 400, length = 5000)
  # Cohort 2 (offset from cohort 1 index): 1:+3 2:+20 3:-100 4:-90 5:-4 6:-5 7:+5; 11 only in cohort 2
  c2 <- c(`1` = 3, `2` = 20, `3` = -100, `4` = -90, `5` = -4, `6` = -5, `7` = 5)
  for (p in names(c2)) add(2, as.integer(p), c2[[p]])
  add(2, 11, 0)
  # Expected cohort 101 (index = cohort 2 date): persons 1,2,4,5,6,7
  # Cohort 3 (ADT) relative to the cohort 2 date of the person: 1:0 2:+100 4:-91 5:-90 6:+400
  c3 <- c(`1` = 0, `2` = 100, `4` = -91, `5` = -90, `6` = 400)
  for (p in names(c3)) add(3, as.integer(p), c2[[p]] + c3[[p]])
  # Expected cohort 102 (index = cohort 3 date): persons 1,2,5,6
  # Cohort 4 (ARPI) relative to the cohort 3 date: 1:+10 2:-200
  add(4, 1, c2[["1"]] + 0 + 10)
  add(4, 2, c2[["2"]] + 100 - 200)
  # Outcomes: hypertension (10): person 1 at +100, person 2 at +200 (after obs end), person 3 before index
  add(10, 1, 100); add(10, 2, 200); add(10, 3, -50)
  # Death (12): person 2 at +200
  add(12, 2, 200)
  cohort <- do.call(rbind, rows)

  op <- data.frame(
    person_id = 1:11,
    observation_period_start_date = as.Date("2010-01-01"),
    observation_period_end_date = as.Date("2023-12-31")
  )
  op$observation_period_end_date[2] <- as.Date("2020-06-01")

  DatabaseConnector::insertTable(connection, tableName = "cohort", data = cohort,
                                 dropTableIfExists = TRUE, createTable = TRUE, camelCaseToSnakeCase = FALSE)
  DatabaseConnector::insertTable(connection, tableName = "observation_period", data = op,
                                 dropTableIfExists = TRUE, createTable = TRUE, camelCaseToSnakeCase = FALSE)
  list(connection = connection, connectionDetails = connectionDetails, cdmDatabaseSchema = "main",
       cohortDatabaseSchema = "main", cohortTable = "cohort", cohortTableNew = "cohort_new")
}
