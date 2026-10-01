test_that("central bin is [-5, 5) and bins are 10 days wide", {
  b <- binDayDifference(c(-5, -4, 0, 4, 5, 14, 15, -6))
  expect_equal(b$binLabel[b$binIndex == 0], "[-5, 5)")
  expect_equal(b$nPersons[b$binIndex == 0], 4) # -5, -4, 0, 4
  expect_equal(b$nPersons[b$binIndex == 1], 2) # 5, 14
  expect_equal(b$nPersons[b$binIndex == 2], 1) # 15
  expect_equal(b$nPersons[b$binIndex == -1], 1) # -6
})

test_that("empty bins between occupied bins are zero filled and counts are weighted", {
  b <- binDayDifference(c(0, 40), nPersons = c(3, 2))
  expect_equal(b$binIndex, 0:4)
  expect_equal(b$nPersons, c(3, 0, 0, 0, 2))
})

test_that("empty input gives empty table", {
  expect_equal(nrow(binDayDifference(numeric())), 0)
})
