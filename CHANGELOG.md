---
type: Changelog
description: User-visible Arcbox release history.
created: "2026-11-07"
---
# Changelog

## Unreleased

- Keep everyday checks fast and local; remove GitHub CI and mandatory PR/status requirements. Full build/test/coverage/mutation verification is available explicitly with `--full`.

- Apply quality rules to the tooling itself: thin shell entry point, named Python gate phases, ShellCheck/shfmt for every shell script and hook, and Ruff for all Python helpers.
- Release mutation locks on failed setup; preserve another run's lock and reject stale mutation reports.

- Publish an EN/RU quality contract for DRY, KISS, YAGNI and SOLID/SRP.
- Enforce formatting, size/safety lint, cyclomatic/cognitive complexity, module boundaries and translation parity locally before commits. Coverage/CRAP, builds and mutations are separate full verification.
- Add behavioral, SwiftCheck property, CLI/MCP and quality-gate contract tests, plus a scoped Muter check.
- Separate archive orchestration, process execution, listing, output validation and shared part streaming; simplify UI and CLI responsibilities.

## 0.2.3 · 2026-11-07

- Visible EN/RU language switch in the toolbar, on the welcome screen and inside archives.
- Compact native titlebar with the application name on the left and actions on the right.
- English is the default for fresh installations; explicit language choices remain saved.
- Resizable sidebar and inspector with saved widths, wide drag targets, keyboard accessibility and double-click reset.
- Both panels slide open/closed smoothly and respect Reduced Motion; the inspector's visibility is saved too.
- Animated operation feedback for reading, checking, creating, extracting and preparing previews, with elapsed time and cancellation.
- Archive-loading placeholders and smooth transitions to results; no invented completion percentages.

## 0.2.2 · 2026-11-07

- Centered welcome screen, with or without the sidebar.
- Compact creation sheet: format and compression share a row; passwords are optional disclosure.
- Source summaries and inline custom part sizes keep all options within a smaller form.
- Content height follows the selected options and available screen height; action buttons stay outside the scroll area.

## 0.2.1 · 2026-11-07

- Clean, flat SVG application icon without the generated surface texture.
- The sidebar and welcome screen use the same artwork as the application bundle.
- Refresh the running Dock icon from the bundled artwork on launch.
- Public source and downloads under MIT, with English/Russian documentation and private vulnerability reporting.

## 0.2.0 · 2026-11-07

- Native Open, Create and Extract workflows, including multipart archives.
- Automatic volume discovery from any numeric, RAR or split-ZIP part.
- Integrated multipart creation with SHA-256 manifests and direct extraction.
- Raw file splitting inside Create; restoration preserves the original bytes.
- Missing-volume errors with exact file names and Retry.
- Discrete part-size slider with presets and a custom-size option.
- English/Russian application localization, language selection and bilingual documentation.
- Smooth sidebar show/hide, state persistence and Reduced Motion support.
- JSON CLI and six MCP stdio tools using the shared core.
- Universal Apple Silicon/Intel packaging, DMG/ZIP downloads and SHA-256 checksums.

This is an early, ad-hoc-signed release without Apple notarization. RAR creation, in-place archive editing and recovery records are not included.
