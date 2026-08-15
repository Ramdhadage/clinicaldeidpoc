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
          shiny::tags$strong("Required worksheet: "),
          config$schema$sheet_name
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
        shiny::tags$h3("Critical validation blockers"),
        DT::DTOutput("blockers"),
        shiny::tags$div(
          class = "alert alert-warning",
          shiny::tags$strong("Download unavailable. "),
          paste(
            "No output can be released because Azure PII processing, residual-",
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
    run_value <- shiny::reactiveVal(new_deid_run(config$hash))
    error_value <- shiny::reactiveVal(NULL)

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
      input$process,
      {
        current <- run_value()
        run_value(invalidate_run(current))
        error_value(NULL)

        tryCatch(
          {
            if (is.null(input$workbook)) {
              deid_abort(
                code = "WORKBOOK_REQUIRED",
                message = "Select an XLSX workbook before processing.",
                subclass = "deid_input_error"
              )
            }

            if (!isTRUE(input$confirm_synthetic)) {
              deid_abort(
                code = "SYNTHETIC_CONFIRMATION_REQUIRED",
                message = "Confirm that the workbook contains synthetic test data only.",
                subclass = "deid_governance_error"
              )
            }

            dataset <- read_clinical_workbook(
              path = input$workbook$datapath,
              original_name = input$workbook$name,
              config = config
            )

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
