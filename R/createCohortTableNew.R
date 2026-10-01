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

#' Create the derived cohort table
#'
#' Creates the table used to hold the derived cohorts
#' (\code{cohort_definition_id}, \code{subject_id}, \code{cohort_start_date},
#' \code{cohort_end_date}). If the table already exists it is dropped first, so
#' the function always returns a fresh, empty table. \strong{Any previously
#' computed derived cohorts in this table are discarded.}
#'
#' @param connection           An open DatabaseConnector connection.
#' @param cohortDatabaseSchema Schema in which to create the table.
#' @param cohortTableNew       Name of the derived cohort table to create.
#'
#' @return Invisibly returns \code{TRUE}.
#'
#' @export
createCohortTableNew <- function(connection,
                                 cohortDatabaseSchema,
                                 cohortTableNew) {

  exists <- DatabaseConnector::existsTable(
    connection     = connection,
    databaseSchema = cohortDatabaseSchema,
    tableName      = cohortTableNew
  )

  if (exists) {
    message("Table ", cohortDatabaseSchema, ".", cohortTableNew, " already exists - dropping it")
    sql <- "DROP TABLE @cohort_database_schema.@cohortTableNew;"
    sql <- SqlRender::render(sql,
                             cohort_database_schema = cohortDatabaseSchema,
                             cohortTableNew         = cohortTableNew)
    sql <- SqlRender::translate(sql, targetDialect = DatabaseConnector::dbms(connection))
    DatabaseConnector::executeSql(connection, sql, progressBar = FALSE, reportOverallTime = FALSE)
  }

  message("Creating ", cohortDatabaseSchema, ".", cohortTableNew)
  sql <- "
    CREATE TABLE @cohort_database_schema.@cohortTableNew (
      cohort_definition_id INT,
      subject_id BIGINT,
      cohort_start_date DATE,
      cohort_end_date DATE
    );"
  sql <- SqlRender::render(sql,
                           cohort_database_schema = cohortDatabaseSchema,
                           cohortTableNew         = cohortTableNew)
  sql <- SqlRender::translate(sql, targetDialect = DatabaseConnector::dbms(connection))
  DatabaseConnector::executeSql(connection, sql, progressBar = FALSE, reportOverallTime = FALSE)
  invisible(TRUE)
}
