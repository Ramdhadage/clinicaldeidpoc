args <- commandArgs(trailingOnly = TRUE)
require_app <- "--app" %in% args

source(file.path("R", "bootstrap.R"))
activate_local_development_library(".")

core_packages <- c("digest", "openssl", "readxl", "writexl", "yaml")
app_packages <- c("shiny", "bslib", "DT")
packages <- if (require_app) {
  c(core_packages, app_packages)
} else {
  core_packages
}

cat("R runtime:", R.version.string, "\n")
cat("Library paths:\n")
cat(paste0("  - ", .libPaths(), collapse = "\n"), "\n")

failed <- character()
for (package in packages) {
  result <- tryCatch(
    {
      suppressPackageStartupMessages(
        library(package, character.only = TRUE)
      )
      version <- as.character(utils::packageVersion(package))
      cat(sprintf("[OK]   %-10s %s\n", package, version))
      TRUE
    },
    error = function(e) {
      cat(sprintf("[FAIL] %-10s %s\n", package, conditionMessage(e)))
      FALSE
    }
  )

  if (!result) {
    failed <- c(failed, package)
  }
}

if (length(failed) > 0L) {
  cat(
    "\nEnvironment check failed. See doc/run-guide.md for the clean restore path.\n"
  )
  quit(status = 1L)
}

cat("\nEnvironment check passed.\n")
