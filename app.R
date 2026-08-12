# Clinical Data De-identification PoC
# Milestone 1: synthetic-only structured processing; release is disabled.

if (!exists("read_deid_config", mode = "function")) {
  source(file.path("R", "bootstrap.R"))
  load_deid_modules(".")
}

config <- read_deid_config(".")

shiny::shinyApp(
  ui = build_deid_ui(config),
  server = build_deid_server(config)
)
