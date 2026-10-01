test_that("diagnostics cohorts map derived cohorts to the cohort that defines their index event", {
  settings <- DataAssessment:::readSettings("DiagnosticsCohorts.csv")
  expect_equal(settings$cohortId, c(1, 101:107))
  expect_equal(settings$indexEventCohortId, c(1, 2:8))
})

test_that("the derived cohort settings form the expected cascade", {
  settings <- DataAssessment:::readSettings("DerivedCohorts.csv")
  expect_equal(settings$cohortId, 101:107)
  expect_equal(settings$anchorCohortId, c(1, 101, rep(102, 5)))
  expect_equal(settings$targetCohortId, c(2:8))
})
