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

#' Run a light CohortDiagnostics on the study cohorts
#'
#' Runs \code{CohortDiagnostics::executeDiagnostics} for the cohorts listed in
#' \code{inst/settings/DiagnosticsCohorts.csv} (cohort 1 and the derived cohorts
#' 101-107), which must all be in \code{cohortTable} (see
#' \code{\link{appendDerivedCohortsToBase}}).
#'
#' Only two diagnostics are on: the index event breakdown and the temporal
#' characterization, limited to procedures and drug era start in the windows
#' -9999 to 0, -90 to 90 and 0 to 9999 days. Derived cohorts are created by SQL
#' and have no ATLAS definition, so for the index event breakdown they use the
#' JSON of the cohort that defines their index event (column
#' \code{indexEventCohortId} of the settings file); they are never regenerated.
#'
#' @param connectionDetails        DatabaseConnector connection details object.
#' @param cdmDatabaseSchema        Schema containing the OMOP CDM tables.
#' @param cohortDatabaseSchema     Schema holding the cohort table.
#' @param cohortTable              Base cohort table holding all diagnosed cohorts.
#' @param exportFolder             Path where diagnostics results will be written.
#' @param databaseId               Short database identifier (no spaces).
#' @param databaseName             Human-readable database name.
#' @param databaseDescription      Longer database description.
#' @param vocabularyDatabaseSchema Schema containing the vocabulary tables
#'   (typically the same as \code{cdmDatabaseSchema}).
#' @param minCellCount             Minimum cell count for censoring small counts
#'   in the exported results.
#' @param incremental              Logical. Use CohortDiagnostics incremental mode.
#' @param packageName              Name of the package holding the settings.
#'
#' @export
runCohortDiagnostics <- function(connectionDetails,
                                 cdmDatabaseSchema,
                                 cohortDatabaseSchema,
                                 cohortTable,
                                 exportFolder,
                                 databaseId,
                                 databaseName        = databaseId,
                                 databaseDescription = databaseId,
                                 vocabularyDatabaseSchema = cdmDatabaseSchema,
                                 minCellCount        = 5,
                                 incremental         = FALSE,
                                 packageName         = "DataAssessment") {

  # --- 1. cohort set ----------------------------------------------------------
  cohortDefinitionSet <- getDiagnosticsCohortDefinitionSet(packageName)

  # --- 2. temporal covariate settings: procedures and drug era start only ----
  temporalCovariateSettings <- FeatureExtraction::createTemporalCovariateSettings(
    useProcedureOccurrence = TRUE,
    useDrugEraStart        = TRUE,
    temporalStartDays      = c(-9999, -90, 0),
    temporalEndDays        = c(0, 90, 9999)
  )

  # --- 3. run -----------------------------------------------------------------
  dir.create(exportFolder, recursive = TRUE, showWarnings = FALSE)
  CohortDiagnostics::executeDiagnostics(
    cohortDefinitionSet       = cohortDefinitionSet,
    exportFolder              = exportFolder,
    databaseId                = databaseId,
    databaseName              = databaseName,
    databaseDescription       = databaseDescription,
    connectionDetails         = connectionDetails,
    cdmDatabaseSchema         = cdmDatabaseSchema,
    cohortDatabaseSchema      = cohortDatabaseSchema,
    cohortTable               = cohortTable,
    cohortTableNames          = CohortGenerator::getCohortTableNames(cohortTable = cohortTable),
    vocabularyDatabaseSchema  = vocabularyDatabaseSchema,
    cohortIds                 = cohortDefinitionSet$cohortId,
    cdmVersion                = 5,
    minCellCount              = minCellCount,
    temporalCovariateSettings = temporalCovariateSettings,
    incremental               = incremental,
    incrementalFolder         = file.path(exportFolder, "incremental"),
    runInclusionStatistics            = FALSE,
    runIncludedSourceConcepts         = FALSE,
    runOrphanConcepts                 = FALSE,
    runTimeSeries                     = FALSE,
    runVisitContext                   = FALSE,
    runBreakdownIndexEvents           = TRUE,
    runIncidenceRate                  = FALSE,
    runCohortRelationship             = FALSE,
    runTemporalCohortCharacterization = TRUE
  )

  invisible(exportFolder)
}

# Cohort definition set for CohortDiagnostics: cohortId / cohortName from
# DiagnosticsCohorts.csv with the JSON and SQL of the cohort that defines the
# index event (itself for base cohorts).
getDiagnosticsCohortDefinitionSet <- function(packageName = "DataAssessment") {
  diagnosticsCohorts <- readSettings("DiagnosticsCohorts.csv", packageName)
  definitions <- loadStudyCohortDefinitionSet(packageName)
  source <- definitions[match(diagnosticsCohorts$indexEventCohortId, definitions$cohortId), ]
  if (anyNA(source$cohortId)) {
    stop("No cohort definition for index event cohort id(s): ",
         paste(diagnosticsCohorts$indexEventCohortId[is.na(source$cohortId)], collapse = ", "))
  }
  data.frame(
    cohortId   = diagnosticsCohorts$cohortId,
    cohortName = diagnosticsCohorts$cohortName,
    sql        = source$sql,
    json       = source$json,
    stringsAsFactors = FALSE
  )
}
