# Clinical Data De-identification PoC
# Milestone 1.2: synthetic-only tagged preview; release is disabled.

if (!exists("read_deid_config", mode = "function")) {
  source(file.path("R", "bootstrap.R"))
  load_deid_modules(".")
}

config <- read_deid_config(".")
default_workbook <- file.path(".", "Clinical_PHI_Anonymization_Data.xlsx")

shiny::shinyApp(
  ui = build_deid_ui(config, basename(default_workbook)),
  server = build_deid_server(config, default_workbook)
)

