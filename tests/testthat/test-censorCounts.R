test_that("small counts are censored", {
  d <- data.frame(n = c(0, 3, 5, 100))
  expect_equal(censorCounts(d, "n", 5)$n, c(0, -5, 5, 100))
})
