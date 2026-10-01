Place one ATLAS cohort definition JSON export per study cohort here, named `<atlasId>.json`
(the `atlasId` column of `../settings/CohortsToCreate.csv`: 1835, 1837-1843, 1324, 1813, 1801).
The study cohort id (`cohortId` column, 1-8 and 10-12) is what is written to the cohort table.
If `inst/sql/sql_server/<atlasId>.sql` does not exist, the SQL is generated from the JSON with CirceR.
