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

#' Execute the DataAssessment study
#'
#' Runs the full DataAssessment analysis end to end. Each analytical step is
#' individually switchable so a site can (re)run just part of the study. The
#' steps run in the following order:
#' \enumerate{
#'   \item \strong{generateCohorts} - instantiate the base cohorts (1-8 and
#'     10-12) on the CDM with \code{\link{generateStudyCohorts}}.
#'   \item \strong{createDerivedCohorts} - build the derived cohorts 101-107 with
#'     \code{\link{createDerivedCohorts}} and append them to the base cohort table
#'     with \code{\link{appendDerivedCohortsToBase}}.
#'   \item \strong{runIntersectionAnalysis} - intersections, binned index date
#'     differences and derived cohort counts with
#'     \code{\link{runIntersectionAnalysis}}.
#'   \item \strong{runTimeToEventAnalysis} - Kaplan-Meier event probabilities at
#'     1, 3 and 5 years with \code{\link{runTimeToEventAnalysis}}.
#'   \item \strong{runDiagnostics} - light CohortDiagnostics with
#'     \code{\link{runCohortDiagnostics}}.
#' }
#' All exported counts below \code{minCellCount} are censored. When
#' \code{zipResults} is \code{TRUE} the files to share are zipped into
#' \code{<outputFolder>/DataAssessment_Results_<databaseId>.zip}.
#'
#' @param connectionDetails        DatabaseConnector connection details object.
#' @param cdmDatabaseSchema        Schema containing the OMOP CDM tables
#'   (read-only).
#' @param vocabularyDatabaseSchema Schema containing the vocabulary tables
#'   (typically the same as \code{cdmDatabaseSchema}).
#' @param cohortDatabaseSchema     Schema where cohort tables will be written
#'   (needs read / write / delete).
#' @param cohortTable              Base name for the cohort table populated by
#'   \code{\link{generateStudyCohorts}}.
#' @param cohortTableNew           Name of the derived cohort table.
#' @param outputFolder             Path where all result files will be written.
#' @param databaseId               Short database identifier (no spaces).
#' @param databaseName             Human-readable database name.
#' @param databaseDescription      Longer database description.
#' @param minDays,maxDays          Window for target minus anchor index date in
#'   the derived cohorts. Defaults -90 and \code{Inf}.
#' @param minCellCount             Minimum cell count for censoring small counts
#'   in the exported results.
#' @param incrementalCohorts       Logical. Passed to
#'   \code{\link{generateStudyCohorts}} as \code{incremental}.
#' @param includeCohortStats       Logical. Passed to
#'   \code{\link{generateStudyCohorts}}.
#' @param generateCohorts          Logical. Run the cohort generation step.
#' @param createDerivedCohorts     Logical. Run the derived cohort step.
#' @param runIntersectionAnalysis  Logical. Run the intersection analysis step.
#' @param runTimeToEventAnalysis   Logical. Run the time to event step.
#' @param runDiagnostics           Logical. Run the diagnostics step.
#' @param zipResults               Logical. Zip the files to share.
#' @param packageName              Name of this package.
#'
#' @export
execute <- function(connectionDetails,
                    cdmDatabaseSchema,
                    vocabularyDatabaseSchema = cdmDatabaseSchema,
                    cohortDatabaseSchema,
                    cohortTable,
                    cohortTableNew,
                    outputFolder,
                    databaseId,
                    databaseName        = databaseId,
                    databaseDescription = databaseId,
                    minDays                 = -90,
                    maxDays                 = Inf,
                    minCellCount            = 5,
                    incrementalCohorts      = TRUE,
                    includeCohortStats      = FALSE,
                    generateCohorts         = TRUE,
                    createDerivedCohorts    = TRUE,
                    runIntersectionAnalysis = TRUE,
                    runTimeToEventAnalysis  = TRUE,
                    runDiagnostics          = TRUE,
                    zipResults              = TRUE,
                    packageName             = "DataAssessment") {

  if (!dir.exists(outputFolder)) {
    dir.create(outputFolder, recursive = TRUE)
  }

  ParallelLogger::addDefaultFileLogger(file.path(outputFolder, "log.txt"), name = "DataAssessmentFileLogger")
  ParallelLogger::addDefaultErrorReportLogger(file.path(outputFolder, "errorReportR.txt"), name = "DataAssessmentErrorLogger")
  on.exit(ParallelLogger::unregisterLogger("DataAssessmentFileLogger", silent = TRUE), add = TRUE)
  on.exit(ParallelLogger::unregisterLogger("DataAssessmentErrorLogger", silent = TRUE), add = TRUE)

  # --------------------------------------------------------------------------
  # 1. Generate the base cohorts
  # --------------------------------------------------------------------------
  if (generateCohorts) {
    ParallelLogger::logInfo("Generating study cohorts")
    generateStudyCohorts(
      connectionDetails        = connectionDetails,
      cdmDatabaseSchema        = cdmDatabaseSchema,
      vocabularyDatabaseSchema = vocabularyDatabaseSchema,
      cohortDatabaseSchema     = cohortDatabaseSchema,
      cohortTable              = cohortTable,
      outputFolder             = outputFolder,
      incremental              = incrementalCohorts,
      includeCohortStats       = includeCohortStats,
      minCellCount             = minCellCount,
      packageName              = packageName
    )
  }

  # --------------------------------------------------------------------------
  # 2. Build the derived cohorts and append them to the base cohort table
  # --------------------------------------------------------------------------
  if (createDerivedCohorts) {
    ParallelLogger::logInfo("Building derived cohorts")
    DataAssessment::createDerivedCohorts(
      connectionDetails    = connectionDetails,
      cohortDatabaseSchema = cohortDatabaseSchema,
      cohortTable          = cohortTable,
      cohortTableNew       = cohortTableNew,
      minDays              = minDays,
      maxDays              = maxDays,
      packageName          = packageName
    )
    DataAssessment::appendDerivedCohortsToBase(
      connectionDetails    = connectionDetails,
      cdmDatabaseSchema    = cdmDatabaseSchema,
      cohortDatabaseSchema = cohortDatabaseSchema,
      cohortTable          = cohortTable,
      cohortTableNew       = cohortTableNew,
      packageName          = packageName
    )
  }

  # --------------------------------------------------------------------------
  # 3. Intersections, index date differences and derived cohort counts
  # --------------------------------------------------------------------------
  if (runIntersectionAnalysis) {
    ParallelLogger::logInfo("Running intersection analysis")
    DataAssessment::runIntersectionAnalysis(
      connectionDetails    = connectionDetails,
      cohortDatabaseSchema = cohortDatabaseSchema,
      cohortTable          = cohortTable,
      cohortTableNew       = cohortTableNew,
      databaseId           = databaseId,
      minDays              = minDays,
      maxDays              = maxDays,
      minCellCount         = minCellCount,
      outputFolder         = outputFolder,
      packageName          = packageName
    )
  }

  # --------------------------------------------------------------------------
  # 4. Time to event (Kaplan-Meier)
  # --------------------------------------------------------------------------
  if (runTimeToEventAnalysis) {
    ParallelLogger::logInfo("Running time to event analysis")
    DataAssessment::appendDerivedCohortsToBase(
      connectionDetails    = connectionDetails,
      cdmDatabaseSchema    = cdmDatabaseSchema,
      cohortDatabaseSchema = cohortDatabaseSchema,
      cohortTable          = cohortTable,
      cohortTableNew       = cohortTableNew,
      packageName          = packageName
    )
    DataAssessment::runTimeToEventAnalysis(
      connectionDetails    = connectionDetails,
      cdmDatabaseSchema    = cdmDatabaseSchema,
      cohortDatabaseSchema = cohortDatabaseSchema,
      cohortTable          = cohortTable,
      databaseId           = databaseId,
      minCellCount         = minCellCount,
      outputFolder         = outputFolder,
      packageName          = packageName
    )
  }

  # --------------------------------------------------------------------------
  # 5. Light CohortDiagnostics
  # --------------------------------------------------------------------------
  if (runDiagnostics) {
    ParallelLogger::logInfo("Running cohort diagnostics")
    DataAssessment::appendDerivedCohortsToBase(
      connectionDetails    = connectionDetails,
      cdmDatabaseSchema    = cdmDatabaseSchema,
      cohortDatabaseSchema = cohortDatabaseSchema,
      cohortTable          = cohortTable,
      cohortTableNew       = cohortTableNew,
      packageName          = packageName
    )
    DataAssessment::runCohortDiagnostics(
      connectionDetails        = connectionDetails,
      cdmDatabaseSchema        = cdmDatabaseSchema,
      cohortDatabaseSchema     = cohortDatabaseSchema,
      cohortTable              = cohortTable,
      exportFolder             = file.path(outputFolder, "diagnostics"),
      databaseId               = databaseId,
      databaseName             = databaseName,
      databaseDescription      = databaseDescription,
      vocabularyDatabaseSchema = vocabularyDatabaseSchema,
      minCellCount             = minCellCount,
      incremental              = incrementalCohorts,
      packageName              = packageName
    )
  }

  if (zipResults) {
    zipFile <- zipStudyResults(outputFolder, databaseId)
    ParallelLogger::logInfo("Results to share: ", zipFile)
  }

  invisible(NULL)
}
