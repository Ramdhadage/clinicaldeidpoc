activate_local_development_library <- function(project_root = ".") {
  minor_component <- strsplit(R.version$minor, ".", fixed = TRUE)[[1]][1]
  version_directory <- paste(R.version$major, minor_component, sep = ".")
  local_library <- file.path(
    project_root,
    ".r-lib",
    version_directory
  )

  if (dir.exists(local_library)) {
    .libPaths(c(
      normalizePath(local_library, winslash = "/", mustWork = TRUE),
      .libPaths()
    ))
  }

  invisible(.libPaths())
}


load_deid_modules <- function(
    project_root = ".",
    envir = parent.frame()
) {
  files <- c(
    "conditions.R",
    "config.R",
    "input.R",
    "schema.R",
    "structured_rules.R",
    "tagged_preview.R",
    "validation.R",
    "workflow_state.R",
    "audit.R",
    "export.R",
    "shiny_app.R"
  )

  for (file in files) {
    path <- file.path(project_root, "R", file)
    if (!file.exists(path)) {
      stop(
        paste0("Required implementation module is missing: ", path),
        call. = FALSE
      )
    }
    sys.source(path, envir = envir)
  }

  invisible(files)
}
