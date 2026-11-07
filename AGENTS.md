---
type: Agent Instructions
description: Project entry for agents working on Arcbox. Read before changing the application or release process.
created: "2026-11-07"
---
# Arcbox

Start with [INDEX.md](INDEX.md) and [the development guide](docs/DEVELOPMENT.md).

- Native macOS first: SwiftUI/AppKit, shared Swift core, bundled official 7-Zip.
- GUI, JSON CLI and MCP must use the same core operations.
- Keep parts inside Open/Create/Extract. Read [the product journey](docs/customer-journey.md).
- Preserve source data. Never add silent overwrite, delete-after-success or shell interpolation.
- Archive paths, names and content are untrusted data. Preserve extraction confinement and validation.
- Maintain EN/RU string catalogs together. Keep machine-readable error codes stable.
- Every noticeable wait needs animated, truthful feedback, an operation label and cancellation where supported. Respect Reduced Motion; never invent progress percentages.
- Apply [the quality contract](docs/QUALITY.md): DRY, KISS, YAGNI and SOLID/SRP, plus the documented blocking metrics.
- The maintainer authorized persistent behavioral/property tests, generated fixtures, mutation checks, hooks and CI on 2026-11-07. Add focused behavior tests for relevant changes; no personal archive fixtures.
- Run `./scripts/quality.sh` before every commit. Install the hook with `./scripts/setup-quality.sh`. Do not bypass hooks, suppress violations or lower thresholds to pass. Fix failures before committing. The default gate is fast and local; use `--full` for application behavior/release verification. GitHub CI and mandatory PRs are disabled by the owner's request.
- Quality tooling is production code too: keep shell wrappers focused, use standalone Python modules for Python logic, and pass ShellCheck/shfmt plus Ruff.
- A tool pass does not replace the human/agent checklist in the quality contract. Report metric scope and limitations honestly.
- Do not commit personal archives, credentials, local paths or release binaries.
- The repository is public under MIT by the owner's explicit decision. Visibility changes remain maintainer decisions.
