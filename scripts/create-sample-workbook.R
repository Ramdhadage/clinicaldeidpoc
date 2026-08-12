source(file.path("R", "bootstrap.R"))
activate_local_development_library(".")
load_deid_modules(".")

source_path <- "Clinical_PHI_Anonymization_Test_Data - Test_Data.csv"
target_directory <- file.path("runtime", "input")
target_path <- file.path(
  target_directory,
  "Clinical_PHI_Anonymization_Test_Data.xlsx"
)

if (!file.exists(source_path)) {
  stop("The supplied synthetic CSV fixture is missing.", call. = FALSE)
}

if (file.exists(target_path)) {
  stop(
    paste0(
      "The sample workbook already exists and will not be overwritten: ",
      target_path
    ),
    call. = FALSE
  )
}

dir.create(target_directory, recursive = TRUE, showWarnings = FALSE)
data <- utils::read.csv(
  source_path,
  stringsAsFactors = FALSE,
  check.names = FALSE
)

validation <- validate_clinical_schema(data, read_deid_config("."))
require_deid_namespace("writexl")
writexl::write_xlsx(
  list(Clinical_Data = validation$data),
  target_path
)

cat("Created synthetic sample workbook:\n")
cat(normalizePath(target_path, winslash = "/", mustWork = TRUE), "\n")
