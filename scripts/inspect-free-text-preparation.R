source(file.path("R", "bootstrap.R"))
activate_local_development_library(".")
load_deid_modules(".")

config <- read_deid_config(".")
source_path <- "Clinical_PHI_Anonymization_Data.xlsx"

if (!file.exists(source_path)) {
  stop("The expected workbook is not available in the project root.", call. = FALSE)
}

dataset <- read_clinical_workbook(
  source_path,
  original_name = basename(source_path),
  config = config
)
preparation <- prepare_free_text_for_azure(dataset$data, config)

cat("Free-text preparation completed locally.\n")
cat("Columns: Diagnosis_Journey, Treatment_History\n")
cat("Documents prepared:", preparation$summary$documents, "\n")
cat("Original code points:", preparation$summary$original_codepoints, "\n")
cat("Prepared code points:", preparation$summary$prepared_codepoints, "\n")
cat(
  "Estimated Azure text records before local preparation:",
  preparation$summary$estimated_original_text_records,
  "\n"
)
cat("Estimated Azure text records:", preparation$summary$estimated_text_records, "\n")
cat("Azure request sent: no\n")
