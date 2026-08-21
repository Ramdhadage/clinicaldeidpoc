build_deid_ui <- function(config) {
  shiny::fluidPage(
    shiny::titlePanel("Clinical Data De-identification PoC"),
    shiny::tags$div(
      class = "alert alert-danger",
      shiny::tags$strong("Synthetic demonstration only. "),
      paste(
        "The tagged preview can miss identifiers; do not upload real PHI.",
        "Download and release remain disabled."
      )
    ),
    shiny::sidebarLayout(
      shiny::sidebarPanel(
        shiny::fileInput(
          "workbook",
          "Choose an XLSX workbook",
          accept = ".xlsx"
        ),
        shiny::uiOutput("worksheet_selector"),
        shiny::uiOutput("workbook_validation"),
        shiny::checkboxInput(
          "confirm_synthetic",
          "I confirm this workbook contains synthetic test data only.",
          value = FALSE
        ),
        shiny::actionButton(
          "process",
          "Generate tagged preview",
          class = "btn-primary"
        ),
        shiny::hr(),
        shiny::tags$p(
          shiny::tags$strong("Worksheet selection: "),
          "Choose a worksheet after upload. It must match the approved column contract."
        ),
        shiny::tags$p(
          shiny::tags$strong("Release enabled: "),
          "No"
        )
      ),
      shiny::mainPanel(
        shiny::uiOutput("run_status"),
        shiny::tags$h3("Approved column contract"),
        DT::DTOutput("classification"),
        shiny::tags$h3("Synthetic tagged preview - not validated"),
        shiny::tags$p(
          "Dates are displayed as [YYYY], and patient names use [Name].",
          paste(
            "Each nonmissing Record_No, MRN, and Patient_ID cell uses an",
            "independent random eight-character hexadecimal preview token."
          )
        ),
        shiny::tags$p(
          paste(
            "Tokens are generated independently of source values, remain stable",
            "only within this run, and are held only in session memory."
          ),
          "Undetected text is shown and may still contain identifiers.",
          "Use synthetic data only; this is not a HIPAA Safe Harbor determination."
        ),
        shiny::tags$details(
          shiny::tags$summary("Coverage and tag behavior"),
          shiny::tags$p(
            paste(
              "The run guide displays a 20-row coverage matrix mapped to the 18",
              "HIPAA Safe Harbor identifier types. This preview attempts only",
              "the deterministic subsets listed there, including known names",
              "and identifiers, dates, contact details, labeled codes, addresses,",
              "ZIP codes, facilities, and network identifiers."
            )
          ),
          shiny::tags$p(
            paste(
              "Arbitrary names and locations, image or biometric content, and",
              "other unique characteristics still require Azure/NER, residual",
              "validation, and human review."
            )
          )
        ),
        DT::DTOutput("tagged_preview"),
        shiny::tags$h3("Detection details — deterministic preview only"),
        shiny::tags$div(
          class = "alert alert-info",
          shiny::tags$strong("Azure is not called in this PoC. "),
          paste(
            "Detected entities and offsets below describe local preview tags",
            "in the redacted preview text. Confidence scores are rule-based,",
            "not Azure confidence scores."
          )
        ),
        DT::DTOutput("detection_details"),
        shiny::uiOutput("synthetic_preview_download"),
        shiny::tags$h3("Critical validation blockers"),
        DT::DTOutput("blockers"),
        shiny::tags$div(
          class = "alert alert-warning",
          shiny::tags$strong("Release unavailable. "),
          paste(
            "No anonymized output can be released because Azure PII processing, residual-",
            "identifier validation, human review, and approval are incomplete."
          )
        )
      )
    )
  )
}


build_deid_server <- function(config) {
  force(config)

  function(input, output, session) {
    require_deid_namespace("shinyvalidate")

    run_value <- shiny::reactiveVal(new_deid_run(config$hash))
    error_value <- shiny::reactiveVal(NULL)
    input_validator <- shinyvalidate::InputValidator$new()
    input_validator$add_rule(
      "workbook",
      shinyvalidate::sv_required("Select an XLSX workbook.")
    )
    input_validator$add_rule(
      "worksheet",
      shinyvalidate::sv_required("Select one worksheet to process.")
    )
    input_validator$add_rule("confirm_synthetic", function(value) {
      if (!isTRUE(value)) {
        "Confirm that the workbook contains synthetic test data only."
      }
    })
    input_validator$enable()

    workbook_inspection <- shiny::reactive({
      shiny::req(input$workbook)

      tryCatch(
        inspect_clinical_workbook(
          path = input$workbook$datapath,
          original_name = input$workbook$name,
          config = config,
          worksheet = NULL
        ),
        error = function(e) e
      )
    })

    selected_dataset <- shiny::reactive({
      shiny::req(input$workbook)

      selected_sheet <- input$worksheet
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
          path = input$workbook$datapath,
          original_name = input$workbook$name,
          config = config,
          worksheet = selected_sheet
        ),
        error = function(e) e
      )
    })

    workbook_validation_message <- shiny::reactive({
      if (is.null(input$workbook)) {
        return(NULL)
      }

      inspection <- workbook_inspection()
      if (inherits(inspection, "condition")) {
        return(conditionMessage(inspection))
      }

      selected_sheet <- input$worksheet
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

      if (!isTRUE(input$confirm_synthetic)) {
        return("Confirm that the workbook contains synthetic test data only.")
      }

      NULL
    })

    output$worksheet_selector <- shiny::renderUI({
      if (is.null(input$workbook)) {
        return(NULL)
      }

      inspection <- workbook_inspection()
      if (inherits(inspection, "condition")) {
        return(NULL)
      }

      sheets <- inspection$all_sheets
      selected_sheet <- input$worksheet
      if (
        !is.character(selected_sheet) ||
          length(selected_sheet) != 1L ||
          is.na(selected_sheet) ||
          !selected_sheet %in% sheets
      ) {
        selected_sheet <- sheets[[1]]
      }

      shiny::selectInput(
        "worksheet",
        "Worksheet to process",
        choices = stats::setNames(sheets, sheets),
        selected = selected_sheet
      )
    })

    output$workbook_validation <- shiny::renderUI({
      message <- workbook_validation_message()
      if (is.null(message)) {
        return(NULL)
      }

      shiny::tags$div(
        id = "workbook_validation_feedback",
        class = "alert alert-danger",
        role = "alert",
        `aria-live` = "assertive",
        shiny::tags$strong("Workbook validation: "),
        message
      )
    })

    shiny::observeEvent(
      input$workbook,
      {
        current <- run_value()
        run_value(invalidate_run(current))
        error_value(NULL)
      },
      ignoreInit = TRUE
    )

    shiny::observeEvent(
      input$worksheet,
      {
        current <- run_value()
        run_value(invalidate_run(current))
        error_value(NULL)
      },
      ignoreInit = TRUE
    )

    shiny::observeEvent(
      input$process,
      {
        current <- run_value()
        run_value(invalidate_run(current))
        error_value(NULL)

        tryCatch(
          {
            if (
              !isTRUE(input_validator$is_valid()) ||
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

            run <- run_structured_deidentification(
              input_dataset = dataset,
              config = config
            )
            run_value(run)
          },
          error = function(e) {
            failed <- failed_run_from_condition(
              config_hash = config$hash,
              condition = e
            )
            run_value(failed)
            error_value(conditionMessage(e))
          }
        )
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

    output$run_status <- shiny::renderUI({
      run <- run_value()
      error <- error_value()

      if (!is.null(error)) {
        return(shiny::tags$div(
          class = "alert alert-danger",
          shiny::tags$strong("Processing failed: "),
          error
        ))
      }

      if (identical(run$state, "EMPTY") || identical(run$state, "RECEIVED")) {
        return(shiny::tags$div(
          class = "alert alert-info",
          "Upload a synthetic XLSX workbook and generate a tagged preview."
        ))
      }

      preview <- tagged_preview_value()
      failed_cells <- if (is.null(preview)) {
        0L
      } else {
        sum(
          unlist(preview, use.names = FALSE) ==
            config$policy$preview$failure_placeholder,
          na.rm = TRUE
        )
      }
      failure_note <- if (failed_cells > 0L) {
        paste0(
          " ",
          failed_cells,
          " preview cell(s) failed redaction and were hidden."
        )
      } else {
        ""
      }

      shiny::tags$div(
        class = "alert alert-warning",
        shiny::tags$strong("Preview generated for synthetic evaluation. "),
        paste0(
          "Run state: ",
          run$state,
          ". This preview is not validated for residual identifiers and is not ",
          "releasable. ",
          "Run-scoped ID tokens are display-only. ",
          nrow(run$blockers),
          " Critical blocker(s) remain.",
          failure_note
        )
      )
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

      if (
        !isTRUE(input$confirm_synthetic) ||
        !identical(run$state, "PROCESSED") ||
        !preview_complete
      ) {
        return(NULL)
      }

      shiny::tagList(
        shiny::tags$div(
          class = "alert alert-info",
          shiny::tags$strong("Synthetic tagged preview download only. "),
          paste(
            "This XLSX is not anonymized, not releasable, and must not be",
            "used or disclosed as de-identified data."
          )
        ),
        shiny::downloadButton(
          "download_synthetic_preview",
          "Download synthetic tagged preview (XLSX)",
          class = "btn-secondary"
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
        if (!isTRUE(input$confirm_synthetic)) {
          deid_abort(
            code = "SYNTHETIC_CONFIRMATION_REQUIRED",
            message = "Confirm synthetic-only data before downloading a preview.",
            subclass = "deid_governance_error"
          )
        }

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
