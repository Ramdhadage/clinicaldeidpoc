build_validation_summary_sheet <- function(run, config) {
  data.frame(
    metric = c(
      "run_id",
      "state",
      "row_count",
      "column_count",
      "schema_version",
      "policy_id",
      "policy_version",
      "configuration_hash",
      "input_hash",
      "output_hash",
      "structured_validation_passed",
      "release_validation_passed",
      "blocker_count",
      "generated_at_utc"
    ),
    value = c(
      run$run_id,
      run$state,
      as.character(nrow(run$result$data)),
      as.character(ncol(run$result$data)),
      config$schema$schema_version,
      config$policy$policy_id,
      config$policy$policy_version,
      run$binding$config_hash,
      run$binding$input_hash,
      run$binding$output_hash,
      as.character(isTRUE(run$validation$structured_passed)),
      as.character(isTRUE(run$validation$release_passed)),
      as.character(nrow(run$blockers)),
      utc_now()
    ),
    stringsAsFactors = FALSE
  )
}

