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

#' Intersections of the cohort cascade (Analyses 1-3)
#'
#' For each row of \code{inst/settings/DerivedCohorts.csv} reports the size of the
#' intersection between the anchor and the target cohort, the target minus anchor
#' index date difference in bins of \code{binWidth} days (central bin
#' \code{[-5, 5)} for the default width of 10), and the number of persons in the
#' derived cohort created by \code{\link{createDerivedCohorts}}. Counts below
#' \code{minCellCount} are censored.
#'
#' Results are written to \code{<outputFolder>/intersectionAnalysis/}:
#' \code{intersections.csv}, \code{dayDifferenceBins.csv} and
#' \code{derivedCohortCounts.csv}.
#'
#' @param connectionDetails    DatabaseConnector connection details object.
#'   Ignored when \code{connection} is supplied.
#' @param connection           An optional open DatabaseConnector connection.
#' @param cohortDatabaseSchema Schema holding the cohort tables.
#' @param cohortTable          Base cohort table.
#' @param cohortTableNew       Derived cohort table.
#' @param databaseId           Short database identifier (no spaces).
#' @param minDays,maxDays      Window used for the derived cohorts (recorded in
#'   the output; use the values passed to \code{\link{createDerivedCohorts}}).
#' @param binWidth             Bin width in days. Default 10.
#' @param minCellCount         Minimum cell count for censoring small counts.
#' @param outputFolder         Path where result files will be written.
#' @param packageName          Name of the package holding the SQL and settings.
#'
#' @return Invisibly, a list with the censored tables \code{intersections},
#'   \code{dayDifferenceBins} and \code{derivedCohortCounts}.
#'
#' @export
runIntersectionAnalysis <- function(connectionDetails = NULL,
                                    connection = NULL,
                                    cohortDatabaseSchema,
                                    cohortTable,
                                    cohortTableNew,
                                    databaseId,
                                    minDays = -90,
                                    maxDays = Inf,
                                    binWidth = 10,
                                    minCellCount = 5,
                                    outputFolder,
                                    packageName = "DataAssessment") {

  analysisFolder <- file.path(outputFolder, "intersectionAnalysis")
  if (!dir.exists(analysisFolder)) {
    dir.create(analysisFolder, recursive = TRUE)
  }
  derivedCohorts <- readSettings("DerivedCohorts.csv", packageName)
  nameMap <- getCohortNameMap(packageName)

  if (is.null(connection)) {
    connection <- DatabaseConnector::connect(connectionDetails)
    on.exit(DatabaseConnector::disconnect(connection))
  }

  intersections <- list()
  bins <- list()
  derivedCounts <- list()

  for (i in seq_len(nrow(derivedCohorts))) {
    spec <- derivedCohorts[i, ]
    ParallelLogger::logInfo(sprintf(
      "Analysis %d: cohort %d x cohort %d -> cohort %d",
      spec$analysisId, spec$anchorCohortId, spec$targetCohortId, spec$cohortId
    ))

    createIntersectionTables(
      connection, cohortDatabaseSchema, cohortTable, cohortTableNew,
      derivedCohorts$cohortId, spec$anchorCohortId, spec$targetCohortId, packageName
    )
    counts <- querySqlFile(connection, "getIntersectionCounts.sql", packageName)
    distribution <- querySqlFile(connection, "getDayDifference.sql", packageName)
    executeSqlFile(connection, "dropIntersectionTables.sql", packageName)

    ids <- data.frame(
      databaseId = databaseId, analysisId = spec$analysisId,
      anchorCohortId = spec$anchorCohortId, targetCohortId = spec$targetCohortId
    )
    intersections[[i]] <- cbind(ids, counts)

    binTable <- binDayDifference(
      dayDifference = distribution$dayDiff,
      nPersons      = distribution$nPersons,
      binWidth      = binWidth
    )
    if (nrow(binTable) > 0) {
      bins[[i]] <- cbind(ids[rep(1, nrow(binTable)), ], binTable, row.names = NULL)
    }

    derivedCount <- getCohortCountsFromTable(
      connection, cohortDatabaseSchema, cohortTableNew, spec$cohortId, packageName
    )
    derivedCounts[[i]] <- data.frame(
      ids, derivedCohortId = spec$cohortId, minDays = minDays, maxDays = maxDays,
      cohortEntries = derivedCount$cohortEntries, cohortSubjects = derivedCount$cohortSubjects
    )
    ParallelLogger::logInfo(sprintf(
      "  intersection n = %s; cohort %d n = %s",
      counts$intersectionN, spec$cohortId, derivedCount$cohortSubjects
    ))
  }

  intersections <- do.call(rbind, intersections)
  intersections <- censorCounts(intersections, c("anchorN", "targetN", "intersectionN"), minCellCount)
  intersections <- addCohortNames(intersections, nameMap, "anchorCohortId", "anchorCohortName")
  intersections <- addCohortNames(intersections, nameMap, "targetCohortId", "targetCohortName")

  bins <- censorCounts(do.call(rbind, bins), "nPersons", minCellCount)

  derivedCounts <- do.call(rbind, derivedCounts)
  derivedCounts <- censorCounts(derivedCounts, c("cohortEntries", "cohortSubjects"), minCellCount)
  derivedCounts <- addCohortNames(derivedCounts, nameMap, "derivedCohortId", "derivedCohortName")

  readr::write_excel_csv(intersections, file.path(analysisFolder, "intersections.csv"), na = "")
  if (!is.null(bins)) {
    readr::write_excel_csv(bins, file.path(analysisFolder, "dayDifferenceBins.csv"), na = "")
  }
  readr::write_excel_csv(derivedCounts, file.path(analysisFolder, "derivedCohortCounts.csv"), na = "")
  ParallelLogger::logInfo("Intersection analysis written to ", analysisFolder)

  invisible(list(intersections = intersections, dayDifferenceBins = bins, derivedCohortCounts = derivedCounts))
}
