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

#' Build the derived study cohorts
#'
#' Populates the derived cohort table (\code{cohortTableNew}) by intersecting an
#' anchor cohort with a target cohort for each row of
#' \code{inst/settings/DerivedCohorts.csv}, in file order, so that later rows can
#' use cohorts created by earlier ones (101 = 1 x 2, 102 = 101 x 3,
#' 103-107 = 102 x 4, 5, 6, 7, 8).
#'
#' The index date of a person in a cohort is the first \code{cohort_start_date}.
#' A person enters the derived cohort when the target index date minus the anchor
#' index date is between \code{minDays} and \code{maxDays}. The derived cohort
#' start (index) date is the target index date; the end date is the target cohort
#' end date. Anchor and target cohorts are read from \code{cohortTable} (base
#' cohorts) or \code{cohortTableNew} (derived cohorts).
#'
#' A connection may be supplied via \code{connection}; otherwise one is opened
#' from \code{connectionDetails} and closed on exit.
#'
#' @param connectionDetails    DatabaseConnector connection details object.
#'   Ignored when \code{connection} is supplied.
#' @param connection           An optional open DatabaseConnector connection.
#' @param cohortDatabaseSchema Schema holding the cohort tables.
#' @param cohortTable          Base name of the cohort table populated by
#'   \code{\link{generateStudyCohorts}}.
#' @param cohortTableNew       Name of the derived cohort table to populate.
#' @param minDays              Lower limit of target minus anchor index date
#'   (days). Default -90.
#' @param maxDays              Upper limit (days); \code{Inf} for none (default).
#' @param packageName          Name of the package holding the SQL and settings.
#' @param createTable          Logical. If \code{TRUE}, (re)create the derived
#'   cohort table via \code{\link{createCohortTableNew}}.
#' @param deleteExisting       Logical. If \code{TRUE}, delete any existing rows
#'   for the derived \code{cohort_definition_id} values before re-populating.
#'
#' @export
createDerivedCohorts <- function(connectionDetails = NULL,
                                 connection = NULL,
                                 cohortDatabaseSchema,
                                 cohortTable,
                                 cohortTableNew,
                                 minDays        = -90,
                                 maxDays        = Inf,
                                 packageName    = "DataAssessment",
                                 createTable    = TRUE,
                                 deleteExisting = TRUE) {

  checkmate::assertNumber(minDays)
  checkmate::assertNumber(maxDays)
  derivedCohorts <- readSettings("DerivedCohorts.csv", packageName)

  if (is.null(connection)) {
    connection <- DatabaseConnector::connect(connectionDetails)
    on.exit(DatabaseConnector::disconnect(connection))
  }

  if (createTable) {
    createCohortTableNew(connection, cohortDatabaseSchema, cohortTableNew)
  }

  if (deleteExisting) {
    sql <- SqlRender::render("DELETE FROM @schema.@table WHERE cohort_definition_id IN (@ids);",
                             schema = cohortDatabaseSchema,
                             table  = cohortTableNew,
                             ids    = derivedCohorts$cohortId)
    sql <- SqlRender::translate(sql, targetDialect = DatabaseConnector::dbms(connection))
    DatabaseConnector::executeSql(connection, sql, progressBar = FALSE, reportOverallTime = FALSE)
  }

  hasMaxDays <- is.finite(maxDays)
  for (i in seq_len(nrow(derivedCohorts))) {
    spec <- derivedCohorts[i, ]
    message("Creating derived cohort ", spec$cohortId, ": ", spec$cohortName)

    createIntersectionTables(
      connection, cohortDatabaseSchema, cohortTable, cohortTableNew,
      derivedCohorts$cohortId, spec$anchorCohortId, spec$targetCohortId, packageName
    )
    tryCatch(
      executeSqlFile(
        connection, "derivedCohort.sql", packageName,
        cohort_database_schema = cohortDatabaseSchema,
        cohortTableNew         = cohortTableNew,
        output_cohort_id       = spec$cohortId,
        min_days               = minDays,
        has_max_days           = hasMaxDays,
        max_days               = if (hasMaxDays) maxDays else 0
      ),
      error = function(e) stop("Failed on derived cohort ", spec$cohortId, ": ", conditionMessage(e))
    )
    executeSqlFile(connection, "dropIntersectionTables.sql", packageName)
  }

  invisible(NULL)
}

# Creates the temporary tables #anchor_idx, #target_idx and #pair (one row per
# person in both cohorts, with the target minus anchor day difference).
createIntersectionTables <- function(connection,
                                     cohortDatabaseSchema,
                                     cohortTable,
                                     cohortTableNew,
                                     derivedCohortIds,
                                     anchorCohortId,
                                     targetCohortId,
                                     packageName) {
  executeSqlFile(
    connection, "getIntersection.sql", packageName,
    cohort_database_schema = cohortDatabaseSchema,
    anchor_cohort_table    = tableForCohort(anchorCohortId, derivedCohortIds, cohortTable, cohortTableNew),
    target_cohort_table    = tableForCohort(targetCohortId, derivedCohortIds, cohortTable, cohortTableNew),
    anchor_cohort_id       = anchorCohortId,
    target_cohort_id       = targetCohortId
  )
}
