empty_drawing_container <- function(xml) {
  !grepl(
    "<(?:[[:alnum:]_-]+:)?(?:twoCellAnchor|oneCellAnchor|absoluteAnchor)(?:[[:space:]>/])",
    xml,
    perl = TRUE
  )
}


read_xlsx_archive_entry <- function(path, entry_name) {
  connection <- unz(path, entry_name, open = "rt")
  on.exit(close(connection), add = TRUE)
  paste(readLines(connection, warn = FALSE), collapse = "\n")
}


contains_unsupported_drawing <- function(path, entry_names) {
  drawing_entries <- entry_names[grepl(
    "^xl/drawings/[^/]+\\.xml$",
    entry_names,
    ignore.case = TRUE,
    perl = TRUE
  )]

  if (length(drawing_entries) == 0L) {
    return(FALSE)
  }

  any(vapply(
    drawing_entries,
    function(entry_name) {
      xml <- tryCatch(
        read_xlsx_archive_entry(path, entry_name),
        error = function(e) NULL
      )
      is.null(xml) || !empty_drawing_container(xml)
    },
    logical(1)
  ))
}


inspect_clinical_workbook <- function(
    path,
    original_name = basename(path),
    config = read_deid_config("."),
    worksheet = config$schema$sheet_name
) {
  assert_scalar_character(path, "path")
  assert_scalar_character(original_name, "original_name")

  if (!file.exists(path)) {
    deid_abort(
      code = "INPUT_FILE_MISSING",
      message = "The selected input file does not exist.",
      subclass = "deid_input_error"
    )
  }

  extension <- tolower(tools::file_ext(original_name))
  if (!identical(extension, "xlsx")) {
    deid_abort(
      code = "UNSUPPORTED_INPUT_TYPE",
      message = "Only .xlsx workbooks are accepted by this milestone.",
      subclass = "deid_input_error"
    )
  }

  file_info <- file.info(path)
  file_size <- unname(file_info$size)
  max_file_bytes <- as.numeric(config$runtime$limits$max_file_bytes)

  if (is.na(file_size) || file_size <= 0) {
    deid_abort(
      code = "EMPTY_INPUT_FILE",
      message = "The selected workbook is empty.",
      subclass = "deid_input_error"
    )
  }

  if (file_size > max_file_bytes) {
    deid_abort(
      code = "INPUT_FILE_TOO_LARGE",
      message = "The selected workbook exceeds the configured size limit.",
      subclass = "deid_input_error"
    )
  }

  entries <- tryCatch(
    utils::unzip(path, list = TRUE),
    error = function(e) {
      deid_abort(
        code = "INVALID_XLSX_CONTAINER",
        message = "The selected file is not a readable XLSX container.",
        subclass = "deid_input_error"
      )
    }
  )

  entry_names <- gsub("\\", "/", entries$Name, fixed = TRUE)
  unsupported_patterns <- c(
    "(^|/)vbaProject\\.bin$",
    "^xl/media/",
    "^xl/externalLinks/",
    "^xl/embeddings/",
    "(^|/)vbaProjectSignature\\.bin$"
  )

  unsupported <- vapply(
    entry_names,
    function(entry) {
      any(vapply(
        unsupported_patterns,
        grepl,
        logical(1),
        x = entry,
        ignore.case = TRUE,
        perl = TRUE
      ))
    },
    logical(1)
  )

  if (any(unsupported) || contains_unsupported_drawing(path, entry_names)) {
    deid_abort(
      code = "UNSUPPORTED_WORKBOOK_CONTENT",
      message = paste(
        "The workbook contains media, drawing objects, external links,",
        "embedded objects, or macros that are outside this milestone."
      ),
      subclass = "deid_input_error"
    )
  }

  require_deid_namespace("readxl")
  sheets <- tryCatch(
    readxl::excel_sheets(path),
    error = function(e) {
      deid_abort(
        code = "WORKBOOK_INSPECTION_FAILED",
        message = "The workbook sheet list could not be read.",
        subclass = "deid_input_error"
      )
    }
  )

  required_sheet <- config$schema$sheet_name
  selected_sheet <- worksheet

  if (is.null(selected_sheet)) {
    selected_sheet <- NULL
  } else if (
    !is.character(selected_sheet) ||
      length(selected_sheet) != 1L ||
      is.na(selected_sheet) ||
      !nzchar(selected_sheet)
  ) {
    deid_abort(
      code = "SELECTED_WORKSHEET_REQUIRED",
      message = "Select one worksheet before processing.",
      subclass = "deid_input_error"
    )
  }

  if (
    !is.null(selected_sheet) &&
      !selected_sheet %in% sheets
  ) {
    missing_sheet_code <- if (identical(selected_sheet, required_sheet)) {
      "MISSING_REQUIRED_SHEET"
    } else {
      "SELECTED_WORKSHEET_NOT_FOUND"
    }
    missing_sheet_message <- if (identical(selected_sheet, required_sheet)) {
      paste0(
        "The workbook does not contain the exact worksheet ",
        required_sheet,
        "."
      )
    } else {
      paste0(
        "The workbook does not contain the selected worksheet ",
        selected_sheet,
        "."
      )
    }
    deid_abort(
      code = missing_sheet_code,
      message = missing_sheet_message,
      subclass = "deid_missing_sheet"
    )
  }

  comparison_sheet <- if (is.null(selected_sheet)) {
    required_sheet
  } else {
    selected_sheet
  }
  additional_sheets <- setdiff(sheets, comparison_sheet)
  if (
    length(additional_sheets) > 0L &&
      !isTRUE(config$schema$allow_additional_sheets)
  ) {
    deid_abort(
      code = "ADDITIONAL_SHEETS_NOT_ALLOWED",
      message = "The workbook contains additional worksheets that are not allowed.",
      subclass = "deid_input_error"
    )
  }

  structure(
    list(
      original_name = original_name,
      size_bytes = file_size,
      input_hash = hash_file(path),
      required_sheet = required_sheet,
      selected_sheet = selected_sheet,
      additional_sheets = additional_sheets,
      all_sheets = sheets
    ),
    class = c("WorkbookInspection", "list")
  )
}


read_clinical_workbook <- function(
    path,
    original_name = basename(path),
    config = read_deid_config("."),
    worksheet = config$schema$sheet_name
) {
  inspection <- inspect_clinical_workbook(
    path = path,
    original_name = original_name,
    config = config,
    worksheet = worksheet
  )

  if (is.null(inspection$selected_sheet)) {
    deid_abort(
      code = "SELECTED_WORKSHEET_REQUIRED",
      message = "Select one worksheet before processing.",
      subclass = "deid_input_error"
    )
  }

  data <- tryCatch(
    readxl::read_excel(
      path,
      sheet = inspection$selected_sheet,
      col_types = "guess",
      .name_repair = "minimal"
    ),
    error = function(e) {
      deid_abort(
        code = "WORKBOOK_READ_FAILED",
        message = paste0(
          "The selected worksheet ",
          inspection$selected_sheet,
          " could not be read."
        ),
        subclass = "deid_input_error"
      )
    }
  )

  data <- as.data.frame(
    data,
    stringsAsFactors = FALSE,
    check.names = FALSE
  )

  structure(
    list(
      data = data,
      metadata = inspection
    ),
    class = c("InputDataset", "list")
  )
}
