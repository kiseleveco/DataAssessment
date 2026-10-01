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

#' Time to first event (Kaplan-Meier)
#'
#' Kaplan-Meier time to first event for each target (population) x outcome pair
#' listed in \code{inst/settings/TTEsettings.csv} (columns \code{target_id},
#' \code{target_name}, \code{outcome_id}, \code{outcome_name}, \code{episodic},
#' \code{chronic}, \code{cap_at_observation_end}), using the same method as the PioneerBPA package.
#'
#' For every pair the person-level time-to-event data are extracted into memory
#' (never saved) with \code{getTimeToEvent.sql}, or with
#' \code{getTimeToEventChronic.sql} when \code{chronic == 1} (new-onset outcome,
#' prevalent cases excluded):
#' \itemize{
#'   \item \code{time_to_event}: days from cohort entry to the first outcome
#'     on/after entry, or to the end of follow-up if there is no event;
#'   \item \code{event}: 1 = outcome occurred, 0 = censored. Subjects without an
#'     event are censored at the earlier of the observation period end and the
#'     cohort end date; outcomes after that date are censored, not counted,
#'     except for outcomes with \code{cap_at_observation_end = 0} in the settings
#'     (death), which count as events whenever they are recorded on/after cohort
#'     entry.
#' }
#' The survival curve is then estimated with \code{survival::survfit}. The
#' targets are expected to have one cohort entry per person; \code{101}-\code{107}
#' must be in \code{cohortTable} (see \code{\link{appendDerivedCohortsToBase}}).
#'
#' Results are written to \code{<outputFolder>/timeToEventAnalysis/}:
#' \itemize{
#'   \item \code{kmTable.csv}: the Kaplan-Meier table (time, n_risk, n_event,
#'     n_censor, surv, std_err, ci_lower, ci_upper) per target and outcome;
#'   \item \code{kmEstimates.csv}: survival, 95\% CI and cumulative incidence
#'     (1 - survival) at the horizons \code{horizonsYears} (the estimate at the
#'     last Kaplan-Meier time on or before the horizon, as in PioneerBPA's
#'     3-year estimate).
#' }
#' Counts below \code{minCellCount} are censored in \code{kmTable.csv}.
#'
#' @param connectionDetails    DatabaseConnector connection details object.
#'   Ignored when \code{connection} is supplied.
#' @param connection           An optional open DatabaseConnector connection.
#' @param cdmDatabaseSchema    Schema containing the OMOP CDM tables
#'   (\code{observation_period}).
#' @param cohortDatabaseSchema Schema holding the cohort table.
#' @param cohortTable          Base cohort table holding targets and outcomes.
#' @param databaseId           Short database identifier (no spaces).
#' @param targetCohortIds      Optional subset of target ids (default \code{NULL}
#'   uses everything in the settings file).
#' @param outcomeCohortIds     Optional subset of outcome ids.
#' @param horizonsYears        Horizons in years. Default \code{c(1, 3, 5)}.
#' @param daysPerYear          Days per year used to convert the horizons
#'   (365 gives 365, 1095 and 1825 days).
#' @param minCellCount         Minimum cell count for censoring small counts.
#' @param outputFolder         Path where result files will be written.
#' @param packageName          Name of the package holding the SQL and settings.
#'
#' @return Invisibly, a list with the data frames \code{kmTable} and
#'   \code{kmEstimates}.
#'
#' @export
runTimeToEventAnalysis <- function(connectionDetails = NULL,
                                   connection = NULL,
                                   cdmDatabaseSchema,
                                   cohortDatabaseSchema,
                                   cohortTable,
                                   databaseId,
                                   targetCohortIds = NULL,
                                   outcomeCohortIds = NULL,
                                   horizonsYears = c(1, 3, 5),
                                   daysPerYear = 365,
                                   minCellCount = 5,
                                   outputFolder,
                                   packageName = "DataAssessment") {

  tteFolder <- file.path(outputFolder, "timeToEventAnalysis")
  if (!dir.exists(tteFolder)) {
    dir.create(tteFolder, recursive = TRUE)
  }

  # --------------------------------------------------------------------------
  # Analysis plan: TTEsettings.csv is the single source of truth for which
  # target x outcome pairs to run. The chronic flag (chronic == 1) marks
  # new-onset outcomes for which prevalent cases are excluded.
  # --------------------------------------------------------------------------
  tteSettings <- readSettings("TTEsettings.csv", packageName)

  # Optional subsetting (default NULL = use everything in the file)
  if (!is.null(targetCohortIds)) {
    tteSettings <- tteSettings[tteSettings$target_id %in% targetCohortIds, ]
  }
  if (!is.null(outcomeCohortIds)) {
    tteSettings <- tteSettings[tteSettings$outcome_id %in% outcomeCohortIds, ]
  }

  # Drop rows with missing IDs
  tteSettings <- tteSettings[
    !is.na(tteSettings$target_id) & !is.na(tteSettings$outcome_id),
    ,
    drop = FALSE
  ]

  if (nrow(tteSettings) == 0) {
    ParallelLogger::logWarn("No target/outcome pairs to analyse after filtering TTEsettings.csv.")
    return(invisible(NULL))
  }

  if (is.null(connection)) {
    connection <- DatabaseConnector::connect(connectionDetails)
    on.exit(DatabaseConnector::disconnect(connection))
  }

  allKmTables    <- list()
  allKmEstimates <- list()
  horizonsDays   <- horizonsYears * daysPerYear

  targetIds <- unique(tteSettings$target_id)
  ParallelLogger::logInfo("Time to event: ", length(targetIds), " target cohort(s) to process.")

  for (targetCohortId in targetIds) {

    targetRows <- tteSettings[tteSettings$target_id == targetCohortId, , drop = FALSE]
    targetName <- as.character(targetRows$target_name[1])
    if (is.na(targetName) || !nzchar(targetName)) {
      targetName <- as.character(targetCohortId)
    }

    ParallelLogger::logInfo(
      "=== Target: ", targetName, " (cohort ", targetCohortId, ") - ",
      nrow(targetRows), " outcome(s) ==="
    )

    for (j in seq_len(nrow(targetRows))) {

      outcomeCohortId <- targetRows$outcome_id[j]
      outcomeName     <- as.character(targetRows$outcome_name[j])
      if (is.na(outcomeName) || !nzchar(outcomeName)) {
        outcomeName <- as.character(outcomeCohortId)
      }
      isChronic <- isTRUE(targetRows$chronic[j] == 1)
      # Death can be recorded after the observation period ends, so it is not
      # capped at the end of follow-up (cap_at_observation_end == 0)
      capAtObservationEnd <- !("cap_at_observation_end" %in% names(targetRows)) ||
        !isTRUE(targetRows$cap_at_observation_end[j] == 0)

      ParallelLogger::logInfo("  Outcome: ", outcomeName, " (cohort ", outcomeCohortId, ")")

      # ----------------------------------------------------------------------
      # 1. Extract time-to-event data (individual level - memory only, not saved)
      #    Chronic (new-onset) outcomes use getTimeToEventChronic.sql, which
      #    excludes prevalent cases (outcome before cohort entry). Episodic
      #    outcomes use getTimeToEvent.sql, which keeps all subjects.
      # ----------------------------------------------------------------------
      sqlFile <- if (isChronic) "getTimeToEventChronic.sql" else "getTimeToEvent.sql"
      ParallelLogger::logInfo(
        "    time-to-event (", if (isChronic) "chronic, prevalent excluded" else "episodic", "): ", sqlFile
      )

      sql <- SqlRender::loadRenderTranslateSql(
        sqlFilename            = sqlFile,
        packageName            = packageName,
        dbms                   = DatabaseConnector::dbms(connection),
        tempEmulationSchema    = getOption("sqlRenderTempEmulationSchema"),
        cohort_database_schema = cohortDatabaseSchema,
        cdm_database_schema    = cdmDatabaseSchema,
        cohort_table           = cohortTable,
        target_cohort_id       = targetCohortId,
        outcome_cohort_id      = outcomeCohortId,
        cap_at_observation_end = capAtObservationEnd
      )

      tteData <- DatabaseConnector::querySql(connection, sql, snakeCaseToCamelCase = TRUE)

      if (nrow(tteData) == 0) {
        ParallelLogger::logWarn("    No data for ", targetName, " / ", outcomeName, " - skipping.")
        next
      }

      # ----------------------------------------------------------------------
      # 2. Kaplan-Meier
      # ----------------------------------------------------------------------
      kmFit <- survival::survfit(
        survival::Surv(timeToEvent, event) ~ 1,
        data = tteData
      )

      kmTable <- data.frame(
        time     = kmFit$time,
        n_risk   = kmFit$n.risk,
        n_event  = kmFit$n.event,
        n_censor = kmFit$n.censor,
        surv     = kmFit$surv,
        std_err  = kmFit$std.err,
        ci_lower = kmFit$lower,
        ci_upper = kmFit$upper
      )

      kmTable$targetId   <- targetCohortId
      kmTable$target     <- targetName
      kmTable$outcome    <- outcomeName
      kmTable$databaseId <- databaseId

      allKmTables[[length(allKmTables) + 1L]] <- kmTable

      # Survival and cumulative incidence at each horizon: the Kaplan-Meier
      # estimate at the last time on or before the horizon
      kmEstimate <- data.frame(
        targetId   = targetCohortId,
        target     = targetName,
        outcome    = outcomeName,
        databaseId = databaseId
      )
      for (k in seq_along(horizonsYears)) {
        suffix <- paste0(horizonsYears[k], "yr")
        idx <- which(kmTable$time <= horizonsDays[k])
        if (length(idx) > 0) {
          lastIdx <- max(idx)
          kmEstimate[[paste0("surv_", suffix)]]                 <- kmTable$surv[lastIdx]
          kmEstimate[[paste0("ci_lower_", suffix)]]             <- kmTable$ci_lower[lastIdx]
          kmEstimate[[paste0("ci_upper_", suffix)]]             <- kmTable$ci_upper[lastIdx]
          kmEstimate[[paste0("cumulative_incidence_", suffix)]] <- 1 - kmTable$surv[lastIdx]
        } else {
          kmEstimate[[paste0("surv_", suffix)]]                 <- NA
          kmEstimate[[paste0("ci_lower_", suffix)]]             <- NA
          kmEstimate[[paste0("ci_upper_", suffix)]]             <- NA
          kmEstimate[[paste0("cumulative_incidence_", suffix)]] <- NA
        }
      }
      allKmEstimates[[length(allKmEstimates) + 1L]] <- kmEstimate

      # Individual-level tteData goes out of scope here and is not saved
      rm(tteData)
    }
  }

  # --------------------------------------------------------------------------
  # 3. Export aggregated results only
  # --------------------------------------------------------------------------
  kmOut <- NULL
  if (length(allKmTables) > 0) {
    kmOut <- do.call(rbind, allKmTables)
    kmOut <- censorCounts(kmOut, c("n_risk", "n_event", "n_censor"), minCellCount)
    readr::write_excel_csv(kmOut, file.path(tteFolder, "kmTable.csv"), na = "")
    ParallelLogger::logInfo("KM table written to kmTable.csv")
  }

  kmEstimatesOut <- NULL
  if (length(allKmEstimates) > 0) {
    kmEstimatesOut <- do.call(rbind, allKmEstimates)
    readr::write_excel_csv(kmEstimatesOut, file.path(tteFolder, "kmEstimates.csv"), na = "")
    ParallelLogger::logInfo("KM estimates written to kmEstimates.csv")
  }

  ParallelLogger::logInfo("Time to event analysis complete. Results written to ", tteFolder)
  invisible(list(kmTable = kmOut, kmEstimates = kmEstimatesOut))
}
