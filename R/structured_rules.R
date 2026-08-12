safe_as_date <- function(value, format) {
  suppressWarnings(
    tryCatch(
      as.Date(value, format = format),
      error = function(e) as.Date(NA)
    )
  )
}


parse_supported_dob <- function(value) {
  value <- trimws(value)
  candidates <- as.Date(character())

  if (
    grepl(
      "^[0-9]{4}-[0-9]{2}-[0-9]{2}( ([01][0-9]|2[0-3]):[0-5][0-9](:[0-5][0-9])?( [A-Za-z]{3})?)?$",
      value,
      perl = TRUE
    )
  ) {
    date_part <- substr(value, 1L, 10L)
    candidates <- safe_as_date(date_part, "%Y-%m-%d")
  } else if (
    grepl(
      "^[0-9]{1,2}-[A-Za-z]{3}-[0-9]{2}([0-9]{2})?( ([01][0-9]|2[0-3]):[0-5][0-9](:[0-5][0-9])?)?$",
      value,
      perl = TRUE
    )
  ) {
    date_part <- sub(" .*", "", value)
    year_format <- if (grepl("-[0-9]{2}$", date_part, perl = TRUE)) {
      "%d-%b-%y"
    } else {
      "%d-%b-%Y"
    }
    candidates <- safe_as_date(date_part, year_format)
  } else if (
    grepl(
      "^[0-9]{1,2}[-/][0-9]{1,2}[-/][0-9]{4}( ([01][0-9]|2[0-3]):[0-5][0-9](:[0-5][0-9])?)?$",
      value,
      perl = TRUE
    )
  ) {
    date_part <- sub(" .*", "", value)
    separator <- if (grepl("/", date_part, fixed = TRUE)) "/" else "-"
    candidates <- c(
      safe_as_date(date_part, paste0("%m", separator, "%d", separator, "%Y")),
      safe_as_date(date_part, paste0("%d", separator, "%m", separator, "%Y"))
    )
  }

  candidates <- unique(candidates[!is.na(candidates)])
  if (length(candidates) == 0L) {
    deid_abort(
      code = "INVALID_DOB",
      message = "DOB contains an unsupported or impossible date value.",
      subclass = "deid_invalid_date"
    )
  }

  candidates
}


age_on_date <- function(birth_date, reference_date) {
  birth_parts <- as.POSIXlt(birth_date, tz = "UTC")
  reference_parts <- as.POSIXlt(reference_date, tz = "UTC")

  age <- reference_parts$year - birth_parts$year
  birthday_not_reached <- (
    reference_parts$mon < birth_parts$mon ||
      (
        reference_parts$mon == birth_parts$mon &&
          reference_parts$mday < birth_parts$mday
      )
  )

  as.integer(age - birthday_not_reached)
}


generalize_dob_value <- function(value, reference_date, age_90_plus_value) {
  if (is.na(value)) {
    return(NA_character_)
  }

  candidates <- parse_supported_dob(value)

  if (any(candidates > reference_date)) {
    deid_abort(
      code = "FUTURE_DOB",
      message = "DOB contains a future date.",
      subclass = "deid_invalid_date"
    )
  }

  years <- unique(format(candidates, "%Y"))
  if (length(years) != 1L) {
    deid_abort(
      code = "AMBIGUOUS_DOB_YEAR",
      message = "DOB does not resolve to one unambiguous year.",
      subclass = "deid_invalid_date"
    )
  }

  ages <- vapply(
    candidates,
    age_on_date,
    integer(1),
    reference_date = reference_date
  )

  if (all(ages >= 90L)) {
    return(age_90_plus_value)
  }

  if (all(ages < 90L)) {
    return(years)
  }

  deid_abort(
    code = "AMBIGUOUS_AGE_90_STATUS",
    message = "An ambiguous DOB format crosses the age-90 threshold.",
    subclass = "deid_invalid_date"
  )
}


transform_structured_fields <- function(
    schema_validation,
    config = read_deid_config(".")
) {
  if (!inherits(schema_validation, "SchemaValidation")) {
    deid_abort(
      code = "INVALID_SCHEMA_RESULT",
      message = "A validated schema result is required.",
      subclass = "deid_argument_error"
    )
  }

  input <- schema_validation$data
  output <- input
  classification <- schema_validation$classification
  reference_date <- as.Date(config$policy$reference_date)

  direct_columns <- classification$name[
    classification$role == "direct_identifier"
  ]

  removed_counts <- integer(length(direct_columns))
  names(removed_counts) <- direct_columns

  for (column in direct_columns) {
    removed_counts[[column]] <- sum(!is.na(output[[column]]))
    output[[column]] <- rep(NA_character_, nrow(output))
  }

  output$DOB <- vapply(
    output$DOB,
    generalize_dob_value,
    character(1),
    reference_date = reference_date,
    age_90_plus_value = config$policy$age_90_plus_value
  )

  structure(
    list(
      data = output,
      classification = classification,
      transformation_summary = data.frame(
        column = direct_columns,
        action = rep("remove", length(direct_columns)),
        affected_cells = unname(removed_counts),
        stringsAsFactors = FALSE
      ),
      reference_date = reference_date
    ),
    class = c("StructuredResult", "list")
  )
}
