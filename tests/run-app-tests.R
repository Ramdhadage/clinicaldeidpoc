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

required <- c("shiny", "DT", "writexl")
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
  list(Clinical_Data = sample_data),
  workbook
)

file_input <- list(
  name = "synthetic.xlsx",
  size = unname(file.info(workbook)$size),
  type = "application/vnd.openxmlformats-officedocument.spreadsheetml.sheet",
  datapath = workbook
)

ui <- build_deid_ui(config)
server <- build_deid_server(config)
app <- shiny::shinyApp(ui = ui, server = server)
stopifnot(inherits(app, "shiny.appobj"))

shiny::testServer(
  server,
  {
    session$flushReact()
    session$setInputs(workbook = file_input)
    session$flushReact()
    stopifnot(identical(run_value()$state, "RECEIVED"))

    session$setInputs(
      confirm_synthetic = FALSE,
      process = 1
    )
    session$flushReact()

    stopifnot(identical(run_value()$state, "VALIDATION_FAILED"))
    stopifnot(is.null(run_value()$result))

    session$setInputs(
      confirm_synthetic = TRUE,
      process = 2
    )
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
stopifnot(!grepl("downloadHandler", source_text, fixed = TRUE))
stopifnot(!grepl("downloadButton", source_text, fixed = TRUE))
stopifnot(grepl("Synthetic tagged preview", source_text, fixed = TRUE))
stopifnot(grepl("not validated", source_text, fixed = TRUE))
stopifnot(grepl("Dates are displayed as [YYYY]", source_text, fixed = TRUE))
stopifnot(grepl("eight-character hexadecimal", source_text, fixed = TRUE))
stopifnot(grepl("held only in session memory", source_text, fixed = TRUE))
stopifnot(!grepl("Safe structured preview", source_text, fixed = TRUE))
stopifnot(!grepl("safe_preview", source_text, fixed = TRUE))
stopifnot(grepl("escape = TRUE", source_text, fixed = TRUE))

ui_text <- paste(as.character(build_deid_ui(config)), collapse = "\n")
stopifnot(grepl("Synthetic demonstration only", ui_text, fixed = TRUE))
stopifnot(grepl("alert alert-danger", ui_text, fixed = TRUE))
stopifnot(grepl("Download unavailable", ui_text, fixed = TRUE))
stopifnot(!grepl("shiny-download-link", ui_text, fixed = TRUE))

cat("All Shiny milestone tests passed.\n")
