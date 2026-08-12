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
    "Patient_ID"
  )

  if (!identical(columns$name, expected) || anyDuplicated(columns$name)) {
    deid_abort(
      code = "INVALID_COLUMN_CONFIGURATION",
      message = "The configured columns do not match the approved seven-column contract.",
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
    "direct_identifier"
  )

  if (!identical(columns$role, expected_roles)) {
    deid_abort(
      code = "INVALID_ROLE_CONFIGURATION",
      message = "The configured column roles do not match the approved contract.",
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

  if (!identical(policy$stable_tokens_enabled, FALSE)) {
    deid_abort(
      code = "STABLE_TOKENS_NOT_ALLOWED",
      message = "Stable identifier tokens are disabled for this milestone.",
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
