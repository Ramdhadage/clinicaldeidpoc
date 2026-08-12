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

required <- c("shiny", "DT", "writexl")
for (package in required) {
  if (!requireNamespace(package, quietly = TRUE)) {
    stop(paste0("Package ", package, " is required for app tests."), call. = FALSE)
  }
}

config <- read_deid_config(project_root)
sample_data <- data.frame(
  Record_No = c("1", "2"),
  Patient_Name = c("Synthetic One", "Synthetic Two"),
  DOB = c("1980-12-15", "13/01/1975"),
  Diagnosis_Journey = c("Synthetic narrative one.", "Synthetic narrative two."),
  Treatment_History = c("Synthetic treatment one.", "Synthetic treatment two."),
  MRN = c("SYN-MRN-001", "SYN-MRN-002"),
  Patient_ID = c("SYN-001", "SYN-002"),
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

    preview <- create_safe_preview(processed, config)
    placeholder <- config$policy$narrative_preview_placeholder
    stopifnot(all(preview$Diagnosis_Journey == placeholder))
    stopifnot(all(preview$Treatment_History == placeholder))

    replacement_input <- file_input
    replacement_input$name <- "replacement-synthetic.xlsx"
    session$setInputs(workbook = replacement_input)
    session$flushReact()

    invalidated <- run_value()
    stopifnot(identical(invalidated$state, "RECEIVED"))
    stopifnot(is.null(invalidated$result))
    stopifnot(is.null(invalidated$validation))
  }
)

source_text <- paste(
  readLines(file.path(project_root, "R", "shiny_app.R"), warn = FALSE),
  collapse = "\n"
)
stopifnot(!grepl("downloadHandler", source_text, fixed = TRUE))
stopifnot(!grepl("downloadButton", source_text, fixed = TRUE))

cat("All Shiny milestone tests passed.\n")
