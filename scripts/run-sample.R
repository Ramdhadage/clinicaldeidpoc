source(file.path("R", "bootstrap.R"))
activate_local_development_library(".")
load_deid_modules(".")

config <- read_deid_config(".")
source_path <- file.path(
  "runtime",
  "input",
  "Clinical_PHI_Anonymization_Data_v0.3.xlsx"
)

if (!file.exists(source_path)) {
  stop(
    paste(
      "The generated synthetic XLSX workbook was not found.",
      "Run scripts/create-sample-workbook.R first."
    ),
    call. = FALSE
  )
}

dataset <- read_clinical_workbook(
  source_path,
  original_name = basename(source_path),
  config = config
)
run <- run_structured_deidentification(dataset, config)

cat("Run ID:", run$run_id, "\n")
cat("State:", run$state, "\n")
cat("Release allowed:", can_release(run, config), "\n")
cat("Blocking items:", nrow(run$blockers), "\n\n")
print(create_tagged_preview(run, config), row.names = FALSE)
