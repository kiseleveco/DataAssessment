test_that("intersection analysis reports counts and bins", {
  db <- makeTestDatabase()
  on.exit(DatabaseConnector::disconnect(db$connection))
  args <- list(connection = db$connection, cohortDatabaseSchema = db$cohortDatabaseSchema,
               cohortTable = db$cohortTable, cohortTableNew = db$cohortTableNew)
  do.call(createDerivedCohorts, args)
  res <- do.call(runIntersectionAnalysis, c(args, list(databaseId = "test", minCellCount = 0, outputFolder = tempfile())))

  i1 <- res$intersections[res$intersections$analysisId == 1, ]
  expect_equal(i1$anchorN, 10)
  expect_equal(i1$intersectionN, 7)
  expect_equal(i1$anchorCohortName, "Prostate cancer")

  b1 <- res$dayDifferenceBins[res$dayDifferenceBins$targetCohortId == 2, ]
  expect_equal(b1$nPersons[b1$binLower == -5], 3)   # +3, -4, -5
  expect_equal(b1$nPersons[b1$binLower == 5], 1)    # +5
  expect_equal(b1$nPersons[b1$binLower == 15], 1)   # +20
  expect_equal(b1$nPersons[b1$binLower == -95], 1)  # -90
  expect_equal(b1$nPersons[b1$binLower == -105], 1) # -100
  expect_equal(sum(b1$nPersons), 7)

  d <- res$derivedCohortCounts
  expect_equal(d$cohortSubjects[d$derivedCohortId == 101], 6)
  expect_equal(d$cohortSubjects[d$derivedCohortId == 102], 4)
  expect_equal(d$cohortSubjects[d$derivedCohortId == 103], 1)

  i2 <- res$intersections[res$intersections$analysisId == 2, ]
  expect_equal(i2$anchorN, 6)
  expect_equal(i2$intersectionN, 5)
})

test_that("results are written censored", {
  db <- makeTestDatabase()
  on.exit(DatabaseConnector::disconnect(db$connection))
  folder <- tempfile()
  args <- list(connection = db$connection, cohortDatabaseSchema = db$cohortDatabaseSchema,
               cohortTable = db$cohortTable, cohortTableNew = db$cohortTableNew)
  do.call(createDerivedCohorts, args)
  do.call(runIntersectionAnalysis, c(args, list(databaseId = "test", minCellCount = 5, outputFolder = folder)))
  d <- read.csv(file.path(folder, "intersectionAnalysis", "derivedCohortCounts.csv"))
  expect_equal(d$cohortSubjects[d$derivedCohortId == 101], 6)
  expect_equal(d$cohortSubjects[d$derivedCohortId == 102], -5)
  expect_equal(d$cohortSubjects[d$derivedCohortId == 104], 0)
})
