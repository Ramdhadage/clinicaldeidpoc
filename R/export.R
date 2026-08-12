write_release_workbook <- function(
    run,
    path,
    config = read_deid_config(".")
) {
  assert_release_allowed(run)
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

  temporary_path <- tempfile(
    pattern = "deid-release-",
    tmpdir = output_directory,
    fileext = ".xlsx"
  )
  on.exit(unlink(temporary_path, force = TRUE), add = TRUE)

  writexl::write_xlsx(
    list(
      Clinical_Data = run$result$data,
      Validation_Summary = build_validation_summary_sheet(run, config)
    ),
    temporary_path
  )

  sheets <- readxl::excel_sheets(temporary_path)
  if (!identical(sheets, c("Clinical_Data", "Validation_Summary"))) {
    deid_abort(
      code = "OUTPUT_VERIFICATION_FAILED",
      message = "The generated release workbook failed sheet verification.",
      subclass = "deid_export_error"
    )
  }

  reopened <- readxl::read_excel(
    temporary_path,
    sheet = "Clinical_Data",
    col_types = "text",
    .name_repair = "minimal"
  )

  if (
    nrow(reopened) != nrow(run$result$data) ||
    !identical(names(reopened), names(run$result$data))
  ) {
    deid_abort(
      code = "OUTPUT_VERIFICATION_FAILED",
      message = "The generated release workbook failed row or column verification.",
      subclass = "deid_export_error"
    )
  }

  if (!file.rename(temporary_path, path)) {
    deid_abort(
      code = "OUTPUT_MOVE_FAILED",
      message = "The verified workbook could not be moved to the release target.",
      subclass = "deid_export_error"
    )
  }

  released_run <- transition_run(run, "RELEASED")
  list(
    run = released_run,
    path = normalizePath(path, winslash = "/", mustWork = TRUE)
  )
}
