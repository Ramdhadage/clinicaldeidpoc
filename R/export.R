normalize_release_sheet <- function(data) {
  output <- as.data.frame(
    data,
    stringsAsFactors = FALSE,
    check.names = FALSE
  )
  for (name in names(output)) {
    output[[name]] <- as.character(output[[name]])
  }
  row.names(output) <- NULL
  output
}


verify_release_workbook <- function(
    path,
    expected_data,
    expected_summary
) {
  sheets <- readxl::excel_sheets(path)
  if (!identical(sheets, c("Clinical_Data", "Validation_Summary"))) {
    deid_abort(
      code = "OUTPUT_VERIFICATION_FAILED",
      message = "The generated release workbook failed sheet verification.",
      subclass = "deid_export_error"
    )
  }

  read_sheet <- function(sheet) {
    normalize_release_sheet(readxl::read_excel(
      path,
      sheet = sheet,
      col_types = "text",
      trim_ws = FALSE,
      .name_repair = "minimal"
    ))
  }

  reopened_data <- read_sheet("Clinical_Data")
  reopened_summary <- read_sheet("Validation_Summary")
  expected_data <- normalize_release_sheet(expected_data)
  expected_summary <- normalize_release_sheet(expected_summary)

  if (
    !identical(reopened_data, expected_data) ||
    !identical(reopened_summary, expected_summary)
  ) {
    deid_abort(
      code = "OUTPUT_VERIFICATION_FAILED",
      message = "The generated release workbook failed exact content verification.",
      subclass = "deid_export_error"
    )
  }

  invisible(TRUE)
}


write_release_workbook <- function(
    run,
    path,
    config = read_deid_config(".")
) {
  assert_release_allowed(run, config)
  assert_scalar_character(path, "path")

  if (!identical(tolower(tools::file_ext(path)), "xlsx")) {
    deid_abort(
      code = "INVALID_OUTPUT_TYPE",
      message = "Release output must use the .xlsx extension.",
      subclass = "deid_export_error"
    )
  }

  if (file.exists(path)) {
    deid_abort(
      code = "OUTPUT_ALREADY_EXISTS",
      message = "The release target already exists and will not be overwritten.",
      subclass = "deid_export_error"
    )
  }

  output_directory <- dirname(normalizePath(
    path,
    winslash = "/",
    mustWork = FALSE
  ))

  if (!dir.exists(output_directory)) {
    deid_abort(
      code = "OUTPUT_DIRECTORY_MISSING",
      message = "The release output directory does not exist.",
      subclass = "deid_export_error"
    )
  }

  require_deid_namespace("writexl")
  require_deid_namespace("readxl")

  release_data <- run$result$data
  release_hash <- hash_object(release_data)
  if (
    !identical(release_hash, run$binding$output_hash) ||
    !identical(run$approval_binding, run$binding)
  ) {
    deid_abort(
      code = "EXPORT_BINDING_CHANGED",
      message = "The approved output changed before export.",
      subclass = "deid_export_not_approved"
    )
  }
  validation_summary <- build_validation_summary_sheet(run, config)

  temporary_path <- tempfile(
    pattern = "deid-release-",
    tmpdir = output_directory,
    fileext = ".xlsx"
  )
  on.exit(unlink(temporary_path, force = TRUE), add = TRUE)

  writexl::write_xlsx(
    list(
      Clinical_Data = release_data,
      Validation_Summary = validation_summary
    ),
    temporary_path
  )

  verify_release_workbook(
    temporary_path,
    release_data,
    validation_summary
  )
  temporary_hash <- hash_file(temporary_path)

  if (!file.rename(temporary_path, path)) {
    deid_abort(
      code = "OUTPUT_MOVE_FAILED",
      message = "The verified workbook could not be moved to the release target.",
      subclass = "deid_export_error"
    )
  }

  final_hash <- hash_file(path)
  if (!identical(final_hash, temporary_hash)) {
    unlink(path, force = TRUE)
    deid_abort(
      code = "OUTPUT_VERIFICATION_FAILED",
      message = "The final release workbook hash did not match the verified file.",
      subclass = "deid_export_error"
    )
  }

  released_run <- transition_run(run, "RELEASED")
  released_run$release_artifact <- list(
    content_hash = release_hash,
    file_hash = final_hash,
    size_bytes = unname(file.info(path)$size),
    released_at = utc_now()
  )
  list(
    run = released_run,
    path = normalizePath(path, winslash = "/", mustWork = TRUE),
    file_hash = final_hash
  )
}
