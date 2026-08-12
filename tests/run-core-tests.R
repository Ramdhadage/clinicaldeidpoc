development_library <- Sys.getenv("DEID_LOCAL_LIBRARY", unset = "")
if (nzchar(development_library) && dir.exists(development_library)) {
  .libPaths(c(
    normalizePath(development_library, winslash = "/", mustWork = TRUE),
    .libPaths()
  ))
}

if (file.exists(file.path("R", "bootstrap.R"))) {
  project_root <- "."
  source(file.path(project_root, "R", "bootstrap.R"))
  activate_local_development_library(project_root)
  load_deid_modules(project_root)
} else {
  suppressPackageStartupMessages(library(clinicaldeidpoc))
  project_root <- file.path("..", "00_pkg_src", "clinicaldeidpoc")
  if (!file.exists(file.path(project_root, "config", "schema.yml"))) {
    stop("Package-check source configuration could not be located.", call. = FALSE)
  }
}

test_count <- 0L
failure_count <- 0L


expect_true <- function(value, message = "Expected TRUE.") {
  if (!isTRUE(value)) {
    stop(message, call. = FALSE)
  }
  invisible(TRUE)
}


expect_false <- function(value, message = "Expected FALSE.") {
  if (!identical(value, FALSE)) {
    stop(message, call. = FALSE)
  }
  invisible(TRUE)
}


expect_identical <- function(actual, expected, message = NULL) {
  if (!identical(actual, expected)) {
    if (is.null(message)) {
      message <- paste(
        "Objects are not identical.",
        "Actual:",
        paste(capture.output(str(actual)), collapse = " "),
        "Expected:",
        paste(capture.output(str(expected)), collapse = " ")
      )
    }
    stop(message, call. = FALSE)
  }
  invisible(TRUE)
}


expect_deid_error <- function(expression, expected_class, expected_code = NULL) {
  expression <- substitute(expression)
  condition <- tryCatch(
    {
      eval(expression, envir = parent.frame())
      NULL
    },
    error = function(e) e
  )

  if (is.null(condition)) {
    stop("Expected an error, but no error was raised.", call. = FALSE)
  }

  if (!inherits(condition, expected_class)) {
    stop(
      paste0(
        "Expected error class ",
        expected_class,
        ", received ",
        paste(class(condition), collapse = "/"),
        "."
      ),
      call. = FALSE
    )
  }

  if (!is.null(expected_code) && !identical(condition$code, expected_code)) {
    stop(
      paste0(
        "Expected error code ",
        expected_code,
        ", received ",
        condition$code,
        "."
      ),
      call. = FALSE
    )
  }

  invisible(condition)
}


run_test <- function(name, expression) {
  expression <- substitute(expression)
  test_count <<- test_count + 1L

  tryCatch(
    {
      eval(expression, envir = parent.frame())
      cat("[PASS]", name, "\n")
    },
    error = function(e) {
      failure_count <<- failure_count + 1L
      cat("[FAIL]", name, "\n")
      cat("       ", conditionMessage(e), "\n", sep = "")
    }
  )
}


synthetic_fixture <- function() {
  data.frame(
    Record_No = c("1", "2", "3"),
    Patient_Name = c(
      "John Michael Smith",
      "Anne-Marie O'Neil",
      "Will Brown"
    ),
    DOB = c(
      "15-Dec-80",
      "1936-08-12",
      "1936-08-13"
    ),
    Diagnosis_Journey = c(
      "John Smith was diagnosed with Stage II lymphoma.",
      "Anne-Marie O'Neil received a diagnosis.",
      "Brown discoloration was observed."
    ),
    Treatment_History = c(
      "Contact john.smith@example.test.",
      "Dose 12.5 mg.",
      "Follow-up planned."
    ),
    MRN = c("MRN-12345678", "MRN-22222222", NA),
    Patient_ID = c("SUBJ-001", "SUBJ-002", NA),
    stringsAsFactors = FALSE,
    check.names = FALSE
  )
}


write_fixture_workbook <- function(
    data,
    include_required_sheet = TRUE,
    include_additional_sheet = FALSE
) {
  if (!requireNamespace("writexl", quietly = TRUE)) {
    stop("The writexl package is required for workbook tests.", call. = FALSE)
  }
  path <- tempfile(fileext = ".xlsx")
  sheets <- list()

  if (include_additional_sheet) {
    sheets$Read_Me <- data.frame(note = "Synthetic test fixture")
  }
  if (include_required_sheet) {
    sheets$Clinical_Data <- data
  }
  if (length(sheets) == 0L) {
    sheets$Wrong_Name <- data
  }

  writexl::write_xlsx(sheets, path)
  path
}


config <- read_deid_config(project_root)


run_test("configuration matches the locked milestone", {
  expect_true(inherits(config, "DeidConfig"))
  expect_identical(config$schema$sheet_name, "Clinical_Data")
  expect_identical(config$runtime$mode, "synthetic_only")
  expect_false(config$runtime$release_enabled)
  expect_identical(nchar(config$hash), 64L)
  expect_identical(
    schema_columns(config)$name,
    c(
      "Record_No",
      "Patient_Name",
      "DOB",
      "Diagnosis_Journey",
      "Treatment_History",
      "MRN",
      "Patient_ID"
    )
  )
})


run_test("valid workbook reads the exact Clinical_Data sheet", {
  path <- write_fixture_workbook(
    synthetic_fixture(),
    include_additional_sheet = TRUE
  )
  on.exit(unlink(path, force = TRUE), add = TRUE)

  dataset <- read_clinical_workbook(
    path,
    original_name = "synthetic.xlsx",
    config = config
  )

  expect_true(inherits(dataset, "InputDataset"))
  expect_identical(dataset$metadata$additional_sheets, "Read_Me")
  expect_identical(nrow(dataset$data), 3L)
})


run_test("missing Clinical_Data sheet fails closed", {
  path <- write_fixture_workbook(
    synthetic_fixture(),
    include_required_sheet = FALSE
  )
  on.exit(unlink(path, force = TRUE), add = TRUE)

  expect_deid_error(
    read_clinical_workbook(
      path,
      original_name = "synthetic.xlsx",
      config = config
    ),
    "deid_missing_sheet",
    "MISSING_REQUIRED_SHEET"
  )
})


run_test("non-XLSX input is rejected", {
  path <- tempfile(fileext = ".csv")
  writeLines("a,b", path)
  on.exit(unlink(path, force = TRUE), add = TRUE)

  expect_deid_error(
    inspect_clinical_workbook(
      path,
      original_name = "synthetic.csv",
      config = config
    ),
    "deid_input_error",
    "UNSUPPORTED_INPUT_TYPE"
  )
})


run_test("schema is exact and reordered input is canonicalized", {
  data <- synthetic_fixture()
  data <- data[, rev(names(data)), drop = FALSE]
  validated <- validate_clinical_schema(data, config)

  expect_identical(
    names(validated$data),
    schema_columns(config)$name
  )

  missing <- data[, names(data) != "Patient_ID", drop = FALSE]
  expect_deid_error(
    validate_clinical_schema(missing, config),
    "deid_invalid_schema",
    "MISSING_REQUIRED_COLUMNS"
  )

  extra <- data
  extra$Site_Name <- "SITE-01"
  expect_deid_error(
    validate_clinical_schema(extra, config),
    "deid_invalid_schema",
    "UNEXPECTED_COLUMNS"
  )
})


run_test("duplicate column names are rejected", {
  data <- synthetic_fixture()
  names(data)[7] <- "MRN"

  expect_deid_error(
    validate_clinical_schema(data, config),
    "deid_invalid_schema",
    "INVALID_COLUMN_NAMES"
  )
})


run_test("structured identifiers are removed and DOB is generalized", {
  validated <- validate_clinical_schema(synthetic_fixture(), config)
  input_before <- validated$data
  result <- transform_structured_fields(validated, config)

  direct_columns <- c(
    "Record_No",
    "Patient_Name",
    "MRN",
    "Patient_ID"
  )
  expect_true(all(vapply(
    result$data[direct_columns],
    function(column) all(is.na(column)),
    logical(1)
  )))
  expect_identical(result$data$DOB, c("1980", "90+", "1936"))
  expect_identical(
    result$data$Diagnosis_Journey,
    input_before$Diagnosis_Journey
  )
  expect_identical(validated$data, input_before)
})


run_test("invalid and future DOB values fail closed", {
  invalid <- synthetic_fixture()
  invalid$DOB[1] <- "31-Feb-1980"
  validated <- validate_clinical_schema(invalid, config)
  expect_deid_error(
    transform_structured_fields(validated, config),
    "deid_invalid_date",
    "INVALID_DOB"
  )

  future <- synthetic_fixture()
  future$DOB[1] <- "2099-01-01"
  validated_future <- validate_clinical_schema(future, config)
  expect_deid_error(
    transform_structured_fields(validated_future, config),
    "deid_invalid_date",
    "FUTURE_DOB"
  )
})


run_test("supported display dates and Excel timestamps retain the correct year", {
  values <- c(
    "15-Dec-80",
    "22-07-1985",
    "11-11-1975 08:30",
    "03-09-1990",
    "30-05-1968",
    "02-02-1988 14:45",
    "10-10-1972",
    "19-01-1982",
    "25-12-1965",
    "09-09-1979 09:15",
    "1975-11-11 08:30:00 UTC"
  )
  expected <- c(
    "1980", "1985", "1975", "1990", "1968", "1988",
    "1972", "1982", "1965", "1979", "1975"
  )

  actual <- vapply(
    values,
    generalize_dob_value,
    character(1),
    reference_date = as.Date(config$policy$reference_date),
    age_90_plus_value = config$policy$age_90_plus_value
  )
  expect_identical(unname(actual), expected)
})


run_test("impossible DOB clock times fail closed", {
  invalid_times <- c(
    "1980-12-15 24:00",
    "15-12-1980 99:99:99",
    "15-Dec-80 23:60"
  )

  for (value in invalid_times) {
    expect_deid_error(
      generalize_dob_value(
        value,
        reference_date = as.Date(config$policy$reference_date),
        age_90_plus_value = config$policy$age_90_plus_value
      ),
      "deid_invalid_date",
      "INVALID_DOB"
    )
  }

  expect_identical(
    generalize_dob_value(
      "1980-12-15 23:59:59",
      reference_date = as.Date(config$policy$reference_date),
      age_90_plus_value = config$policy$age_90_plus_value
    ),
    "1980"
  )
})


run_test("pipeline remains processed and non-releasable", {
  path <- write_fixture_workbook(synthetic_fixture())
  on.exit(unlink(path, force = TRUE), add = TRUE)
  dataset <- read_clinical_workbook(
    path,
    original_name = "synthetic.xlsx",
    config = config
  )
  run <- run_structured_deidentification(dataset, config)

  expect_identical(run$state, "PROCESSED")
  expect_true(run$validation$structured_passed)
  expect_false(run$validation$release_passed)
  expect_identical(nrow(run$blockers), 2L)
  expect_false(can_release(run))
})


run_test("safe preview never contains raw narrative text", {
  path <- write_fixture_workbook(synthetic_fixture())
  on.exit(unlink(path, force = TRUE), add = TRUE)
  dataset <- read_clinical_workbook(
    path,
    original_name = "synthetic.xlsx",
    config = config
  )
  run <- run_structured_deidentification(dataset, config)
  preview <- create_safe_preview(run, config)
  placeholder <- config$policy$narrative_preview_placeholder

  expect_true(all(preview$Diagnosis_Journey == placeholder))
  expect_true(all(preview$Treatment_History == placeholder))
  expect_true(all(is.na(preview$Patient_Name)))
  expect_true(all(is.na(preview$MRN)))
  expect_true(all(is.na(preview$Patient_ID)))
})


run_test("new input invalidates all downstream state", {
  path <- write_fixture_workbook(synthetic_fixture())
  on.exit(unlink(path, force = TRUE), add = TRUE)
  dataset <- read_clinical_workbook(
    path,
    original_name = "synthetic.xlsx",
    config = config
  )
  run <- run_structured_deidentification(dataset, config)
  invalidated <- invalidate_run(run, input_hash = "NEW_HASH")

  expect_identical(invalidated$state, "RECEIVED")
  expect_true(is.null(invalidated$result))
  expect_true(is.null(invalidated$validation))
  expect_true(is.null(invalidated$approval_binding))
  expect_identical(nrow(invalidated$blockers), 0L)
  expect_identical(invalidated$binding$input_hash, "NEW_HASH")
})


run_test("invalid state transitions are rejected", {
  run <- new_deid_run(config$hash)
  expect_deid_error(
    transition_run(run, "APPROVED"),
    "deid_workflow_error",
    "INVALID_STATE_TRANSITION"
  )
})


run_test("export is blocked and creates no file", {
  path <- write_fixture_workbook(synthetic_fixture())
  on.exit(unlink(path, force = TRUE), add = TRUE)
  dataset <- read_clinical_workbook(
    path,
    original_name = "synthetic.xlsx",
    config = config
  )
  run <- run_structured_deidentification(dataset, config)
  output_path <- tempfile(fileext = ".xlsx")

  expect_deid_error(
    write_release_workbook(run, output_path, config),
    "deid_export_not_approved",
    "EXPORT_NOT_APPROVED"
  )
  expect_false(file.exists(output_path))
})


run_test("supplied ten-row sample follows the structured contract", {
  sample_path <- file.path(
    project_root,
    "Clinical_PHI_Anonymization_Test_Data - Test_Data.csv"
  )
  if (!file.exists(sample_path)) {
    cat("[SKIP] supplied sample is intentionally excluded from the package tarball\n")
  } else {
    sample_data <- utils::read.csv(
      sample_path,
      stringsAsFactors = FALSE,
      check.names = FALSE
    )
    workbook <- write_fixture_workbook(sample_data)
    on.exit(unlink(workbook, force = TRUE), add = TRUE)
    dataset <- read_clinical_workbook(
      workbook,
      original_name = "supplied-synthetic-sample.xlsx",
      config = config
    )
    run <- run_structured_deidentification(dataset, config)

    expected_years <- c(
      "1980", "1985", "1975", "1990", "1968",
      "1988", "1972", "1982", "1965", "1979"
    )
    expect_identical(run$result$data$DOB, expected_years)
    expect_identical(nrow(run$result$data), 10L)
    expect_true(all(is.na(run$result$data$Record_No)))
    expect_true(all(is.na(run$result$data$Patient_Name)))
    expect_true(all(is.na(run$result$data$MRN)))
    expect_true(all(is.na(run$result$data$Patient_ID)))
    expect_identical(run$state, "PROCESSED")
    expect_false(can_release(run))
  }
})


cat("\n")
cat("Tests run:", test_count, "\n")
cat("Failures:", failure_count, "\n")

if (failure_count > 0L) {
  quit(status = 1L)
}

cat("All core milestone tests passed.\n")
