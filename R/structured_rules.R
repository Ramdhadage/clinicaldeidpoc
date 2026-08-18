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
    if (grepl("-[0-9]{2}$", date_part, perl = TRUE)) {
      year <- sub(".*-", "", date_part)
      date_prefix <- sub("[0-9]{2}$", "", date_part)
      candidates <- c(
        safe_as_date(paste0(date_prefix, "19", year), "%d-%b-%Y"),
        safe_as_date(paste0(date_prefix, "20", year), "%d-%b-%Y")
      )
    } else {
      candidates <- safe_as_date(date_part, "%d-%b-%Y")
    }
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

  candidates <- candidates[candidates <= reference_date]
  if (length(candidates) == 0L) {
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


generalize_zip_code_value <- function(value, eligible_prefixes) {
  if (is.na(value)) {
    return(NA_character_)
  }

  normalized_value <- sub("\\.0+$", "", value, perl = TRUE)
  if (grepl("^[0-9]{4}$", normalized_value, perl = TRUE)) {
    normalized_value <- paste0("0", normalized_value)
  }
  if (grepl("^[0-9]{9}$", normalized_value, perl = TRUE)) {
    normalized_value <- substr(normalized_value, 1L, 5L)
  }

  if (!grepl("^[0-9]{5}(?:-[0-9]{4})?$", normalized_value, perl = TRUE)) {
    return(NA_character_)
  }

  prefix <- substr(normalized_value, 1L, 3L)
  retained_prefix <- if (prefix %in% eligible_prefixes) prefix else "000"
  retained_prefix
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

  geographic_columns <- classification$name[
    classification$role == "geographic_identifier"
  ]
  eligible_prefixes <- unlist(
    config$policy$preview$zip_code$eligible_three_digit_prefixes,
    use.names = FALSE
  )
  generalized_counts <- integer(length(geographic_columns))
  names(generalized_counts) <- geographic_columns
  for (column in geographic_columns) {
    generalized_counts[[column]] <- sum(!is.na(output[[column]]))
    output[[column]] <- vapply(
      output[[column]],
      generalize_zip_code_value,
      character(1),
      eligible_prefixes = eligible_prefixes
    )
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
        column = c(direct_columns, geographic_columns),
        action = c(
          rep("remove", length(direct_columns)),
          rep("retain_eligible_three_digit_or_000", length(geographic_columns))
        ),
        affected_cells = c(unname(removed_counts), unname(generalized_counts)),
        stringsAsFactors = FALSE
      ),
      reference_date = reference_date
    ),
    class = c("StructuredResult", "list")
  )
}
