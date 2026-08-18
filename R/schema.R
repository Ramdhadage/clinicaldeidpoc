normalize_input_values <- function(data) {
  output <- data

  for (name in names(output)) {
    if (is.list(output[[name]]) && !is.data.frame(output[[name]])) {
      deid_abort(
        code = "UNSUPPORTED_LIST_COLUMN",
        message = "List columns are not supported.",
        subclass = "deid_invalid_schema"
      )
    }

    output[[name]] <- as.character(output[[name]])
    blank <- !is.na(output[[name]]) & !nzchar(trimws(output[[name]]))
    output[[name]][blank] <- NA_character_
  }

  output
}


validate_clinical_schema <- function(
    data,
    config = read_deid_config(".")
) {
  if (!is.data.frame(data)) {
    deid_abort(
      code = "INPUT_NOT_DATA_FRAME",
      message = "Clinical_Data must be a rectangular data frame.",
      subclass = "deid_invalid_schema"
    )
  }

  if (nrow(data) == 0L) {
    deid_abort(
      code = "EMPTY_DATASET",
      message = "Clinical_Data must contain at least one data row.",
      subclass = "deid_invalid_schema"
    )
  }

  max_rows <- as.integer(config$runtime$limits$max_rows)
  if (nrow(data) > max_rows) {
    deid_abort(
      code = "ROW_LIMIT_EXCEEDED",
      message = "Clinical_Data exceeds the configured row limit.",
      subclass = "deid_invalid_schema"
    )
  }

  actual <- names(data)
  if (is.null(actual) || any(!nzchar(actual)) || anyDuplicated(actual)) {
    deid_abort(
      code = "INVALID_COLUMN_NAMES",
      message = "Column names must be present and unique.",
      subclass = "deid_invalid_schema"
    )
  }

  classification <- schema_columns(config)
  expected <- classification$name
  missing_columns <- setdiff(expected, actual)
  extra_columns <- setdiff(actual, expected)

  if (length(missing_columns) > 0L) {
    deid_abort(
      code = "MISSING_REQUIRED_COLUMNS",
      message = paste0(
        "Clinical_Data is missing required columns: ",
        paste(missing_columns, collapse = ", "),
        "."
      ),
      subclass = "deid_invalid_schema"
    )
  }

  if (
    length(extra_columns) > 0L &&
    !isTRUE(config$schema$allow_additional_columns)
  ) {
    deid_abort(
      code = "UNEXPECTED_COLUMNS",
      message = paste0(
        "Clinical_Data contains unapproved columns: ",
        paste(extra_columns, collapse = ", "),
        "."
      ),
      subclass = "deid_invalid_schema"
    )
  }

  canonical <- data[, expected, drop = FALSE]
  canonical <- normalize_input_values(canonical)

  record_values <- canonical$Record_No
  invalid_record <- !is.na(record_values) &
    !grepl("^[0-9]+$", record_values, perl = TRUE)

  if (any(invalid_record)) {
    deid_abort(
      code = "INVALID_RECORD_NUMBER_TYPE",
      message = "Record_No must contain only integer-like values or missing values.",
      subclass = "deid_invalid_schema"
    )
  }

  zip_values <- canonical$Zip_Code
  invalid_zip <- !is.na(zip_values) &
    !grepl(
      "^(?:[0-9]{4,9}(?:\\.0+)?|[0-9]{5}-[0-9]{4})$",
      zip_values,
      perl = TRUE
    )

  if (any(invalid_zip)) {
    deid_abort(
      code = "INVALID_ZIP_CODE_TYPE",
      message = paste(
        "Zip_Code must contain a five-digit ZIP or ZIP+4 value,",
        "a numeric postal code, or be missing."
      ),
      subclass = "deid_invalid_schema"
    )
  }

  structure(
    list(
      data = canonical,
      classification = classification,
      row_count = nrow(canonical),
      column_count = ncol(canonical)
    ),
    class = c("SchemaValidation", "list")
  )
}
