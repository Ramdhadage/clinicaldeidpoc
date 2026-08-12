source(file.path("R", "bootstrap.R"))
activate_local_development_library(".")
load_deid_modules(".")

config <- read_deid_config(".")
source_path <- "Clinical_PHI_Anonymization_Test_Data - Test_Data.csv"

if (!file.exists(source_path)) {
  stop("The supplied synthetic CSV fixture is missing.", call. = FALSE)
}

data <- utils::read.csv(
  source_path,
  stringsAsFactors = FALSE,
  check.names = FALSE
)
validation <- validate_clinical_schema(data, config)

temporary_workbook <- tempfile(fileext = ".xlsx")
on.exit(unlink(temporary_workbook, force = TRUE), add = TRUE)
require_deid_namespace("writexl")
writexl::write_xlsx(
  list(Clinical_Data = validation$data),
  temporary_workbook
)

dataset <- read_clinical_workbook(
  temporary_workbook,
  original_name = "synthetic-test-data.xlsx",
  config = config
)
run <- run_structured_deidentification(dataset, config)

cat("Run ID:", run$run_id, "\n")
cat("State:", run$state, "\n")
cat("Release allowed:", can_release(run), "\n")
cat("Blocking items:", nrow(run$blockers), "\n\n")
print(create_safe_preview(run, config), row.names = FALSE)
