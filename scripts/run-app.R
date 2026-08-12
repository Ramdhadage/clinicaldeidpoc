source(file.path("R", "bootstrap.R"))
activate_local_development_library(".")

if (!requireNamespace("shiny", quietly = TRUE)) {
  stop(
    paste(
      "The Shiny packages are not available.",
      "Follow the environment setup in doc/run-guide.md."
    ),
    call. = FALSE
  )
}

shiny::runApp(
  appDir = ".",
  host = "127.0.0.1",
  port = 3838,
  launch.browser = identical(
    tolower(Sys.getenv("DEID_LAUNCH_BROWSER", "false")),
    "true"
  )
)
