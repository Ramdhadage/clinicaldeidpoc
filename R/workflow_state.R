allowed_run_transitions <- function() {
  list(
    EMPTY = c("RECEIVED"),
    RECEIVED = c("SCHEMA_VALIDATED", "VALIDATION_FAILED"),
    SCHEMA_VALIDATED = c("PROCESSED", "VALIDATION_FAILED"),
    PROCESSED = c("VALIDATED", "VALIDATION_FAILED"),
    VALIDATED = c("REVIEW_PENDING", "VALIDATION_FAILED"),
    REVIEW_PENDING = c("APPROVED", "REJECTED", "VALIDATION_FAILED"),
    APPROVED = c("RELEASED", "VALIDATION_FAILED"),
    REJECTED = c("RECEIVED"),
    RELEASED = c("RECEIVED"),
    VALIDATION_FAILED = c("RECEIVED")
  )
}


new_deid_run <- function(config_hash, run_id = new_run_id()) {
  assert_scalar_character(config_hash, "config_hash")
  assert_scalar_character(run_id, "run_id")

  structure(
    list(
      run_id = run_id,
      state = "EMPTY",
      input = NULL,
      schema_validation = NULL,
      result = NULL,
      preview_tokens = NULL,
      validation = NULL,
      blockers = empty_blockers(),
      binding = list(
        input_hash = NULL,
        config_hash = config_hash,
        output_hash = NULL
      ),
      approval_binding = NULL,
      release_artifact = NULL,
      failure = NULL,
      created_at = utc_now(),
      updated_at = utc_now()
    ),
    class = c("DeidRun", "list")
  )
}


transition_run <- function(run, to_state) {
  if (!inherits(run, "DeidRun")) {
    deid_abort(
      code = "INVALID_RUN_OBJECT",
      message = "A DeidRun object is required.",
      subclass = "deid_workflow_error"
    )
  }

  assert_scalar_character(to_state, "to_state")
  transitions <- allowed_run_transitions()
  allowed <- transitions[[run$state]]

  if (is.null(allowed) || !to_state %in% allowed) {
    deid_abort(
      code = "INVALID_STATE_TRANSITION",
      message = paste0(
        "Run state cannot transition from ",
        run$state,
        " to ",
        to_state,
        "."
      ),
      subclass = "deid_workflow_error"
    )
  }

  run$state <- to_state
  run$updated_at <- utc_now()
  run
}


invalidate_run <- function(run, input_hash = NULL) {
  if (!inherits(run, "DeidRun")) {
    deid_abort(
      code = "INVALID_RUN_OBJECT",
      message = "A DeidRun object is required.",
      subclass = "deid_workflow_error"
    )
  }

  fresh <- new_deid_run(
    config_hash = run$binding$config_hash
  )
  fresh <- transition_run(fresh, "RECEIVED")
  fresh$binding$input_hash <- input_hash
  fresh
}


failed_run_from_condition <- function(
    config_hash,
    condition,
    input_hash = NULL
) {
  run <- new_deid_run(config_hash)
  run <- transition_run(run, "RECEIVED")
  run <- transition_run(run, "VALIDATION_FAILED")
  run$binding$input_hash <- input_hash
  run$failure <- list(
    code = if (!is.null(condition$code)) {
      condition$code
    } else {
      "UNEXPECTED_ERROR"
    },
    message = conditionMessage(condition)
  )
  run
}


run_structured_deidentification <- function(
    input_dataset,
    config = read_deid_config("."),
    preview_token_factory = secure_random_hex_token
) {
  if (!inherits(input_dataset, "InputDataset")) {
    deid_abort(
      code = "INVALID_INPUT_DATASET",
      message = "An InputDataset produced by read_clinical_workbook is required.",
      subclass = "deid_argument_error"
    )
  }

  run <- new_deid_run(config$hash)
  run <- transition_run(run, "RECEIVED")
  run$input <- input_dataset
  run$binding$input_hash <- input_dataset$metadata$input_hash

  schema_validation <- validate_clinical_schema(
    input_dataset$data,
    config
  )
  run$schema_validation <- schema_validation
  run <- transition_run(run, "SCHEMA_VALIDATED")
  run$preview_tokens <- create_preview_token_bundle(
    source = schema_validation$data,
    config = config,
    token_factory = preview_token_factory
  )

  structured_result <- transform_structured_fields(
    schema_validation,
    config
  )
  run$result <- structured_result
  run$binding$output_hash <- hash_object(structured_result$data)
  run <- transition_run(run, "PROCESSED")

  validation <- validate_structured_result(
    schema_validation$data,
    structured_result,
    config
  )
  run$validation <- validation
  run$blockers <- validation$blockers
  run
}


release_binding_is_current <- function(run) {
  if (
    !inherits(run, "DeidRun") ||
    is.null(run$result) ||
    is.null(run$result$data) ||
    is.null(run$binding$output_hash) ||
    is.null(run$approval_binding)
  ) {
    return(FALSE)
  }

  current_output_hash <- tryCatch(
    hash_object(run$result$data),
    error = function(e) NULL
  )

  !is.null(current_output_hash) &&
    identical(run$binding$output_hash, current_output_hash) &&
    identical(run$approval_binding, run$binding)
}


can_release <- function(run, config = NULL) {
  if (!inherits(run, "DeidRun")) {
    return(FALSE)
  }

  config_valid <- !is.null(config) &&
    inherits(config, "DeidConfig") &&
    isTRUE(tryCatch(
      {
        validate_deid_config(config)
        TRUE
      },
      error = function(e) FALSE
    ))
  release_enabled <- config_valid && isTRUE(config$runtime$release_enabled)

  narrative_release_ready <- !is.null(run$validation) &&
    isTRUE(run$validation$narrative_redaction_validated) &&
    !isTRUE(run$validation$tagged_preview_only)

  binding_complete <- all(vapply(
    run$binding,
    function(value) {
      is.character(value) && length(value) == 1L && !is.na(value) && nzchar(value)
    },
    logical(1)
  ))

  release_enabled &&
    narrative_release_ready &&
    identical(run$state, "APPROVED") &&
    !is.null(run$validation) &&
    isTRUE(run$validation$release_passed) &&
    is.data.frame(run$blockers) &&
    nrow(run$blockers) == 0L &&
    binding_complete &&
    release_binding_is_current(run)
}


assert_release_allowed <- function(run, config = NULL) {
  if (!can_release(run, config)) {
    deid_abort(
      code = "EXPORT_NOT_APPROVED",
      message = paste(
        "Export is blocked until full text processing, validation,",
        "independent review, and approval are implemented and complete."
      ),
      subclass = "deid_export_not_approved"
    )
  }

  invisible(TRUE)
}
