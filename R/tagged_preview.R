preview_tag <- function(config, name) {
  value <- config$policy$preview$tags[[name]]
  if (!is.character(value) || length(value) != 1L || is.na(value) || !nzchar(value)) {
    deid_abort(
      code = "INVALID_PREVIEW_TAG",
      message = "A required tagged-preview label is missing.",
      subclass = "deid_config_error"
    )
  }
  value
}


new_tag_buffer <- function(text) {
  if (grepl("__DEID_PREVIEW_TAG_", text, fixed = TRUE)) {
    deid_abort(
      code = "PREVIEW_SENTINEL_COLLISION",
      message = "Narrative text contains a reserved preview marker.",
      subclass = "deid_preview_error"
    )
  }

  list(
    text = text,
    tags = character(),
    counter = 0L
  )
}


protect_preview_tag <- function(buffer, tag) {
  buffer$counter <- buffer$counter + 1L
  token <- sprintf("__DEID_PREVIEW_TAG_%06d__", buffer$counter)
  buffer$tags[[token]] <- tag
  list(buffer = buffer, token = token)
}


replace_regex_tag <- function(
    buffer,
    pattern,
    tag,
    ignore_case = FALSE
) {
  if (!grepl(
    pattern,
    buffer$text,
    perl = TRUE,
    ignore.case = ignore_case
  )) {
    return(buffer)
  }

  protected <- protect_preview_tag(buffer, tag)
  buffer <- protected$buffer
  buffer$text <- gsub(
    pattern,
    protected$token,
    buffer$text,
    perl = TRUE,
    ignore.case = ignore_case
  )
  buffer
}


replace_regex_callback <- function(
    buffer,
    pattern,
    callback,
    ignore_case = FALSE
) {
  locations <- gregexpr(
    pattern,
    buffer$text,
    perl = TRUE,
    ignore.case = ignore_case
  )[[1]]

  if (length(locations) == 1L && locations[[1]] == -1L) {
    return(buffer)
  }

  lengths <- attr(locations, "match.length")
  matches <- substring(
    buffer$text,
    locations,
    locations + lengths - 1L
  )

  for (index in rev(seq_along(locations))) {
    replacement <- callback(matches[[index]])
    protected <- protect_preview_tag(buffer, replacement)
    buffer <- protected$buffer

    start <- locations[[index]]
    end <- start + lengths[[index]] - 1L
    before <- if (start > 1L) {
      substring(buffer$text, 1L, start - 1L)
    } else {
      ""
    }
    after <- if (end < nchar(buffer$text)) {
      substring(buffer$text, end + 1L)
    } else {
      ""
    }
    buffer$text <- paste0(before, protected$token, after)
  }

  buffer
}


restore_preview_tags <- function(buffer) {
  output <- buffer$text
  if (length(buffer$tags) == 0L) {
    return(output)
  }

  for (token in names(buffer$tags)) {
    output <- gsub(
      token,
      buffer$tags[[token]],
      output,
      fixed = TRUE
    )
  }
  output
}


escape_regex_literal <- function(value) {
  characters <- strsplit(value, "", fixed = TRUE)[[1]]
  special <- characters %in% c(
    "\\", ".", "^", "$", "|", "(", ")",
    "[", "]", "{", "}", "*", "+", "?"
  )
  characters[special] <- paste0("\\", characters[special])
  paste0(characters, collapse = "")
}


replace_known_value <- function(buffer, value, tag) {
  if (is.na(value) || !nzchar(trimws(value))) {
    return(buffer)
  }

  escaped <- escape_regex_literal(trimws(value))
  pattern <- paste0(
    "(?<![[:alnum:]_])",
    escaped,
    "(?![[:alnum:]_])"
  )
  replace_regex_tag(buffer, pattern, tag, ignore_case = TRUE)
}


normalize_known_values <- function(...) {
  values <- unlist(list(...), use.names = FALSE)
  if (length(values) == 0L) {
    return(character())
  }

  values <- trimws(as.character(values))
  values <- unique(values[!is.na(values) & nzchar(values)])
  values[order(nchar(values), decreasing = TRUE)]
}


secure_random_hex_token <- function() {
  require_deid_namespace("openssl")
  bytes <- openssl::rand_bytes(4L)
  if (!is.raw(bytes) || length(bytes) != 4L) {
    deid_abort(
      code = "PREVIEW_TOKEN_RANDOMNESS_FAILED",
      message = "Secure random bytes could not be generated.",
      subclass = "deid_preview_error"
    )
  }
  paste(sprintf("%02x", as.integer(bytes)), collapse = "")
}


generate_run_scoped_hex_ids <- function(
    count,
    deny_values = character(),
    token_factory = secure_random_hex_token,
    max_attempts = 1000L
) {
  count <- as.integer(count)
  max_attempts <- as.integer(max_attempts)
  if (
    length(count) != 1L ||
    is.na(count) ||
    count < 0L ||
    length(max_attempts) != 1L ||
    is.na(max_attempts) ||
    max_attempts < 1L ||
    !is.function(token_factory)
  ) {
    deid_abort(
      code = "INVALID_PREVIEW_TOKEN_REQUEST",
      message = "The structured preview token request is invalid.",
      subclass = "deid_preview_error"
    )
  }
  if (count == 0L) {
    return(character())
  }

  deny_values <- tolower(trimws(as.character(deny_values)))
  deny_values <- unique(deny_values[!is.na(deny_values) & nzchar(deny_values)])
  used <- new.env(hash = TRUE, parent = emptyenv())
  for (value in deny_values) {
    assign(value, TRUE, envir = used)
  }

  output <- character(count)
  for (index in seq_len(count)) {
    accepted <- FALSE
    for (attempt in seq_len(max_attempts)) {
      candidate <- tryCatch(
        token_factory(),
        error = function(e) {
          deid_abort(
            code = "PREVIEW_TOKEN_RANDOMNESS_FAILED",
            message = "Secure preview token generation failed.",
            subclass = "deid_preview_error"
          )
        }
      )
      if (
        !is.character(candidate) ||
        length(candidate) != 1L ||
        is.na(candidate) ||
        !grepl("^[0-9a-f]{8}$", candidate, perl = TRUE)
      ) {
        deid_abort(
          code = "INVALID_PREVIEW_TOKEN_VALUE",
          message = "A generated preview token is not eight lowercase hex characters.",
          subclass = "deid_preview_error"
        )
      }

      if (!exists(candidate, envir = used, inherits = FALSE)) {
        assign(candidate, TRUE, envir = used)
        output[[index]] <- candidate
        accepted <- TRUE
        break
      }
    }

    if (!accepted) {
      deid_abort(
        code = "PREVIEW_TOKEN_GENERATION_FAILED",
        message = "Unique structured preview tokens could not be generated.",
        subclass = "deid_preview_error"
      )
    }
  }

  output
}


create_preview_token_bundle <- function(
    source,
    config,
    token_factory = secure_random_hex_token
) {
  id_columns <- config$policy$preview$structured_id$columns
  configured_columns <- schema_columns(config)
  direct_identifier_columns <- configured_columns$name[
    configured_columns$role == "direct_identifier"
  ]
  values <- stats::setNames(
    lapply(id_columns, function(column) rep(NA_character_, nrow(source))),
    id_columns
  )
  positions <- data.frame(
    column = character(),
    row = integer(),
    stringsAsFactors = FALSE
  )

  for (column in id_columns) {
    present <- which(!is.na(source[[column]]))
    if (length(present) > 0L) {
      positions <- rbind(
        positions,
        data.frame(
          column = rep(column, length(present)),
          row = present,
          stringsAsFactors = FALSE
        )
      )
    }
  }

  tokens <- generate_run_scoped_hex_ids(
    count = nrow(positions),
    deny_values = unlist(
      source[direct_identifier_columns],
      use.names = FALSE
    ),
    token_factory = token_factory
  )
  for (index in seq_len(nrow(positions))) {
    values[[positions$column[[index]]]][[positions$row[[index]]]] <-
      tokens[[index]]
  }

  structure(
    list(
      mode = config$policy$preview$structured_id$mode,
      length = config$policy$preview$structured_id$length,
      columns = id_columns,
      values = values
    ),
    class = c("PreviewTokenBundle", "list")
  )
}


validate_preview_token_bundle <- function(bundle, source, config) {
  specification <- config$policy$preview$structured_id
  configured_columns <- schema_columns(config)
  direct_identifier_columns <- configured_columns$name[
    configured_columns$role == "direct_identifier"
  ]
  valid_shape <- inherits(bundle, "PreviewTokenBundle") &&
    identical(bundle$mode, specification$mode) &&
    identical(as.integer(bundle$length), as.integer(specification$length)) &&
    identical(bundle$columns, specification$columns) &&
    is.list(bundle$values) &&
    identical(names(bundle$values), specification$columns)

  if (!valid_shape) {
    deid_abort(
      code = "INVALID_PREVIEW_TOKEN_BUNDLE",
      message = "Structured preview tokens are missing or invalid.",
      subclass = "deid_preview_error"
    )
  }

  for (column in specification$columns) {
    tokens <- bundle$values[[column]]
    present <- !is.na(source[[column]])
    if (
      !is.character(tokens) ||
      length(tokens) != nrow(source) ||
      !identical(!is.na(tokens), present) ||
      any(!grepl("^[0-9a-f]{8}$", tokens[present], perl = TRUE))
    ) {
      deid_abort(
        code = "INVALID_PREVIEW_TOKEN_BUNDLE",
        message = "Structured preview tokens failed format or alignment validation.",
        subclass = "deid_preview_error"
      )
    }
  }

  tokens <- unlist(bundle$values, use.names = FALSE)
  tokens <- tokens[!is.na(tokens)]
  source_values <- tolower(trimws(as.character(unlist(
    source[direct_identifier_columns],
    use.names = FALSE
  ))))
  source_values <- source_values[!is.na(source_values) & nzchar(source_values)]
  if (anyDuplicated(tokens) || any(tokens %in% source_values)) {
    deid_abort(
      code = "INVALID_PREVIEW_TOKEN_BUNDLE",
      message = "Structured preview tokens are duplicated or conflict with source identifiers.",
      subclass = "deid_preview_error"
    )
  }

  invisible(TRUE)
}


known_name_variants <- function(value) {
  if (is.na(value) || !nzchar(trimws(value))) {
    return(character())
  }

  words <- strsplit(trimws(value), "[[:space:]]+", perl = TRUE)[[1]]
  variants <- trimws(value)
  if (length(words) >= 2L) {
    variants <- c(variants, paste(words[c(1L, length(words))], collapse = " "))
  }
  variants <- unique(variants[nzchar(variants)])
  variants[order(nchar(variants), decreasing = TRUE)]
}


validated_date_candidates <- function(value, type) {
  date_part <- sub(
    " ([0-2][0-9]):[0-5][0-9](:[0-5][0-9])?( [A-Za-z]{3})?$",
    "",
    value,
    perl = TRUE
  )

  day_month_name_candidates <- function(value) {
    separator <- if (grepl("/", value, fixed = TRUE)) "/" else "-"
    year <- sub(".*[-/]", "", value)
    year_format <- if (nchar(year) == 2L) "%y" else "%Y"
    c(
      safe_as_date(
        value,
        paste0("%d", separator, "%b", separator, year_format)
      ),
      safe_as_date(
        value,
        paste0("%d", separator, "%B", separator, year_format)
      )
    )
  }

  month_day_value <- sub(
    "([0-9])(?:st|nd|rd|th)",
    "\\1",
    date_part,
    ignore.case = TRUE,
    perl = TRUE
  )

  candidates <- switch(
    type,
    iso = safe_as_date(substr(date_part, 1L, 10L), "%Y-%m-%d"),
    numeric = parse_supported_dob(date_part),
    day_month_name = day_month_name_candidates(date_part),
    month_day = c(
      safe_as_date(month_day_value, "%B %d, %Y"),
      safe_as_date(month_day_value, "%b %d, %Y"),
      safe_as_date(month_day_value, "%B %d %Y"),
      safe_as_date(month_day_value, "%b %d %Y")
    ),
    deid_abort(
      code = "UNSUPPORTED_PREVIEW_DATE_TYPE",
      message = "A narrative date rule is not configured correctly.",
      subclass = "deid_preview_error"
    )
  )

  candidates <- unique(candidates[!is.na(candidates)])
  if (length(candidates) == 0L) {
    deid_abort(
      code = "INVALID_NARRATIVE_DATE",
      message = "Narrative text contains an unsupported or impossible date.",
      subclass = "deid_preview_error"
    )
  }

  candidates
}


validated_date_year <- function(value, type) {
  candidates <- validated_date_candidates(value, type)
  years <- unique(format(candidates, "%Y"))
  if (length(years) != 1L) {
    deid_abort(
      code = "AMBIGUOUS_NARRATIVE_DATE_YEAR",
      message = "Narrative text contains a date with an ambiguous year.",
      subclass = "deid_preview_error"
    )
  }
  years[[1]]
}


date_preview_tag <- function(value, type, config) {
  year <- validated_date_year(value, type)
  sub(
    "{year}",
    year,
    preview_tag(config, "date"),
    fixed = TRUE
  )
}


birth_date_preview_tag <- function(value, type, config) {
  candidates <- validated_date_candidates(value, type)
  reference_date <- as.Date(config$policy$reference_date)

  if (any(candidates > reference_date)) {
    deid_abort(
      code = "FUTURE_NARRATIVE_DOB",
      message = "Narrative text contains a future date of birth.",
      subclass = "deid_preview_error"
    )
  }

  ages <- vapply(
    candidates,
    age_on_date,
    integer(1),
    reference_date = reference_date
  )
  if (all(ages >= 90L)) {
    return(preview_tag(config, "age_90_or_older"))
  }
  if (all(ages < 90L)) {
    return(date_preview_tag(value, type, config))
  }

  deid_abort(
    code = "AMBIGUOUS_NARRATIVE_AGE_90_STATUS",
    message = "A narrative date of birth crosses the age-90 threshold.",
    subclass = "deid_preview_error"
  )
}


birth_year_preview_tag <- function(year, config) {
  year <- suppressWarnings(as.integer(year))
  reference_year <- as.integer(format(
    as.Date(config$policy$reference_date),
    "%Y"
  ))
  if (is.na(year) || year > reference_year) {
    deid_abort(
      code = "INVALID_NARRATIVE_BIRTH_YEAR",
      message = "Narrative text contains an invalid birth year.",
      subclass = "deid_preview_error"
    )
  }

  if (year <= reference_year - 90L) {
    return(preview_tag(config, "age_90_or_older"))
  }

  sub(
    "{year}",
    as.character(year),
    preview_tag(config, "date"),
    fixed = TRUE
  )
}


redact_narrative_text <- function(
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
    return(NA_character_)
  }
  if (!is.character(text) || length(text) != 1L) {
    deid_abort(
      code = "INVALID_NARRATIVE_VALUE",
      message = "Narrative preview input must be one character value.",
      subclass = "deid_preview_error"
    )
  }

  buffer <- new_tag_buffer(text)

  url_pattern <- paste0(
    "(?:\\b(?:https?|ftp)://|\\bwww\\.)",
    "[^[:space:]<>{}\\[\\]\"']*[A-Za-z0-9/#]"
  )
  email_pattern <- paste0(
    "(?<![A-Z0-9._%+\\-])",
    "[A-Z0-9._%+\\-]+@[A-Z0-9\\-]+",
    "(?:\\.[A-Z0-9\\-]+)+",
    "(?![A-Z0-9_%+\\-])"
  )
  ipv4_pattern <- paste0(
    "(?<![0-9])",
    "(?:(?:25[0-5]|2[0-4][0-9]|1[0-9]{2}|[1-9]?[0-9])\\.){3}",
    "(?:25[0-5]|2[0-4][0-9]|1[0-9]{2}|[1-9]?[0-9])",
    "(?![0-9])"
  )

  buffer <- replace_regex_tag(
    buffer,
    url_pattern,
    preview_tag(config, "url"),
    ignore_case = TRUE
  )
  buffer <- replace_regex_tag(
    buffer,
    email_pattern,
    preview_tag(config, "email"),
    ignore_case = TRUE
  )
  for (value in normalize_known_values(known_mrn, known_mrns)) {
    buffer <- replace_known_value(
      buffer,
      value,
      preview_tag(config, "medical_record_number")
    )
  }
  for (value in normalize_known_values(known_patient_id, known_patient_ids)) {
    buffer <- replace_known_value(
      buffer,
      value,
      preview_tag(config, "other_unique_identifier")
    )
  }
  buffer <- replace_regex_tag(
    buffer,
    ipv4_pattern,
    preview_tag(config, "ip_address")
  )

  buffer <- replace_regex_tag(
    buffer,
    "(?<![0-9])[0-9]{3}[- ][0-9]{2}[- ][0-9]{4}(?![0-9])",
    preview_tag(config, "ssn")
  )

  phone_core <- paste0(
    "(?:",
    "\\+[0-9]{1,3}(?:[-. ]*\\(?[0-9]{1,5}\\)?){2,4}",
    "|(?:(?:\\+?1)[-. ]*)?",
    "(?:\\([0-9]{3}\\)|[0-9]{3})[-. ]*[0-9]{3}[-. ]*[0-9]{4}",
    ")",
    "(?:\\s*(?:(?:ext(?:ension)?\\.?|x)\\s*|#\\s*)[0-9]{1,6})?"
  )
  buffer <- replace_regex_tag(
    buffer,
    paste0(
      "\\bfax(?:\\s+(?:number|no\\.?))?\\s*[:#-]?\\s*",
      phone_core
    ),
    preview_tag(config, "fax_number"),
    ignore_case = TRUE
  )
  buffer <- replace_regex_tag(
    buffer,
    paste0(
      "(?<![A-Za-z0-9])",
      phone_core,
      "(?![A-Za-z0-9])"
    ),
    preview_tag(config, "telephone_number")
  )

  age_number <- "(?:9[0-9]|[1-9][0-9]{2,})"
  age_units <- paste0(
    "(?:(?:years?|yrs?)(?:[-[:space:]]*old|",
    "[[:space:]]+of[[:space:]]+age)",
    "|y[[:space:]]*\\.?[[:space:]]*o\\.?)"
  )
  age_pattern <- paste0(
    "\\b(?:",
    "aged?\\s*[:=]?\\s*(?:(?:is|was)\\s*)?",
    age_number,
    "(?:[-[:space:]]*",
    age_units,
    ")?",
    "|",
    age_number,
    "[-[:space:]]*",
    age_units,
    ")(?=$|[^[:alnum:]_])"
  )
  buffer <- replace_regex_tag(
    buffer,
    age_pattern,
    preview_tag(config, "age_90_or_older"),
    ignore_case = TRUE
  )

  time_suffix <- "(?:\\s+(?:[01][0-9]|2[0-3]):[0-5][0-9](?::[0-5][0-9])?(?:\\s+[A-Za-z]{3})?)?"
  date_rules <- list(
    list(
      type = "month_day",
      pattern = paste0(
        "\\b(?:January|February|March|April|May|June|July|August|",
        "September|October|November|December|Jan|Feb|Mar|Apr|Jun|",
        "Jul|Aug|Sep|Sept|Oct|Nov|Dec)\\s+",
        "[0-9]{1,2}(?:st|nd|rd|th)?,?\\s+[12][0-9]{3}",
        time_suffix,
        "\\b"
      )
    ),
    list(
      type = "day_month_name",
      pattern = paste0(
        "\\b[0-9]{1,2}[-/]",
        "(?:January|February|March|April|May|June|July|August|",
        "September|October|November|December|Jan|Feb|Mar|Apr|Jun|",
        "Jul|Aug|Sep|Sept|Oct|Nov|Dec)[-/]",
        "(?:[0-9]{2}|[12][0-9]{3})",
        time_suffix,
        "\\b"
      )
    ),
    list(
      type = "iso",
      pattern = paste0(
        "\\b[12][0-9]{3}-[0-9]{2}-[0-9]{2}",
        time_suffix,
        "\\b"
      )
    ),
    list(
      type = "numeric",
      pattern = paste0(
        "\\b[0-9]{1,2}[-/][0-9]{1,2}[-/][12][0-9]{3}",
        time_suffix,
        "\\b"
      )
    )
  )
  month_year_pattern <- paste0(
    "\\b(?:January|February|March|April|May|June|July|August|",
    "September|October|November|December|Jan|Feb|Mar|Apr|Jun|",
    "Jul|Aug|Sep|Sept|Oct|Nov|Dec)\\s+[12][0-9]{3}\\b"
  )

  birth_context <- paste0(
    "\\b(?:DOB|date\\s+of\\s+birth|birth\\s*date|",
    "year\\s+of\\s+birth|born(?:\\s+(?:on|in))?)",
    "\\s*[:=-]?\\s*(?:(?:is|was)\\s*)?[:=-]?\\s*"
  )
  for (rule in date_rules) {
    callback <- local({
      type <- rule$type
      function(value) {
        date_value <- sub(
          birth_context,
          "",
          value,
          ignore.case = TRUE,
          perl = TRUE
        )
        birth_date_preview_tag(date_value, type, config)
      }
    })
    buffer <- replace_regex_callback(
      buffer,
      paste0(birth_context, rule$pattern),
      callback,
      ignore_case = TRUE
    )
  }

  buffer <- replace_regex_callback(
    buffer,
    paste0(birth_context, month_year_pattern),
    function(value) {
      year <- regmatches(
        value,
        regexpr("[12][0-9]{3}", value, perl = TRUE)
      )
      birth_year_preview_tag(year, config)
    },
    ignore_case = TRUE
  )
  buffer <- replace_regex_callback(
    buffer,
    paste0(birth_context, "\\b[12][0-9]{3}\\b"),
    function(value) {
      year <- regmatches(
        value,
        regexpr("[12][0-9]{3}", value, perl = TRUE)
      )
      birth_year_preview_tag(year, config)
    },
    ignore_case = TRUE
  )

  for (rule in date_rules) {
    callback <- local({
      type <- rule$type
      function(value) date_preview_tag(value, type, config)
    })
    buffer <- replace_regex_callback(
      buffer,
      rule$pattern,
      callback,
      ignore_case = TRUE
    )
  }

  buffer <- replace_regex_callback(
    buffer,
    month_year_pattern,
    function(value) {
      year <- regmatches(
        value,
        regexpr("[12][0-9]{3}", value, perl = TRUE)
      )
      sub("{year}", year, preview_tag(config, "date"), fixed = TRUE)
    },
    ignore_case = TRUE
  )

  identifier_value <- "[A-Z0-9][A-Z0-9._/-]{2,}"
  contextual_rules <- list(
    list(
      pattern = paste0(
        "\\b(?:MRN|medical\\s+record\\s+(?:number|no\\.?)|",
        "record\\s+(?:number|no\\.?))\\b\\s*(?:was|is)?",
        "\\s*[:#-]?\\s*(?!(?:was|is)\\b)",
        identifier_value,
        "\\b"
      ),
      tag = "medical_record_number"
    ),
    list(
      pattern = paste0(
        "\\b(?:member|beneficiary|insurance|policy)\\s+",
        "(?:ID|number|no\\.?)\\b\\s*(?:was|is)?\\s*[:#-]?\\s*",
        "(?!(?:was|is)\\b)",
        identifier_value,
        "\\b"
      ),
      tag = "health_plan_number"
    ),
    list(
      pattern = paste0(
        "\\b(?:billing\\s+)?account\\s+(?:ID|number|no\\.?)",
        "\\b\\s*(?:was|is)?\\s*[:#-]?\\s*(?!(?:was|is)\\b)",
        identifier_value,
        "\\b"
      ),
      tag = "account_number"
    ),
    list(
      pattern = paste0(
        "\\b(?:certificate|licen[cs]e|driver'?s\\s+licen[cs]e)\\s+",
        "(?:ID|number|no\\.?)\\b\\s*(?:was|is)?\\s*[:#-]?\\s*",
        "(?!(?:was|is)\\b)",
        identifier_value,
        "\\b"
      ),
      tag = "certificate_license_number"
    ),
    list(
      pattern = paste0(
        "\\b(?:VIN|vehicle\\s+(?:ID|serial)|license\\s+plate)",
        "\\b\\s*(?:was|is)?\\s*[:#-]?\\s*(?!(?:was|is)\\b)",
        identifier_value,
        "\\b"
      ),
      tag = "vehicle_identifier"
    ),
    list(
      pattern = paste0(
        "\\b(?:device|implant|pacemaker|UDI)\\s+",
        "(?:ID|identifier|serial|number|no\\.?)\\b",
        "\\s*(?:was|is)?\\s*[:#-]?\\s*(?!(?:was|is)\\b)",
        identifier_value,
        "\\b"
      ),
      tag = "device_identifier"
    ),
    list(
      pattern = paste0(
        "\\b(?:patient|subject|participant)\\s+",
        "(?:ID|identifier|code)\\b\\s*(?:was|is)?\\s*[:#-]?\\s*",
        "(?!(?:was|is)\\b)",
        identifier_value,
        "\\b"
      ),
      tag = "other_unique_identifier"
    ),
    list(
      pattern = paste0(
        "\\b(?:biometric|fingerprint|voiceprint|retinal|iris)\\s+",
        "(?:ID|identifier|template|code)\\b",
        "\\s*(?:was|is)?\\s*[:#-]?\\s*(?!(?:was|is)\\b)",
        identifier_value,
        "\\b"
      ),
      tag = "biometric_identifier"
    )
  )
  for (rule in contextual_rules) {
    buffer <- replace_regex_tag(
      buffer,
      rule$pattern,
      preview_tag(config, rule$tag),
      ignore_case = TRUE
    )
  }

  address_pattern <- paste0(
    "\\b[0-9]{1,6}\\s+",
    "(?:[A-Z0-9][A-Za-z0-9.'-]*\\s+){0,6}",
    "(?:Street|St\\.?|Avenue|Ave\\.?|Road|Rd\\.?|Boulevard|",
    "Blvd\\.?|Lane|Ln\\.?|Drive|Dr\\.?|Court|Ct\\.?|Way|",
    "Parkway|Pkwy\\.?)",
    "(?:,\\s*[A-Z][A-Za-z.'-]*(?:\\s+[A-Z][A-Za-z.'-]*){0,3})?",
    "(?:,\\s*(?:[A-Z]{2}|[A-Z][a-z]+))?",
    "(?:\\s+[0-9]{5}(?:-[0-9]{4})?)?\\b"
  )
  buffer <- replace_regex_tag(
    buffer,
    address_pattern,
    preview_tag(config, "geographic_subdivision")
  )
  buffer <- replace_regex_tag(
    buffer,
    "(?<![0-9])[0-9]{5}(?:-[0-9]{4})?(?![0-9])",
    preview_tag(config, "zip_code")
  )

  facility_pattern <- paste0(
    "\\b(?:[A-Z][A-Za-z&.'-]*\\s+){0,6}",
    "(?:Hospital|Hospitals|Clinic|Medical\\s+Center|",
    "Cancer\\s+Center|Health\\s+Care)\\b"
  )
  buffer <- replace_regex_tag(
    buffer,
    facility_pattern,
    preview_tag(config, "facility")
  )

  clinician_name_pattern <- paste0(
    "\\b(?:Dr\\.|Doctor)\\s+",
    "[A-Z][A-Za-z'-]+(?:\\s+[A-Z][A-Za-z'-]+){0,2}\\b"
  )
  buffer <- replace_regex_tag(
    buffer,
    clinician_name_pattern,
    preview_tag(config, "name")
  )

  name_values <- normalize_known_values(known_name, known_names)
  variants <- unique(unlist(
    lapply(name_values, known_name_variants),
    use.names = FALSE
  ))
  variants <- variants[order(nchar(variants), decreasing = TRUE)]
  for (variant in variants) {
    buffer <- replace_known_value(
      buffer,
      variant,
      preview_tag(config, "name")
    )
  }

  if (!is.na(known_name) && nzchar(trimws(known_name))) {
    first_name <- strsplit(trimws(known_name), "[[:space:]]+", perl = TRUE)[[1]][1]
    first_pattern <- paste0("^", escape_regex_literal(first_name), "\\b")
    buffer <- replace_regex_tag(
      buffer,
      first_pattern,
      preview_tag(config, "name"),
      ignore_case = TRUE
    )
  }

  location_pattern <- paste0(
    "\\b(?:in|from)\\s+",
    "[A-Z][a-z]+(?:\\s+[A-Z][a-z]+){0,2}",
    "(?=,|\\s+where\\b|\\s+and\\b|[.]|$)"
  )
  buffer <- replace_regex_tag(
    buffer,
    location_pattern,
    preview_tag(config, "geographic_subdivision")
  )

  restore_preview_tags(buffer)
}


create_tagged_preview <- function(
    run,
    config = read_deid_config(".")
) {
  if (is.null(run$result) || !inherits(run$result, "StructuredResult")) {
    return(NULL)
  }
  if (
    is.null(run$schema_validation) ||
    !inherits(run$schema_validation, "SchemaValidation")
  ) {
    deid_abort(
      code = "PREVIEW_SOURCE_MISSING",
      message = "Validated source data are unavailable for tagged preview.",
      subclass = "deid_preview_error"
    )
  }

  preview <- run$result$data
  source <- run$schema_validation$data
  validate_preview_token_bundle(run$preview_tokens, source, config)
  for (column in config$policy$preview$structured_id$columns) {
    preview[[column]] <- run$preview_tokens$values[[column]]
  }

  present_names <- !is.na(source$Patient_Name) &
    nzchar(trimws(source$Patient_Name))
  preview$Patient_Name <- rep(NA_character_, nrow(preview))
  preview$Patient_Name[present_names] <- preview_tag(config, "name")

  present_dob <- !is.na(source$DOB) & nzchar(trimws(source$DOB))
  preview$DOB <- rep(NA_character_, nrow(preview))
  for (row in which(present_dob)) {
    generalized <- run$result$data$DOB[[row]]
    preview$DOB[[row]] <- if (identical(
      generalized,
      config$policy$age_90_plus_value
    )) {
      preview_tag(config, "age_90_or_older")
    } else {
      sub(
        "{year}",
        generalized,
        preview_tag(config, "date"),
        fixed = TRUE
      )
    }
  }

  narrative_columns <- schema_columns(config)$name[
    schema_columns(config)$role == "free_text"
  ]
  failure_placeholder <- config$policy$preview$failure_placeholder
  global_names <- normalize_known_values(source$Patient_Name)
  global_mrns <- normalize_known_values(source$MRN)
  global_patient_ids <- normalize_known_values(source$Patient_ID)

  for (column in narrative_columns) {
    preview[[column]] <- vapply(
      seq_len(nrow(source)),
      function(row) {
        value <- source[[column]][[row]]
        if (is.na(value)) {
          return(NA_character_)
        }

        tryCatch(
          redact_narrative_text(
            text = value,
            known_name = source$Patient_Name[[row]],
            known_mrn = source$MRN[[row]],
            known_patient_id = source$Patient_ID[[row]],
            config = config,
            known_names = global_names,
            known_mrns = global_mrns,
            known_patient_ids = global_patient_ids
          ),
          error = function(e) failure_placeholder
        )
      },
      character(1)
    )
  }

  preview
}
