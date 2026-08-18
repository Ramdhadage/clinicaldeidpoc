development_library <- Sys.getenv("DEID_LOCAL_LIBRARY", unset = "")
if (nzchar(development_library) && dir.exists(development_library)) {
  development_library <- normalizePath(
    development_library,
    winslash = "/",
    mustWork = TRUE
  )
} else {
  development_library <- character()
}

if (file.exists(file.path("R", "bootstrap.R"))) {
  .libPaths(c(development_library, .libPaths()))
  project_root <- "."
  source(file.path(project_root, "R", "bootstrap.R"))
  activate_local_development_library(project_root)
  load_deid_modules(project_root)
} else {
  check_libraries <- .libPaths()
  .libPaths(c(
    check_libraries[[1]],
    development_library,
    check_libraries[-1]
  ))
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
    Zip_Code = c("44101", "05910", NA),
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
internal_function_for_test <- function(name) {
  if (exists(name, mode = "function", inherits = TRUE)) {
    return(get(name, mode = "function", inherits = TRUE))
  }
  getFromNamespace(name, "clinicaldeidpoc")
}
redact_narrative_for_test <- internal_function_for_test(
  "redact_narrative_text"
)
generalize_dob_for_test <- internal_function_for_test("generalize_dob_value")
validate_config_for_test <- internal_function_for_test("validate_deid_config")
generate_tokens_for_test <- internal_function_for_test(
  "generate_run_scoped_hex_ids"
)
release_binding_is_current_for_test <- internal_function_for_test(
  "release_binding_is_current"
)
verify_release_workbook_for_test <- internal_function_for_test(
  "verify_release_workbook"
)
build_validation_summary_for_test <- internal_function_for_test(
  "build_validation_summary_sheet"
)


token_factory_from <- function(values) {
  index <- 0L
  force(values)
  function() {
    index <<- index + 1L
    if (index > length(values)) {
      stop("The synthetic token stream was exhausted.", call. = FALSE)
    }
    values[[index]]
  }
}


run_test("configuration matches the locked milestone", {
  expect_true(inherits(config, "DeidConfig"))
  expect_identical(config$schema$schema_version, "0.3.0")
  expect_identical(config$policy$policy_version, "0.5.0")
  expect_identical(config$schema$sheet_name, "Clinical_Data")
  expect_identical(config$runtime$mode, "synthetic_only")
  expect_false(config$runtime$release_enabled)
  expect_identical(
    config$policy$free_text_action,
    "deterministic_tagged_preview_only"
  )
  expect_true(config$policy$preview$enabled)
  expect_identical(config$policy$preview$tags$date, "[{year}]")
  expect_identical(
    config$policy$preview$structured_id$columns,
    c("Record_No", "MRN", "Patient_ID")
  )
  expect_identical(
    as.integer(config$policy$preview$structured_id$length),
    8L
  )
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
      "Patient_ID",
      "Zip_Code"
    )
  )
})


run_test("configuration rejects action drift", {
  drifted <- config
  drifted$schema$columns[[4]]$action <- "retain"
  expect_deid_error(
    validate_config_for_test(drifted),
    "deid_config_error",
    "INVALID_ACTION_CONFIGURATION"
  )

  token_drift <- config
  token_drift$policy$preview$structured_id$source_derived <- TRUE
  expect_deid_error(
    validate_config_for_test(token_drift),
    "deid_config_error",
    "INVALID_STRUCTURED_PREVIEW_ID_CONFIGURATION"
  )

  zip_drift <- config
  zip_drift$policy$preview$zip_code$eligible_three_digit_prefixes <- "44"
  expect_deid_error(
    validate_config_for_test(zip_drift),
    "deid_config_error",
    "INVALID_SAFE_HARBOR_ZIP_CONFIGURATION"
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


run_test("empty drawing containers are accepted but drawing objects fail", {
  expect_true(empty_drawing_container(
    '<xdr:wsDr xmlns:xdr="http://schemas.openxmlformats.org/drawingml/2006/spreadsheetDrawing"/>'
  ))
  expect_false(empty_drawing_container(
    '<xdr:wsDr><xdr:twoCellAnchor/></xdr:wsDr>'
  ))
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
  invalid_zip <- data
  invalid_zip$Zip_Code[[1]] <- "ZIP-44101"
  expect_deid_error(
    validate_clinical_schema(invalid_zip, config),
    "deid_invalid_schema",
    "INVALID_ZIP_CODE_TYPE"
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
  expect_identical(result$data$Zip_Code, c("000", "000", NA_character_))
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
    generalize_dob_for_test,
    character(1),
    reference_date = as.Date(config$policy$reference_date),
    age_90_plus_value = config$policy$age_90_plus_value
  )
  expect_identical(unname(actual), expected)
})


run_test("numeric and non-US postal values are generalized safely", {
  data <- synthetic_fixture()
  data$Zip_Code <- c("44101.0", "04410.0", "560001.0")
  validated <- validate_clinical_schema(data, config)
  result <- transform_structured_fields(validated, config)

  expect_identical(result$data$Zip_Code, c("000", "000", NA_character_))
})


run_test("two-digit DOB years never use R's implicit century cutoff", {
  generalize <- function(value) {
    generalize_dob_for_test(
      value,
      reference_date = as.Date(config$policy$reference_date),
      age_90_plus_value = config$policy$age_90_plus_value
    )
  }

  expect_identical(generalize("15-Dec-68"), "1968")
  expect_identical(generalize("15-Dec-69"), "1969")
  expect_deid_error(
    generalize("15-Dec-20"),
    "deid_invalid_date",
    "AMBIGUOUS_DOB_YEAR"
  )
})


run_test("impossible DOB clock times fail closed", {
  invalid_times <- c(
    "1980-12-15 24:00",
    "15-12-1980 99:99:99",
    "15-Dec-80 23:60"
  )

  for (value in invalid_times) {
    expect_deid_error(
      generalize_dob_for_test(
        value,
        reference_date = as.Date(config$policy$reference_date),
        age_90_plus_value = config$policy$age_90_plus_value
      ),
      "deid_invalid_date",
      "INVALID_DOB"
    )
  }

  expect_identical(
    generalize_dob_for_test(
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


run_test("tagged preview masks structured identifiers without mutating results", {
  path <- write_fixture_workbook(synthetic_fixture())
  on.exit(unlink(path, force = TRUE), add = TRUE)
  dataset <- read_clinical_workbook(
    path,
    original_name = "synthetic.xlsx",
    config = config
  )
  run <- run_structured_deidentification(dataset, config)
  result_before <- run$result$data
  source_before <- run$schema_validation$data
  preview <- create_tagged_preview(run, config)

  expect_true(all(preview$Patient_Name == "[Name]"))
  expect_identical(
    preview$DOB,
    c("[1980]", "[Age: 90 or older]", "[1936]")
  )
  id_columns <- c("Record_No", "MRN", "Patient_ID")
  id_values <- unlist(preview[id_columns], use.names = FALSE)
  tokens <- id_values[!is.na(id_values)]
  expect_true(all(grepl("^[0-9a-f]{8}$", tokens, perl = TRUE)))
  expect_identical(length(unique(tokens)), length(tokens))
  expect_identical(is.na(preview$MRN), c(FALSE, FALSE, TRUE))
  expect_identical(is.na(preview$Patient_ID), c(FALSE, FALSE, TRUE))
  expect_false(any(tokens %in% tolower(unlist(
    source_before[id_columns],
    use.names = FALSE
  ))))
  expect_identical(
    preview$Diagnosis_Journey,
    c(
      "[Name] was diagnosed with Stage II lymphoma.",
      "[Name] received a diagnosis.",
      "Brown discoloration was observed."
    )
  )
  expect_identical(
    preview$Treatment_History,
    c("Contact [Email].", "Dose 12.5 mg.", "Follow-up planned.")
  )
  expect_identical(run$result$data, result_before)
  expect_identical(run$schema_validation$data, source_before)
  expect_identical(create_tagged_preview(run, config), preview)
  expect_true(all(vapply(
    run$result$data[c(id_columns, "Patient_Name")],
    function(column) all(is.na(column)),
    logical(1)
  )))
  expect_false(any(grepl(
    "PENDING_TEXT_DEIDENTIFICATION",
    unlist(preview, use.names = FALSE),
    fixed = TRUE
  )))
})


run_test("structured preview tokens are unique and source independent", {
  data <- synthetic_fixture()
  data$Patient_Name[[1]] <- "deadbeef"
  data$MRN <- c("MRN-DUPLICATE", "MRN-DUPLICATE", NA_character_)
  first_path <- write_fixture_workbook(data)
  on.exit(unlink(first_path, force = TRUE), add = TRUE)
  first_dataset <- read_clinical_workbook(
    first_path,
    original_name = "synthetic.xlsx",
    config = config
  )
  expected <- sprintf("%08x", seq_len(7L))
  first_stream <- c("deadbeef", expected[[1]], expected[[1]], expected[-1])
  first_run <- run_structured_deidentification(
    first_dataset,
    config,
    preview_token_factory = token_factory_from(first_stream)
  )
  first_tokens <- unlist(first_run$preview_tokens$values, use.names = FALSE)
  first_tokens <- first_tokens[!is.na(first_tokens)]
  expect_identical(first_tokens, expected)
  expect_identical(length(unique(first_tokens)), 7L)

  changed <- data
  changed$Record_No <- c("101", "102", "103")
  changed$Patient_Name <- c("Changed One", "Changed Two", "Changed Three")
  changed$MRN <- c("CHANGED-A", "CHANGED-B", NA_character_)
  changed$Patient_ID <- c("OTHER-A", "OTHER-B", NA_character_)
  changed_path <- write_fixture_workbook(changed)
  on.exit(unlink(changed_path, force = TRUE), add = TRUE)
  changed_dataset <- read_clinical_workbook(
    changed_path,
    original_name = "changed-synthetic.xlsx",
    config = config
  )
  changed_run <- run_structured_deidentification(
    changed_dataset,
    config,
    preview_token_factory = token_factory_from(expected)
  )
  changed_tokens <- unlist(
    changed_run$preview_tokens$values,
    use.names = FALSE
  )
  changed_tokens <- changed_tokens[!is.na(changed_tokens)]
  expect_identical(changed_tokens, expected)

  next_expected <- sprintf("%08x", seq.int(101L, 107L))
  next_run <- run_structured_deidentification(
    first_dataset,
    config,
    preview_token_factory = token_factory_from(next_expected)
  )
  next_tokens <- unlist(next_run$preview_tokens$values, use.names = FALSE)
  next_tokens <- next_tokens[!is.na(next_tokens)]
  expect_identical(next_tokens, next_expected)
  expect_false(identical(first_tokens, next_tokens))
  expect_true(all(vapply(
    first_run$result$data[c("Record_No", "MRN", "Patient_ID")],
    function(column) all(is.na(column)),
    logical(1)
  )))
})


run_test("structured preview token collisions and tampering fail closed", {
  collision_factory <- function() "deadbeef"
  expect_deid_error(
    generate_tokens_for_test(
      count = 2L,
      token_factory = collision_factory,
      max_attempts = 2L
    ),
    "deid_preview_error",
    "PREVIEW_TOKEN_GENERATION_FAILED"
  )
  expect_identical(
    generate_tokens_for_test(
      count = 1L,
      deny_values = "deadbeef",
      token_factory = token_factory_from(c("deadbeef", "cafebabe"))
    ),
    "cafebabe"
  )

  data <- synthetic_fixture()
  data$Patient_Name[[1]] <- "deadbeef"
  path <- write_fixture_workbook(data)
  on.exit(unlink(path, force = TRUE), add = TRUE)
  dataset <- read_clinical_workbook(
    path,
    original_name = "synthetic.xlsx",
    config = config
  )
  run <- run_structured_deidentification(
    dataset,
    config,
    preview_token_factory = token_factory_from(sprintf("%08x", 1:7))
  )
  tampered <- run
  tampered$preview_tokens$values$MRN[[1]] <-
    tampered$preview_tokens$values$Record_No[[1]]
  expect_deid_error(
    create_tagged_preview(tampered, config),
    "deid_preview_error",
    "INVALID_PREVIEW_TOKEN_BUNDLE"
  )

  source_conflict <- run
  source_conflict$preview_tokens$values$Record_No[[1]] <- "deadbeef"
  expect_deid_error(
    create_tagged_preview(source_conflict, config),
    "deid_preview_error",
    "INVALID_PREVIEW_TOKEN_BUNDLE"
  )

  missing <- run
  missing$preview_tokens <- NULL
  expect_deid_error(
    create_tagged_preview(missing, config),
    "deid_preview_error",
    "INVALID_PREVIEW_TOKEN_BUNDLE"
  )
})


run_test("deterministic preview tags requested identifier examples", {
  text <- paste(
    "Rashad contacted john.smith@email.com from 192.168.1.100",
    "on 15-Dec-2015. See https://hospital.example.com/patient/12345.",
    "Fax: 617-555-0142. SSN 123-45-6789. Age 90."
  )
  redacted <- redact_narrative_for_test(
    text,
    known_name = "Rashad",
    config = config
  )

  required_tags <- c(
    "[Name]",
    "[Email]",
    "[IP Address]",
    "[2015]",
    "[URL]",
    "[Fax Number]",
    "[SSN]",
    "[Age: 90 or older]"
  )
  expect_true(all(vapply(
    required_tags,
    grepl,
    logical(1),
    x = redacted,
    fixed = TRUE
  )))
  raw_identifiers <- c(
    "Rashad",
    "john.smith@email.com",
    "192.168.1.100",
    "15-Dec-2015",
    "https://hospital.example.com/patient/12345",
    "617-555-0142",
    "123-45-6789"
  )
  expect_false(any(vapply(
    raw_identifiers,
    grepl,
    logical(1),
    x = redacted,
    fixed = TRUE
  )))
  expect_identical(
    redact_narrative_for_test(
      "https://192.168.1.100/u/rashad@example.com",
      known_name = "Rashad",
      config = config
    ),
    "[URL]"
  )
  expect_identical(
    redact_narrative_for_test(
      "Brown discoloration; Dose 12.5 mg; BP 120/80; May improve.",
      known_name = "Will Brown",
      config = config
    ),
    "Brown discoloration; Dose 12.5 mg; BP 120/80; May improve."
  )
  expect_identical(
    redact_narrative_for_test(
      "Seen on December 15th, 2015 and 15-December-2015.",
      config = config
    ),
    "Seen on [2015] and [2015]."
  )

  contextual_examples <- c(
    "Member ID: PLAN-12345." = "[Health Plan Beneficiary Number]",
    "Account number was ACCT-98765." = "[Account Number]",
    "License number: DL-12345." = "[Certificate/License Number]",
    "VIN: 1HGCM82633A004352." = "[Vehicle Identifier]",
    "Device serial: DEV-12345." = "[Device Identifier]",
    "Patient ID: PT-001-ABC." = "[Other Unique Identifier]",
    "Biometric template: BIO-12345." = "[Biometric Identifier]",
    "Call 216-555-0188." = "[Telephone Number]",
    "ZIP 44101." = "ZIP 000."
  )
  for (example in names(contextual_examples)) {
    tagged <- redact_narrative_for_test(example, config = config)
    expect_true(grepl(
      contextual_examples[[example]],
      tagged,
      fixed = TRUE
    ))
  }

  expect_identical(
    redact_narrative_for_test(
      "DOB 15-Dec-1930. A 90-year-old patient.",
      config = config
    ),
    "[Age: 90 or older]. A [Age: 90 or older] patient."
  )
  expect_identical(
    redact_narrative_for_test("DOB 15-Dec-2015.", config = config),
    "[2015]."
  )
  birth_context_examples <- c(
    "DOB was 15-Dec-1930." = "[Age: 90 or older].",
    "Date of birth is December 15, 1930." = "[Age: 90 or older].",
    "DOB December 1930." = "[Age: 90 or older].",
    "Born in 1930." = "[Age: 90 or older].",
    "Birth date: 15-Dec-1930." = "[Age: 90 or older].",
    "Birthdate 15-Dec-1930." = "[Age: 90 or older].",
    "Year of birth: 1930." = "[Age: 90 or older].",
    "Aged 90 years old." = "[Age: 90 or older].",
    "Age is 90." = "[Age: 90 or older].",
    "Age was 91." = "[Age: 90 or older].",
    "A 90 yrs old patient." = "A [Age: 90 or older] patient.",
    "A 90 years of age patient." = "A [Age: 90 or older] patient.",
    "A 90 y.o. patient." = "A [Age: 90 or older] patient."
  )
  for (example in names(birth_context_examples)) {
    expect_identical(
      redact_narrative_for_test(example, config = config),
      birth_context_examples[[example]]
    )
  }
  expect_identical(
    redact_narrative_for_test("Fax: (216) 555-0188.", config = config),
    "[Fax Number]."
  )
  expect_identical(
    redact_narrative_for_test(
      "Phone: +1 (216) 555-0188 ext 42.",
      config = config
    ),
    "Phone: [Telephone Number]."
  )
  expect_identical(
    redact_narrative_for_test("Call 9876543210.", config = config),
    "Call [Telephone Number]."
  )
  phone_examples <- c(
    "Call 1-216-555-0188." = "Call [Telephone Number].",
    "Fax: 1-216-555-0188." = "[Fax Number].",
    "Call +44 20 7946 0958." = "Call [Telephone Number].",
    "Call +61 2 9374 4000." = "Call [Telephone Number].",
    "Call 216-555-0188 #42." = "Call [Telephone Number]."
  )
  for (example in names(phone_examples)) {
    expect_identical(
      redact_narrative_for_test(example, config = config),
      phone_examples[[example]]
    )
  }
})


run_test("tagged preview scans known identifiers across rows", {
  data <- synthetic_fixture()[1:2, , drop = FALSE]
  data$Patient_Name[[2]] <- "Maria Garcia"
  data$Diagnosis_Journey[[1]] <- paste(
    "Referral from Maria Garcia,",
    "MRN-22222222, SUBJ-002."
  )
  path <- write_fixture_workbook(data)
  on.exit(unlink(path, force = TRUE), add = TRUE)
  dataset <- read_clinical_workbook(
    path,
    original_name = "synthetic.xlsx",
    config = config
  )
  run <- run_structured_deidentification(dataset, config)
  preview <- create_tagged_preview(run, config)

  expect_identical(
    preview$Diagnosis_Journey[[1]],
    paste(
      "Referral from [Name],",
      "[Medical Record Number], [Other Unique Identifier]."
    )
  )
  expect_false(grepl(
    "Maria Garcia|MRN-22222222|SUBJ-002",
    preview$Diagnosis_Journey[[1]],
    perl = TRUE
  ))
})


run_test("tagged preview fails closed for a redaction error", {
  data <- synthetic_fixture()[1, , drop = FALSE]
  data$Diagnosis_Journey <- "Impossible date 31-Feb-1980."
  data$Treatment_History <- "Reserved __DEID_PREVIEW_TAG_ marker."
  path <- write_fixture_workbook(data)
  on.exit(unlink(path, force = TRUE), add = TRUE)
  dataset <- read_clinical_workbook(
    path,
    original_name = "synthetic.xlsx",
    config = config
  )
  run <- run_structured_deidentification(dataset, config)
  preview <- create_tagged_preview(run, config)

  expect_identical(
    preview$Diagnosis_Journey,
    config$policy$preview$failure_placeholder
  )
  expect_identical(
    preview$Treatment_History,
    config$policy$preview$failure_placeholder
  )
  expect_false(can_release(run))
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
  expect_true(is.null(invalidated$preview_tokens))
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


run_test("ZIP preview applies the conditional three-digit exception", {
  allowed_config <- config
  allowed_config$policy$preview$zip_code$eligible_three_digit_prefixes <- "441"
  validate_config_for_test(allowed_config)

  expect_identical(
    redact_narrative_for_test("ZIP 44101 and 05910.", config = allowed_config),
    "ZIP 441 and 000."
  )
  expect_identical(
    redact_narrative_for_test("ZIP 44101.", config = config),
    "ZIP 000."
  )
  expect_identical(
    redact_narrative_for_test("ZIP 44101-1234.", config = allowed_config),
    "ZIP 441."
  )
})


run_test("release binding detects output changes after approval", {
  path <- write_fixture_workbook(synthetic_fixture())
  on.exit(unlink(path, force = TRUE), add = TRUE)
  dataset <- read_clinical_workbook(
    path,
    original_name = "synthetic.xlsx",
    config = config
  )
  run <- run_structured_deidentification(dataset, config)
  run$approval_binding <- run$binding

  expect_true(release_binding_is_current_for_test(run))

  tampered <- run
  tampered$result$data$Diagnosis_Journey[[1]] <- "Changed after approval"
  expect_false(release_binding_is_current_for_test(tampered))
})


run_test("release verification accepts an exact workbook", {
  path <- write_fixture_workbook(synthetic_fixture())
  on.exit(unlink(path, force = TRUE), add = TRUE)
  dataset <- read_clinical_workbook(
    path,
    original_name = "synthetic.xlsx",
    config = config
  )
  run <- run_structured_deidentification(dataset, config)
  summary <- build_validation_summary_for_test(run, config)
  candidate <- tempfile(fileext = ".xlsx")
  on.exit(unlink(candidate, force = TRUE), add = TRUE)
  writexl::write_xlsx(
    list(
      Clinical_Data = run$result$data,
      Validation_Summary = summary
    ),
    candidate
  )

  expect_identical(
    verify_release_workbook_for_test(
      candidate,
      run$result$data,
      summary
    ),
    TRUE
  )
})


run_test("release verification compares every exported data cell", {
  path <- write_fixture_workbook(synthetic_fixture())
  on.exit(unlink(path, force = TRUE), add = TRUE)
  dataset <- read_clinical_workbook(
    path,
    original_name = "synthetic.xlsx",
    config = config
  )
  run <- run_structured_deidentification(dataset, config)
  summary <- build_validation_summary_for_test(run, config)

  tampered_data <- run$result$data
  tampered_data$Diagnosis_Journey[[1]] <- "Same shape, different content"
  candidate <- tempfile(fileext = ".xlsx")
  on.exit(unlink(candidate, force = TRUE), add = TRUE)
  writexl::write_xlsx(
    list(
      Clinical_Data = tampered_data,
      Validation_Summary = summary
    ),
    candidate
  )

  expect_deid_error(
    verify_release_workbook_for_test(
      candidate,
      run$result$data,
      summary
    ),
    "deid_export_error",
    "OUTPUT_VERIFICATION_FAILED"
  )
})


run_test("release verification compares the validation summary", {
  path <- write_fixture_workbook(synthetic_fixture())
  on.exit(unlink(path, force = TRUE), add = TRUE)
  dataset <- read_clinical_workbook(
    path,
    original_name = "synthetic.xlsx",
    config = config
  )
  run <- run_structured_deidentification(dataset, config)
  summary <- build_validation_summary_for_test(run, config)
  tampered_summary <- summary
  tampered_summary$value[tampered_summary$metric == "output_hash"] <-
    paste(rep("0", 64L), collapse = "")

  candidate <- tempfile(fileext = ".xlsx")
  on.exit(unlink(candidate, force = TRUE), add = TRUE)
  writexl::write_xlsx(
    list(
      Clinical_Data = run$result$data,
      Validation_Summary = tampered_summary
    ),
    candidate
  )

  expect_deid_error(
    verify_release_workbook_for_test(
      candidate,
      run$result$data,
      summary
    ),
    "deid_export_error",
    "OUTPUT_VERIFICATION_FAILED"
  )
})


run_test("forged approval cannot bypass the milestone export gate", {
  path <- write_fixture_workbook(synthetic_fixture())
  on.exit(unlink(path, force = TRUE), add = TRUE)
  dataset <- read_clinical_workbook(
    path,
    original_name = "synthetic.xlsx",
    config = config
  )
  forged <- run_structured_deidentification(dataset, config)
  forged$state <- "APPROVED"
  forged$validation$release_passed <- TRUE
  forged$blockers <- forged$blockers[0, , drop = FALSE]
  forged$approval_binding <- forged$binding

  expect_false(can_release(forged, config))

  future_config <- config
  future_config$runtime$release_enabled <- TRUE
  forged$validation$tagged_preview_only <- FALSE
  forged$validation$narrative_redaction_validated <- TRUE
  expect_false(can_release(forged, future_config))

  output_path <- tempfile(fileext = ".xlsx")
  expect_deid_error(
    write_release_workbook(forged, output_path, config),
    "deid_export_not_approved",
    "EXPORT_NOT_APPROVED"
  )
  expect_false(file.exists(output_path))
})


cat("\n")
cat("Tests run:", test_count, "\n")
cat("Failures:", failure_count, "\n")

if (failure_count > 0L) {
  quit(status = 1L)
}

cat("All core milestone tests passed.\n")
