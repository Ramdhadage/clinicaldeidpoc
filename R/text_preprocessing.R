unicode_codepoints <- function(text) {
  if (is.na(text)) {
    return(integer())
  }
  utf8ToInt(enc2utf8(text))
}


text_record_count <- function(text, record_size = 1000L) {
  if (!is.character(text) || length(text) != 1L || is.na(text)) {
    deid_abort(
      code = "INVALID_TEXT_RECORD_INPUT",
      message = "Text-record estimation requires one non-missing character value.",
      subclass = "deid_text_preprocessing_error"
    )
  }

  record_size <- as.integer(record_size)
  if (length(record_size) != 1L || is.na(record_size) || record_size < 1L) {
    deid_abort(
      code = "INVALID_TEXT_RECORD_SIZE",
      message = "The Azure text-record size must be a positive integer.",
      subclass = "deid_text_preprocessing_error"
    )
  }

  codepoint_count <- length(unicode_codepoints(text))
  if (codepoint_count == 0L) {
    return(0L)
  }
  as.integer(ceiling(codepoint_count / record_size))
}


chunk_prepared_text <- function(
    text,
    maximum_codepoints = 5000L,
    overlap_codepoints = 0L
) {
  if (!is.character(text) || length(text) != 1L || is.na(text)) {
    deid_abort(
      code = "INVALID_CHUNK_INPUT",
      message = "Text chunking requires one non-missing character value.",
      subclass = "deid_text_preprocessing_error"
    )
  }

  maximum_codepoints <- as.integer(maximum_codepoints)
  overlap_codepoints <- as.integer(overlap_codepoints)
  if (
    length(maximum_codepoints) != 1L ||
    is.na(maximum_codepoints) ||
    maximum_codepoints < 1L ||
    length(overlap_codepoints) != 1L ||
    is.na(overlap_codepoints) ||
    overlap_codepoints < 0L ||
    overlap_codepoints >= maximum_codepoints
  ) {
    deid_abort(
      code = "INVALID_CHUNK_CONFIGURATION",
      message = "Chunk size must be positive and overlap must be smaller than chunk size.",
      subclass = "deid_text_preprocessing_error"
    )
  }

  codepoints <- unicode_codepoints(text)
  if (length(codepoints) == 0L) {
    return(data.frame(
      chunk_index = integer(),
      start_codepoint = integer(),
      end_codepoint = integer(),
      text = character(),
      stringsAsFactors = FALSE
    ))
  }

  starts <- seq.int(
    from = 1L,
    to = length(codepoints),
    by = maximum_codepoints - overlap_codepoints
  )
  ends <- pmin(starts + maximum_codepoints - 1L, length(codepoints))
  data.frame(
    chunk_index = seq_along(starts),
    start_codepoint = starts - 1L,
    end_codepoint = ends - 1L,
    text = vapply(
      seq_along(starts),
      function(index) intToUtf8(codepoints[starts[[index]]:ends[[index]]]),
      character(1)
    ),
    stringsAsFactors = FALSE
  )
}


prepare_free_text_for_azure <- function(
    source,
    config = read_deid_config("."),
    maximum_codepoints = 5000L,
    overlap_codepoints = 0L
) {
  if (!is.data.frame(source)) {
    deid_abort(
      code = "INVALID_FREE_TEXT_SOURCE",
      message = "Azure free-text preparation requires a data frame.",
      subclass = "deid_text_preprocessing_error"
    )
  }

  free_text_columns <- schema_columns(config)$name[
    schema_columns(config)$role == "free_text"
  ]
  required_columns <- c(
    free_text_columns,
    "Patient_Name",
    "MRN",
    "Patient_ID"
  )
  if (!all(required_columns %in% names(source))) {
    deid_abort(
      code = "FREE_TEXT_SOURCE_SCHEMA_MISMATCH",
      message = "Azure free-text preparation requires the approved free-text and identifier columns.",
      subclass = "deid_text_preprocessing_error"
    )
  }

  known_names <- normalize_known_values(source$Patient_Name)
  known_mrns <- normalize_known_values(source$MRN)
  known_patient_ids <- normalize_known_values(source$Patient_ID)
  documents <- vector("list", length = 0L)
  document_index <- 0L
  original_codepoints <- 0L
  prepared_codepoints <- 0L
  estimated_original_text_records <- 0L

  for (column in free_text_columns) {
    for (row_index in seq_len(nrow(source))) {
      original_text <- source[[column]][[row_index]]
      if (is.na(original_text) || !nzchar(original_text)) {
        next
      }

      prepared_text <- redact_narrative_text(
        text = original_text,
        known_name = source$Patient_Name[[row_index]],
        known_mrn = source$MRN[[row_index]],
        known_patient_id = source$Patient_ID[[row_index]],
        config = config,
        known_names = known_names,
        known_mrns = known_mrns,
        known_patient_ids = known_patient_ids
      )
      original_codepoints <- original_codepoints + length(unicode_codepoints(original_text))
      prepared_codepoints <- prepared_codepoints + length(unicode_codepoints(prepared_text))
      original_chunks <- chunk_prepared_text(
        original_text,
        maximum_codepoints = maximum_codepoints,
        overlap_codepoints = overlap_codepoints
      )
      estimated_original_text_records <- estimated_original_text_records + sum(
        vapply(original_chunks$text, text_record_count, integer(1))
      )
      chunks <- chunk_prepared_text(
        prepared_text,
        maximum_codepoints = maximum_codepoints,
        overlap_codepoints = overlap_codepoints
      )

      for (chunk_row in seq_len(nrow(chunks))) {
        document_index <- document_index + 1L
        documents[[document_index]] <- data.frame(
          document_id = sprintf("free-text-%06d", document_index),
          row_index = row_index,
          column = column,
          chunk_index = chunks$chunk_index[[chunk_row]],
          start_codepoint = chunks$start_codepoint[[chunk_row]],
          end_codepoint = chunks$end_codepoint[[chunk_row]],
          original_codepoints = length(unicode_codepoints(original_text)),
          prepared_codepoints = length(unicode_codepoints(prepared_text)),
          estimated_text_records = text_record_count(chunks$text[[chunk_row]]),
          text = chunks$text[[chunk_row]],
          stringsAsFactors = FALSE
        )
      }
    }
  }

  if (length(documents) == 0L) {
    documents <- data.frame(
      document_id = character(),
      row_index = integer(),
      column = character(),
      chunk_index = integer(),
      start_codepoint = integer(),
      end_codepoint = integer(),
      original_codepoints = integer(),
      prepared_codepoints = integer(),
      estimated_text_records = integer(),
      text = character(),
      stringsAsFactors = FALSE
    )
  } else {
    documents <- do.call(rbind, documents)
  }

  structure(
    list(
      documents = documents,
      summary = list(
        documents = nrow(documents),
        original_codepoints = original_codepoints,
        prepared_codepoints = prepared_codepoints,
        estimated_original_text_records = estimated_original_text_records,
        estimated_text_records = sum(documents$estimated_text_records)
      )
    ),
    class = c("FreeTextAzurePreparation", "list")
  )
}


check_post_redaction_residuals <- function(
    text,
    known_name = NA_character_,
    known_mrn = NA_character_,
    known_patient_id = NA_character_,
    config = read_deid_config("."),
    known_names = character(),
    known_mrns = character(),
    known_patient_ids = character()
) {
  if (is.na(text)) {
    return(list(has_residual = FALSE, deterministic_redaction = NA_character_))
  }

  deterministic_redaction <- redact_narrative_text(
    text = text,
    known_name = known_name,
    known_mrn = known_mrn,
    known_patient_id = known_patient_id,
    config = config,
    known_names = known_names,
    known_mrns = known_mrns,
    known_patient_ids = known_patient_ids
  )

  list(
    has_residual = !identical(text, deterministic_redaction),
    deterministic_redaction = deterministic_redaction
  )
}


build_deterministic_detection_table <- function(preview, config) {
  if (!is.data.frame(preview)) {
    deid_abort(
      code = "INVALID_DETECTION_PREVIEW",
      message = "The deterministic detection table requires a preview data frame.",
      subclass = "deid_text_preprocessing_error"
    )
  }

  free_text_columns <- schema_columns(config)$name[
    schema_columns(config)$role == "free_text"
  ]
  if (!all(free_text_columns %in% names(preview))) {
    deid_abort(
      code = "DETECTION_PREVIEW_SCHEMA_MISMATCH",
      message = "The deterministic detection table requires the configured free-text columns.",
      subclass = "deid_text_preprocessing_error"
    )
  }

  rows <- vector("list", length = 0L)
  row_number <- 0L
  for (column in free_text_columns) {
    for (source_row in seq_len(nrow(preview))) {
      text <- preview[[column]][[source_row]]
      if (is.na(text)) {
        next
      }

      row_number <- row_number + 1L
      matches <- gregexpr("\\[[^][]+\\]", text, perl = TRUE)[[1]]
      has_matches <- !(length(matches) == 1L && matches[[1]] == -1L)
      if (has_matches) {
        lengths <- attr(matches, "match.length")
        entities <- substring(text, matches, matches + lengths - 1L)
        offsets <- vapply(
          matches,
          function(start) {
            length(unicode_codepoints(substr(text, 1L, start - 1L)))
          },
          integer(1)
        )
        detected_entities <- paste(unique(entities), collapse = ", ")
        offset_values <- paste(offsets, collapse = ", ")
        confidence_scores <- "Deterministic rule"
      } else {
        detected_entities <- "No deterministic match"
        offset_values <- NA_character_
        confidence_scores <- "Not applicable"
      }

      rows[[row_number]] <- data.frame(
        document_id = sprintf(
          "%s-%06d",
          tolower(column),
          source_row
        ),
        detected_entities = detected_entities,
        offsets = offset_values,
        confidence_scores = confidence_scores,
        redacted_text = text,
        stringsAsFactors = FALSE
      )
    }
  }

  if (length(rows) == 0L) {
    return(data.frame(
      document_id = character(),
      detected_entities = character(),
      offsets = character(),
      confidence_scores = character(),
      redacted_text = character(),
      stringsAsFactors = FALSE
    ))
  }

  do.call(rbind, rows)
}
