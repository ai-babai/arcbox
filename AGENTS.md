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
- Do not introduce durable tests, fixtures or CI checks without explicit maintainer approval. Scratch checks outside the repository are allowed.
- Do not commit personal archives, credentials, local paths or release binaries.
- The repository is public under MIT by the owner's explicit decision. Visibility changes remain maintainer decisions.
