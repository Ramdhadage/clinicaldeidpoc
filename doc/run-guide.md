# Clinical De-identification PoC — Milestone 1 Run Guide

## 1. What This Milestone Implements

Milestone 1 is a **synthetic-only, non-releasing structured-data foundation**.

It currently:

- Accepts only an XLSX workbook.
- Requires the exact worksheet name **Clinical_Data**.
- Requires the seven approved columns:
  - **Record_No**
  - **Patient_Name**
  - **DOB**
  - **Diagnosis_Journey**
  - **Treatment_History**
  - **MRN**
  - **Patient_ID**
- Removes all values from Record_No, Patient_Name, MRN, and Patient_ID.
- Converts DOB to a four-digit year or **90+**.
- Hides narrative text in the UI behind **[PENDING_TEXT_DEIDENTIFICATION]**.
- Invalidates previous results whenever another file is uploaded.
- Blocks every download/export because Azure free-text processing, complete validation, human review, and approval have not yet been implemented.

This milestone does **not** produce a releasable or HIPAA-de-identified dataset.

> **Security restriction:** Use only the supplied synthetic test data. Do not upload real PHI to the local application.

## 2. Repository Entry Points

| File | Purpose |
|---|---|
| app.R | Thin Shiny application entry point |
| config/schema.yml | Exact workbook and column contract |
| config/poc.yml | Synthetic-only runtime controls |
| rules/safe_harbor_candidate.yml | Proposed structured transformation policy |
| R/ | Modular input, schema, transformation, validation, workflow, UI, and export-guard functions |
| tests/run-core-tests.R | Core regression and fail-closed tests |
| tests/run-app-tests.R | Shiny server/state safety tests |
| scripts/create-sample-workbook.R | Converts the supplied CSV test data to the required XLSX format |
| scripts/run-sample.R | Runs the pipeline without launching Shiny |
| scripts/run-app.R | Starts the local Shiny application |

## 3. Open PowerShell in the Project

    $project = "D:\R shiny Apps\deidentification"
    Set-Location -LiteralPath $project

## 4. Choose the R Environment

### Option A — Current verified development environment

The current workstation has R 4.6.0. A compatible project-local test library has been created under **.r-lib/4.6**. This directory is ignored by Git.

    $rscript = "C:\Program Files\R\R-4.6.0\bin\Rscript.exe"
    & $rscript --version

The implementation scripts automatically prepend .r-lib/4.6 when it exists.

### Option B — Reproducible environment from renv.lock

The committed lockfile targets R 4.5.2. This is the recommended environment for the controlled project baseline, but R 4.5.2 is not currently installed on this workstation.

After installing R 4.5.2 side by side:

    $rscript = "C:\Program Files\R\R-4.5.2\bin\Rscript.exe"

    & $rscript --vanilla -e "stopifnot(getRversion() == '4.5.2')"
    & $rscript --vanilla -e "source('renv/activate.R'); renv::restore(prompt = FALSE)"

Do not point R 4.6 at the shared R 4.5 package library. Mixing those versions produces DLL errors such as failures loading rlang.dll or vctrs.dll.

## 5. Check the Environment

Check the core packages:

    & $rscript --vanilla scripts/check-environment.R

Check both core and Shiny packages:

    & $rscript --vanilla scripts/check-environment.R --app

Expected result:

    Environment check passed.

## 6. Run the Automated Tests

Run the core workbook, schema, transformation, state, and export-gate tests:

    & $rscript --vanilla tests/run-core-tests.R

Expected result:

    Tests run: 16
    Failures: 0
    All core milestone tests passed.

Run the Shiny server safety tests:

    & $rscript --vanilla tests/run-app-tests.R

Expected result:

    All Shiny milestone tests passed.

These tests use synthetic data and temporary XLSX files. They make no Azure or external network calls.

## 7. Create the Sample XLSX Workbook

The application does not accept CSV directly. It requires an XLSX workbook containing Clinical_Data.

The sample workbook is generated at:

    runtime/input/Clinical_PHI_Anonymization_Test_Data.xlsx

If that file is absent, create it with:

    if (-not (Test-Path -LiteralPath "runtime\input\Clinical_PHI_Anonymization_Test_Data.xlsx")) {
        & $rscript --vanilla scripts/create-sample-workbook.R
    }

The script intentionally refuses to overwrite an existing workbook.

## 8. Run the Pipeline Without Shiny

    & $rscript --vanilla scripts/run-sample.R

Expected summary:

    State: PROCESSED
    Release allowed: FALSE
    Blocking items: 2

Expected safe-preview behavior:

- Record_No, Patient_Name, MRN, and Patient_ID contain missing values.
- DOB contains only year values for the supplied sample.
- Both narrative columns display [PENDING_TEXT_DEIDENTIFICATION].
- No output workbook is released.

## 9. Run the Shiny Application

Start the app:

    & $rscript --vanilla scripts/run-app.R

When this message appears:

    Listening on http://127.0.0.1:3838

open the following address in a browser:

    http://127.0.0.1:3838

To stop the app, return to PowerShell and press **Ctrl+C**.

## 10. Use the Shiny Application

1. Confirm that the red banner says **Synthetic data only**.
2. Select:

       runtime/input/Clinical_PHI_Anonymization_Test_Data.xlsx

3. Select **I confirm this workbook contains synthetic test data only**.
4. Select **Run structured processing**.
5. Confirm the status reports:

       Run state: PROCESSED

6. Review the safe structured preview:

   - Direct identifier columns must be blank.
   - DOB must contain only year or 90+.
   - Narrative cells must show [PENDING_TEXT_DEIDENTIFICATION].

7. Confirm two Critical blockers are shown:

   - Diagnosis_Journey — TEXT_PROCESSING_PENDING
   - Treatment_History — TEXT_PROCESSING_PENDING

8. Confirm that no download button is available.

## 11. Expected Fail-Closed Behavior

| Scenario | Expected result |
|---|---|
| CSV, XLS, or XLSM selected | Input rejected |
| Clinical_Data missing or misspelled | Input rejected |
| Required column missing | Input rejected |
| Unknown column added | Input rejected |
| Duplicate column headers | Input rejected |
| Invalid or future DOB | Processing rejected |
| Synthetic-data confirmation not selected | Processing rejected |
| New workbook uploaded | Previous result and validation state cleared |
| Export called before approval | EXPORT_NOT_APPROVED; no file created |
| Structured processing succeeds | State remains PROCESSED, not APPROVED |

## 12. Important Data-Handling Rules

- Do not place PHI in the repository, runtime directory, tests, logs, screenshots, or bug reports.
- Do not deploy this milestone to the existing shinyapps.io target.
- Do not enable release_enabled in config/poc.yml.
- Do not add API keys, bearer tokens, or connection strings to .Rprofile, .Renviron, YAML files, or Git.
- Do not describe the structured preview as anonymized or Safe Harbor compliant.
- Generated runtime files and the project-local R library are excluded by .gitignore.

## 13. Troubleshooting

### Rscript is not recognized

Use the full executable path:

    & "C:\Program Files\R\R-4.6.0\bin\Rscript.exe" --version

### rlang.dll or vctrs.dll fails to load

This indicates that packages built under a different R version are being loaded.

Use the verified scripts, which activate .r-lib/4.6, or install R 4.5.2 and restore the committed renv.lock. Do not delete or overwrite the shared library.

### The sample-workbook script says the file already exists

Use the existing workbook. The script refuses to overwrite files intentionally.

### The app reports MISSING_REQUIRED_SHEET

Rename the worksheet exactly:

    Clinical_Data

Worksheet matching is case-sensitive.

### The app reports UNEXPECTED_COLUMNS

Remove the unknown column from the test workbook or add it only through a formally reviewed schema change. The app does not guess how unknown columns should be handled.

## 14. What Remains Before Real PHI

The following are intentionally not implemented in Milestone 1:

- Azure AI Language Text PII integration
- Local/Azure narrative detection and redaction
- Complete residual-PHI validation
- Enterprise SSO and role-based access
- Sanitized persistent audit/evidence storage
- Privacy and clinical-data review workflow
- Independent approval transition
- Releasable output
- Organization-confirmed Azure, security, privacy, contractual, and retention controls

The next technical milestone is the Azure free-text adapter and deterministic narrative preprocessing, using mocked responses first and no real PHI until Phase 0 governance approval is complete.

Before publishing the project as an R package, replace the placeholder maintainer email in DESCRIPTION with an approved organizational contact.
