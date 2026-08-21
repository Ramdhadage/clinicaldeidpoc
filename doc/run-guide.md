# Clinical De-identification PoC — Milestone 1.2 Run Guide

## 1. What This Milestone Implements

Milestone 1.2 is a **synthetic-only, non-releasing structured-data foundation with run-scoped hexadecimal ID tokens and a deterministic narrative preview**.

It currently:

- Accepts only an XLSX workbook.
- After upload, select the worksheet to process. The selected worksheet must
  match the approved column contract before it can be processed.
- Requires the eight approved columns:
  - **Record_No**
  - **Patient_Name**
  - **DOB**
  - **Diagnosis_Journey**
  - **Treatment_History**
  - **MRN**
  - **Patient_ID**
  - **Zip_Code**
- Removes all values from Record_No, Patient_Name, MRN, and Patient_ID.
- Converts DOB to a four-digit year or **90+**.
- Converts a valid U.S. Zip_Code to its approved three-digit prefix, or `000` when its prefix is not on the approved Census allowlist. Numeric postal values that cannot be unambiguously normalized to a U.S. ZIP are suppressed.
- Displays `[Name]` for Patient_Name and independent random eight-character lowercase hexadecimal values for nonmissing Record_No, MRN, and Patient_ID cells without restoring their source values.
- Generates the structured ID tokens from secure random bytes once per run, rejects collisions, keeps them only in session memory, and regenerates them for a new run.
- Applies ordered deterministic transformations to selected narrative patterns, including known names and identifiers, dates, contact details, URLs, IP addresses, labeled codes, addresses, ZIP codes, and facilities.
- Invalidates previous results whenever another file is uploaded.
- Blocks anonymized-data release/export because Azure free-text processing, complete validation, human review, and approval have not yet been implemented. A separate synthetic tagged-preview XLSX can be downloaded only after synthetic-data confirmation; it is not anonymized or releasable.

This milestone does **not** produce a releasable or HIPAA-de-identified dataset.

> **Security restriction:** Use only the generated fixture or data whose synthetic provenance has been independently confirmed. Do not upload real PHI to the local application.

### Tagged-preview coverage

HHS defines 18 Safe Harbor identifier types. The requested list contains 20 operational checks because it separates ZIP from geography and age over 89 from the date/age rule. The preview uses the following implementation status; **partial** means deterministic patterns can miss valid identifiers.

| Operational check | Preview behavior | Coverage |
|---|---|---|
| Names | Known patient names and titled clinician names become [Name] | Partial |
| Geographic subdivisions | Recognized addresses and selected location phrases become [Geographic Subdivision] | Partial |
| ZIP codes | Preserves an approved eligible three-digit prefix; all other prefixes become 000. ZIP+4 extensions are removed. The current policy has no approved Census allowlist, so every recognized ZIP becomes 000. | Conditional rule implemented; default deny pending approved Census evidence |
| Dates except year | Recognized valid dates become [YYYY] | Partial |
| Ages over 89 | Structured DOB, DOB-context narrative dates, or explicit ages become [Age: 90 or older] | Partial |
| Telephone numbers | Recognized North American and selected international formats become [Telephone Number] | Partial |
| Fax numbers | Fax-labeled numbers become [Fax Number] | Partial |
| Email addresses | Recognized addresses become [Email] | Deterministic pattern |
| Social Security numbers | Recognized formatted values become [SSN] | Partial |
| Medical record numbers | Structured MRN cells use random 8-character hex tokens; known or labeled narrative values become [Medical Record Number] | Partial |
| Health-plan beneficiary numbers | Labeled values become [Health Plan Beneficiary Number] | Partial |
| Account numbers | Labeled values become [Account Number] | Partial |
| Certificate/license numbers | Labeled values become [Certificate/License Number] | Partial |
| Vehicle identifiers | Labeled VIN/vehicle/plate values become [Vehicle Identifier] | Partial |
| Device identifiers | Labeled device/implant/UDI values become [Device Identifier] | Partial |
| Web URLs | Recognized URLs become [URL] | Deterministic pattern |
| IP addresses | Valid IPv4 values become [IP Address] | IPv4 only |
| Biometric identifiers | Only labeled textual biometric IDs become [Biometric Identifier] | Content unsupported |
| Full-face photos | Workbooks containing media or drawing objects are rejected; empty Excel drawing containers are accepted | No image redaction |
| Other unique characteristics | Structured Record_No and Patient_ID cells use random 8-character hex tokens; known or labeled narrative codes become [Other Unique Identifier] | Partial |

Official reference: [HHS de-identification guidance](https://www.hhs.gov/hipaa/for-professionals/special-topics/de-identification/index.html).

## 2. Repository Entry Points

| File | Purpose |
|---|---|
| app.R | Thin Shiny application entry point |
| config/schema.yml | Exact workbook and column contract |
| config/poc.yml | Synthetic-only runtime controls |
| rules/safe_harbor_candidate.yml | Proposed structured transformation policy |
| R/ | Modular input, schema, transformation, validation, workflow, UI, and export-guard functions |
| R/azure_pii_client.R | Disabled-by-default Azure Text PII LRO request, poll, retry, and response-validation contract |
| tests/run-core-tests.R | Core regression and fail-closed tests |
| tests/run-app-tests.R | Shiny server/state safety tests |
| scripts/create-sample-workbook.R | Generates a small synthetic XLSX fixture with the required contract |
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

    Tests run: 34
    Failures: 0
    All core milestone tests passed.

Run the Shiny server safety tests:

    & $rscript --vanilla tests/run-app-tests.R

Expected result:

    All Shiny milestone tests passed.

These tests use synthetic data and temporary XLSX files. They make no Azure or external network calls.

## 7. Create or Confirm the Generated Sample XLSX Workbook

The application does not accept CSV directly. The CLI demonstration deliberately uses only the generated synthetic fixture at `runtime/input/Clinical_PHI_Anonymization_Data_v0.3.xlsx`; it never selects a user-provided workbook from the project root. The versioned file name avoids overwriting an older generated fixture that predates the required `Zip_Code` column.

Confirm whether the generated fixture exists:

    Test-Path -LiteralPath "runtime/input/Clinical_PHI_Anonymization_Data_v0.3.xlsx"

If the result is `False`, create it:

    & $rscript --vanilla scripts/create-sample-workbook.R

To evaluate another workbook, use the Shiny upload flow only after its synthetic provenance has been confirmed. Do not substitute real PHI.

## 8. Run the Pipeline Without Shiny

    & $rscript --vanilla scripts/run-sample.R

Expected summary:

    State: PROCESSED
    Release allowed: FALSE
    Blocking items: 2

Expected tagged-preview behavior:

- Nonmissing Record_No, MRN, and Patient_ID cells display unique lowercase values matching `^[0-9a-f]{8}$`.
- Patient_Name displays [Name].
- DOB displays [YYYY] or [Age: 90 or older].
- Detected narrative values display typed tags such as [Email], [URL], [IP Address], [Telephone Number], and [YYYY].
- Undetected narrative text remains visible and may still contain identifiers.
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

1. Confirm that the red banner says **Synthetic demonstration only**.
2. Select the generated fixture (or another workbook whose synthetic provenance has been confirmed):

       runtime/input/Clinical_PHI_Anonymization_Data_v0.3.xlsx

3. Select **I confirm this workbook contains synthetic test data only**.
4. Select **Generate tagged preview**.
5. Confirm the status reports:

       Run state: PROCESSED

6. Review **Synthetic tagged preview - not validated**:

   - Record_No, MRN, and Patient_ID must contain random eight-character lowercase hexadecimal values, not source values.
   - Patient_Name must contain [Name].
   - DOB must contain [YYYY] or [Age: 90 or older].
   - Known patient names and selected deterministic patterns must be replaced with typed tags.
   - Clinical text that was not detected remains visible for synthetic evaluation.

7. Confirm two Critical blockers are shown:

   - Diagnosis_Journey — NARRATIVE_REDACTION_NOT_VALIDATED
   - Treatment_History — NARRATIVE_REDACTION_NOT_VALIDATED

8. Select **Download synthetic tagged preview (XLSX)** only for synthetic evaluation. The workbook contains `Synthetic_Tagged_Preview` and `Preview_Notice` sheets; it is not anonymized, not releasable, and must not be used or disclosed as de-identified data.

## 11. Expected Fail-Closed Behavior

| Scenario | Expected result |
|---|---|
| CSV, XLS, or XLSM selected | Input rejected |
| Selected worksheet missing, unavailable, or incompatible with the approved column contract | Input rejected with validation feedback |
| Required column missing | Input rejected |
| Unknown column added | Input rejected |
| Duplicate column headers | Input rejected |
| Invalid or future DOB | Processing rejected |
| Synthetic-data confirmation not selected | Processing rejected |
| New workbook uploaded | Previous result and validation state cleared |
| Export called before approval | EXPORT_NOT_APPROVED; no file created |
| Synthetic tagged-preview download after confirmation | XLSX contains only the derived tagged preview and a non-releasable notice; no run is released |
| Structured processing succeeds | State remains PROCESSED, not APPROVED |

## 12. Important Data-Handling Rules

- Do not place PHI in the repository, runtime directory, tests, logs, screenshots, or bug reports.
- Do not deploy this milestone to the existing shinyapps.io target.
- Do not enable release_enabled in config/poc.yml.
- Do not add API keys, bearer tokens, or connection strings to .Rprofile, .Renviron, YAML files, or Git.
- Do not describe the tagged preview as anonymized or Safe Harbor compliant.
- Treat run-scoped hexadecimal preview tokens as sensitive, ephemeral pseudonymous values; do not persist or use them for cross-run linkage. They may appear only in the synthetic tagged-preview XLSX, which remains non-releasable.
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

The following are intentionally not implemented in Milestone 1.2:

- Live Azure AI Language Text PII connectivity, Entra workload identity, and private-network integration
- Validated Azure/NER narrative detection and redaction
- Complete residual-PHI validation
- Enterprise SSO and role-based access
- Sanitized persistent audit/evidence storage
- Privacy and clinical-data review workflow
- Independent approval transition
- Releasable output
- Organization-confirmed Azure, security, privacy, contractual, and retention controls

The first Phase 3 foundation is implemented but remains disabled: `R/azure_pii_client.R` builds the reviewed GA `2026-05-01` Text PII long-running-job request, requires `loggingOptOut=true`, submits through an injected transport, validates the same-origin `Operation-Location`, polls terminal state, retries transient failures, and validates exact returned model/document/entity spans. The automated tests use synthetic mocked responses only; no live Azure request, credential, or PHI was used.

The next technical work is bounded chunking and offset maps, an approved Entra workload-identity provider, private-connectivity validation, and synthetic connectivity evidence. Do not enable `azure.enabled`, provide an endpoint, or call the client against Azure until Phase 0 governance approval is complete.

Before publishing the project as an R package, replace the placeholder maintainer email in DESCRIPTION with an approved organizational contact.
