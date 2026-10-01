test_that("derived cohorts reproduce the expected counts", {
  db <- makeTestDatabase()
  on.exit(DatabaseConnector::disconnect(db$connection))
  createDerivedCohorts(
    connection = db$connection, cohortDatabaseSchema = db$cohortDatabaseSchema,
    cohortTable = db$cohortTable, cohortTableNew = db$cohortTableNew
  )
  counts <- getCohortCountsFromTable(
    db$connection, db$cohortDatabaseSchema, db$cohortTableNew, 101:107, "DataAssessment"
  )
  n <- function(id) counts$cohortSubjects[counts$cohortId == id]
  expect_equal(n(101), 6) # person 3 (-100 days) excluded, -90 included
  expect_equal(n(102), 4)
  expect_equal(n(103), 1)
  expect_equal(n(104), 0)
})

test_that("derived cohort index date is the target date and the build is idempotent", {
  db <- makeTestDatabase()
  on.exit(DatabaseConnector::disconnect(db$connection))
  for (i in 1:2) {
    createDerivedCohorts(
      connection = db$connection, cohortDatabaseSchema = db$cohortDatabaseSchema,
      cohortTable = db$cohortTable, cohortTableNew = db$cohortTableNew
    )
  }
  q <- DatabaseConnector::querySql(
    db$connection,
    "SELECT subject_id, cohort_start_date FROM main.cohort_new WHERE cohort_definition_id = 101"
  )
  names(q) <- tolower(names(q))
  expect_equal(nrow(q), 6)
  expect_equal(as.Date(q$cohort_start_date[q$subject_id == 1]), as.Date("2020-01-04"))
})

test_that("a finite maxDays limits the window", {
  db <- makeTestDatabase()
  on.exit(DatabaseConnector::disconnect(db$connection))
  createDerivedCohorts(
    connection = db$connection, cohortDatabaseSchema = db$cohortDatabaseSchema,
    cohortTable = db$cohortTable, cohortTableNew = db$cohortTableNew, minDays = -90, maxDays = 10
  )
  counts <- getCohortCountsFromTable(
    db$connection, db$cohortDatabaseSchema, db$cohortTableNew, 101, "DataAssessment"
  )
  expect_equal(counts$cohortSubjects, 5) # +20 excluded
})

test_that("derived cohorts are appended to the base cohort table", {
  db <- makeTestDatabase()
  on.exit(DatabaseConnector::disconnect(db$connection))
  args <- list(connection = db$connection, cohortDatabaseSchema = db$cohortDatabaseSchema,
               cohortTable = db$cohortTable, cohortTableNew = db$cohortTableNew)
  do.call(createDerivedCohorts, args)
  do.call(appendDerivedCohortsToBase, c(args, list(cdmDatabaseSchema = db$cdmDatabaseSchema)))
  do.call(appendDerivedCohortsToBase, c(args, list(cdmDatabaseSchema = db$cdmDatabaseSchema))) # idempotent
  counts <- getCohortCountsFromTable(
    db$connection, db$cohortDatabaseSchema, db$cohortTable, c(1, 101, 102), "DataAssessment"
  )
  expect_equal(counts$cohortEntries, c(11, 6, 4)) # cohort 1 has 11 entries (person 1 twice)
})
