# DataAssessment

Data assessment of a prostate cancer treatment cohort cascade in an OMOP CDM

- **Analytics use case(s):** Characterization
- **Study type:** Data assessment
- **Tags:** Prostate cancer, Metastasis, ADT, ARPI, Chemotherapy, BPA, Radioligand therapy, Triptorelin
- **Data model:** OMOP CDM v5.x
- **Study package status:** In development

## Introduction

`DataAssessment` is an OHDSI ([HADES](https://ohdsi.github.io/Hades/)) study package that
assesses how many patients a database holds along a prostate cancer treatment pathway. It
instantiates simple cohorts (prostate cancer, metastasis, initiation of ADT, ARPI, chemotherapy,
BPA, radioligand therapy and triptorelin), intersects them in a cascade, and characterizes the
resulting cohorts. It is structured like the
[PioneerBPA](https://github.com/kiseleveco/PioneerBPA) study package.

## Features

- Generates the base study cohorts with [CohortGenerator](https://ohdsi.github.io/CohortGenerator/).
- Builds the derived cohorts 101-107 by intersecting cohorts and reports intersection sizes and
  index date differences in 10-day bins.
- Estimates Kaplan-Meier (`survival::survfit`) event probabilities at 1, 3 and 5 years for hypertension, hospitalization
  and death.
- Runs a light [CohortDiagnostics](https://ohdsi.github.io/CohortDiagnostics/).
- Censors counts below `minCellCount` in every exported file.

## Requirements

- R (>= 4.3.0)
- Java (for [DatabaseConnector](https://ohdsi.github.io/DatabaseConnector/) / the JDBC drivers)
- A database account with:
  - **read** access to the OMOP CDM schema, and
  - **read / write / delete** access to a results (work) schema.

## Installation

1. Restore the package versions recorded in `renv.lock`
   ([`renv`](https://rstudio.github.io/renv/)):

   ```r
   install.packages("renv")
   renv::restore()
   ```

2. Install the package itself:

   ```r
   remotes::install_local("path/to/DataAssessment")
   # or, during development:
   devtools::install(".")
   ```

3. Add the ATLAS cohort definition JSON files to `inst/cohorts/` (`<cohortId>.json` for ids 1-8
   and 10-12) and reinstall. If `inst/sql/sql_server/<cohortId>.sql` is absent, the SQL is built
   from the JSON with CirceR.

## How to run

The single file a site edits and runs is [`extras/codeToRun.R`](extras/codeToRun.R). Fill in the
connection details and schema names, then source it. It calls the package's main entry point,
`execute()`.

```r
library(DataAssessment)

connectionDetails <- DatabaseConnector::createConnectionDetails(
  dbms         = "...",
  user         = "...",
  password     = "...",
  server       = "...",
  port         = ...,
  pathToDriver = "/path/to/jdbc"
)

DataAssessment::execute(
  connectionDetails        = connectionDetails,
  cdmDatabaseSchema        = "your_cdm",           # read-only CDM
  vocabularyDatabaseSchema = "your_cdm",           # usually same as CDM
  cohortDatabaseSchema     = "your_results",       # read/write/delete
  cohortTable              = "cohortDataAssessment",
  cohortTableNew           = "cohortTableNew",
  outputFolder             = "/path/to/output",
  databaseId               = "YourDb",
  databaseName             = "Your database",
  databaseDescription      = "Your database description"
)
```

`execute()` runs the study steps, each individually switchable via its `generateCohorts` /
`createDerivedCohorts` / `runIntersectionAnalysis` / `runTimeToEventAnalysis` / `runDiagnostics`
arguments so a site can re-run just part of the study.

Results are written under `outputFolder`: `CohortCounts.csv`; an `intersectionAnalysis/` folder
(intersections, binned index date differences, derived cohort counts); a `timeToEventAnalysis/`
folder; and a `diagnostics/` folder (CohortDiagnostics). With `zipResults = TRUE` the files to
share are zipped into `DataAssessment_Results_<databaseId>.zip`.

## Package structure

Each analytical function lives in its own file under `R/`, with inline documentation.

| File | Function | Role |
|------|----------|------|
| `R/execute.R` | `execute()` | **Main entry point** — orchestrates the steps below. |
| `R/generateStudyCohorts.R` | `generateStudyCohorts()` | Instantiates the base cohorts on the CDM. |
| `R/createCohortTableNew.R` | `createCohortTableNew()` | Creates (drop-and-recreate) the derived cohort table. |
| `R/createDerivedCohorts.R` | `createDerivedCohorts()` | Builds derived cohorts 101-107 by intersecting cohorts. |
| `R/appendDerivedCohorts.R` | `appendDerivedCohortsToBase()` | Copies the derived cohorts into the base cohort table so populations and outcomes share one table. |
| `R/runIntersectionAnalysis.R` | `runIntersectionAnalysis()` | Intersection sizes, binned index date differences and derived cohort counts. |
| `R/runTimeToEventAnalysis.R` | `runTimeToEventAnalysis()` | Kaplan-Meier time to first event (`survival::survfit`). |
| `R/runCohortDiagnostics.R` | `runCohortDiagnostics()` | Light CohortDiagnostics on cohorts 1 and 101-107. |
| `R/utils.R` | (internal) | Settings readers, SQL helpers, binning, censoring. |

Supporting resources under `inst/`:

- `inst/cohorts/` — Circe cohort definitions (JSON).
- `inst/sql/sql_server/` — SQL for the derivation, intersection and time-to-event steps.
- `inst/settings/CohortsToCreate.csv` — base cohorts to generate (ids 1-8, 10-12).
- `inst/settings/DerivedCohorts.csv` — derived cohorts (101-107) with their anchor and target cohort.
- `inst/settings/TTEsettings.csv` — target x outcome pairs for the time to event analysis.
- `inst/settings/DiagnosticsCohorts.csv` — cohorts for CohortDiagnostics and the cohort whose JSON
  defines their index event.

## Cohorts

**Base cohorts** (`inst/settings/CohortsToCreate.csv`):

| id | Cohort | id | Cohort |
|----|--------|----|--------|
| 1 | Prostate cancer | 7 | Initiation of radioligand therapy |
| 2 | Metastasis | 8 | Initiation of triptorelin |
| 3 | Initiation of ADT | 10 | Hypertension (outcome) |
| 4 | Initiation of ARPI | 11 | Hospitalization (outcome) |
| 5 | Initiation of chemotherapy | 12 | Death (outcome) |
| 6 | Initiation of BPA | | |

**Derived cohorts** (`inst/settings/DerivedCohorts.csv`):

| Analysis | Anchor | Target | Derived cohort |
|----------|--------|--------|----------------|
| 1 | 1 | 2 | 101 |
| 2 | 101 | 3 | 102 |
| 3 | 102 | 4, 5, 6, 7, 8 | 103, 104, 105, 106, 107 |

The index date of a person in a cohort is the first `cohort_start_date`. A person enters the derived
cohort when the target index date minus the anchor index date is within `minDays` (default -90) and
`maxDays` (default `Inf`). The derived cohort index date is the target index date.

## Time to event

`runTimeToEventAnalysis()` uses the same Kaplan-Meier method as PioneerBPA for the pairs in
`inst/settings/TTEsettings.csv`: cohorts 1, 101 and 102 against outcomes 10 (hypertension),
11 (hospitalization) and 12 (death).

- Person-level `time_to_event` / `event` data are extracted into memory with `getTimeToEvent.sql`
  (episodic: first outcome on/after cohort entry, prior outcomes do not exclude anyone) or
  `getTimeToEventChronic.sql` (chronic: new-onset, prevalent cases excluded), chosen by the
  `episodic` / `chronic` flags in `TTEsettings.csv`. Persons without an event are censored at the
  earlier of the observation period end and the cohort end date; outcomes after that date are
  censored, except death (`cap_at_observation_end = 0` in `TTEsettings.csv`), which counts as an
  event whenever it is recorded on/after cohort entry, also after the observation period ends. Derived cohorts are appended to the base cohort table with the end of continuous
  observation as cohort end date.
- The curve is fitted with `survival::survfit(Surv(timeToEvent, event) ~ 1)`.
- `timeToEventAnalysis/kmTable.csv` holds the Kaplan-Meier table (time, n_risk, n_event, n_censor,
  surv, std_err, ci_lower, ci_upper) and `kmEstimates.csv` the survival, 95% CI and cumulative
  incidence (1 - survival) at 1, 3 and 5 years (365, 1095, 1825 days): the estimate at the last
  Kaplan-Meier time on or before the horizon.
- The target cohorts must have one entry per person.

## Light CohortDiagnostics

`runCohortDiagnostics()` runs only the index event breakdown and a temporal characterization of
procedures and drug era start in the windows -9999 to 0, -90 to 90 and 0 to 9999 days. Derived
cohorts have no ATLAS definition, so they use the JSON of the cohort that defines their index event
(see `DiagnosticsCohorts.csv`). Browse the results with `extras/launchDiagnosticsExplorer.R`.

## License

`DataAssessment` is licensed under Apache License 2.0.
