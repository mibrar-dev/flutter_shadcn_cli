# Flutter Shadcn CLI Full QA Report

- QA score: **75/100**
- Raw pass rate: **41/46 (89.1%)**
- Adjusted pass rate: **93.5%**
- Components installed: **133**
- Registry validate: **PASS**, 1833 files checked
- Dependency audit: **PASS**, 12 package rows
- Full audit: **FAIL**, 47 missing files
- Flutter analyze full install: **238 issues** (60 errors, 104 warnings, 74 infos)

## Product Defects

- **dry run all json**: dry-run --all exits 30 even though it returns a large plan. It injects missing pseudo IDs icon_fonts and typography_fonts as component warnings.
- **doctor json**: doctor --json validates against registry/components.schema.json instead of the v1 manifest schema path under manifests/.
- **audit json full install**: audit expects preview-state files that default add does not install. Full install reports 47 missing files, mostly preview internals.

## Evidence

See `qa_report.pdf`, `qa_report.html`, `qa_summary.json`, and `evidence/`.
