build_deid_ui <- function(config) {
  shiny::fluidPage(
    shiny::titlePanel("Clinical Data De-identification PoC"),
    shiny::tags$div(
      class = "alert alert-danger",
      shiny::tags$strong("Synthetic data only. "),
      paste(
        "Real PHI processing and release are disabled until the governance,",
        "Azure text-processing, validation, and approval milestones are complete."
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
          "Run structured processing",
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
        shiny::tags$h3("Safe structured preview"),
        shiny::tags$p(
          "Direct identifiers are blanked. Raw narrative text is never shown;",
          "it remains pending the Azure text-processing milestone."
        ),
        DT::DTOutput("safe_preview"),
        shiny::tags$h3("Blocking items"),
        DT::DTOutput("blockers"),
        shiny::tags$div(
          class = "alert alert-warning",
          shiny::tags$strong("Download unavailable. "),
          paste(
            "No output can be released from this milestone because free-text",
            "processing, complete validation, review, and approval are pending."
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
          "Upload a synthetic XLSX workbook and run structured processing."
        ))
      }

      shiny::tags$div(
        class = "alert alert-success",
        shiny::tags$strong("Structured processing completed. "),
        paste0(
          "Run state: ",
          run$state,
          ". Release remains blocked by ",
          nrow(run$blockers),
          " pending text-processing item(s)."
        )
      )
    })

    output$safe_preview <- DT::renderDT({
      preview <- create_safe_preview(run_value(), config)
      shiny::req(preview)

      DT::datatable(
        preview,
        rownames = FALSE,
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

