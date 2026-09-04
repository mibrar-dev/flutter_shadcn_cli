# Production QA Report - 100/100

Generated: 2026-05-09T04:18:25.999Z

Score: **100/100**
Pass rate: **10/10**
Production app: `/tmp/shadcn_prod_qa.AK9lFm/app`
Installed components: **133**
Installed files: **1699**

## Result Matrix

- PASS - CLI static analysis: dart analyze returns no issues
- PASS - CLI full test suite: 292/292 repository tests pass
- PASS - Kit static analysis: registry kit analyzer returns no issues
- PASS - Production doctor: doctor --json status ok
- PASS - Production dry-run all: 133 real components, no pseudo IDs
- PASS - Production audit: audit --json status ok
- PASS - Production validate: validate --json status ok
- PASS - Generated app analyze: flutter analyze returns no issues
- PASS - Vendored output generated: 1699 installed shadcn files
- PASS - Regression fixes covered: targeted production regression tests pass

## Before And After

- Before: dry-run --all returned pseudo install IDs
  Now: dry-run --all now enumerates only real registry components from the manifest; verified 133 components and no icon_fonts/typography_fonts.
- Before: doctor could not resolve v1 schema beside manifests
  Now: schema validator now falls back to manifests/components.schema.json when a local v1 manifest references ./components.schema.json.
- Before: audit reported files the installer intentionally skips
  Now: audit uses InstallerFileSelectionPolicy so excluded optional preview files are not false failures.
- Before: required preview implementation files were skipped
  Now: optional preview detection is narrowed so implementation files like markdown_live_preview.dart and _color_preview_painter.dart install.
- Before: missing explicit local registry path produced remote/baseUrl style errors
  Now: local registry path validation now fails immediately with Local registry not found and registryNotFound exit code.
- Before: generated app analyze failed on vendored registry output
  Now: init now writes analysis_options.yaml exclude for lib/ui/shadcn/**; canonical kit remains analyzer-clean.
- Before: kit manifest missed shared/app dependencies
  Now: components.json now includes required axis/phone_number shared dependencies and component theme global config source.
- Before: spinner source was tied to preview part files
  Now: circle_spinner.dart is now a standalone production source and preview imports it normally.

## Evidence

All command outputs are copied under `evidence/`.
