normalize_azure_endpoint <- function(endpoint) {
  assert_scalar_character(endpoint, "endpoint")
  endpoint <- sub("/+$", "", trimws(endpoint))

  if (
    !grepl("^https://[^/?#@]+$", endpoint, perl = TRUE) ||
    !nzchar(sub("^https://", "", endpoint))
  ) {
    deid_abort(
      code = "INVALID_AZURE_ENDPOINT",
      message = paste(
        "Azure endpoint must be an HTTPS origin without credentials, query,",
        "fragment, or path."
      ),
      subclass = "deid_azure_error"
    )
  }

  endpoint
}


assert_positive_integer <- function(value, name, allow_zero = FALSE) {
  if (
    length(value) != 1L ||
    is.na(value) ||
    !is.numeric(value) ||
    !is.finite(value) ||
    value != as.integer(value) ||
    value < if (allow_zero) 0L else 1L
  ) {
    deid_abort(
      code = "INVALID_AZURE_CLIENT_CONFIGURATION",
      message = paste0(name, " must be ", if (allow_zero) {
        "a non-negative"
      } else {
        "a positive"
      }, " whole number."),
      subclass = "deid_azure_error"
    )
  }

  as.integer(value)
}


assert_non_negative_number <- function(value, name) {
  if (
    length(value) != 1L ||
    is.na(value) ||
    !is.numeric(value) ||
    !is.finite(value) ||
    value < 0
  ) {
    deid_abort(
      code = "INVALID_AZURE_CLIENT_CONFIGURATION",
      message = paste0(name, " must be one non-negative number."),
      subclass = "deid_azure_error"
    )
  }

  as.numeric(value)
}


new_azure_pii_client <- function(
    endpoint,
    token_provider,
    api_version = "2026-05-01",
    model_version = "2026-05-01",
    request_timeout_seconds = 60,
    max_attempts = 3,
    initial_retry_seconds = 1,
    max_poll_attempts = 60,
    poll_interval_seconds = 1,
    request_transport = azure_curl_transport,
    sleep_function = Sys.sleep
) {
  endpoint <- normalize_azure_endpoint(endpoint)
  assert_scalar_character(api_version, "api_version")
  assert_scalar_character(model_version, "model_version")

  if (!identical(api_version, "2026-05-01")) {
    deid_abort(
      code = "UNSUPPORTED_AZURE_API_VERSION",
      message = "Only the reviewed 2026-05-01 Azure Text PII API is supported.",
      subclass = "deid_azure_error"
    )
  }
  if (!identical(model_version, "2026-05-01")) {
    deid_abort(
      code = "UNSUPPORTED_AZURE_MODEL_VERSION",
      message = "Only the reviewed 2026-05-01 Azure Text PII model is supported.",
      subclass = "deid_azure_error"
    )
  }
  if (!is.function(token_provider)) {
    deid_abort(
      code = "INVALID_AZURE_TOKEN_PROVIDER",
      message = "token_provider must be a function that returns an Entra access token.",
      subclass = "deid_azure_error"
    )
  }
  if (!is.function(request_transport) || !is.function(sleep_function)) {
    deid_abort(
      code = "INVALID_AZURE_CLIENT_CONFIGURATION",
      message = "request_transport and sleep_function must be functions.",
      subclass = "deid_azure_error"
    )
  }

  client <- list(
    endpoint = endpoint,
    api_version = api_version,
    model_version = model_version,
    request_timeout_seconds = assert_positive_integer(
      request_timeout_seconds,
      "request_timeout_seconds"
    ),
    max_attempts = assert_positive_integer(max_attempts, "max_attempts"),
    initial_retry_seconds = assert_non_negative_number(
      initial_retry_seconds,
      "initial_retry_seconds"
    ),
    max_poll_attempts = assert_positive_integer(
      max_poll_attempts,
      "max_poll_attempts"
    ),
    poll_interval_seconds = assert_non_negative_number(
      poll_interval_seconds,
      "poll_interval_seconds"
    ),
    token_provider = token_provider,
    request_transport = request_transport,
    sleep_function = sleep_function
  )
  class(client) <- c("AzurePiiClient", "list")
  client
}


new_configured_azure_pii_client <- function(
    config,
    endpoint,
    token_provider,
    request_transport = azure_curl_transport,
    sleep_function = Sys.sleep
) {
  if (!inherits(config, "DeidConfig")) {
    deid_abort(
      code = "INVALID_CONFIG",
      message = "A validated DeidConfig is required for Azure processing.",
      subclass = "deid_azure_error"
    )
  }

  validate_deid_config(config)
  azure <- config$runtime$azure
  if (!isTRUE(azure$enabled)) {
    deid_abort(
      code = "AZURE_PROCESSING_DISABLED",
      message = "Azure processing remains disabled by the synthetic-only runtime configuration.",
      subclass = "deid_governance_error"
    )
  }

  new_azure_pii_client(
    endpoint = endpoint,
    token_provider = token_provider,
    api_version = azure$api_version,
    model_version = azure$model_version,
    request_timeout_seconds = azure$request_timeout_seconds,
    max_attempts = azure$max_attempts,
    initial_retry_seconds = azure$initial_retry_seconds,
    max_poll_attempts = azure$max_poll_attempts,
    poll_interval_seconds = azure$poll_interval_seconds,
    request_transport = request_transport,
    sleep_function = sleep_function
  )
}


normalize_azure_documents <- function(documents) {
  if (!is.data.frame(documents) || !identical(names(documents), c("id", "text"))) {
    deid_abort(
      code = "INVALID_AZURE_DOCUMENTS",
      message = "documents must be a data frame with exactly id and text columns.",
      subclass = "deid_azure_error"
    )
  }
  if (nrow(documents) == 0L) {
    deid_abort(
      code = "INVALID_AZURE_DOCUMENTS",
      message = "At least one document is required for Azure PII processing.",
      subclass = "deid_azure_error"
    )
  }

  ids <- as.character(documents$id)
  texts <- as.character(documents$text)
  if (
    anyNA(ids) ||
    any(!nzchar(ids)) ||
    anyDuplicated(ids) ||
    anyNA(texts) ||
    any(!nzchar(texts))
  ) {
    deid_abort(
      code = "INVALID_AZURE_DOCUMENTS",
      message = paste(
        "Each Azure document requires a unique non-empty id and a non-empty",
        "non-missing text value."
      ),
      subclass = "deid_azure_error"
    )
  }

  data.frame(id = ids, text = texts, stringsAsFactors = FALSE)
}


build_azure_pii_job <- function(client, documents) {
  if (!inherits(client, "AzurePiiClient")) {
    deid_abort(
      code = "INVALID_AZURE_CLIENT",
      message = "An AzurePiiClient is required.",
      subclass = "deid_azure_error"
    )
  }

  documents <- normalize_azure_documents(documents)
  api_documents <- lapply(
    seq_len(nrow(documents)),
    function(row) {
      list(
        id = documents$id[[row]],
        language = "en",
        text = documents$text[[row]]
      )
    }
  )

  list(
    displayName = "clinical-deidentification-pii",
    analysisInput = list(documents = api_documents),
    tasks = list(list(
      kind = "PiiEntityRecognition",
      taskName = "clinical-deidentification-pii",
      parameters = list(
        disableEntityValidation = FALSE,
        domain = "none",
        loggingOptOut = TRUE,
        modelVersion = client$model_version,
        piiCategories = list("All"),
        redactionPolicies = list(list(
          policyKind = "entityMask",
          isDefault = TRUE,
          policyName = "clinical-deidentification-pii"
        )),
        stringIndexType = "UnicodeCodePoint"
      )
    ))
  )
}


azure_submission_url <- function(client) {
  paste0(
    client$endpoint,
    "/language/analyze-text/jobs?api-version=",
    utils::URLencode(client$api_version, reserved = TRUE)
  )
}


azure_authorization_header <- function(client) {
  token <- tryCatch(
    client$token_provider(),
    error = function(e) NULL
  )
  if (!is.character(token) || length(token) != 1L || is.na(token) || !nzchar(token)) {
    deid_abort(
      code = "AZURE_ACCESS_TOKEN_UNAVAILABLE",
      message = "The configured Entra token provider did not return an access token.",
      subclass = "deid_azure_authentication_error"
    )
  }

  paste("Bearer", token)
}


azure_curl_transport <- function(request) {
  require_deid_namespace("curl")
  handle <- curl::new_handle()
  curl::handle_setopt(
    handle,
    customrequest = request$method,
    timeout = request$timeout_seconds,
    followlocation = FALSE
  )
  curl::handle_setheaders(handle, .list = request$headers)
  if (!is.null(request$body)) {
    curl::handle_setopt(handle, postfields = request$body)
  }

  response <- curl::curl_fetch_memory(request$url, handle = handle)
  headers <- curl::parse_headers(rawToChar(response$headers))
  list(
    status_code = response$status_code,
    headers = as.list(headers),
    body = rawToChar(response$content)
  )
}


response_header <- function(response, name) {
  headers <- response$headers
  if (is.null(headers) || length(headers) == 0L) {
    return(NULL)
  }

  matches <- which(tolower(names(headers)) == tolower(name))
  if (length(matches) == 0L) {
    return(NULL)
  }
  as.character(headers[[matches[[1]]]])
}


validate_azure_response <- function(response) {
  if (
    !is.list(response) ||
    length(response$status_code) != 1L ||
    is.na(response$status_code) ||
    !is.numeric(response$status_code) ||
    is.null(response$headers) ||
    !is.list(response$headers) ||
    !is.character(response$body) ||
    length(response$body) != 1L ||
    is.na(response$body)
  ) {
    deid_abort(
      code = "INVALID_AZURE_RESPONSE",
      message = "Azure transport returned an invalid response structure.",
      subclass = "deid_azure_error"
    )
  }

  response$status_code <- as.integer(response$status_code)
  response
}


is_retryable_azure_status <- function(status_code) {
  status_code %in% c(408L, 429L, 500L, 502L, 503L, 504L)
}


azure_retry_delay <- function(client, response, attempt) {
  retry_after <- response_header(response, "Retry-After")
  retry_after_seconds <- suppressWarnings(as.numeric(retry_after))
  if (
    !is.na(retry_after_seconds) &&
    is.finite(retry_after_seconds) &&
    retry_after_seconds >= 0
  ) {
    return(retry_after_seconds)
  }

  client$initial_retry_seconds * (2 ^ (attempt - 1L))
}


perform_azure_request <- function(client, method, url, body = NULL) {
  assert_scalar_character(method, "method")
  assert_scalar_character(url, "url")
  if (!is.null(body) && !is.list(body)) {
    deid_abort(
      code = "INVALID_AZURE_REQUEST",
      message = "Azure request body must be NULL or a JSON-compatible list.",
      subclass = "deid_azure_error"
    )
  }

  for (attempt in seq_len(client$max_attempts)) {
    request <- list(
      method = method,
      url = url,
      headers = c(
        Authorization = azure_authorization_header(client),
        Accept = "application/json",
        `Content-Type` = "application/json"
      ),
      body = if (is.null(body)) {
        NULL
      } else {
        jsonlite::toJSON(body, auto_unbox = TRUE, null = "null")
      },
      timeout_seconds = client$request_timeout_seconds
    )
    response <- tryCatch(
      client$request_transport(request),
      error = function(e) NULL
    )

    if (is.null(response)) {
      if (attempt == client$max_attempts) {
        deid_abort(
          code = "AZURE_TRANSPORT_FAILED",
          message = "Azure request failed after the configured retry limit.",
          subclass = "deid_azure_error"
        )
      }
      client$sleep_function(client$initial_retry_seconds * (2 ^ (attempt - 1L)))
      next
    }

    response <- validate_azure_response(response)
    if (response$status_code >= 200L && response$status_code < 300L) {
      return(response)
    }
    if (
      !is_retryable_azure_status(response$status_code) ||
      attempt == client$max_attempts
    ) {
      deid_abort(
        code = "AZURE_REQUEST_FAILED",
        message = paste0(
          "Azure request failed with HTTP status ", response$status_code, "."
        ),
        subclass = "deid_azure_error"
      )
    }

    client$sleep_function(azure_retry_delay(client, response, attempt))
  }

  deid_abort(
    code = "AZURE_REQUEST_FAILED",
    message = "Azure request failed unexpectedly.",
    subclass = "deid_azure_error"
  )
}


validate_azure_operation_url <- function(client, operation_url) {
  assert_scalar_character(operation_url, "Operation-Location")
  expected_prefix <- paste0(client$endpoint, "/language/analyze-text/jobs/")
  expected_suffix <- paste0("?api-version=", client$api_version)
  if (
    !startsWith(operation_url, expected_prefix) ||
    !endsWith(operation_url, expected_suffix) ||
    grepl("[#@]", operation_url, perl = TRUE)
  ) {
    deid_abort(
      code = "INVALID_AZURE_OPERATION_LOCATION",
      message = "Azure returned an unexpected Operation-Location URL.",
      subclass = "deid_azure_error"
    )
  }

  operation_url
}


parse_azure_json <- function(body) {
  parsed <- tryCatch(
    jsonlite::fromJSON(body, simplifyVector = FALSE),
    error = function(e) NULL
  )
  if (!is.list(parsed)) {
    deid_abort(
      code = "INVALID_AZURE_RESPONSE",
      message = "Azure returned a response that was not valid JSON.",
      subclass = "deid_azure_error"
    )
  }

  parsed
}


normalize_azure_entity <- function(entity, document_id, source_text) {
  required_fields <- c("text", "category", "offset", "length", "confidenceScore")
  if (
    !is.list(entity) ||
    !all(required_fields %in% names(entity)) ||
    !is.character(entity$text) ||
    length(entity$text) != 1L ||
    is.na(entity$text) ||
    !is.character(entity$category) ||
    length(entity$category) != 1L ||
    is.na(entity$category) ||
    !is.numeric(entity$offset) ||
    length(entity$offset) != 1L ||
    !is.finite(entity$offset) ||
    entity$offset < 0 ||
    entity$offset != as.integer(entity$offset) ||
    !is.numeric(entity$length) ||
    length(entity$length) != 1L ||
    !is.finite(entity$length) ||
    entity$length <= 0 ||
    entity$length != as.integer(entity$length) ||
    !is.numeric(entity$confidenceScore) ||
    length(entity$confidenceScore) != 1L ||
    !is.finite(entity$confidenceScore) ||
    entity$confidenceScore < 0 ||
    entity$confidenceScore > 1
  ) {
    deid_abort(
      code = "INVALID_AZURE_ENTITY",
      message = "Azure returned an entity with an invalid span or confidence score.",
      subclass = "deid_azure_error"
    )
  }

  start <- as.integer(entity$offset)
  length <- as.integer(entity$length)
  end <- start + length
  if (end > nchar(source_text, type = "chars")) {
    deid_abort(
      code = "INVALID_AZURE_ENTITY",
      message = "Azure returned an entity span outside the requested document.",
      subclass = "deid_azure_error"
    )
  }

  expected_text <- substr(source_text, start + 1L, end)
  if (!identical(entity$text, expected_text)) {
    deid_abort(
      code = "INVALID_AZURE_ENTITY",
      message = "Azure entity text did not match the returned Unicode code-point span.",
      subclass = "deid_azure_error"
    )
  }

  data.frame(
    document_id = document_id,
    offset = start,
    length = length,
    text = entity$text,
    category = entity$category,
    subcategory = if (
      is.character(entity$subcategory) &&
      length(entity$subcategory) == 1L &&
      !is.na(entity$subcategory)
    ) {
      entity$subcategory
    } else {
      NA_character_
    },
    type = if (
      is.character(entity$type) &&
      length(entity$type) == 1L &&
      !is.na(entity$type)
    ) {
      entity$type
    } else {
      NA_character_
    },
    confidence_score = as.numeric(entity$confidenceScore),
    source = "azure",
    stringsAsFactors = FALSE
  )
}


normalize_azure_pii_results <- function(job, documents) {
  if (!is.list(job$tasks) || !is.list(job$tasks$items)) {
    deid_abort(
      code = "INVALID_AZURE_RESPONSE",
      message = "Azure job response did not include task results.",
      subclass = "deid_azure_error"
    )
  }

  task_matches <- vapply(
    job$tasks$items,
    function(task) {
      is.list(task) &&
        identical(task$kind, "PiiEntityRecognitionLROResults") &&
        identical(task$taskName, "clinical-deidentification-pii")
    },
    logical(1)
  )
  if (sum(task_matches) != 1L) {
    deid_abort(
      code = "INVALID_AZURE_RESPONSE",
      message = "Azure job response did not include exactly one PII task result.",
      subclass = "deid_azure_error"
    )
  }

  task <- job$tasks$items[[which(task_matches)[[1]]]]
  if (!identical(task$status, "succeeded") || !is.list(task$results)) {
    deid_abort(
      code = "AZURE_JOB_FAILED",
      message = "Azure PII task did not complete successfully.",
      subclass = "deid_azure_error"
    )
  }
  if (
    !is.character(task$results$modelVersion) ||
    length(task$results$modelVersion) != 1L ||
    is.na(task$results$modelVersion) ||
    !identical(task$results$modelVersion, "2026-05-01")
  ) {
    deid_abort(
      code = "UNEXPECTED_AZURE_MODEL_VERSION",
      message = "Azure returned an unexpected PII model version.",
      subclass = "deid_azure_error"
    )
  }
  if (
    !is.list(task$results$documents) ||
    !is.list(task$results$errors) ||
    length(task$results$errors) > 0L
  ) {
    deid_abort(
      code = "AZURE_DOCUMENT_PROCESSING_FAILED",
      message = "Azure did not return successful results for every requested document.",
      subclass = "deid_azure_error"
    )
  }

  returned_ids <- vapply(
    task$results$documents,
    function(document) {
      if (!is.list(document) || !is.character(document$id) || length(document$id) != 1L) {
        deid_abort(
          code = "INVALID_AZURE_RESPONSE",
          message = "Azure returned a document without a valid id.",
          subclass = "deid_azure_error"
        )
      }
      document$id
    },
    character(1)
  )
  if (
    anyDuplicated(returned_ids) ||
    !identical(sort(returned_ids), sort(documents$id))
  ) {
    deid_abort(
      code = "AZURE_DOCUMENT_SET_MISMATCH",
      message = "Azure document result ids did not match the submitted batch.",
      subclass = "deid_azure_error"
    )
  }

  document_rows <- vector("list", length(task$results$documents))
  entity_rows <- list()
  entity_index <- 0L
  for (index in seq_along(task$results$documents)) {
    document <- task$results$documents[[index]]
    document_id <- document$id
    source_text <- documents$text[match(document_id, documents$id)]
    if (
      !is.character(document$redactedText) ||
      length(document$redactedText) != 1L ||
      is.na(document$redactedText) ||
      !is.list(document$entities)
    ) {
      deid_abort(
        code = "INVALID_AZURE_RESPONSE",
        message = "Azure returned an invalid PII document result.",
        subclass = "deid_azure_error"
      )
    }

    document_rows[[index]] <- data.frame(
      id = document_id,
      redacted_text = document$redactedText,
      stringsAsFactors = FALSE
    )
    for (entity in document$entities) {
      entity_index <- entity_index + 1L
      entity_rows[[entity_index]] <- normalize_azure_entity(
        entity,
        document_id = document_id,
        source_text = source_text
      )
    }
  }

  entities <- if (length(entity_rows) == 0L) {
    data.frame(
      document_id = character(),
      offset = integer(),
      length = integer(),
      text = character(),
      category = character(),
      subcategory = character(),
      type = character(),
      confidence_score = numeric(),
      source = character(),
      stringsAsFactors = FALSE
    )
  } else {
    do.call(rbind, entity_rows)
  }

  result <- list(
    model_version = task$results$modelVersion,
    documents = do.call(rbind, document_rows),
    entities = entities
  )
  class(result) <- c("AzurePiiResult", "list")
  result
}


analyze_azure_pii_batch <- function(client, documents) {
  if (!inherits(client, "AzurePiiClient")) {
    deid_abort(
      code = "INVALID_AZURE_CLIENT",
      message = "An AzurePiiClient is required.",
      subclass = "deid_azure_error"
    )
  }

  documents <- normalize_azure_documents(documents)
  submission <- perform_azure_request(
    client = client,
    method = "POST",
    url = azure_submission_url(client),
    body = build_azure_pii_job(client, documents)
  )
  if (!identical(submission$status_code, 202L)) {
    deid_abort(
      code = "INVALID_AZURE_SUBMISSION_RESPONSE",
      message = "Azure Text PII submission did not return HTTP 202.",
      subclass = "deid_azure_error"
    )
  }

  operation_url <- validate_azure_operation_url(
    client,
    response_header(submission, "Operation-Location")
  )
  for (attempt in seq_len(client$max_poll_attempts)) {
    poll <- perform_azure_request(
      client = client,
      method = "GET",
      url = operation_url
    )
    if (!identical(poll$status_code, 200L)) {
      deid_abort(
        code = "INVALID_AZURE_POLL_RESPONSE",
        message = "Azure Text PII polling did not return HTTP 200.",
        subclass = "deid_azure_error"
      )
    }

    job <- parse_azure_json(poll$body)
    job_status <- job$status
    if (
      !is.character(job_status) ||
      length(job_status) != 1L ||
      is.na(job_status)
    ) {
      deid_abort(
        code = "INVALID_AZURE_JOB_STATUS",
        message = "Azure returned an invalid Text PII job status.",
        subclass = "deid_azure_error"
      )
    }
    if (identical(job_status, "succeeded")) {
      return(normalize_azure_pii_results(job, documents))
    }
    if (job_status %in% c("failed", "cancelled", "cancelling")) {
      deid_abort(
        code = "AZURE_JOB_FAILED",
        message = "Azure Text PII job did not complete successfully.",
        subclass = "deid_azure_error"
      )
    }
    if (!identical(job_status, "notStarted") && !identical(job_status, "running")) {
      deid_abort(
        code = "INVALID_AZURE_JOB_STATUS",
        message = "Azure returned an unrecognized Text PII job status.",
        subclass = "deid_azure_error"
      )
    }
    if (attempt < client$max_poll_attempts) {
      client$sleep_function(client$poll_interval_seconds)
    }
  }

  deid_abort(
    code = "AZURE_JOB_POLL_TIMEOUT",
    message = "Azure Text PII job did not complete before the polling limit.",
    subclass = "deid_azure_error"
  )
}
