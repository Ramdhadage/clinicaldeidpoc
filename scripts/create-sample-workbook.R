source(file.path("R", "bootstrap.R"))
activate_local_development_library(".")
load_deid_modules(".")

target_directory <- file.path("runtime", "input")
target_path <- file.path(
  target_directory,
  "Clinical_PHI_Anonymization_Data.xlsx"
)

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
data <- data.frame(
  Record_No = c("1", "2"),
  Patient_Name = c("Rashad Test", "Morgan Example"),
  DOB = c("15-Dec-1980", "22-07-1985"),
  Diagnosis_Journey = c(
    "Rashad Test contacted john.smith@example.test from 192.168.1.100.",
    "Morgan Example reported symptoms in December 2020."
  ),
  Treatment_History = c(
    "See https://hospital.example.test/patient/12345 on 15-Dec-2015.",
    "Call 216-555-0188."
  ),
  MRN = c("SYN-MRN-001", "SYN-MRN-002"),
  Patient_ID = c("SYN-001", "SYN-002"),
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
