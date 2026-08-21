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

required <- c("bslib", "cli", "shiny", "DT", "writexl")
for (package in required) {
  if (!requireNamespace(package, quietly = TRUE)) {
    stop(paste0("Package ", package, " is required for app tests."), call. = FALSE)
  }
}

config <- read_deid_config(project_root)
sample_data <- data.frame(
  Record_No = c("1", "2"),
  Patient_Name = c("Rashad", "Synthetic Two"),
  DOB = c("1980-12-15", "13/01/1975"),
  Diagnosis_Journey = c(
    "Rashad contacted john.smith@email.com from 192.168.1.100.",
    "Synthetic narrative two."
  ),
  Treatment_History = c(
    "See https://hospital.example.com/patient/12345 on 15-Dec-2015.",
    "Synthetic treatment two."
  ),
  MRN = c("SYN-MRN-001", "SYN-MRN-002"),
  Patient_ID = c("SYN-001", "SYN-002"),
  Zip_Code = c("44101", "05910"),
  stringsAsFactors = FALSE,
  check.names = FALSE
)
workbook <- tempfile(fileext = ".xlsx")
on.exit(unlink(workbook, force = TRUE), add = TRUE)
writexl::write_xlsx(
  list(
    Clinical_Data = sample_data,
    Alternative_Clinical_Data = sample_data,
    Wrong_Schema = data.frame(
      Record_No = "1",
      Patient_Name = "Synthetic",
      stringsAsFactors = FALSE,
      check.names = FALSE
    )
  ),
  workbook
)

file_input <- list(
  name = "synthetic.xlsx",
  size = unname(file.info(workbook)$size),
  type = "application/vnd.openxmlformats-officedocument.spreadsheetml.sheet",
  datapath = workbook
)

ui <- build_deid_ui(config, "default-synthetic.xlsx")
server <- build_deid_server(config, workbook)
app <- shiny::shinyApp(ui = ui, server = server)
stopifnot(inherits(app, "shiny.appobj"))

shiny::testServer(
  server,
  {
    session$setInputs(data_source = "default")
    session$flushReact()
    default_run <- run_value()
    stopifnot(identical(default_run$state, "PROCESSED"))
    stopifnot(is.null(error_value()))
    stopifnot(identical(active_workbook()$source, "default"))

    download_ui <- paste(
      as.character(output$synthetic_preview_download),
      collapse = "\n"
    )
    download_icons <- gregexpr("fa-download", download_ui, fixed = TRUE)[[1]]
    stopifnot(sum(download_icons > 0L) == 1L)

    session$setInputs(data_source = "upload")
    session$flushReact()
    stopifnot(identical(run_value()$state, "RECEIVED"))

    session$setInputs(workbook = file_input)
    session$flushReact()
    stopifnot(identical(run_value()$state, "RECEIVED"))

    session$setInputs(worksheet = "Alternative_Clinical_Data")
    session$flushReact()

    session$setInputs(process = 1)
    session$flushReact()

    processed <- run_value()
    stopifnot(identical(processed$state, "PROCESSED"))
    stopifnot(is.null(error_value()))
    stopifnot(!can_release(processed))
    stopifnot(!processed$validation$release_passed)
    stopifnot(all(processed$blockers$severity == "Critical"))
    stopifnot(all(
      processed$blockers$code == "NARRATIVE_REDACTION_NOT_VALIDATED"
    ))

    result_before <- processed$result$data
    preview <- create_tagged_preview(processed, config)
    details <- build_deterministic_detection_table(preview, config)
    stopifnot(identical(
      preview$Diagnosis_Journey[[1]],
      "[Name] contacted [Email] from [IP Address]."
    ))
    stopifnot(identical(
      preview$Treatment_History[[1]],
      "See [URL] on [2015]."
    ))
    stopifnot(identical(preview$Patient_Name[[1]], "[Name]"))
    stopifnot(identical(preview$DOB[[1]], "[1980]"))
    stopifnot(identical(
      names(details),
      c(
        "document_id",
        "detected_entities",
        "offsets",
        "confidence_scores",
        "redacted_text"
      )
    ))
    id_columns <- c("Record_No", "MRN", "Patient_ID")
    preview_ids <- unlist(preview[id_columns], use.names = FALSE)
    stopifnot(all(grepl("^[0-9a-f]{8}$", preview_ids, perl = TRUE)))
    stopifnot(length(unique(preview_ids)) == length(preview_ids))
    stopifnot(identical(
      create_tagged_preview(processed, config),
      preview
    ))
    stopifnot(identical(processed$result$data, result_before))
    stopifnot(all(vapply(
      processed$result$data[c(id_columns, "Patient_Name")],
      function(column) all(is.na(column)),
      logical(1)
    )))
    stopifnot(!grepl(
      "john.smith@email.com",
      paste(unlist(preview, use.names = FALSE), collapse = "\n"),
      fixed = TRUE
    ))

    session$setInputs(worksheet = "Wrong_Schema")
    session$flushReact()

    validation_feedback <- paste(
      as.character(output$workbook_validation),
      collapse = "\n"
    )
    stopifnot(grepl(
      "does not match the approved column contract",
      validation_feedback,
      fixed = TRUE
    ))
    stopifnot(grepl(
      "alert alert-danger",
      validation_feedback,
      fixed = TRUE
    ))

    session$setInputs(process = 2)
    session$flushReact()

    invalid_selection <- run_value()
    stopifnot(identical(invalid_selection$state, "VALIDATION_FAILED"))
    stopifnot(is.null(invalid_selection$result))
    stopifnot(identical(
      invalid_selection$failure$code,
      "WORKBOOK_VALIDATION_FAILED"
    ))

    replacement_input <- file_input
    replacement_input$name <- "replacement-synthetic.xlsx"
    session$setInputs(workbook = replacement_input)
    session$flushReact()

    invalidated <- run_value()
    stopifnot(identical(invalidated$state, "RECEIVED"))
    stopifnot(is.null(invalidated$result))
    stopifnot(is.null(invalidated$preview_tokens))
    stopifnot(is.null(invalidated$validation))
  }
)

source_text <- paste(
  readLines(file.path(project_root, "R", "shiny_app.R"), warn = FALSE),
  collapse = "\n"
)
stopifnot(grepl("downloadHandler", source_text, fixed = TRUE))
stopifnot(grepl("downloadButton", source_text, fixed = TRUE))
stopifnot(grepl("download_synthetic_preview", source_text, fixed = TRUE))
stopifnot(grepl("not releasable", source_text, fixed = TRUE))
stopifnot(grepl("synthetic tagged preview", source_text, fixed = TRUE))
stopifnot(grepl("not validated", source_text, fixed = TRUE))
stopifnot(grepl("Dates are displayed as [YYYY]", source_text, fixed = TRUE))
stopifnot(grepl("eight-character hexadecimal", source_text, fixed = TRUE))
stopifnot(grepl("detection_details", source_text, fixed = TRUE))
stopifnot(grepl("deterministic preview only", source_text, fixed = TRUE))
stopifnot(grepl("Azure is not called", source_text, fixed = TRUE))
stopifnot(grepl("held only in session memory", source_text, fixed = TRUE))
stopifnot(grepl("shinyvalidate", source_text, fixed = TRUE))
stopifnot(grepl("worksheet", source_text, fixed = TRUE))
stopifnot(grepl("bslib::page_sidebar", source_text, fixed = TRUE))
stopifnot(grepl("bslib::bs_theme", source_text, fixed = TRUE))
stopifnot(grepl("bslib::card", source_text, fixed = TRUE))
stopifnot(grepl("bslib::accordion", source_text, fixed = TRUE))
stopifnot(grepl("bslib::input_task_button", source_text, fixed = TRUE))
stopifnot(grepl("bslib::tooltip", source_text, fixed = TRUE))
stopifnot(grepl('`aria-label` = "Generate tagged preview"', source_text, fixed = TRUE))
stopifnot(grepl("not anonymized and not releasable", source_text, fixed = TRUE))
stopifnot(grepl("Anonymized data table", source_text, fixed = TRUE))
stopifnot(grepl("Synthetic preview only - not validated", source_text, fixed = TRUE))
stopifnot(grepl("bslib::navset_pill", source_text, fixed = TRUE))
stopifnot(grepl("bslib::nav_panel", source_text, fixed = TRUE))
stopifnot(grepl("Default clinical data", source_text, fixed = TRUE))
stopifnot(grepl("Upload XLSX workbook", source_text, fixed = TRUE))
stopifnot(grepl('value = "default"', source_text, fixed = TRUE))
stopifnot(grepl('value = "upload"', source_text, fixed = TRUE))
stopifnot(!grepl("shiny::radioButtons", source_text, fixed = TRUE))
stopifnot(!grepl("shiny::conditionalPanel", source_text, fixed = TRUE))
stopifnot(grepl("label = NULL", source_text, fixed = TRUE))
stopifnot(!grepl("Preview generated for synthetic evaluation", source_text, fixed = TRUE))
stopifnot(!grepl("Run state: ", source_text, fixed = TRUE))
stopifnot(grepl("processing_error", source_text, fixed = TRUE))
stopifnot(grepl("Processing failed: ", source_text, fixed = TRUE))
stopifnot(grepl("shiny::updateSelectInput", source_text, fixed = TRUE))
stopifnot(!grepl("output$worksheet_selector", source_text, fixed = TRUE))
stopifnot(!grepl("shiny::fluidPage", source_text, fixed = TRUE))
stopifnot(!grepl("shiny::sidebarLayout", source_text, fixed = TRUE))
stopifnot(!grepl("shiny::sidebarPanel", source_text, fixed = TRUE))
stopifnot(grepl("workbook_validation_feedback", source_text, fixed = TRUE))
stopifnot(!grepl("Safe structured preview", source_text, fixed = TRUE))
stopifnot(!grepl("safe_preview", source_text, fixed = TRUE))
stopifnot(grepl("escape = TRUE", source_text, fixed = TRUE))

ui_text <- paste(as.character(build_deid_ui(config)), collapse = "\n")
stopifnot(grepl("Synthetic demonstration only", ui_text, fixed = TRUE))
stopifnot(grepl(
  "alert alert-warning alert-dismissible fade show",
  ui_text,
  fixed = TRUE
))
stopifnot(grepl('data-bs-dismiss="alert"', ui_text, fixed = TRUE))
stopifnot(grepl(
  'aria-label="Close synthetic demonstration warning"',
  ui_text,
  fixed = TRUE
))
dismiss_controls <- gregexpr('data-bs-dismiss="alert"', ui_text, fixed = TRUE)[[1]]
stopifnot(sum(dismiss_controls > 0L) == 1L)
stopifnot(grepl("bslib-page-dashboard", ui_text, fixed = TRUE))
stopifnot(grepl('id="worksheet"', ui_text, fixed = TRUE))
stopifnot(grepl('id="data_source"', ui_text, fixed = TRUE))
stopifnot(grepl('data-value="default"', ui_text, fixed = TRUE))
stopifnot(grepl('data-value="upload"', ui_text, fixed = TRUE))
stopifnot(grepl("Clinical_PHI_Anonymization_Data.xlsx", ui_text, fixed = TRUE))
stopifnot(grepl("Release unavailable", ui_text, fixed = TRUE))
stopifnot(!grepl("shiny-download-link", ui_text, fixed = TRUE))
stopifnot(
  regexpr("Synthetic demonstration only", ui_text, fixed = TRUE) <
    regexpr("bslib-page-dashboard", ui_text, fixed = TRUE)
)
stopifnot(
  regexpr("Anonymized data table", ui_text, fixed = TRUE) <
    regexpr("Approved column contract", ui_text, fixed = TRUE)
)
stopifnot(
  regexpr('id="synthetic_preview_download"', ui_text, fixed = TRUE) <
    regexpr('id="tagged_preview"', ui_text, fixed = TRUE)
)

cli::cli_alert_success("All Shiny milestone tests passed.")
