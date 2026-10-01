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

#' Instantiate study cohorts on the CDM
#'
#' Generates the base study cohorts (ids 1-8 and 10-12) using the
#' \pkg{CohortGenerator} package. Cohort definitions are read from
#' \code{inst/settings/CohortsToCreate.csv}, \code{inst/cohorts/} (ATLAS JSON,
#' \code{<cohortId>.json}) and, when present, \code{inst/sql/sql_server/}
#' (\code{<cohortId>.sql}). When a SQL file is missing the SQL is built from the
#' JSON with CirceR.
#'
#' When \code{includeCohortStats = TRUE} the cohort SQL is rebuilt from the Circe
#' JSON expressions using \code{CirceR::buildCohortQuery(..., generateStats = TRUE)}
#' so that inclusion rule statistics are populated during generation. The
#' statistics are then exported to \code{outputFolder/cohortStatistics/} as CSV
#' files compatible with \code{CohortDiagnostics}.
#'
#' Cohort counts are written to \code{outputFolder/CohortCounts.csv} with counts
#' below \code{minCellCount} censored.
#'
#' @param connectionDetails        DatabaseConnector connection details object.
#' @param cdmDatabaseSchema        Schema containing the OMOP CDM tables (read-only).
#' @param vocabularyDatabaseSchema Schema containing the vocabulary tables
#'   (typically the same as \code{cdmDatabaseSchema}; CohortGenerator resolves the
#'   vocabulary from the CDM schema).
#' @param cohortDatabaseSchema     Schema where cohort tables will be written
#'   (needs read / write / delete).
#' @param cohortTable              Base name for the cohort table. Additional
#'   statistics tables are derived from this name by
#'   \code{CohortGenerator::getCohortTableNames()}.
#' @param outputFolder             Path where result files will be written.
#' @param incremental              Logical. If \code{TRUE},
#'   \code{CohortGenerator::generateCohortSet} skips cohorts whose SQL checksum
#'   has not changed since the last run.
#' @param includeCohortStats       Logical. If \code{TRUE}, regenerates cohort SQL
#'   with \code{generateStats = TRUE} and exports the inclusion rule statistics.
#' @param minCellCount             Minimum cell count for censoring small counts.
#' @param packageName              Name of the package holding the cohort
#'   definitions.
#'
#' @export
generateStudyCohorts <- function(connectionDetails,
                                 cdmDatabaseSchema,
                                 vocabularyDatabaseSchema = cdmDatabaseSchema,
                                 cohortDatabaseSchema,
                                 cohortTable,
                                 outputFolder,
                                 incremental        = FALSE,
                                 includeCohortStats = FALSE,
                                 minCellCount       = 5,
                                 packageName        = "DataAssessment") {

  if (!dir.exists(outputFolder)) {
    dir.create(outputFolder, recursive = TRUE)
  }

  # --------------------------------------------------------------------------
  # 1. Load cohort definition set from inst/
  # --------------------------------------------------------------------------
  ParallelLogger::logInfo("Loading cohort definition set from package")
  cohortDefinitionSet <- loadStudyCohortDefinitionSet(packageName, rebuildSql = includeCohortStats)
  ParallelLogger::logInfo(nrow(cohortDefinitionSet), " cohort(s) found in definition set.")

  # --------------------------------------------------------------------------
  # 2. Create cohort tables (incremental keeps existing tables and results)
  # --------------------------------------------------------------------------
  cohortTableNames <- CohortGenerator::getCohortTableNames(cohortTable = cohortTable)
  ParallelLogger::logInfo("Creating cohort tables")
  CohortGenerator::createCohortTables(
    connectionDetails    = connectionDetails,
    cohortTableNames     = cohortTableNames,
    cohortDatabaseSchema = cohortDatabaseSchema,
    incremental          = incremental
  )

  # --------------------------------------------------------------------------
  # 3. Generate cohorts
  # --------------------------------------------------------------------------
  ParallelLogger::logInfo("Generating cohorts")
  CohortGenerator::generateCohortSet(
    connectionDetails    = connectionDetails,
    cdmDatabaseSchema    = cdmDatabaseSchema,
    cohortDatabaseSchema = cohortDatabaseSchema,
    cohortTableNames     = cohortTableNames,
    cohortDefinitionSet  = cohortDefinitionSet,
    incremental          = incremental,
    incrementalFolder    = file.path(outputFolder, "incrementalCohorts")
  )

  # --------------------------------------------------------------------------
  # 4. Cohort counts (censored)
  # --------------------------------------------------------------------------
  counts <- CohortGenerator::getCohortCounts(
    connectionDetails    = connectionDetails,
    cohortDatabaseSchema = cohortDatabaseSchema,
    cohortTable          = cohortTableNames$cohortTable
  )
  counts <- censorCounts(counts, c("cohortEntries", "cohortSubjects"), minCellCount)
  readr::write_excel_csv(counts, file.path(outputFolder, "CohortCounts.csv"), na = "")
  ParallelLogger::logInfo("Cohort counts written to CohortCounts.csv")

  # --------------------------------------------------------------------------
  # 5. Export cohort statistics (inclusion rule statistics)
  # --------------------------------------------------------------------------
  if (includeCohortStats) {
    statsFolder <- file.path(outputFolder, "cohortStatistics")
    if (!dir.exists(statsFolder)) {
      dir.create(statsFolder, recursive = TRUE)
    }
    ParallelLogger::logInfo("Inserting inclusion rule names")
    CohortGenerator::insertInclusionRuleNames(
      connectionDetails    = connectionDetails,
      cohortDefinitionSet  = cohortDefinitionSet,
      cohortDatabaseSchema = cohortDatabaseSchema,
      cohortInclusionTable = cohortTableNames$cohortInclusionTable
    )
    ParallelLogger::logInfo("Exporting cohort statistics to cohortStatistics/")
    CohortGenerator::exportCohortStatsTables(
      connectionDetails      = connectionDetails,
      cohortDatabaseSchema   = cohortDatabaseSchema,
      cohortTableNames       = cohortTableNames,
      cohortStatisticsFolder = statsFolder,
      minCellCount           = minCellCount
    )
  }

  invisible(counts)
}

# Cohort definition set (cohortId, cohortName, sql, json) of the base cohorts.
# JSON is inst/cohorts/<cohortId>.json; SQL is inst/sql/sql_server/<cohortId>.sql
# when it exists (and rebuildSql is FALSE), otherwise it is built from the JSON.
loadStudyCohortDefinitionSet <- function(packageName = "DataAssessment", rebuildSql = FALSE) {
  settings <- readSettings("CohortsToCreate.csv", packageName)
  cohortDefinitionSet <- data.frame(
    cohortId   = as.double(settings$cohortId),
    cohortName = settings$cohort_name,
    stringsAsFactors = FALSE
  )

  jsonFiles <- file.path(system.file("cohorts", package = packageName), paste0(settings$cohortId, ".json"))
  missingJson <- settings$cohortId[!file.exists(jsonFiles)]
  if (length(missingJson) > 0) {
    stop(
      "Cohort definition JSON not found for cohort ids: ", paste(missingJson, collapse = ", "),
      ". Add '<cohortId>.json' files to inst/cohorts/ and reinstall the package."
    )
  }
  cohortDefinitionSet$json <- vapply(
    jsonFiles, function(f) paste(readLines(f, warn = FALSE), collapse = "\n"), character(1), USE.NAMES = FALSE
  )

  sqlFiles <- file.path(system.file("sql", "sql_server", package = packageName), paste0(settings$cohortId, ".sql"))
  cohortDefinitionSet$sql <- vapply(seq_along(sqlFiles), function(i) {
    if (!rebuildSql && file.exists(sqlFiles[i])) {
      SqlRender::readSql(sqlFiles[i])
    } else {
      expression <- CirceR::cohortExpressionFromJson(cohortDefinitionSet$json[i])
      CirceR::buildCohortQuery(expression, options = CirceR::createGenerateOptions(generateStats = TRUE))
    }
  }, character(1))
  cohortDefinitionSet
}
