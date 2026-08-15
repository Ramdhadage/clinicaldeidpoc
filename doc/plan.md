# Clinical Data De-identification PoC Project Plan

This plan uses three evidence states:

- **PLANNED:** proposed design or control in this plan.
- **PoC-DEMONSTRATED:** supported by retained execution evidence after the PoC.
- **ORGANIZATION-CONFIRMED:** approved by privacy, security, legal/compliance, data governance, or platform owners.

Nothing proposed below is currently considered implemented, tested, approved, HIPAA compliant, or production ready.

Locked planning decisions:

- Primary outcome: **Safe Harbor-candidate dataset**, not a compliance declaration.
- Primary evaluation data: organization-approved PHI, processed only after Phase 0 approval.
- Input contract: .xlsx workbook containing the exact worksheet **Clinical_Data**.
- Hosting: organization-approved enterprise R platform.
- Released output: no stable identifiers or cross-run linkage.
- Architecture: deterministic R pipeline plus Azure AI Language Text PII; no RAG or autonomous agent in the initial PoC.

Implementation status as of 2026-08-16:

- Milestone 1.2, the synthetic-only structured-data foundation with run-scoped hexadecimal ID tokens and a deterministic narrative preview, is implemented.
- The exact Clinical_Data schema, deterministic identifier removal, DOB generalization, source-independent token generation, collision rejection, state invalidation, and server-side export guard have automated test evidence.
- The tagged preview covers known values and selected deterministic patterns, but it is not validated for residual identifiers and is not a Safe Harbor determination.
- Azure/NER text processing, complete residual validation, enterprise controls, human approval, and release remain unimplemented and blocking.
- See [the step-by-step run guide](run-guide.md) for verified commands and current limitations.

## 1. PoC Objective

Determine whether deterministic structured-field rules plus Azure AI Language Text PII detection can remove required identifiers from clinical datasets while preserving useful non-identifying clinical information.

Expected users:

- Clinical data analysts and statistical programmers
- Clinical data-management teams
- Privacy officers and data stewards
- Security and compliance reviewers
- R/Shiny developers and data engineers

Original prototype baseline, recorded before Milestone 1 and now superseded:

- The original app classified columns from names rather than values.
- Against the supplied [test CSV](</D:/R shiny Apps/deidentification/Clinical_PHI_Anonymization_Test_Data - Test_Data.csv>), it transformed Patient_Name, DOB, and MRN, but left both narrative columns and Patient_ID unchanged.
- Its download path could return the original dataset before detection. Milestone 1 replaces that implementation with a modular, synthetic-only, non-releasing foundation.

The PoC will demonstrate:

- Controlled ingestion of one known worksheet
- Versioned structured and free-text transformation
- Azure REST integration from R
- Accuracy, residual-leakage, utility, repeatability, and failure evidence
- Fail-closed release and human approval workflow
- Traceability without storing raw PHI in application logs

Explicitly out of scope:

- A claim of HIPAA compliance or legal Safe Harbor determination
- Expert Determination
- Production validation or GxP validation
- Autonomous decisions or release by an AI agent
- RAG-based anonymization
- Images, scanned documents, audio, OCR, and embedded workbook media
- Non-English narratives in v1
- Multiple worksheets, arbitrary schemas, and longitudinal cross-run tokenization
- Production-scale performance, disaster recovery, or enterprise rollout

## 2. User Requirements

| ID | User requirement | Reason | Proposed solution | Validation method | Priority |
|---|---|---|---|---|---|
| UR-01 | Accept clinical Excel input | Required source format | Accept .xlsx; require worksheet Clinical_Data; create a new output workbook | Positive and malformed-workbook tests | Must |
| UR-02 | Handle known structured identifiers | Prevent direct identifier leakage | Versioned schema and deterministic rule catalogue | Unit and end-to-end labelled tests | Must |
| UR-03 | Detect PII in clinical narratives | Identifiers appear inside notes | Local known-value/regex pass plus Azure Text PII | Span-level ground-truth evaluation | Must |
| UR-04 | Support configurable rules | Policies vary by dataset and organization | Reviewed YAML configuration with schema validation and versioning | Configuration contract tests | Must |
| UR-05 | Produce reproducible results | Required for audit and regression | Pin R dependencies, rules, API, model, and configuration; deterministic overlap resolution | Repeated-run comparison | Must |
| UR-06 | Maintain auditability | Explain every transformation and release | Run manifest, configuration hash, code version, detection metadata, validation and review records | Traceability reconstruction exercise | Must |
| UR-07 | Fail safely | Partial processing can leak PHI | Reject unknown schemas and block export on any unresolved error | Injected failure tests | Must |
| UR-08 | Support human review | AI false negatives and false positives are possible | Restricted exception queue and independent approval | Workflow and authorization tests | Must |
| UR-09 | Validate output integrity | Prevent silent row/schema corruption | Row, column, type, workbook, hash, and reopen checks | Automated integrity tests | Must |
| UR-10 | Handle PHI securely | Source and Azure responses remain sensitive | Enterprise SSO/RBAC, approved storage, private network, Entra authentication, no content logs | Security evidence review | Must |
| UR-11 | Preserve clinical usefulness | Excessive redaction can invalidate analysis | Typed placeholders plus clinical-anchor preservation metrics | Utility evaluation and data-steward review | Must |
| UR-12 | Prevent accidental raw export | Existing app fails open | Export available only from an approved terminal run state | Shiny state-transition tests | Must |
| UR-13 | Handle unexpected columns | Unknown fields may contain PHI | Classify every column; unresolved columns block processing/release | Schema-drift tests | Must |
| UR-14 | Record limitations honestly | PoC evidence has bounded applicability | Versioned limitations and decision report | Final evidence review | Must |

## 3. Proposed Technical Architecture

    Approved XLSX
        |
        v
    Secure upload + workbook inspection
        |
        v
    Schema validation: exact sheet "Clinical_Data"
        |
        v
    Column classification
    (direct ID | quasi-ID | free text | non-sensitive | unresolved)
        |
        +-------------------------+
        |                         |
        v                         v
    Structured R rules      Free-text preparation
        |                   - ephemeral known-value matching
        |                   - deterministic regex/context rules
        |                   - bounded chunking with offset maps
        |                         |
        |                         v
        |                  Azure Text PII REST API
        |                         |
        +-----------+-------------+
                    v
            Detection reconciliation
            + local typed redaction
                    |
                    v
            Multi-layer validation
                    |
                    v
               Exception queue
                    |
                    v
        Privacy + clinical data review
                    |
                    v
            Approval or rejection
                    |
                    v
    New anonymized XLSX + release manifest

Component responsibilities:

| Component | Responsibility |
|---|---|
| Secure input | Enforce file size/type, isolate temporary storage, calculate restricted integrity hash, and invalidate previous run state |
| Workbook inspector | Require Clinical_Data; flag additional sheets but never copy them into output; reject macros, encrypted files, external links, unsupported media, or unreadable workbooks |
| Schema validator | Require the approved column contract and expected types; reject missing, duplicate, or unresolved columns |
| Column classifier | Assign each field to direct identifier, quasi-identifier, free text, non-sensitive, or unresolved |
| Structured engine | Apply typed, deterministic transformations based on a versioned rule catalogue |
| Known-value scanner | Temporarily derive normalized variants of structured identifiers and redact matches in narratives before Azure submission |
| Azure adapter | Batch synchronous REST calls, authenticate with Entra ID, validate responses, retry transient failures, and return normalized detections |
| Reconciliation engine | Combine local and Azure spans, resolve overlaps deterministically, and apply replacements from right to left |
| Validation engine | Check residual identifiers, schema integrity, clinical preservation, completeness, and release gates |
| Review workflow | Expose only necessary original/redacted snippets to authorized reviewers and capture reason-coded decisions |
| Audit service | Record versions, safe locations, counts, status, validation, and approvals without raw request or entity text |
| Export service | Create a new workbook containing only anonymized Clinical_Data and a non-PHI validation summary |

Structured defaults for the selected Safe Harbor-candidate profile:

- Patient_Name, MRN, Patient_ID, and Record_No: remove from released values; do not create stable or cross-run tokens. The non-releasing synthetic preview may display ephemeral, independently generated run-scoped tokens for Record_No, MRN, and Patient_ID.
- DOB and other patient-related dates: retain year only, subject to age-over-89 handling.
- Sub-state geography: remove; retain state only.
- Phone, email, URL, IP, account, licence, device, and other unique identifiers: remove or replace with typed non-reversible placeholders.
- Narrative identifiers: replace with typed markers such as [PERSON], [DATE], [PHONE], or [IDENTIFIER].
- Clinician names and healthcare facilities: conservatively redact in the PoC unless the approved rule catalogue explicitly permits retention.
- Internal row_id: random and run-scoped, retained only in restricted evidence; not exported.

Proposed R interfaces:

- read_clinical_workbook(path, schema) -> InputDataset
- classify_columns(data, schema, policy) -> ColumnClassification
- transform_structured(data, classification, policy) -> StructuredResult
- detect_free_text(text_cells, azure_client, policy) -> DetectionResult
- validate_run(input, output, detections, policy) -> ValidationSummary
- create_review_queue(validation, detections) -> ReviewQueue
- approve_release(run_id, decisions, actor) -> ReleaseManifest
- run_deidentification(run_spec) -> RunResult

app.R will become a thin Shiny launcher. Business logic will be package-style R functions independent of Shiny reactives.

## 4. RAG vs Agent vs Deterministic Pipeline

| Option | Purpose | Advantages | Disadvantages and governance | Reproducibility/auditability | PoC suitability |
|---|---|---|---|---|---|
| A — Deterministic R + Azure PII | Execute approved rules and detect free-text PII | Testable, explainable, versionable, limited tool surface | Azure false negatives still require validation and human review | High when API/model/configuration are pinned | **Recommended** |
| B — RAG-enhanced | Retrieve policies, dictionaries, or governance guidance | Useful for reviewer context and policy discovery | Retrieval errors, stale documents, access-control complexity; retrieval does not itself identify PII reliably | Medium; requires corpus, chunk, retrieval, and citation provenance | Not needed for v1 anonymization |
| C — Agent-based workflow | Dynamically choose tools or remediation steps | Could coordinate future exception triage | Variable behavior, prompt-injection risk, broader permissions, harder validation and approval | Lower without strict state machines | Not justified for v1 |
| D — Hybrid with RAG/agent | Deterministic engine plus governed assistance | May improve later review/reporting workflows | Highest implementation and validation burden | Depends on keeping the release path deterministic | Future-only |

Recommendation: implement Option A. RAG adds no inherent detection capability unless a real requirement exists to retrieve approved policies, organization-specific dictionaries, or data standards. Any later RAG result may advise a reviewer but must not dynamically change release rules.

An agent could later assemble evidence, route exceptions, or draft failure reports. It must not autonomously alter rules, access unapproved PHI, accept residual risk, or release output.

## 5. HIPAA / Privacy Rule Mapping

This is planning-level technical guidance, not legal advice. HHS describes both Safe Harbor and Expert Determination and requires consideration of identifiers appearing in structured fields and free text, including identifiers of relatives, household members, and employers, plus the “actual knowledge” condition. [HHS de-identification guidance](https://www.hhs.gov/hipaa/for-professionals/special-topics/de-identification/index.html) (accessed 2026-08-11).

| Identifier/category | Example | Structured-field handling | Free-text handling | Validation required | Residual-risk consideration |
|---|---|---|---|---|---|
| Names | Patient or relative name | Remove value | Local known-value scan plus Azure/local person detection | Normalized and alias matching | Initials, nicknames, partial names, clinician/patient ambiguity |
| Geographic information | Street, city, county, ZIP | Retain state only; remove all smaller geography | Redact street/city/ZIP mentions | Address/ZIP regex and labelled review | Facility and rare-location combinations |
| Dates except year | DOB, admission date | Parse format-aware; retain year only | Replace month/day/time while retaining approved year | Date parser plus labelled spans | Ages over 89 and temporal combinations |
| Telephone numbers | 617-555-0142 | Remove | Regex plus Azure detection | Digits-only normalized scan | International formats and extensions |
| Fax numbers | Fax field/mention | Remove | Regex plus Azure detection | Pattern variants | Misclassified phone/fax |
| Email addresses | Patient email | Remove | Regex plus Azure detection | Case-normalized scan | Email local part can reveal names |
| Social Security numbers | SSN | Remove | Strict regex/context detection | Full and punctuation-stripped scan | Partial SSNs do not satisfy Safe Harbor |
| Medical record numbers | MRN-12345678 | Remove; no stable token | Dictionary, normalized-ID and contextual regex | Prefix-stripped and digits-only checks | Embedded variants without MRN prefix |
| Health-plan numbers | Member ID | Remove | Contextual regex plus Azure where supported | Labelled category tests | Can resemble ordinary clinical codes |
| Account numbers | Billing account | Remove | Contextual regex plus Azure | Normalized scan | False positives on protocol/account terminology |
| Certificate/license numbers | Driver/professional licence | Remove | Contextual rules plus Azure where GA-supported | Format-specific fixtures | Country/state variation |
| Vehicle identifiers | VIN, licence plate | Remove | VIN/plate patterns plus review | Pattern and checksum tests where applicable | Azure category coverage may vary |
| Device identifiers | Implant serial number | Remove | Contextual dictionary/regex; Azure cannot be sole detector | Device-specific fixtures | May be clinically meaningful and identifying |
| URLs | Patient portal URL | Remove | URL parser/regex plus Azure | Normalized URL scan | Identifiers embedded in path/query |
| IP addresses | IPv4/IPv6 | Remove | IP parser/regex plus Azure | Canonical IPv4/IPv6 scan | Private IPs still fall in the category |
| Biometric identifiers | Fingerprint/voiceprint | Reject binary biometric content; remove textual identifier | Flag textual references; no claim of inspecting actual biometric media | Workbook-media inspection and review | Text PII cannot inspect image/audio content |
| Full-face photographs/images | Embedded patient photo | Reject embedded media and image-bearing inputs | Flag links/references; do not treat text scan as image de-identification | XLSX package/media inspection | Comparable images require a different controlled workflow |
| Other unique characteristics/codes | Subject ID, rare unique code | Remove | Dictionary/context rules plus Azure where supported | Uniqueness and normalized-value checks | Rare diagnosis/facility combinations and actual knowledge |

Additional policy rules:

- Age 90 or older will be represented as 90+; birth-year information that reveals an age over 89 will be suppressed or generalized.
- The PoC will not use the conditional three-digit ZIP exception; all ZIP codes will be removed.
- Removal, masking, generalization, and typed replacement are acceptable transformation mechanisms only when validation proves that the identifying value is unavailable.
- Tokenization or pseudonymization preserves linkage and is not automatically equivalent to de-identification. It is excluded from the released PoC profile.
- Supplementary quasi-identifier uniqueness checks may identify risky combinations, but will not be presented as Expert Determination.

## 6. Azure PII Governance and Approval Plan

Planned Azure integration:

- Service: Azure AI Language Text PII.
- API: synchronous POST {Endpoint}/language/:analyze-text.
- Pinned GA api-version=2026-05-01 and modelVersion=2026-05-01; preview capabilities excluded. [Model lifecycle](https://learn.microsoft.com/en-us/azure/ai-services/language-service/concepts/model-lifecycle) and [REST reference](https://learn.microsoft.com/en-us/rest/api/language/analyze-text/analyze-text/analyze-text?view=rest-language-analyze-text-2026-05-01) (accessed 2026-08-11).
- Full PII category coverage rather than domain=phi, because domain=phi is only a service category subset and is not Safe Harbor assurance.
- disableEntityValidation=false.
- loggingOptOut=true explicitly on every request.
- English-only input for v1.
- Entity detection and service redaction returned for comparison; final transformation applied locally from validated spans.

The Azure response contains original detected entity text as well as redacted text, offsets, categories, and confidence. The full response must therefore be handled as PHI in memory and never written to normal logs.

| Governance item | PoC-demonstrable evidence | Organization confirmation required |
|---|---|---|
| Service/API/model | Request configuration, returned model version, integration test | Exact service/SKU/GA capability permitted for PHI |
| Endpoint and region | Redacted resource metadata and deployment export | Approved Azure geography and residency |
| R integration | Dependency manifest and REST adapter tests | Enterprise platform permits outbound connection |
| Authentication | Entra token flow and RBAC evidence | Approved workload identity and Cognitive Services User assignment |
| Secrets | No keys in code/repository/logs | Enterprise secret store or managed identity configuration |
| Data sent | Data-flow diagram and payload-field inventory | Minimum-necessary PHI transmission approved |
| Retention | loggingOptOut=true evidence and diagnostic review | Organizational acceptance of Microsoft’s documented handling |
| Network controls | Private endpoint/DNS/connectivity evidence | Private connectivity, firewall, and public-access configuration approved |
| Encryption | TLS and Azure resource configuration evidence | Required CMK/platform encryption policy |
| Access control | SSO role matrix and access-test results | Named operators, reviewers, and approvers authorized |
| Logging | Sample sanitized logs and telemetry review | Retention, access, and monitoring policy approved |
| Contractual coverage | Recorded service/tenant/agreement identifiers | Legal/privacy confirmation of applicable DPA/BAA and audit scope |
| Hosting | Enterprise R platform deployment record | Platform security and PHI processing authorization |
| Production status | Explicit “PoC only” banner and manifest | Separate production approval; never inherited from the PoC |

Microsoft states that no HHS-approved cloud-provider HIPAA certification exists and that a Microsoft BAA does not make the customer’s solution compliant. [Microsoft’s Azure HIPAA offering](https://learn.microsoft.com/en-us/azure/compliance/offerings/offering-hipaa-us) (accessed 2026-08-11) will be treated as vendor information, not organizational approval.

Mandatory controls before any approved PHI is processed:

- Signed data-flow, minimum-necessary, purpose, retention, and disposal approval
- Confirmed tenant, subscription, resource, region, GA feature, DPA/BAA applicability, and audit scope
- Entra workload identity; local/key authentication disabled
- Private endpoint or equivalent approved private path; public access disabled
- Approved enterprise R platform storage, temporary-file, backup, session, and browser-cache controls
- Azure diagnostic categories reviewed; content-bearing RequestResponse logging disabled unless explicitly approved
- Security and privacy approval records linked to the run evidence store
- No PHI deployment to the repository’s current [shinyapps.io target](</D:/R shiny Apps/deidentification/rsconnect/shinyapps.io/ti5syn-ramdhadage/deidentification.dcf>)

## 7. AI/PII Detection Evaluation Framework

Evaluation layers:

1. **Structured deterministic rules:** exact expected input/output tests for every supported data type, format, missing value, and category.
2. **Azure component:** span/entity evaluation against independently labelled free text.
3. **End-to-end pipeline:** determine whether every required identifier is fully transformed and whether clinical content is preserved.
4. **Operational behavior:** retries, partial errors, repeatability, latency, cost, and fail-closed release.

Ground-truth annotations will include:

- Record, field, start/end offsets, surface text, normalized value
- Entity type and subject role
- Canonical entity ID for aliases
- Required transformation and severity
- Policy/rule version
- Reviewer and adjudication status

Metrics:

| Metric | Definition |
|---|---|
| TP/FP/FN | Required span correctly detected; non-PII incorrectly detected; required span missed |
| TN | Negative row/document correctly contains no detection |
| Precision | TP / (TP + FP) |
| Recall | TP / (TP + FN) |
| F1 | Harmonic mean of precision and recall |
| Containment recall | Percentage of gold spans for which every identifying character is transformed |
| Identifier-level recall | Percentage of distinct canonical identifiers fully removed across all occurrences |
| Row leakage rate | Rows with at least one residual required identifier divided by evaluated rows |
| Residual-PHI percentage | Released records containing any adjudicated residual PII |
| Utility preservation | Non-PHI text retained and predefined clinical facts preserved |
| Repeatability | Agreement across identical runs with pinned rules/API/model/configuration |

False negatives and residual PHI are Critical failures.

**PROPOSED — REQUIRES APPROVAL acceptance thresholds:**

| Measure | Proposed gate |
|---|---|
| Supplied 10-row regression dataset | 100% of must_transform annotations handled; zero residual identifiers |
| Deterministic structured rules | 100% expected transformation accuracy |
| Email, phone, MRN/ID, IP, and URL containment recall | 100% |
| Blind end-to-end holdout containment recall | At least 99.5% overall and 99.0% per critical identifier class |
| Observed residual PHI in releasable holdout | Zero |
| Transformation precision | At least 95% overall |
| Non-PHI character/token preservation | At least 98% |
| Predefined diagnosis/treatment anchor preservation | 100% |
| Row, column, and workbook integrity | 100% |
| API/error behavior | 100% fail-closed; no partial output release |
| Annotation quality before holdout freeze | Span-level inter-annotator F1 at least 0.95 |
| Repeatability | Five identical runs with identical detections and normalized output, excluding run IDs/timestamps and run-scoped random preview tokens; token format and uniqueness are assessed separately |
| Raw PHI in application logs/telemetry | Zero occurrences |

Azure confidence thresholds will be calibrated by category against the development set. The service default will be recorded as a baseline; a threshold sweep will select the lowest operating point that satisfies approved recall and precision gates. Confidence will support triage, not determine whether a record is safe.

## 8. Failure Analysis

Failure-handling process:

1. Block the affected record and the complete export.
2. Record a sanitized failure event.
3. Classify severity and source.
4. Reproduce using an approved minimal fixture.
5. Determine root cause: schema, rule, parser, Azure behavior, chunking, configuration, or human decision.
6. Implement corrective action through change control.
7. Add a regression test.
8. Re-run the complete applicable test suite and sealed holdout where necessary.
9. Obtain reviewer disposition before release resumes.

Failure log schema:

| Field | Content rule |
|---|---|
| run_id | Opaque run identifier |
| record_id | Run-scoped opaque ID, not source patient ID |
| column | Approved column name |
| input_category | Structured, free text, schema, API, validation, review |
| expected_result | Category/action code, never raw PHI |
| actual_result | Sanitized outcome code |
| failure_classification | Missed PII, over-redaction, API, schema, integrity, security, workflow |
| severity | Critical, Major, Minor |
| root_cause | Controlled taxonomy plus sanitized note |
| resolution | Change/reference identifier |
| retest_status | Pending, passed, failed |
| owner | Responsible role |
| timestamps | UTC detected/resolved times |

Required scenarios:

- Missed or partially redacted PII
- Incorrectly removed clinical facts
- Malformed or unexpected Azure responses
- Invalid offsets or Unicode boundary mismatches
- Unsupported language/text
- HTTP 401/403/408/429/5xx, timeouts, and network failures
- Partial batch/document errors
- Incorrect column classification
- Missing/renamed/extra columns
- Missing Clinical_Data sheet
- Malformed, encrypted, macro-enabled, or media-containing workbook
- New upload after a prior approved run
- Reviewer rejection or expired approval

Azure retry policy: bounded exponential backoff with jitter, respect Retry-After, and stop after three attempts. Exhausted retries create a blocking exception; the local engine must never silently retain unprocessed narrative text.

## 9. Validation Rules

| Layer | Planned validation | Failure behavior |
|---|---|---|
| Schema | .xlsx; exact Clinical_Data; approved columns/types; unique names; allowable size/rows; no unsupported workbook content | Reject input |
| Pre-processing | Every column classified; language supported; dates parseable; no unresolved data type | Block processing/release |
| Structured transformation | Known values absent after normalization; expected types and missingness preserved | Critical exception |
| Free text | Validate spans/offsets; local normalized scanner; second post-redaction scan; compare with labels during evaluation | Critical exception or review |
| Output | Expected row count/order; approved columns only; workbook reopens; no copied sheets/media/external links | Reject output |
| Clinical utility | Diagnosis/treatment anchors, numeric values, and non-identifying text preserved | Major exception |
| Privacy | No residual required identifier; quasi-identifier/actual-knowledge review completed | Block release |
| Workflow | All errors resolved; review complete; approvals current and bound to hashes/configuration | Export disabled |

Additional controls:

- Unknown columns are never silently retained.
- Any new upload or configuration change invalidates detections, validation, review, and approval.
- The output workbook is newly generated rather than modifying or copying the source workbook.
- The Shiny download control is enabled only in the terminal APPROVED state.
- Original data is never offered through the anonymized download handler.
- Post-redaction Azure rescanning is corroborative, not independent proof, because it may use the same model.

## 10. Prompt Design and Versioning

Azure Text PII is an entity-detection API, not a conversational prompt workflow. No prompt, system message, temperature, or free-form LLM instruction will be invented for v1.

The versioned API configuration will contain:

- Configuration ID/version/hash
- API and model version
- Language
- Included/excluded entity categories
- Confidence threshold
- Entity validation setting
- Redaction policy
- loggingOptOut
- Chunking and offset convention
- Retry/time-out policy
- Rule and schema versions

If RAG or an LLM is later approved, its registry must additionally include:

- Prompt ID and version
- System-instruction version
- Retrieval corpus and policy versions
- Model/deployment version
- Temperature and other generation parameters
- Structured-output schema
- Evaluation results and approval
- Prompt-injection controls

Any generated advice remains non-binding until a human applies an approved deterministic configuration change.

## 11. Structured Outputs and Schemas

Persisted detection/evidence record:

| Field | Definition |
|---|---|
| run_id | UUID for the processing run |
| row_id | Random run-scoped row ID |
| column_name | Source column |
| chunk_id | Chunk identifier for long text |
| detection_source | Structured rule, known-value scan, regex, Azure PII, reviewer |
| entity_type | Normalized internal category |
| original_location | Sheet, row, column, start offset, length; no entity text |
| confidence_score | Azure score or NA for deterministic rules |
| transformation | Remove, generalize, mask, typed replacement |
| validation_status | Pending, passed, failed, exception |
| review_status | Not required, pending, accepted, rejected |
| rule_version | Applied rule catalogue version |
| api_version | Azure API version or NA |
| model_version | Returned Azure model version or NA |
| configuration_hash | Hash of effective configuration |
| timestamp | UTC processing time |
| error_code | Sanitized controlled code |

Raw request text, full API response, and Azure’s returned entity text may exist transiently in process memory but must not be persisted in this schema.

Run state model:

    RECEIVED
      -> SCHEMA_VALIDATED
      -> PROCESSED
      -> VALIDATED
      -> REVIEW_PENDING
      -> APPROVED or REJECTED
      -> RELEASED

Any input/configuration change returns the run to RECEIVED. Any error moves it to VALIDATION_FAILED; only controlled reprocessing can advance it.

Public result types:

- RunResult: state, safe summary, validation status, exception count
- DetectionResult: normalized detections without persisted raw text
- ValidationSummary: metrics, gates, failures, evidence references
- ReviewDecision: actor, role, reason code, timestamp, decision
- ReleaseManifest: approved hashes, versions, reviewers, and output location

## 12. Logging, Provenance, and Traceability

Each run must answer:

- What approved source was processed?
- Which schema, policy, rule, configuration, and code version applied?
- Which Azure API/model processed each free-text chunk?
- Which transformations and validations occurred?
- Which failures and retries occurred?
- Who reviewed and approved the output?
- Which exact output was released?

Persist:

- Run ID and UTC timestamps
- Enterprise actor IDs and roles
- Source name or approved dataset reference
- Restricted whole-file input and output SHA-256 hashes
- Code commit/build identifier
- R and dependency-lock versions
- Schema, rule, and configuration versions/hashes
- API and returned model versions
- Counts by detection source, category, status, retry, and failure
- Validation metrics and gate outcomes
- Review and approval records
- Final decision and release location

Do not persist:

- Raw notes, source rows, patient identifiers, detected entity text
- Full Azure request/response JSON
- Cell-level hashes of low-entropy identifiers
- API keys, bearer tokens, connection strings, or secrets
- Original/redacted snippets in general application logs

Logs will be written to an approved restricted evidence store, not the repository. Retention, immutability, access, backup, and disposal periods require organization confirmation.

## 13. Human Review and Approval

    Automated processing
      -> automated validation
      -> exception queue
      -> privacy reviewer
      -> clinical data steward
      -> independent release approver
      -> accepted or rejected output

Review responsibilities:

- **Operator:** uploads the approved workbook and starts the run; cannot self-approve.
- **Privacy reviewer:** evaluates residual PII, uncertain categories, unusual identifiers, and policy compliance.
- **Clinical data steward:** evaluates loss or distortion of clinical meaning.
- **Security/platform reviewer:** reviews environment or Azure-control exceptions.
- **Release approver:** verifies all evidence and authorizes export.

Mandatory review:

- Every residual-match or validation exception
- Every API failure or partial response
- Every unsupported/ambiguous column
- All low-confidence detections within the approved review band
- All false positives affecting predefined clinical anchors
- Every row in the labelled PoC evaluation corpus
- Any clinician/facility retention decision

The review interface will:

- Require enterprise SSO and role authorization
- Show the minimum necessary original/redacted context
- Prevent bulk raw-PHI download
- Record reason-coded actions and UTC timestamps
- Apply inactivity/session expiry
- Revoke prior approval when data, code, policy, or configuration changes

Release documentation:

- Run and release manifests
- Passing validation report
- Exception dispositions
- Privacy and clinical-data approvals
- Security approval reference
- Known-limitations acknowledgement
- Output hash and approved destination

## 14. PoC Evaluation Dataset

Dataset tiers:

1. **Engineering regression:** the supplied 10-row CSV, converted programmatically to an XLSX fixture with worksheet Clinical_Data. It exercises names, mixed-format DOBs, MRNs, subject IDs, narrative dates, clinicians, facilities, addresses, phones, emails, IP, URL, and embedded identifier variants.
2. **Synthetic challenge corpus:** difficult and negative examples covering all Safe Harbor categories, malformed formats, Unicode, aliases, abbreviations, misspellings, OCR-like errors, adversarial delimiters, and clinical terms resembling identifiers.
3. **Primary PoC evidence corpus:** organization-approved English PHI sampled only after Phase 0 approval.

Primary-corpus design:

- Target 500–1,000 notes/rows or enough to obtain at least 200 examples for common critical classes and 50 for rarer represented classes.
- At least 20% negative/no-PII text.
- At least 25% difficult formatting, alias, abbreviation, or ambiguity cases across the combined corpus.
- Split by canonical patient/entity, never by row alone.
- Use a calibration set for rule/threshold selection and a sealed holdout for final evaluation.
- Double-annotate the holdout; adjudicate disagreements before freezing ground truth.
- Version and hash the dataset inventory, annotation guide, labels, and policy.
- Store approved PHI and PHI-derived labels outside source control in the approved data zone.

Ground-truth categories will distinguish patient, clinician, relative, and other names; DOB and event dates; address components; phone/email/URL/IP; MRN/patient/other IDs; facility/organization; age; and other unique characteristics.

The primary evidence report must explicitly distinguish synthetic performance from approved-PHI performance.

## 15. Strongest PoC Scenario

**Business problem:** A clinical analyst needs a Safe Harbor-candidate dataset from a workbook containing direct identifiers and two narrative fields without losing diagnosis and treatment information.

**Users:** Clinical analyst/operator, privacy reviewer, clinical data steward, security reviewer, and release approver.

**Source:** Approved .xlsx workbook with Clinical_Data and the initial seven-column contract:

- Record_No
- Patient_Name
- DOB
- Diagnosis_Journey
- Treatment_History
- MRN
- Patient_ID

**Scope:** English text, one worksheet, tabular data, no images/media, no cross-run linkage.

**Approach:**

1. Validate the workbook and schema.
2. Remove direct structured identifiers and generalize dates.
3. Use ephemeral normalized structured identifiers to pre-redact narrative matches.
4. Run deterministic pattern detection.
5. Call the pinned Azure Text PII API for remaining narrative text.
6. Reconcile detections and apply typed local replacements.
7. Perform integrity, residual-leakage, and clinical-utility validation.
8. Route exceptions for privacy and clinical review.
9. Release a newly generated workbook only after approval.

**Expected result:** No releasable direct identifier remains; allowed years and non-identifying clinical facts remain usable; every transformation is traceable without raw PHI in logs.

**Limitations:** Azure coverage is not identical to Safe Harbor categories, AI errors remain possible, clinical/facility terms may cause over-redaction, and PoC results cannot establish legal de-identification.

Decision framework:

| Decision | Conditions |
|---|---|
| CONTINUE | Phase 0 approvals are complete; all approved acceptance gates pass; zero observed residual PHI; no critical security finding; reviewers confirm adequate clinical utility |
| CHANGE | Security pathway remains acceptable but one or more recall, precision, utility, rule, schema, chunking, or configuration gates fail and a bounded remediation is available |
| STOP | Required PHI/contract/environment approval is absent; any uncontrolled PHI exposure occurs; residual leakage remains after remediation; Azure coverage is inadequate; private secure integration is infeasible; or business utility is insufficient |

## 16. Proposed Implementation Phases

| Phase | Objective and major activities | Deliverables | Exit criteria |
|---|---|---|---|
| 0 — Governance/environment approval | Confirm purpose, dataset, platform, Azure tenant/service/region, DPA/BAA, identity, network, logging, retention, reviewers | Approved data flow, risk register, control checklist, authorization records | All mandatory PHI gates signed; otherwise stop |
| 1 — Baseline and contracts | Formalize Clinical_Data schema; catalogue existing behavior/defects; reconcile renv and enterprise R version | Requirements, schema, rule catalogue, test baseline, environment record | Contracts approved and reproducible environment restored |
| 2 — Structured engine | Extract pure R modules; implement strict transformations, date/age rules, state invalidation, fail-closed export | Structured engine and unit tests | 100% approved deterministic tests pass |
| 3 — Azure integration | Implement Entra REST adapter, chunking, offsets, response validation, retry, memory-only response handling | Azure adapter, security configuration, integration evidence | Approved synthetic connectivity tests and security review pass |
| 4 — Validation/evaluation | Build annotations, scanners, metrics, utility checks, sealed holdout workflow | Ground truth, evaluation code, threshold report | Evaluation protocol frozen and approved |
| 5 — Logging/traceability | Add sanitized events, manifests, version/hash provenance, restricted evidence storage | Audit schema, sample trace, reconstruction report | A complete run can be reconstructed without raw PHI logs |
| 6 — Human review | Add role-based exception queue, decisions, segregation of duties, export gate | Review UI, role matrix, workflow tests | Authorization and state-transition tests pass |
| 7 — PoC execution | Run approved PHI corpus, repeatability tests, failure injection, utility review | Metrics, failures, reviewed output, cost/latency summary | Evidence package complete; no unresolved Critical failure |
| 8 — Go/change/stop | Compare evidence with approved thresholds and risk tolerance | Final decision memo and limitations | Named approvers record Continue, Change, or Stop |
| 9 — Optional extension | Evaluate policy RAG or constrained review agent only if a measured requirement remains | Separate business case, threat model, evaluation plan | New governance approval before implementation |

The current lockfile targets R 4.5.2 while the inspected workstation exposes R 4.6.0 with incompatible project binaries. Phase 1 will initially target the locked R 4.5.2 environment; any migration requires a rebuilt lockfile and full regression baseline.

## 17. Evidence Matrix for Final Assignment Questions

All status values below describe the state at plan approval, not completed work.

| Assignment evidence | Planned | Implemented | Tested | Approved | Future evidence location |
|---|---:|---:|---:|---:|---|
| Technology/service/API/model and R integration | Yes | Not yet | Not yet | Not yet | docs/technology-register.md, run manifest |
| Azure region, identity, network, retention, DPA/BAA and environment approval | Yes | Not yet | Not yet | Not yet | Restricted governance evidence store |
| Structured accuracy and completeness | Yes | Not yet | Not yet | Not yet | reports/structured-evaluation.html |
| Azure precision, recall, F1 and identifier coverage | Yes | Not yet | Not yet | Not yet | reports/azure-pii-evaluation.html |
| End-to-end residual leakage and fitness for purpose | Yes | Not yet | Not yet | Not yet | reports/poc-evaluation.html |
| Consistency and repeatability | Yes | Not yet | Not yet | Not yet | evaluation/results/repeatability-summary.json |
| Prompt applicability and API/configuration versioning | Yes | Not yet | Not yet | Not yet | docs/configuration-register.md |
| Structured output schema and validation | Yes | Not yet | Not yet | Not yet | docs/data-contracts.md, validation manifest |
| Logging, provenance and traceability | Yes | Not yet | Not yet | Not yet | Restricted audit store and trace report |
| Human review and release approval | Yes | Not yet | Not yet | Not yet | Restricted review/approval record |
| Strong scenario, scope, assumptions, limitations and success criteria | Yes | Not yet | Not yet | Not yet | reports/final-poc-decision.md |
| Continue/change/stop decision | Yes | Not yet | Not yet | Not yet | Signed decision record |

The final report may change a status only when the referenced evidence exists and has been reviewed.

## 18. Deliverables

| Artifact | Location/classification |
|---|---|
| Requirements and approved assumptions | Repository documentation |
| Architecture and PHI data-flow diagram | Repository documentation |
| Threat model and privacy/security risk register | Restricted governance store |
| Workbook schema and column classification | Repository; no source values |
| Versioned anonymization rule catalogue | Repository |
| Modular R source and Shiny interface | Repository |
| Reproducible dependency lock | Repository |
| Azure integration/configuration specification | Repository without secrets |
| Azure resource, IAM, network, and contractual evidence | Restricted governance store |
| Synthetic test corpus | Repository if confirmed non-PHI |
| Approved-PHI corpus and ground-truth labels | Approved external data zone only |
| Automated unit, integration, and Shiny tests | Repository |
| Evaluation and threshold report | Restricted report store; sanitized summary in repository |
| Failure-analysis report | Restricted report store |
| Sanitized run logs and manifests | Restricted evidence store |
| Human-review and approval records | Restricted evidence store |
| Anonymized sample output | Approved output zone |
| Traceability/reconstruction report | Restricted evidence store |
| Known-limitations document | Repository |
| Final Continue/Change/Stop report | Restricted approval store; sanitized summary as allowed |
| Software bill of materials and deployment record | Repository/evidence store |

## 19. Recommended Repository Structure

    project/
      app.R                         # Thin Shiny launcher
      DESCRIPTION                   # Package metadata and dependencies
      NAMESPACE
      renv.lock
      R/
        input.R                     # Workbook reading and inspection
        schema.R                    # Schema validation/classification
        structured_rules.R
        text_preprocessing.R
        azure_pii_client.R
        detection_reconciliation.R
        validation.R
        review_workflow.R
        audit.R
        export.R
        shiny_modules.R
      config/
        schema.yml                  # Requires Clinical_Data
        poc.yml                     # Non-secret execution settings
        logging.yml
      rules/
        safe_harbor_candidate.yml
        entity_mapping.yml
        clinical_preservation.yml
      inst/
        schemas/                    # JSON/YAML schema definitions
        report_templates/
      tests/
        testthat/
        shinytest2/
        fixtures/
          synthetic/
      evaluation/
        annotation_guide/
        scripts/
        synthetic_labels/
        results/                    # Sanitized summaries only
      docs/
        requirements.md
        architecture.md
        data-contracts.md
        technology-register.md
        limitations.md
      reports/
        templates/
      scripts/
        validate_environment.R
        run_tests.R
        build_reports.R
      runtime/
        input/                      # External encrypted mount; gitignored
        output/                     # External approved destination; gitignored
        logs/                       # Restricted evidence sink; gitignored
      .gitignore
      .Renviron.example             # Variable names only, never values

Repository controls:

- No PHI, approved-PHI labels, logs, outputs, secrets, tokens, or full Azure responses in Git.
- CI uses synthetic fixtures only.
- Add secret scanning and checks preventing deployment to unapproved targets.
- Exclude the current rsconnect/shinyapps.io configuration from the approved-PHI deployment path.
- Keep runtime directories externally mounted or absent from source-control clones.

## 20. Final Recommendation

1. **Recommended architecture:** a package-style, deterministic R engine with a thin Shiny review interface, versioned rules, local known-value/regex scanning, Azure Text PII GA integration, independent validation, and human-gated export.

2. **Why preferable to RAG or autonomous agents:** the task is primarily transformation and verification. Deterministic execution provides better reproducibility, testability, failure control, and traceability. Azure adds bounded entity detection without giving an autonomous component release authority.

3. **Later RAG value:** retrieve approved internal policies, study-specific data dictionaries, prior adjudications, or validation guidance for reviewers. Retrieved material must be versioned, access-controlled, cited, and non-executable.

4. **Later agent value:** assemble evidence packages, route exceptions, recommend regression tests, and draft failure summaries. Tool access must be least-privilege, with no autonomous rule changes or output release.

5. **Top five privacy/security risks:**

   - Azure tenant/service/region or contractual coverage is not approved for the intended PHI.
   - False negatives leave identifiers in structured or narrative content.
   - Raw PHI leaks through logs, temporary files, API responses, previews, browser caches, or downloads.
   - Weak identity, secret, network, or reviewer access controls expose the pipeline.
   - Remaining quasi-identifiers or unique combinations enable re-identification despite removing explicit identifiers.

6. **Top five technical risks:**

   - Schema drift and malformed Excel content bypass expected rules.
   - Azure category/model behavior does not cover all Safe Harbor classes.
   - Chunking, Unicode, and offset reconciliation produce partial redaction.
   - API limits, throttling, and partial failures lead to incomplete processing.
   - Over-redaction removes clinically important information and undermines business value.

7. **Organization decisions required before production code or PHI execution:**

   - Approve the enterprise R platform, identity, network, storage, logging, backup, and retention design.
   - Confirm the Azure tenant, subscription, resource, GA feature, region, DPA/BAA applicability, and audit scope.
   - Approve the PHI dataset, purpose, minimum-necessary selection, access list, annotation process, and disposal.
   - Approve the rule catalogue, including dates, ages over 89, clinician/facility handling, quasi-identifiers, and no cross-run linkage.
   - Approve acceptance thresholds, reviewers, segregation of duties, release criteria, and residual-risk authority.

8. **First implementation milestone after approval:** complete Phase 0, then build a non-releasing deterministic foundation that validates Clinical_Data, implements the seven-column structured policy, resets state correctly, blocks raw/partial export, and passes the synthetic regression suite. Azure integration and approved-PHI execution begin only after that milestone and the corresponding security gate pass.
