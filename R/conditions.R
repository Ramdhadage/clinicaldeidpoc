deid_abort <- function(code, message, subclass = "deid_error") {
  condition <- structure(
    list(
      message = message,
      call = NULL,
      code = code
    ),
    class = c(subclass, "deid_error", "error", "condition")
  )

  stop(condition)
}


conditionMessage.deid_error <- function(c) {
  c$message
}


require_deid_namespace <- function(package) {
  if (!requireNamespace(package, quietly = TRUE)) {
    deid_abort(
      code = "MISSING_DEPENDENCY",
      message = paste0(
        "Required R package '",
        package,
        "' is not available in the active library."
      ),
      subclass = "deid_environment_error"
    )
  }

  invisible(TRUE)
}


assert_scalar_character <- function(x, name) {
  if (!is.character(x) || length(x) != 1L || is.na(x) || !nzchar(x)) {
    deid_abort(
      code = "INVALID_ARGUMENT",
      message = paste0(name, " must be one non-empty character value."),
      subclass = "deid_argument_error"
    )
  }

  invisible(TRUE)
}


empty_blockers <- function() {
  data.frame(
    code = character(),
    column = character(),
    severity = character(),
    stringsAsFactors = FALSE
  )
}


utc_now <- function() {
  format(
    Sys.time(),
    tz = "UTC",
    usetz = TRUE
  )
}


new_run_id <- function() {
  paste0(
    "RUN-",
    format(Sys.time(), "%Y%m%dT%H%M%SZ", tz = "UTC"),
    "-",
    sprintf("%08X", sample.int(.Machine$integer.max, 1L))
  )
}


hash_object <- function(x) {
  require_deid_namespace("digest")
  digest::digest(x, algo = "sha256", serialize = TRUE)
}


hash_file <- function(path) {
  require_deid_namespace("digest")
  digest::digest(file = path, algo = "sha256", serialize = FALSE)
}

