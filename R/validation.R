validate_structured_result <- function(
    input_data,
    structured_result,
    config = read_deid_config(".")
) {
  if (!is.data.frame(input_data)) {
    deid_abort(
      code = "INVALID_VALIDATION_INPUT",
      message = "The original validated data frame is required.",
      subclass = "deid_argument_error"
    )
  }

  if (!inherits(structured_result, "StructuredResult")) {
    deid_abort(
      code = "INVALID_STRUCTURED_RESULT",
      message = "A StructuredResult is required for validation.",
      subclass = "deid_argument_error"
    )
  }

  output <- structured_result$data
  expected_columns <- schema_columns(config)$name

  if (
    nrow(output) != nrow(input_data) ||
    !identical(names(output), expected_columns)
  ) {
    deid_abort(
      code = "OUTPUT_INTEGRITY_FAILED",
      message = "Structured output row or column integrity validation failed.",
      subclass = "deid_validation_error"
    )
  }

  direct_columns <- schema_columns(config)$name[
    schema_columns(config)$role == "direct_identifier"
  ]

  direct_values_removed <- all(vapply(
    output[direct_columns],
    function(column) all(is.na(column)),
    logical(1)
  ))

  if (!direct_values_removed) {
    deid_abort(
      code = "DIRECT_IDENTIFIER_REMAINS",
      message = "A structured direct identifier remains in the output.",
      subclass = "deid_validation_error"
    )
  }

  dob_valid <- is.na(output$DOB) |
    grepl("^([12][0-9]{3}|90\\+)$", output$DOB, perl = TRUE)

  if (!all(dob_valid)) {
    deid_abort(
      code = "DOB_GENERALIZATION_FAILED",
      message = "A generalized DOB value is outside the approved output format.",
      subclass = "deid_validation_error"
    )
  }

  zip_valid <- is.na(output$Zip_Code) |
    grepl("^[0-9]{3}$", output$Zip_Code, perl = TRUE)

  if (!all(zip_valid)) {
    deid_abort(
      code = "ZIP_GENERALIZATION_FAILED",
      message = "A generalized Zip_Code value is outside the approved output format.",
      subclass = "deid_validation_error"
    )
  }

  narrative_columns <- schema_columns(config)$name[
    schema_columns(config)$role == "free_text"
  ]
  blockers <- data.frame(
    code = rep(
      "NARRATIVE_REDACTION_NOT_VALIDATED",
      length(narrative_columns)
    ),
    column = narrative_columns,
    severity = rep("Critical", length(narrative_columns)),
    stringsAsFactors = FALSE
  )

  structure(
    list(
      structured_passed = TRUE,
      release_passed = FALSE,
      row_count_preserved = TRUE,
      column_contract_preserved = TRUE,
      direct_values_removed = TRUE,
      dob_generalization_valid = TRUE,
      zip_generalization_valid = TRUE,
      tagged_preview_only = TRUE,
      narrative_redaction_validated = FALSE,
      blockers = blockers,
      validated_at = utc_now()
    ),
    class = c("ValidationSummary", "list")
  )
}
