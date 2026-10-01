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

# ==============================================================================
# DataAssessment - study execution script
#
# This is the single file a site edits and runs to execute the study. Fill in
# the site-specific parameters below, then call DataAssessment::execute().
# Share ONLY the zip file reported at the end.
# ==============================================================================

# Restore the package versions recorded in renv.lock, then install the package
# install.packages("renv")
# renv::restore()
# remotes::install_local("path/to/DataAssessment")

library(DataAssessment)

# ------------------------------------------------------------------------------
# 1. Site-specific database connection  (edit these for every site)
# ------------------------------------------------------------------------------
source("../credentials.r")

JDBC <- "/home/a_kiselev/Jdbc"
connectionDetails <- DatabaseConnector::createConnectionDetails(
  dbms         = DBMS,
  user         = USER,
  password     = PASSWORD,
  server       = SERVER,
  port         = DB_PORT,
  pathToDriver = JDBC
)

# ------------------------------------------------------------------------------
# 2. Schema and table names
# ------------------------------------------------------------------------------
cdmDatabaseSchema        <- "marketscan_ccaemdcr_prod_merged"                      # read-only CDM
vocabularyDatabaseSchema <- cdmDatabaseSchema          # usually same as CDM
cohortDatabaseSchema     <- "marketscan_ccaemdcr_aug2025_results"                  # write-enabled; needs read/write/delete
cohortTable              <- "cohortDataAssessment"
cohortTableNew           <- "cohortTableNewDataAssessment"

databaseId          <- "MarketScan"                    # short identifier, no spaces
databaseName        <- "MarketScan"
databaseDescription <- "MarketScan"

outputFolder <- file.path("output", paste0(databaseId, "_DataAssessment_v0.1"))

# Temp table emulation (Oracle / some Spark configs)
options(sqlRenderTempEmulationSchema = NULL)

# ------------------------------------------------------------------------------
# 3. Cohort definition ids  (inst/settings/*.csv; definitions in inst/cohorts/)
#
#   Base cohorts      (CohortsToCreate.csv; ATLAS ids in the atlasId column, JSON/SQL in
#                      inst/cohorts/<atlasId>.json and inst/sql/sql_server/<atlasId>.sql)
#     1 Prostate cancer         2 Metastasis             3 ADT initiation
#     4 ARPI initiation         5 Chemotherapy initiation 6 BPA initiation
#     7 Radioligand initiation  8 Triptorelin initiation
#     10 Hypertension           11 Hospitalization        12 Death
#   Derived cohorts   (DerivedCohorts.csv)
#     101 = 1 x 2   102 = 101 x 3   103-107 = 102 x 4, 5, 6, 7, 8
# ------------------------------------------------------------------------------

# Derived cohort window: target index date minus anchor index date
minDays <- -90
maxDays <- Inf

# ------------------------------------------------------------------------------
# 4. Run options
# ------------------------------------------------------------------------------
minCellCount            <- 5       # counts below this are censored in all exported files
includeCohortStats      <- FALSE
incrementalCohorts      <- TRUE
generateCohorts         <- TRUE
createDerivedCohorts    <- TRUE
runIntersectionAnalysis <- TRUE
runTimeToEventAnalysis  <- TRUE
runDiagnostics          <- TRUE
zipResults              <- TRUE

# ------------------------------------------------------------------------------
# 5. Execute the study
# ------------------------------------------------------------------------------
DataAssessment::execute(
  connectionDetails        = connectionDetails,
  cdmDatabaseSchema        = cdmDatabaseSchema,
  vocabularyDatabaseSchema = vocabularyDatabaseSchema,
  cohortDatabaseSchema     = cohortDatabaseSchema,
  cohortTable              = cohortTable,
  cohortTableNew           = cohortTableNew,
  outputFolder             = outputFolder,
  databaseId               = databaseId,
  databaseName             = databaseName,
  databaseDescription      = databaseDescription,
  minDays                  = minDays,
  maxDays                  = maxDays,
  minCellCount             = minCellCount,
  incrementalCohorts       = incrementalCohorts,
  includeCohortStats       = includeCohortStats,
  generateCohorts          = generateCohorts,
  createDerivedCohorts     = createDerivedCohorts,
  runIntersectionAnalysis  = runIntersectionAnalysis,
  runTimeToEventAnalysis   = runTimeToEventAnalysis,
  runDiagnostics           = runDiagnostics,
  zipResults               = zipResults
)

# ------------------------------------------------------------------------------
# 6. Share
# ------------------------------------------------------------------------------
list.files(outputFolder, pattern = "DataAssessment_Results_.*\\.zip", full.names = TRUE)
