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
# Build a results database from the CohortDiagnostics output and launch the
# Diagnostics Explorer Shiny app.
#
# `execute()` writes one CohortDiagnostics results zip per database into
# `<outputFolder>/diagnostics/` (i.e. the `exportFolder`). This script loads
# those zip(s) into a results database and opens the interactive viewer.
#
# Two options are provided - pick ONE:
#
#   Option A - Local SQLite  (simplest; no database server needed).
#   Option B - Results database server (PostgreSQL / SQL Server / etc.), the
#              "build a database and upload" workflow for a shared instance.
#
# Open this file in RStudio, edit the variables in section 1, then run the
# section for the option you want.
# ==============================================================================

library(CohortDiagnostics)

# ------------------------------------------------------------------------------
# 1. Inputs  (edit these)
# ------------------------------------------------------------------------------

# Folder holding the CohortDiagnostics result zip(s). With the default study
# layout this is <outputFolder>/diagnostics.
dataFolder <- file.path("output", "MyDatabase_DataAssessment_v0.1", "diagnostics")


# ==============================================================================
# Option A - Local SQLite  (no server required)
# ==============================================================================
# Merges every zip in `dataFolder` into a single SQLite file, then launches the
# viewer against it. Requires the RSQLite package (install.packages("RSQLite")).

sqliteDbPath <- file.path(dataFolder, "MergedCohortDiagnosticsData.sqlite")

# Build: merge the per-database zips into one SQLite results file.
CohortDiagnostics::createMergedResultsFile(
  dataFolder   = dataFolder,
  sqliteDbPath = sqliteDbPath,
  overwrite    = TRUE
)

# Launch the Shiny app against the SQLite file.
CohortDiagnostics::launchDiagnosticsExplorer(
  sqliteDbPath = sqliteDbPath
)


# ==============================================================================
# Option B - Results database server (PostgreSQL / SQL Server / etc.)
# ==============================================================================
# Creates the CohortDiagnostics results data model in a database schema, uploads
# each result zip into it, then launches the viewer against that schema. Use
# this for a shared/persistent results instance.

# -- B.1 Connection to the RESULTS database (not the CDM) ----------------------
# `dbms` is any DatabaseConnector-supported dialect, e.g. "postgresql",
# "sql server", "redshift". Provide the matching JDBC driver via pathToDriver
# (see DatabaseConnector::downloadJdbcDrivers()).
resultsConnectionDetails <- DatabaseConnector::createConnectionDetails(
  dbms         = "postgresql",
  server       = "localhost/ohdsi",       # host/database
  user         = "results_user",
  password     = keyring::key_get("results_db"),  # avoid hard-coding secrets
  port         = 5432,
  pathToDriver = "/path/to/jdbc"
)

resultsDatabaseSchema <- "cohort_diagnostics"

# -- B.2 Build the results data model (tables) --------------------------------
# Creates the empty CohortDiagnostics result tables in `resultsDatabaseSchema`.
CohortDiagnostics::createResultsDataModel(
  connectionDetails = resultsConnectionDetails,
  databaseSchema    = resultsDatabaseSchema
)

# -- B.3 Upload every result zip into the schema ------------------------------
zipFiles <- list.files(dataFolder, pattern = "\\.zip$", full.names = TRUE)
if (length(zipFiles) == 0) {
  stop("No result zip files found in ", dataFolder)
}
for (zipFile in zipFiles) {
  message("Uploading ", basename(zipFile))
  CohortDiagnostics::uploadResults(
    connectionDetails = resultsConnectionDetails,
    schema            = resultsDatabaseSchema,
    zipFileName       = zipFile
  )
}

# -- B.4 Launch the Shiny app against the results schema ----------------------
CohortDiagnostics::launchDiagnosticsExplorer(
  connectionDetails     = resultsConnectionDetails,
  resultsDatabaseSchema = resultsDatabaseSchema
)
