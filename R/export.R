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


build_synthetic_preview_notice <- function() {
  data.frame(
    notice = c(
      "Classification",
      "Release status",
      "Restriction",
      "Required use"
    ),
    value = c(
      "Synthetic tagged preview",
      "Not releasable",
      "Not validated anonymization or a HIPAA Safe Harbor determination",
      "Synthetic evaluation only; do not use or disclose as de-identified data"
    ),
    stringsAsFactors = FALSE
  )
}


prepare_synthetic_preview_download <- function(run, config) {
  if (!inherits(run, "DeidRun") || !inherits(config, "DeidConfig")) {
    deid_abort(
      code = "PREVIEW_DOWNLOAD_NOT_ALLOWED",
      message = "A processed synthetic preview and valid configuration are required.",
      subclass = "deid_preview_download_error"
    )
  }

  validate_deid_config(config)

  if (
    !identical(config$runtime$mode, "synthetic_only") ||
    isTRUE(config$runtime$release_enabled) ||
    !identical(run$state, "PROCESSED") ||
    is.null(run$validation) ||
    !isTRUE(run$validation$tagged_preview_only) ||
    isTRUE(run$validation$narrative_redaction_validated)
  ) {
    deid_abort(
      code = "PREVIEW_DOWNLOAD_NOT_ALLOWED",
      message = "Only a non-releasing synthetic tagged preview can be downloaded.",
      subclass = "deid_preview_download_error"
    )
  }

  preview <- create_tagged_preview(run, config)
  if (is.null(preview) || any(
    unlist(preview, use.names = FALSE) ==
      config$policy$preview$failure_placeholder,
    na.rm = TRUE
  )) {
    deid_abort(
      code = "PREVIEW_DOWNLOAD_NOT_ALLOWED",
      message = "The synthetic tagged preview is incomplete and cannot be downloaded.",
      subclass = "deid_preview_download_error"
    )
  }

  list(
    preview = preview,
    notice = build_synthetic_preview_notice()
  )
}


verify_synthetic_preview_workbook <- function(path, preview, notice) {
  expected_sheets <- c("Synthetic_Tagged_Preview", "Preview_Notice")
  if (!identical(readxl::excel_sheets(path), expected_sheets)) {
    deid_abort(
      code = "PREVIEW_DOWNLOAD_VERIFICATION_FAILED",
      message = "The synthetic preview workbook failed sheet verification.",
      subclass = "deid_preview_download_error"
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

  if (
    !identical(
      read_sheet("Synthetic_Tagged_Preview"),
      normalize_release_sheet(preview)
    ) ||
    !identical(read_sheet("Preview_Notice"), normalize_release_sheet(notice))
  ) {
    deid_abort(
      code = "PREVIEW_DOWNLOAD_VERIFICATION_FAILED",
      message = "The synthetic preview workbook failed exact content verification.",
      subclass = "deid_preview_download_error"
    )
  }

  invisible(TRUE)
}


write_synthetic_preview_workbook <- function(run, path, config) {
  assert_scalar_character(path, "path")

  if (!identical(tolower(tools::file_ext(path)), "xlsx")) {
    deid_abort(
      code = "INVALID_OUTPUT_TYPE",
      message = "Synthetic preview output must use the .xlsx extension.",
      subclass = "deid_preview_download_error"
    )
  }

  download <- prepare_synthetic_preview_download(run, config)
  require_deid_namespace("writexl")
  require_deid_namespace("readxl")

  writexl::write_xlsx(
    list(
      Synthetic_Tagged_Preview = download$preview,
      Preview_Notice = download$notice
    ),
    path
  )

  verify_synthetic_preview_workbook(
    path,
    download$preview,
    download$notice
  )

  invisible(path)
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
