# Clinical Data De-identification PoC

This repository currently implements Milestone 1.2 of the approved project plan: a synthetic-only, fail-closed structured-data foundation with run-scoped hexadecimal ID tokens and a deterministic narrative preview.

- [Approved project plan](doc/plan.md)
- [Step-by-step setup and run guide](doc/run-guide.md)

Do not use real PHI. The tagged preview can miss identifiers and is not a HIPAA Safe Harbor determination. Azure free-text processing, residual validation, human approval, and release are not implemented yet.

Structured Record_No, MRN, and Patient_ID values remain removed from the processed result. Their eight-character hexadecimal values are source-independent, collision-checked, run-scoped display tokens only and are regenerated for a new run.
