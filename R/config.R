read_yaml_config <- function(path, label) {
  require_deid_namespace("yaml")

  if (!file.exists(path)) {
    deid_abort(
      code = "CONFIG_FILE_MISSING",
      message = paste0(label, " configuration file is missing."),
      subclass = "deid_config_error"
    )
  }

  tryCatch(
    yaml::read_yaml(path),
    error = function(e) {
      deid_abort(
        code = "CONFIG_PARSE_FAILED",
        message = paste0(label, " configuration could not be parsed."),
        subclass = "deid_config_error"
      )
    }
  )
}


schema_columns <- function(config) {
  columns <- config$schema$columns

  do.call(
    rbind,
    lapply(
      columns,
      function(column) {
        data.frame(
          name = as.character(column$name),
          role = as.character(column$role),
          type = as.character(column$type),
          required = isTRUE(column$required),
          action = as.character(column$action),
          stringsAsFactors = FALSE
        )
      }
    )
  )
}


validate_deid_config <- function(config) {
  schema <- config$schema
  policy <- config$policy
  runtime <- config$runtime

  if (!identical(schema$schema_version, "0.3.0")) {
    deid_abort(
      code = "INVALID_SCHEMA_VERSION",
      message = "The schema configuration version is not supported.",
      subclass = "deid_config_error"
    )
  }

  if (!identical(schema$sheet_name, "Clinical_Data")) {
    deid_abort(
      code = "INVALID_SHEET_CONFIGURATION",
      message = "The first milestone requires the exact worksheet Clinical_Data.",
      subclass = "deid_config_error"
    )
  }

  columns <- schema_columns(config)
  expected <- c(
    "Record_No",
    "Patient_Name",
    "DOB",
    "Diagnosis_Journey",
    "Treatment_History",
    "MRN",
    "Patient_ID",
    "Zip_Code"
  )

  if (!identical(columns$name, expected) || anyDuplicated(columns$name)) {
    deid_abort(
      code = "INVALID_COLUMN_CONFIGURATION",
      message = "The configured columns do not match the approved eight-column contract.",
      subclass = "deid_config_error"
    )
  }

  expected_roles <- c(
    "direct_identifier",
    "direct_identifier",
    "date_identifier",
    "free_text",
    "free_text",
    "direct_identifier",
    "direct_identifier",
    "geographic_identifier"
  )

  if (!identical(columns$role, expected_roles)) {
    deid_abort(
      code = "INVALID_ROLE_CONFIGURATION",
      message = "The configured column roles do not match the approved contract.",
      subclass = "deid_config_error"
    )
  }

  expected_actions <- c(
    "remove",
    "remove",
    "keep_year_or_90_plus",
    "deterministic_tagged_preview_only",
    "deterministic_tagged_preview_only",
    "remove",
    "remove",
    "retain_eligible_three_digit_or_000"
  )
  if (!identical(columns$action, expected_actions)) {
    deid_abort(
      code = "INVALID_ACTION_CONFIGURATION",
      message = "The configured column actions do not match the approved contract.",
      subclass = "deid_config_error"
    )
  }

  if (!identical(runtime$mode, "synthetic_only")) {
    deid_abort(
      code = "UNAPPROVED_RUNTIME_MODE",
      message = "Only synthetic_only mode is implemented in this milestone.",
      subclass = "deid_config_error"
    )
  }

  if (isTRUE(runtime$release_enabled)) {
    deid_abort(
      code = "RELEASE_MUST_REMAIN_DISABLED",
      message = "Release must remain disabled until later validation and approval milestones.",
      subclass = "deid_config_error"
    )
  }

  reference_date <- as.Date(policy$reference_date)
  if (is.na(reference_date)) {
    deid_abort(
      code = "INVALID_REFERENCE_DATE",
      message = "The policy reference_date is invalid.",
      subclass = "deid_config_error"
    )
  }

  if (!identical(policy$cross_run_stable_tokens_enabled, FALSE)) {
    deid_abort(
      code = "STABLE_TOKENS_NOT_ALLOWED",
      message = "Stable identifier tokens are disabled for this milestone.",
      subclass = "deid_config_error"
    )
  }

  if (
    !identical(policy$free_text_action, "deterministic_tagged_preview_only") ||
    !isTRUE(policy$preview$enabled) ||
    !identical(policy$preview$mode, "synthetic_deterministic_tagged")
  ) {
    deid_abort(
      code = "INVALID_PREVIEW_CONFIGURATION",
      message = "The synthetic deterministic tagged-preview policy is required.",
      subclass = "deid_config_error"
    )
  }

  structured_id <- policy$preview$structured_id
  if (
    !is.list(structured_id) ||
    !identical(structured_id$mode, "run_scoped_random_hex") ||
    !identical(
      structured_id$columns,
      c("Record_No", "MRN", "Patient_ID")
    ) ||
    !identical(as.integer(structured_id$length), 8L) ||
    !identical(structured_id$alphabet, "lowercase_hex") ||
    !identical(structured_id$source_derived, FALSE) ||
    !identical(structured_id$persist, FALSE)
  ) {
    deid_abort(
      code = "INVALID_STRUCTURED_PREVIEW_ID_CONFIGURATION",
      message = "The run-scoped structured preview ID policy is invalid.",
      subclass = "deid_config_error"
    )
  }

  zip_code <- policy$preview$zip_code
  eligible_prefixes <- unlist(
    zip_code$eligible_three_digit_prefixes,
    use.names = FALSE
  )
  if (
    !is.list(zip_code) ||
    !identical(zip_code$mode, "safe_harbor_conditional_three_digit") ||
    !is.character(zip_code$population_source) ||
    length(zip_code$population_source) != 1L ||
    is.na(zip_code$population_source) ||
    !nzchar(zip_code$population_source) ||
    !is.character(zip_code$population_reference_date) ||
    length(zip_code$population_reference_date) != 1L ||
    is.na(as.Date(zip_code$population_reference_date)) ||
    any(!grepl("^[0-9]{3}$", eligible_prefixes, perl = TRUE)) ||
    anyDuplicated(eligible_prefixes)
  ) {
    deid_abort(
      code = "INVALID_SAFE_HARBOR_ZIP_CONFIGURATION",
      message = paste(
        "The conditional three-digit ZIP policy must use an approved",
        "unique three-digit Census allowlist."
      ),
      subclass = "deid_config_error"
    )
  }

  required_preview_tags <- c(
    "name",
    "geographic_subdivision",
    "zip_code",
    "date",
    "age_90_or_older",
    "telephone_number",
    "fax_number",
    "email",
    "ssn",
    "medical_record_number",
    "health_plan_number",
    "account_number",
    "certificate_license_number",
    "vehicle_identifier",
    "device_identifier",
    "url",
    "ip_address",
    "biometric_identifier",
    "facility",
    "other_unique_identifier"
  )
  configured_tags <- policy$preview$tags
  if (
    !is.list(configured_tags) ||
    !all(required_preview_tags %in% names(configured_tags)) ||
    any(!vapply(
      configured_tags[required_preview_tags],
      function(value) {
        is.character(value) && length(value) == 1L && !is.na(value) && nzchar(value)
      },
      logical(1)
    )) ||
    !is.character(policy$preview$failure_placeholder) ||
    length(policy$preview$failure_placeholder) != 1L ||
    !nzchar(policy$preview$failure_placeholder) ||
    !identical(configured_tags$date, "[{year}]")
  ) {
    deid_abort(
      code = "INVALID_PREVIEW_TAG_CONFIGURATION",
      message = "The tagged-preview labels are incomplete or invalid.",
      subclass = "deid_config_error"
    )
  }

  max_file_bytes <- as.numeric(runtime$limits$max_file_bytes)
  max_rows <- as.integer(runtime$limits$max_rows)

  if (
    length(max_file_bytes) != 1L ||
    is.na(max_file_bytes) ||
    max_file_bytes <= 0 ||
    length(max_rows) != 1L ||
    is.na(max_rows) ||
    max_rows <= 0
  ) {
    deid_abort(
      code = "INVALID_RUNTIME_LIMITS",
      message = "Configured file and row limits must be positive.",
      subclass = "deid_config_error"
    )
  }

  invisible(TRUE)
}


read_deid_config <- function(project_root = ".") {
  schema <- read_yaml_config(
    file.path(project_root, "config", "schema.yml"),
    "Schema"
  )
  policy <- read_yaml_config(
    file.path(project_root, "rules", "safe_harbor_candidate.yml"),
    "Policy"
  )
  runtime <- read_yaml_config(
    file.path(project_root, "config", "poc.yml"),
    "Runtime"
  )

  config <- list(
    schema = schema,
    policy = policy,
    runtime = runtime
  )

  validate_deid_config(config)
  config$hash <- hash_object(config)
  class(config) <- c("DeidConfig", "list")
  config
}
