# Copyright 2026 Observational Health Data Sciences and Informatics
#
# This file is part of DataAssessment
#
# Licensed under the Apache License, Version 2.0 (the "License");
# you may not use this file except in compliance with the License.
# You may obtain a copy of the License at
#
#     http://www.apache.org/licenses/LICENSE-2.0
#
# Unless required by applicable law or agreed to in writing, software
# distributed under the License is distributed on an "AS IS" BASIS,
# WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
# See the License for the specific language governing permissions and
# limitations under the License.

# ------------------------------------------------------------------------------
# Internal helpers shared by the analysis functions
# ------------------------------------------------------------------------------

# Read one of the CSV files in inst/settings
readSettings <- function(fileName, packageName = "DataAssessment") {
  path <- system.file("settings", fileName, package = packageName)
  if (!nzchar(path)) {
    stop("Settings file not found in package ", packageName, ": ", fileName)
  }
  utils::read.csv(path, stringsAsFactors = FALSE)
}

# cohortId -> cohortName for the base and the derived cohorts
getCohortNameMap <- function(packageName = "DataAssessment") {
  base <- readSettings("CohortsToCreate.csv", packageName)
  derived <- readSettings("DerivedCohorts.csv", packageName)
  rbind(
    data.frame(cohortId = base$cohortId, cohortName = base$cohort_name, stringsAsFactors = FALSE),
    data.frame(cohortId = derived$cohortId, cohortName = derived$cohortName, stringsAsFactors = FALSE)
  )
}

executeSqlFile <- function(connection, sqlFilename, packageName, ...) {
  sql <- SqlRender::loadRenderTranslateSql(
    sqlFilename         = sqlFilename,
    packageName         = packageName,
    dbms                = DatabaseConnector::dbms(connection),
    tempEmulationSchema = getOption("sqlRenderTempEmulationSchema"),
    ...
  )
  DatabaseConnector::executeSql(connection, sql, progressBar = FALSE, reportOverallTime = FALSE)
  invisible(NULL)
}

querySqlFile <- function(connection, sqlFilename, packageName, ...) {
  sql <- SqlRender::loadRenderTranslateSql(
    sqlFilename         = sqlFilename,
    packageName         = packageName,
    dbms                = DatabaseConnector::dbms(connection),
    tempEmulationSchema = getOption("sqlRenderTempEmulationSchema"),
    ...
  )
  DatabaseConnector::querySql(connection, sql, snakeCaseToCamelCase = TRUE)
}

# Derived cohorts live in cohortTableNew, base cohorts in cohortTable
tableForCohort <- function(cohortId, derivedCohortIds, cohortTable, cohortTableNew) {
  ifelse(cohortId %in% derivedCohortIds, cohortTableNew, cohortTable)
}

# Number of persons / entries per cohort id in one cohort table (zero for absent cohorts)
getCohortCountsFromTable <- function(connection, cohortDatabaseSchema, cohortTable, cohortIds, packageName) {
  counts <- querySqlFile(
    connection, "getCohortCounts.sql", packageName,
    cohort_database_schema = cohortDatabaseSchema,
    cohort_table           = cohortTable,
    cohort_ids             = cohortIds
  )
  out <- data.frame(cohortId = cohortIds, cohortEntries = 0, cohortSubjects = 0)
  m <- match(counts$cohortId, out$cohortId)
  out$cohortEntries[m] <- counts$cohortEntries
  out$cohortSubjects[m] <- counts$cohortSubjects
  out
}

# Non-zero counts below minCellCount are replaced by -minCellCount (OHDSI convention)
censorCounts <- function(data, countColumns, minCellCount = 5) {
  if (is.null(data) || nrow(data) == 0 || minCellCount <= 1) {
    return(data)
  }
  for (column in countColumns) {
    small <- !is.na(data[[column]]) & data[[column]] > 0 & data[[column]] < minCellCount
    data[[column]][small] <- -minCellCount
  }
  data
}

addCohortNames <- function(data, nameMap, idColumn, nameColumn) {
  data[[nameColumn]] <- nameMap$cohortName[match(data[[idColumn]], nameMap$cohortId)]
  data
}

# Half-open bins `[lower, upper)` of binWidth days. With the defaults the central
# bin is [-5, 5), followed by [5, 15), [-15, -5) and so on. Empty bins between the
# smallest and the largest occupied bin are returned with a count of zero.
binDayDifference <- function(dayDifference,
                             nPersons = rep(1, length(dayDifference)),
                             binWidth = 10,
                             centerHalfWidth = binWidth / 2) {
  checkmate::assertNumeric(dayDifference)
  checkmate::assertNumeric(nPersons, len = length(dayDifference))
  checkmate::assertNumber(binWidth, lower = 1)
  checkmate::assertNumber(centerHalfWidth, lower = 0)

  if (length(dayDifference) == 0) {
    return(data.frame(
      binIndex = integer(), binLower = numeric(), binUpper = numeric(),
      binLabel = character(), nPersons = numeric()
    ))
  }
  binIndex <- floor((dayDifference + centerHalfWidth) / binWidth)
  counts <- tapply(nPersons, binIndex, sum)
  allIndex <- seq(min(binIndex), max(binIndex))
  n <- as.numeric(counts[as.character(allIndex)])
  n[is.na(n)] <- 0
  lower <- allIndex * binWidth - centerHalfWidth
  upper <- lower + binWidth
  data.frame(
    binIndex = as.integer(allIndex),
    binLower = lower,
    binUpper = upper,
    binLabel = sprintf("[%s, %s)", format(lower, trim = TRUE), format(upper, trim = TRUE)),
    nPersons = n,
    stringsAsFactors = FALSE
  )
}

# Zip the censored result files for sharing
zipStudyResults <- function(outputFolder, databaseId) {
  zipFile <- file.path(outputFolder, sprintf("DataAssessment_Results_%s.zip", databaseId))
  files <- c(
    list.files(outputFolder, pattern = "^CohortCounts\\.csv$", full.names = TRUE),
    list.files(file.path(outputFolder, "intersectionAnalysis"), full.names = TRUE),
    list.files(file.path(outputFolder, "timeToEventAnalysis"), full.names = TRUE),
    list.files(file.path(outputFolder, "diagnostics"), pattern = "\\.zip$", full.names = TRUE)
  )
  zip::zipr(zipfile = zipFile, files = files)
  zipFile
}
