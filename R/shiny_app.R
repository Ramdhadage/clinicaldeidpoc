.build_deid_theme <- function() {
  bslib::bs_theme(
    version = 5,
    preset = "shiny",
    bg = "#ffffff",
    fg = "#24313d",
    primary = "#176b75",
    secondary = "#526777",
    success = "#287a4b",
    info = "#176b75",
    warning = "#a15c00",
    danger = "#b42318",
    base_font = bslib::font_collection(
      "Segoe UI Variable",
      "Segoe UI",
      "Arial",
      "sans-serif"
    ),
    heading_font = bslib::font_collection(
      "Segoe UI Variable Display",
      "Segoe UI",
      "Arial",
      "sans-serif"
    ),
    "border-radius" = "0.625rem",
    "card-border-radius" = "0.875rem",
    "card-cap-bg" = "transparent",
    "input-border-radius" = "0.5rem",
    "btn-border-radius" = "0.5rem"
  )
}


.build_deid_alert <- function(
    type,
    title,
    ...,
    id = NULL,
    live = NULL,
    dismissible = FALSE,
    close_label = "Close"
) {
  alert_classes <- c(
    "alert",
    paste0("alert-", type),
    if (dismissible) c("alert-dismissible", "fade", "show"),
    "mb-0"
  )

  shiny::div(
    id = id,
    class = paste(alert_classes, collapse = " "),
    role = "alert",
    `aria-live` = live,
    shiny::strong(title),
    ...,
    if (dismissible) {
      shiny::tags$button(
        type = "button",
        class = "btn-close",
        `data-bs-dismiss` = "alert",
        `aria-label` = close_label
      )
    }
  )
}


build_deid_ui <- function(
    config,
    default_workbook_name = "Clinical_PHI_Anonymization_Data.xlsx"
) {
  force(config)
  force(default_workbook_name)

  page <- bslib::page_sidebar(
    title = shiny::tagList(
      "Clinical Data De-identification PoC",
      shiny::span(
        class = "badge text-bg-danger ms-2 align-middle",
        "Synthetic only"
      )
    ),
    theme = .build_deid_theme(),
    class = "bslib-page-dashboard",
    fillable = FALSE,
    sidebar = bslib::sidebar(
      title = "Preview controls",
      width = "22rem",
      open = "always",
      bslib::navset_pill(
        id = "data_source",
        selected = "default",
        bslib::nav_panel(
          "Default clinical data",
          value = "default",
          .build_deid_alert(
            "info",
            "Default workbook: ",
            default_workbook_name
          )
        ),
        bslib::nav_panel(
          "Upload XLSX workbook",
          value = "upload",
          shiny::fileInput(
            "workbook",
            "Choose an XLSX workbook",
            accept = ".xlsx"
          ),
          shiny::selectInput(
            "worksheet",
            "Worksheet to process",
            choices = character(),
            selectize = FALSE
          ),
          shiny::p(
        class = "small text-secondary",
        shiny::strong("Worksheet selection: "),
        "Choose a worksheet after upload. It must match the approved column contract."
      ),
        )
      ),
      shiny::uiOutput("workbook_validation"),
      bslib::tooltip(
        bslib::input_task_button(
          "process",
          shiny::icon("play", verify_fa = FALSE),
          class = "btn-primary w-100",
          `aria-label` = "Generate tagged preview"
        ),
        "Generate tagged preview"
      ),
      shiny::hr(),
      shiny::p(
        class = "small mb-0",
        shiny::strong("Release enabled: "),
        shiny::span(class = "badge text-bg-danger", "No")
      )
    ),
    shiny::uiOutput("processing_error"),
    bslib::card(
      full_screen = TRUE,
      bslib::card_header(
        class = "d-flex align-items-center gap-2",
        shiny::span(
          class = "fw-semibold",
          "Anonymized data table"
        ),
        shiny::span(
          class = "badge text-bg-warning",
          "Synthetic preview only - not validated"
        ),
        shiny::span(
          class = "ms-auto",
          shiny::uiOutput("synthetic_preview_download", inline = TRUE)
        )
      ),
      bslib::card_body(
        fillable = FALSE,
        DT::DTOutput("tagged_preview"),
        bslib::accordion(
          class = "mt-3",
          open = FALSE,
          bslib::accordion_panel(
            "Preview limitations and tag behavior",
            shiny::p(
              "Dates are displayed as [YYYY], and patient names use [Name].",
              paste(
                "Each nonmissing Record_No, MRN, and Patient_ID cell uses an",
                "independent random eight-character hexadecimal preview token."
              )
            ),
            shiny::p(
              paste(
                "Tokens are generated independently of source values, remain stable",
                "only within this run, and are held only in session memory."
              ),
              "Undetected text is shown and may still contain identifiers.",
              "Use synthetic data only; this is not a HIPAA Safe Harbor determination."
            ),
            shiny::p(
              paste(
                "The run guide displays a 20-row coverage matrix mapped to the 18",
                "HIPAA Safe Harbor identifier types. This preview attempts only",
                "the deterministic subsets listed there, including known names",
                "and identifiers, dates, contact details, labeled codes, addresses,",
                "ZIP codes, facilities, and network identifiers."
              )
            ),
            shiny::p(
              class = "mb-0",
              paste(
                "Arbitrary names and locations, image or biometric content, and",
                "other unique characteristics still require Azure/NER, residual",
                "validation, and human review."
              )
            )
          )
        )
      )
    ),
    bslib::card(
      full_screen = TRUE,
      bslib::card_header(
        class = "fw-semibold",
        "Approved column contract"
      ),
      bslib::card_body(
        fillable = FALSE,
        DT::DTOutput("classification")
      )
    ),
    bslib::card(
      full_screen = TRUE,
      bslib::card_header(
        class = "fw-semibold",
        "Detection details - deterministic preview only"
      ),
      bslib::card_body(
        fillable = FALSE,
        .build_deid_alert(
          "info",
          "Azure is not called in this PoC. ",
          paste(
            "Detected entities and offsets below describe local preview tags",
            "in the redacted preview text. Confidence scores are rule-based,",
            "not Azure confidence scores."
          )
        ),
        shiny::div(class = "mt-3", DT::DTOutput("detection_details"))
      )
    ),
    bslib::card(
      full_screen = TRUE,
      bslib::card_header(
        class = "fw-semibold",
        "Critical validation blockers"
      ),
      bslib::card_body(
        fillable = FALSE,
        DT::DTOutput("blockers"),
        .build_deid_alert(
          "warning",
          "Release unavailable. ",
          paste(
            "No anonymized output can be released because Azure PII processing, residual-",
            "identifier validation, human review, and approval are incomplete."
          )
        )
      )
    )
  )

  synthetic_warning <- .build_deid_alert(
    "warning",
    "Synthetic demonstration only. ",
    paste(
      "The tagged preview can miss identifiers; do not upload real PHI.",
      "Anonymized-data download and release remain disabled."
    ),
    dismissible = TRUE,
    close_label = "Close synthetic demonstration warning"
  )

  shiny::tagList(synthetic_warning, page)
}


build_deid_server <- function(
    config,
    default_workbook_path = "Clinical_PHI_Anonymization_Data.xlsx"
) {
  force(config)
  force(default_workbook_path)

  function(input, output, session) {
    require_deid_namespace("shinyvalidate")

    run_value <- shiny::reactiveVal(new_deid_run(config$hash))
    error_value <- shiny::reactiveVal(NULL)
    input_validator <- shinyvalidate::InputValidator$new()
    input_validator$add_rule(
      "workbook",
      function(value) {
        if (identical(input$data_source, "upload") && is.null(value)) {
          return("Select an XLSX workbook.")
        }
        NULL
      }
    )
    input_validator$add_rule(
      "worksheet",
      function(value) {
        if (
          identical(input$data_source, "upload") &&
            (
              !is.character(value) ||
                length(value) != 1L ||
                is.na(value) ||
                !nzchar(value)
            )
        ) {
          return("Select one worksheet to process.")
        }
        NULL
      }
    )
    input_validator$enable()

    active_workbook <- shiny::reactive({
      source <- input$data_source
      if (is.null(source) || identical(source, "default")) {
        return(list(
          path = default_workbook_path,
          name = basename(default_workbook_path),
          worksheet = config$schema$sheet_name,
          source = "default"
        ))
      }

      if (!identical(source, "upload") || is.null(input$workbook)) {
        return(NULL)
      }

      list(
        path = input$workbook$datapath,
        name = input$workbook$name,
        worksheet = input$worksheet,
        source = "upload"
      )
    })

    workbook_inspection <- shiny::reactive({
      workbook <- active_workbook()
      shiny::req(workbook)

      tryCatch(
        inspect_clinical_workbook(
          path = workbook$path,
          original_name = workbook$name,
          config = config,
          worksheet = NULL
        ),
        error = function(e) e
      )
    })

    selected_dataset <- shiny::reactive({
      workbook <- active_workbook()
      shiny::req(workbook)
      selected_sheet <- workbook$worksheet
      if (
        !is.character(selected_sheet) ||
          length(selected_sheet) != 1L ||
          is.na(selected_sheet) ||
          !nzchar(selected_sheet)
      ) {
        return(NULL)
      }

      tryCatch(
        read_clinical_workbook(
          path = workbook$path,
          original_name = workbook$name,
          config = config,
          worksheet = selected_sheet
        ),
        error = function(e) e
      )
    })

    workbook_validation_message <- shiny::reactive({
      workbook <- active_workbook()
      if (is.null(workbook)) {
        return(NULL)
      }

      inspection <- workbook_inspection()
      if (inherits(inspection, "condition")) {
        return(conditionMessage(inspection))
      }

      selected_sheet <- workbook$worksheet
      if (
        !is.character(selected_sheet) ||
          length(selected_sheet) != 1L ||
          is.na(selected_sheet) ||
          !nzchar(selected_sheet)
      ) {
        return("Select a worksheet to validate against the approved column contract.")
      }

      dataset <- selected_dataset()
      if (inherits(dataset, "condition")) {
        return(conditionMessage(dataset))
      }

      schema_error <- tryCatch(
        {
          validate_clinical_schema(dataset$data, config)
          NULL
        },
        error = function(e) e
      )
      if (inherits(schema_error, "condition")) {
        return(paste(
          "The selected worksheet does not match the approved column contract:",
          conditionMessage(schema_error)
        ))
      }

      NULL
    })

    output$workbook_validation <- shiny::renderUI({
      message <- workbook_validation_message()
      if (is.null(message)) {
        return(NULL)
      }

      .build_deid_alert(
        "danger",
        "Workbook validation: ",
        message,
        id = "workbook_validation_feedback",
        live = "assertive"
      )
    })

    process_active_workbook <- function() {
      current <- run_value()
      run_value(invalidate_run(current))
      error_value(NULL)

      tryCatch(
        {
          requires_upload_validation <- identical(input$data_source, "upload")
          if (
            (requires_upload_validation && !isTRUE(input_validator$is_valid())) ||
              !is.null(workbook_validation_message())
          ) {
            deid_abort(
              code = "WORKBOOK_VALIDATION_FAILED",
              message = "Correct the highlighted workbook validation errors before processing.",
              subclass = "deid_input_error"
            )
          }

          dataset <- selected_dataset()
          if (is.null(dataset)) {
            deid_abort(
              code = "SELECTED_WORKSHEET_REQUIRED",
              message = "Select one worksheet before processing.",
              subclass = "deid_input_error"
            )
          }

          if (inherits(dataset, "condition")) {
            stop(dataset)
          }

          run_value(run_structured_deidentification(
            input_dataset = dataset,
            config = config
          ))
        },
        error = function(e) {
          run_value(failed_run_from_condition(
            config_hash = config$hash,
            condition = e
          ))
          error_value(conditionMessage(e))
        }
      )
    }

    shiny::observeEvent(
      input$data_source,
      {
        current <- run_value()
        run_value(invalidate_run(current))
        error_value(NULL)

        if (identical(input$data_source, "default")) {
          process_active_workbook()
          return()
        }

        shiny::freezeReactiveValue(input, "worksheet")

        if (is.null(input$workbook)) {
          shiny::updateSelectInput(
            session,
            "worksheet",
            choices = character(),
            selected = character()
          )
          return()
        }

        inspection <- workbook_inspection()
        if (inherits(inspection, "condition")) {
          shiny::updateSelectInput(
            session,
            "worksheet",
            choices = character(),
            selected = character()
          )
          return()
        }

        sheets <- inspection$all_sheets
        shiny::updateSelectInput(
          session,
          "worksheet",
          choices = stats::setNames(sheets, sheets),
          selected = sheets[[1]]
        )
      },
      ignoreInit = FALSE
    )

    shiny::observeEvent(
      input$workbook,
      {
        if (!identical(input$data_source, "upload")) {
          return()
        }

        current <- run_value()
        run_value(invalidate_run(current))
        error_value(NULL)
        shiny::freezeReactiveValue(input, "worksheet")

        inspection <- workbook_inspection()
        if (inherits(inspection, "condition")) {
          shiny::updateSelectInput(
            session,
            "worksheet",
            choices = character(),
            selected = character()
          )
          return()
        }

        sheets <- inspection$all_sheets
        shiny::updateSelectInput(
          session,
          "worksheet",
          choices = stats::setNames(sheets, sheets),
          selected = sheets[[1]]
        )
      },
      ignoreInit = TRUE
    )

    shiny::observeEvent(
      input$worksheet,
      {
        if (!identical(input$data_source, "upload")) {
          return()
        }
        current <- run_value()
        run_value(invalidate_run(current))
        error_value(NULL)
      },
      ignoreInit = TRUE
    )

    shiny::observeEvent(
      input$process,
      {
        process_active_workbook()
      },
      ignoreInit = TRUE
    )

    tagged_preview_value <- shiny::reactive({
      create_tagged_preview(run_value(), config)
    })

    output$classification <- DT::renderDT({
      data <- schema_columns(config)
      DT::datatable(
        data,
        rownames = FALSE,
        options = list(
          dom = "t",
          paging = FALSE,
          ordering = FALSE
        )
      )
    })

    output$processing_error <- shiny::renderUI({
      error <- error_value()
      if (is.null(error)) {
        return(NULL)
      }

      .build_deid_alert("danger", "Processing failed: ", error, live = "assertive")
    })

    output$tagged_preview <- DT::renderDT({
      preview <- tagged_preview_value()
      shiny::req(preview)

      DT::datatable(
        preview,
        rownames = FALSE,
        escape = TRUE,
        options = list(
          pageLength = 10,
          scrollX = TRUE
        )
      )
    })

    output$synthetic_preview_download <- shiny::renderUI({
      run <- run_value()
      preview <- tagged_preview_value()
      preview_complete <- !is.null(preview) && !any(
        unlist(preview, use.names = FALSE) ==
          config$policy$preview$failure_placeholder,
        na.rm = TRUE
      )

      if (!identical(run$state, "PROCESSED") || !preview_complete) {
        return(NULL)
      }

      bslib::tooltip(
        shiny::downloadButton(
          "download_synthetic_preview",
          label = NULL,
          class = "btn-sm btn-secondary",
          `aria-label` = paste(
            "Download synthetic tagged preview (XLSX) -",
            "not anonymized and not releasable"
          )
        ),
        paste(
          "Download synthetic tagged preview (XLSX) -",
          "not anonymized and not releasable"
        )
      )
    })

    output$detection_details <- DT::renderDT({
      preview <- tagged_preview_value()
      shiny::req(preview)

      DT::datatable(
        build_deterministic_detection_table(preview, config),
        rownames = FALSE,
        escape = TRUE,
        options = list(
          pageLength = 10,
          scrollX = TRUE
        )
      )
    })

    output$download_synthetic_preview <- shiny::downloadHandler(
      filename = function() {
        "synthetic-tagged-preview-not-releasable.xlsx"
      },
      content = function(file) {
        write_synthetic_preview_workbook(run_value(), file, config)
      },
      contentType = "application/vnd.openxmlformats-officedocument.spreadsheetml.sheet"
    )

    output$blockers <- DT::renderDT({
      run <- run_value()
      shiny::req(nrow(run$blockers) > 0L)

      DT::datatable(
        run$blockers,
        rownames = FALSE,
        options = list(
          dom = "t",
          paging = FALSE,
          ordering = FALSE
        )
      )
    })

    session$onSessionEnded(function() {
      run_value(NULL)
      error_value(NULL)
    })
  }
}
